-- Feed a SIXEL file through Comm 1 after POST, then capture the
-- firmware-rendered result.  The normal regression loads a null-modem
-- bitbanger image.  Set VT340_SIXEL_EXTERNAL=1 when a host process will feed
-- the stream through MAME's pseudo-terminal endpoint instead.  The script
-- observes bitmap memory but never writes graphics state directly.

io.stdout:setvbuf("no")

local screen = manager.machine.screens[":screen"]
local planes = manager.machine.memory.shares[":bitmap_planes"]
local keyboard = manager.machine.natkeyboard
local cpu1_xdata = manager.machine.devices[":cpu1"].spaces["xdata"]
local cpu2_xdata = manager.machine.devices[":cpu2"].spaces["xdata"]
local sixel_path = os.getenv("VT340_SIXEL_FILE")
local external_input = os.getenv("VT340_SIXEL_EXTERNAL") == "1"
local select_color = os.getenv("VT340_SELECT_COLOR") == "1"
local snapshot_path = os.getenv("VT340_SIXEL_SNAPSHOT") or "/tmp/vt340-sixel-bill.png"
local capture_time = tonumber(os.getenv("VT340_SIXEL_CAPTURE_TIME")) or 360
local bitbanger = nil
local expected_file = assert(io.open(sixel_path, "rb"))
local expected_stream = expected_file:read("*a")
expected_file:close()

assert(planes, "VT340 bitmap_planes memory share is unavailable")
assert(sixel_path and sixel_path ~= "", "VT340_SIXEL_FILE is not set")

for _, image in pairs(manager.machine.images) do
	if image.brief_instance_name == "bitb" then
		bitbanger = image
		break
	end
end

if not external_input then
	assert(bitbanger, "Comm 1 bitbanger image is unavailable; use -comm1 null_modem")
end

-- A sustained 93 KiB graphics stream must honor the terminal's XON/XOFF
-- backpressure.  This configures only the host-side null modem; the VT340
-- firmware remains responsible for generating the control characters.
local flow_tag = external_input and ":comm1:pty:FLOW_CONTROL" or ":comm1:null_modem:FLOW_CONTROL"
local flow_port = manager.machine.ioport.ports[flow_tag]
assert(flow_port, "Comm 1 flow-control setting is unavailable")
local baud_setting = tonumber(os.getenv("VT340_SIXEL_BAUD_SETTING"))
if baud_setting then
	manager.machine.ioport.ports[":comm1:null_modem:RS232_TXBAUD"].fields["TX Baud"]:set_value(baud_setting)
	manager.machine.ioport.ports[":comm1:null_modem:RS232_RXBAUD"].fields["RX Baud"]:set_value(baud_setting)
end

local loaded = false
local captured = false
local left_post = false
local received_bytes = 0
local received_mismatches = 0
local first_received_mismatch = -1
local received_prefix = {}
local xoff_count = 0
local xon_count = 0
local graphics_commands = 0
local normal_commands = 0
local nonnormal_commands = 0
local operation_counts = { 0, 0, 0, 0 }
local raster_candidates = 0
local source2_commands = 0
local viper_loads = 0
local dc323_mode = 0
local viper_select = 0
local command_counts = {}
local mode_counts = {}
local raster_outcomes = {}
local select_counts = {}
local visible_rasters = 0
local source1_rasters = 0
local dc323_regs = {}
local viper_regs = {}
for plane = 0, 3 do viper_regs[plane] = {} end
local destination_min_x = 0xffff
local destination_min_y = 0xffff
local destination_max_x = 0
local destination_max_y = 0
local screen_intersections = 0
local id_data_writes = 0
local id_trace_events = 0
local pbt_trace_events = 0
local last_command = 0
local post_pbt_commands = 0
local palette_rg = {}
local palette_gb = {}
local palette_rg_writes = 0
local palette_gb_writes = 0
local duart_csra = 0
local duart_acr = 0
local duart_mr_writes = {}
local trace_ring = os.getenv("VT340_TRACE_RING") == "1"
local trace_color_state = os.getenv("VT340_TRACE_COLOR_STATE") == "1"
local setup_enter = nil
local setup_down = nil
local setup_right = nil
local setup_started = false
local setup_enter_pressed = false
local setup_enter_released = false
local setup_down_pulses = 0
local setup_down_released = true
local setup_right_pressed = false
local setup_right_released = false
local setup_left = false
local ring_events = 0
local ring_previous_producer = cpu1_xdata:read_u8(0x7e7e)

keyboard.in_use = true

if select_color then
	setup_enter = manager.machine.ioport.ports[":keyboard:KBD17"].fields["Enter"]
	setup_down = manager.machine.ioport.ports[":keyboard:KBD16"].fields["Down"]
	setup_right = manager.machine.ioport.ports[":keyboard:KBD15"].fields["Right"]
end

if trace_color_state then
	local function color_state_access(cpu, access, data)
		print(string.format(
			'VT340_SIXEL_JSON {"event":"color_state_%s","time":%.9f,"cpu":"%s","pc":"%04X","value":"%02X"}',
			access, manager.machine.time:as_double(), cpu.tag,
			cpu.state["PC"].value, data))
	end
	sixel_cpu1_color_state_read = cpu1_xdata:install_read_tap(
		0x4c00, 0x4c00, "vt340_sixel_cpu1_color_state_read",
		function(offset, data, mask) color_state_access(manager.machine.devices[":cpu1"], "read", data) end)
	sixel_cpu1_color_state_write = cpu1_xdata:install_write_tap(
		0x4c00, 0x4c00, "vt340_sixel_cpu1_color_state_write",
		function(offset, data, mask) color_state_access(manager.machine.devices[":cpu1"], "write", data) end)
	sixel_cpu2_color_state_read = cpu2_xdata:install_read_tap(
		0x4c00, 0x4c00, "vt340_sixel_cpu2_color_state_read",
		function(offset, data, mask) color_state_access(manager.machine.devices[":cpu2"], "read", data) end)
	sixel_cpu2_color_state_write = cpu2_xdata:install_write_tap(
		0x4c00, 0x4c00, "vt340_sixel_cpu2_color_state_write",
		function(offset, data, mask) color_state_access(manager.machine.devices[":cpu2"], "write", data) end)
	sixel_color_config_write = cpu1_xdata:install_write_tap(
		0x7b00, 0x7b00, "vt340_sixel_color_config_write",
		function(offset, data, mask)
			print(string.format(
				'VT340_SIXEL_JSON {"event":"color_config_write","time":%.9f,"cpu":":cpu1","pc":"%04X","value":"%02X"}',
				manager.machine.time:as_double(), manager.machine.devices[":cpu1"].state["PC"].value, data))
		end)
end

sixel_comm1_read_tap = cpu1_xdata:install_read_tap(
	0xf040, 0xf07f, "vt340_sixel_comm1_read",
	function(offset, data, mask)
		if (offset & 0x0f) == 0x00 then
			duart_mr_writes[#duart_mr_writes + 1] = string.format("%02X", data)
		end
		if (offset & 0x0f) == 0x01 then duart_csra = data end
		if (offset & 0x0f) == 0x04 then duart_acr = data end
		if loaded and (offset & 0x0f) == 0x03 then
			received_bytes = received_bytes + 1
			local expected = expected_stream:byte(received_bytes)
			if expected == nil or data ~= expected then
				received_mismatches = received_mismatches + 1
				if first_received_mismatch < 0 then
					first_received_mismatch = received_bytes - 1
					print(string.format(
						'VT340_SIXEL_JSON {"event":"receive_mismatch","offset":%d,"expected":%s,"observed":"%02X"}',
						first_received_mismatch,
						expected and string.format('"%02X"', expected) or "null", data))
				end
			end
			if #received_prefix < 128 then
				received_prefix[#received_prefix + 1] = string.format("%02X", data)
			end
		end
	end)

sixel_comm1_write_tap = cpu1_xdata:install_write_tap(
	0xf040, 0xf07f, "vt340_sixel_comm1_write",
	function(offset, data, mask)
		if loaded and (offset & 0x0f) == 0x03 then
			if data == 0x13 then xoff_count = xoff_count + 1 end
			if data == 0x11 then xon_count = xon_count + 1 end
		end
	end)

if trace_ring then
	sixel_ring_producer_tap = cpu1_xdata:install_write_tap(
		0x7e7e, 0x7e7e, "vt340_sixel_ring_producer",
		function(offset, data, mask)
			if not loaded then
				ring_previous_producer = data
				return
			end
			local bytes = {}
			local index = ring_previous_producer
			while index ~= data and #bytes < 0x7e do
				bytes[#bytes + 1] = string.format("%02X", cpu1_xdata:read_u8(0x7e00 + index))
				index = (index + 1) % 0x7e
			end
			ring_events = ring_events + 1
			if ring_events <= 256 then
				print(string.format(
					'VT340_SIXEL_JSON {"event":"ring_packet","time":%.9f,"pc":"%04X","old":"%02X","new":"%02X","consumer":"%02X","bytes":"%s"}',
					manager.machine.time:as_double(), manager.machine.devices[":cpu1"].state["PC"].value,
					ring_previous_producer, data, cpu1_xdata:read_u8(0x7e7f), table.concat(bytes)))
			end
			ring_previous_producer = data
		end)
end

sixel_dc323_write_tap = cpu2_xdata:install_write_tap(
	0xf000, 0xffff, "vt340_sixel_dc323_write",
	function(offset, data, mask)
		if loaded and (offset & 0xffe0) == 0xf080 then
			palette_rg[offset & 0x0f] = data
			palette_rg_writes = palette_rg_writes + 1
		elseif loaded and (offset & 0xffe0) == 0xf0a0 then
			palette_gb[offset & 0x0f] = data
			palette_gb_writes = palette_gb_writes + 1
		end
		if offset >= 0xf060 and offset <= 0xf07f then
			viper_select = (((data >> 5) & 1) << 0) |
				(((data >> 4) & 1) << 1) |
				(((data >> 3) & 1) << 2) |
				(((data >> 2) & 1) << 3)
			return
		end
		if (offset & 0xf0c0) ~= 0xf000 then return end
		local reg = offset & 0x3f
		local register_value = (manager.machine.devices[":cpu2"].state["P1"].value << 8) | data
		dc323_regs[reg] = register_value
		if reg == 0x08 and (register_value & 0xffe0) == 0x0180 then
			local viper_reg = register_value & 0x1f
			for plane = 0, 3 do
				if (viper_select & (1 << plane)) ~= 0 then
					viper_regs[plane][viper_reg] = dc323_regs[0x07] or 0
				end
			end
		end
		if loaded and reg == 0x07 then
			id_data_writes = id_data_writes + 1
			if id_trace_events < 80 then
				id_trace_events = id_trace_events + 1
				print(string.format(
					'VT340_SIXEL_JSON {"event":"id_data_write","time":%.9f,"value":"%04X","last_command":"%04X"}',
					manager.machine.time:as_double(), register_value, last_command))
			end
		elseif reg == 0x09 then
			dc323_mode = register_value
		elseif loaded and reg == 0x08 then
			local command = register_value
			last_command = command
			graphics_commands = graphics_commands + 1
			local operation = (command >> 8) & 3
			local command_key = string.format("%04X", command)
			command_counts[command_key] = (command_counts[command_key] or 0) + 1
			operation_counts[operation + 1] = operation_counts[operation + 1] + 1
			if operation == 2 then
				local mode_key = string.format("%04X", dc323_mode)
				mode_counts[mode_key] = (mode_counts[mode_key] or 0) + 1
				local reason = "executed"
				local indexed = (dc323_mode & 0x60) ~= 0
				local zero_indexes = ((dc323_regs[0x17] or 0) | (dc323_regs[0x18] or 0) |
					(dc323_regs[0x19] or 0) | (dc323_regs[0x1a] or 0)) == 0
				local raster_mode = dc323_mode & 0x03
				local source1 = ((command >> 11) & 1) ~= 0
				if ((command >> 10) & 1) == 0 then reason = "destination_disabled"
				elseif ((command >> 12) & 1) ~= 0 then reason = "source2"
				elseif (dc323_mode & 0x80) == 0 then reason = "pen_up"
				elseif raster_mode == 0 and indexed and not zero_indexes then reason = "nonzero_index"
				elseif raster_mode == 1 then reason = "reserved_mode"
				elseif raster_mode == 2 and not source1 then reason = "linear_without_source1"
				elseif raster_mode == 3 and source1 then reason = "fill_with_source1"
				end
				local outcome_key = command_key .. ":" .. reason
				raster_outcomes[outcome_key] = (raster_outcomes[outcome_key] or 0) + 1
			end
			if (command & 0xffe0) == 0x0180 then
				viper_loads = viper_loads + 1
			end
			if operation == 3 and ((command >> 10) & 1) ~= 0 and pbt_trace_events < 80 then
				pbt_trace_events = pbt_trace_events + 1
				local csr = command & 7
				local details = {}
				for plane = 0, 3 do
					if (viper_select & (1 << plane)) ~= 0 then
						details[#details + 1] = string.format(
							'{"plane":%d,"csr":"%04X","logic":"%02X","mask1":"%04X","mask2":"%04X","source":"%04X","background":"%04X","foreground":"%04X"}',
							plane, viper_regs[plane][0x10 + csr] or 0,
							viper_regs[plane][0x04 + ((command >> 4) & 3)] or 0,
							viper_regs[plane][0x08] or 0, viper_regs[plane][0x09] or 0,
							viper_regs[plane][0x0a] or 0, viper_regs[plane][0x0e] or 0,
							viper_regs[plane][0x0f] or 0)
					end
				end
				print(string.format(
					'VT340_SIXEL_JSON {"event":"ptb_command","time":%.9f,"command":"%04X","id_data":"%04X","destination":[%d,%d],"extent":[%d,%d],"mode":"%04X","select":"%X","vipers":[%s]}',
					manager.machine.time:as_double(), command, dc323_regs[0x07] or 0,
					(dc323_regs[0x24] or 0) & 0x3fff, (dc323_regs[0x25] or 0) & 0x3fff,
					(dc323_regs[0x26] or 0) & 0x1fff, (dc323_regs[0x29] or 0) & 0x1fff,
					dc323_mode, viper_select, table.concat(details, ",")))
				post_pbt_commands = 4
			elseif post_pbt_commands > 0 then
				post_pbt_commands = post_pbt_commands - 1
				print(string.format(
					'VT340_SIXEL_JSON {"event":"post_ptb_command","time":%.9f,"command":"%04X","source":[%d,%d],"destination":[%d,%d],"source_extent":["%04X","%04X"],"destination_vectors":["%04X","%04X","%04X","%04X"],"indexes":["%04X","%04X","%04X","%04X"],"mode":"%04X","select":"%X","logic":["%02X","%02X","%02X","%02X"]}',
					manager.machine.time:as_double(), command,
					(dc323_regs[0x22] or 0) & 0x3fff, (dc323_regs[0x23] or 0) & 0x1fff,
					(dc323_regs[0x24] or 0) & 0x3fff, (dc323_regs[0x25] or 0) & 0x3fff,
					dc323_regs[0x20] or 0, dc323_regs[0x21] or 0,
					dc323_regs[0x26] or 0, dc323_regs[0x27] or 0,
					dc323_regs[0x28] or 0, dc323_regs[0x29] or 0,
					dc323_regs[0x17] or 0, dc323_regs[0x18] or 0,
					dc323_regs[0x19] or 0, dc323_regs[0x1a] or 0,
					dc323_mode, viper_select,
					viper_regs[0][0x04 + ((command >> 4) & 3)] or 0,
					viper_regs[1][0x04 + ((command >> 4) & 3)] or 0,
					viper_regs[2][0x04 + ((command >> 4) & 3)] or 0,
					viper_regs[3][0x04 + ((command >> 4) & 3)] or 0))
			end
			if operation == 2 and ((command >> 10) & 1) ~= 0 then
				raster_candidates = raster_candidates + 1
				select_counts[viper_select] = (select_counts[viper_select] or 0) + 1
				if ((command >> 11) & 1) ~= 0 then source1_rasters = source1_rasters + 1 end
				visible_rasters = visible_rasters + 1
				local x = (dc323_regs[0x24] or 0) & 0x3fff
				local y = (dc323_regs[0x25] or 0) & 0x3fff
				local width = (dc323_regs[0x26] or 0) & 0x1fff
				local height = (dc323_regs[0x29] or 0) & 0x1fff
				destination_min_x = math.min(destination_min_x, x)
				destination_min_y = math.min(destination_min_y, y)
				destination_max_x = math.max(destination_max_x, x + math.max(width, 1) - 1)
				destination_max_y = math.max(destination_max_y, y + math.max(height, 1) - 1)
				if width ~= 0 and height ~= 0 and x < 800 and y < 500 and x + width > 0 and y + height > 0 then
					screen_intersections = screen_intersections + 1
				end
			end
			if ((command >> 12) & 1) ~= 0 then source2_commands = source2_commands + 1 end
			if (dc323_mode & 0x03) == 0 and (dc323_mode & 0x80) ~= 0 then
				normal_commands = normal_commands + 1
			else
				nonnormal_commands = nonnormal_commands + 1
			end
		end
	end)

local function capture_visible_bitmap()
	local hash = 0x811c9dc5
	local counts = {}
	for color = 0, 15 do counts[color] = 0 end
	for y = 0, 499 do
		for x = 0, 799 do
			local address = y * 1024 + x
			local color = 0
			for plane = 0, 3 do
				color = color | ((planes:read_u8(plane * 1024 * 2048 + address) & 1) << plane)
			end
			counts[color] = counts[color] + 1
			hash = ((hash ~ color) * 0x01000193) & 0xffffffff
		end
	end

	local count_text = {}
	for color = 0, 15 do
		count_text[color + 1] = tostring(counts[color])
	end
	local nonzero_min_x = 1024
	local nonzero_min_y = 2048
	local nonzero_max_x = -1
	local nonzero_max_y = -1
	local nonzero_pixels = 0
	for y = 0, 2047 do
		for x = 0, 1023 do
			local address = y * 1024 + x
			local color = 0
			for plane = 0, 3 do
				color = color | ((planes:read_u8(plane * 1024 * 2048 + address) & 1) << plane)
			end
			if color ~= 0 then
				nonzero_pixels = nonzero_pixels + 1
				nonzero_min_x = math.min(nonzero_min_x, x)
				nonzero_min_y = math.min(nonzero_min_y, y)
				nonzero_max_x = math.max(nonzero_max_x, x)
				nonzero_max_y = math.max(nonzero_max_y, y)
			end
		end
	end
	screen:snapshot(snapshot_path)
	for command, count in pairs(command_counts) do
		print(string.format(
			'VT340_SIXEL_JSON {"event":"command_count","command":"%s","count":%d}',
			command, count))
	end
	for mode, count in pairs(mode_counts) do
		print(string.format(
			'VT340_SIXEL_JSON {"event":"mode_count","mode":"%s","count":%d}',
			mode, count))
	end
	for outcome, count in pairs(raster_outcomes) do
		local command, reason = outcome:match("^([^:]+):(.+)$")
		print(string.format(
			'VT340_SIXEL_JSON {"event":"raster_outcome","command":"%s","reason":"%s","count":%d}',
			command, reason, count))
	end
	for select, count in pairs(select_counts) do
		print(string.format(
			'VT340_SIXEL_JSON {"event":"select_count","select":"%X","count":%d}',
			select, count))
	end
	for index = 0, 15 do
		print(string.format(
			'VT340_SIXEL_JSON {"event":"palette","index":%d,"rg":"%02X","gb":"%02X"}',
			index, palette_rg[index] or 0, palette_gb[index] or 0))
	end
	print(string.format(
		'VT340_SIXEL_JSON {"event":"received_prefix","hex":"%s","csra":"%02X","acr":"%02X","mr_writes":"%s"}',
		table.concat(received_prefix), duart_csra, duart_acr, table.concat(duart_mr_writes)))
	print(string.format(
		'VT340_SIXEL_JSON {"event":"capture","time":%.9f,"bitmap_hash":"%08X","color_counts":[%s],"received_bytes":%d,"received_mismatches":%d,"first_received_mismatch":%d,"flow_control":{"xoff":%d,"xon":%d},"graphics_commands":%d,"normal_commands":%d,"nonnormal_commands":%d,"operation_counts":[%d,%d,%d,%d],"raster_candidates":%d,"source1_rasters":%d,"destination_bounds":[%d,%d,%d,%d],"screen_intersections":%d,"nonzero_pixels":%d,"nonzero_bounds":[%d,%d,%d,%d],"y_offset":"%04X","y_scroll":"%04X","source2_commands":%d,"viper_loads":%d,"id_data_writes":%d,"palette_writes":{"rg":%d,"gb":%d},"snapshot":"%s"}',
		manager.machine.time:as_double(), hash, table.concat(count_text, ","),
		received_bytes, received_mismatches, first_received_mismatch,
		xoff_count, xon_count, graphics_commands, normal_commands,
		nonnormal_commands, operation_counts[1], operation_counts[2],
		operation_counts[3], operation_counts[4], raster_candidates,
		source1_rasters, destination_min_x, destination_min_y,
		destination_max_x, destination_max_y, screen_intersections,
		nonzero_pixels, nonzero_min_x, nonzero_min_y, nonzero_max_x, nonzero_max_y,
		dc323_regs[0x13] or 0, dc323_regs[0x14] or 0,
		source2_commands, viper_loads, id_data_writes,
		palette_rg_writes, palette_gb_writes, snapshot_path))
end

emu.register_frame_done(function()
	local now = manager.machine.time:as_double()
	if not left_post and now >= 130 then
		keyboard:post_coded("{TAB}")
		left_post = true
		print(string.format('VT340_SIXEL_JSON {"event":"leave_post","time":%.9f}', now))
	end
	if select_color then
		if not setup_started and now >= 140 then
			keyboard:post_coded("{F3}")
			setup_started = true
		end
		if not setup_enter_pressed and now >= 142 then
			setup_enter:set_value(1)
			setup_enter_pressed = true
		end
		if setup_enter_pressed and not setup_enter_released and now >= 142.5 then
			setup_enter:set_value(0)
			setup_enter_released = true
		end
		local next_down_time = 190 + setup_down_pulses * 5
		if setup_down_pulses < 7 and setup_down_released and now >= next_down_time then
			setup_down:set_value(1)
			setup_down_released = false
		end
		if not setup_down_released and now >= next_down_time + 0.5 then
			setup_down:set_value(0)
			setup_down_released = true
			setup_down_pulses = setup_down_pulses + 1
		end
		if not setup_right_pressed and now >= 235 then
			setup_right:set_value(1)
			setup_right_pressed = true
		end
		if setup_right_pressed and not setup_right_released and now >= 235.5 then
			setup_right:set_value(0)
			setup_right_released = true
		end
		if not setup_left and now >= 270 then
			keyboard:post_coded("{F3}")
			setup_left = true
			print(string.format(
				'VT340_SIXEL_JSON {"event":"native_color_setup","time":%.9f,"config":"%02X","state":"%02X"}',
				now, cpu1_xdata:read_u8(0x7b00), cpu1_xdata:read_u8(0x4c00)))
		end
	end
	local load_time = select_color and 280 or 140
	if not loaded and now >= load_time then
		loaded = true
		-- Let the connector consume the terminal firmware's XON/XOFF bytes.
		-- This applies equally to the reproducible bitbanger and the real PTY
		-- path used by an interactive host.
		flow_port.fields["Flow Control"]:set_value(0x04)
		if external_input then
			print(string.format(
				'VT340_SIXEL_JSON {"event":"external_ready","time":%.9f,"path":"%s"}',
				now, sixel_path))
		else
			local error_message = bitbanger:load(sixel_path)
			assert(not error_message, "unable to load SIXEL stream: " .. tostring(error_message))
			print(string.format(
				'VT340_SIXEL_JSON {"event":"load","time":%.9f,"path":"%s"}',
				now, sixel_path))
		end
	end
	if not captured and now >= capture_time then
		capture_visible_bitmap()
		captured = true
	end
end)

emu.add_machine_stop_notifier(function()
	print(string.format(
		'VT340_SIXEL_JSON {"event":"summary","time":%.9f,"loaded":%s,"captured":%s}',
		manager.machine.time:as_double(), loaded and "true" or "false", captured and "true" or "false"))
end)

-- Observe a native ReGIS hardcopy emitted through the SCN2641 printer port.

io.stdout:setvbuf("no")

local cpu1 = manager.machine.devices[":cpu1"]
local xdata = cpu1.spaces["xdata"]
local sfr = cpu1.spaces["sfr"]
local idata = cpu1.spaces["idata"]
local debugger = manager.machine.debugger
local keyboard = manager.machine.natkeyboard
local ready = false
local byte_count = 0
local last_byte_time = 0
local previous_byte = -1
local sixel_started = false
local sixel_finished = false
local host_byte_count = 0
local host_output_count = 0
local host_previous_byte = -1
local host_bytes = {}
local timeout = tonumber(os.getenv("VT340_MEDIACOPY_TIMEOUT")) or 300
local printer_dsr_reads = 0
local printer_uart_reads = 0
local printer_uart_writes = 0
local printer_state_writes = 0
local printer_setup = os.getenv("VT340_MEDIACOPY_PRINTER_SETUP") or "none"
local setup_down = manager.machine.ioport.ports[":keyboard:KBD16"].fields["Down"]
local setup_right = manager.machine.ioport.ports[":keyboard:KBD15"].fields["Right"]
local setup_enter = manager.machine.ioport.ports[":keyboard:KBD17"].fields["Enter"]
local setup_select = manager.machine.ioport.ports[":keyboard:KBD12"].fields["Select"]
local actions = {}
local next_action = 1
local ready_time = 0
local state_snapshots = 0
local route_breakpoints_installed = false

keyboard.in_use = true

local function coded(time, code)
	table.insert(actions, { time = time, code = code })
end

local function key(time, field)
	table.insert(actions, { time = time, field = field, value = 1 })
	table.insert(actions, { time = time + 0.2, field = field, value = 0 })
end

local function hex_range(space, first, last)
	local bytes = {}
	for address = first, last do
		bytes[#bytes + 1] = string.format("%02X", space:read_u8(address))
	end
	return table.concat(bytes)
end

coded(130, "{TAB}")
if printer_setup ~= "none" then
	coded(140, "{F3}")
	for index = 0, 3 do key(142 + index, setup_down) end
	key(147, setup_enter)
	if printer_setup == "dtr" then
		for index = 0, 5 do key(152 + index, setup_down) end
		key(159, setup_right)
		key(160, setup_right) -- XON/XOFF -> DTR flow control
	elseif printer_setup == "level2" then
		for index = 0, 10 do key(152 + index, setup_down) end
		key(164, setup_right) -- Level 1 -> Level 2 sixel graphics
	else
		error("unknown VT340_MEDIACOPY_PRINTER_SETUP value: " .. printer_setup)
	end
	key(167, setup_select)
	coded(170, "{F3}")
end

printer_write_tap = xdata:install_write_tap(
	0xf000, 0xf03f, "vt340_mediacopy_printer_write",
	function(offset, data, mask)
		if ready then
			printer_uart_writes = printer_uart_writes + 1
			if printer_uart_writes <= 64 then
				print(string.format(
					'VT340_MEDIACOPY_JSON {"event":"printer_uart_write","time":%.9f,"pc":"%04X","address":"%04X","data":"%02X"}',
					manager.machine.time:as_double(), cpu1.state["PC"].value,
					offset, data))
			end
			if (offset & 0x03) == 0 then
				byte_count = byte_count + 1
				last_byte_time = manager.machine.time:as_double()
				if previous_byte == 0x1b and data == 0x50 then
					sixel_started = true
					print(string.format(
						'VT340_MEDIACOPY_JSON {"event":"sixel_start","time":%.9f,"byte":%d}',
						last_byte_time, byte_count))
				end
				if sixel_started and previous_byte == 0x1b and data == 0x5c then
					sixel_finished = true
					print(string.format(
						'VT340_MEDIACOPY_JSON {"event":"sixel_end","time":%.9f,"byte":%d}',
						last_byte_time, byte_count))
				end
				previous_byte = data
			end
		end
	end)

printer_read_tap = xdata:install_read_tap(
	0xf000, 0xf003, "vt340_mediacopy_printer_read",
	function(offset, data, mask)
		if ready and printer_uart_reads < 64 then
			printer_uart_reads = printer_uart_reads + 1
			print(string.format(
				'VT340_MEDIACOPY_JSON {"event":"printer_uart_read","time":%.9f,"pc":"%04X","address":"%04X","data":"%02X"}',
				manager.machine.time:as_double(), cpu1.state["PC"].value,
				offset, data))
		end
	end)

printer_state_tap = xdata:install_write_tap(
	0x7c90, 0x7cd0, "vt340_mediacopy_printer_state",
	function(offset, data, mask)
		if ready and printer_state_writes < 256 then
			printer_state_writes = printer_state_writes + 1
			print(string.format(
				'VT340_MEDIACOPY_JSON {"event":"printer_state_write","time":%.9f,"pc":"%04X","address":"%04X","data":"%02X"}',
				manager.machine.time:as_double(), cpu1.state["PC"].value,
				offset, data))
		end
	end)

local printer_route_points = {
	[0x0000] = "cpu1_reset_vector",
	[0x38da] = "cpu1_startup_entry",
	[0x38ec] = "cpu1_nvram_wait",
	[0x6554] = "firmware_restart_low",
	[0x84c5] = "firmware_restart_high",
	[0x5bd0] = "host_output_poll",
	[0x5bd5] = "host_output_fetch",
	[0xa8aa] = "printer_process_entry",
	[0xa8e6] = "printer_process_queue",
	[0xa8f4] = "printer_input_entry",
	[0xa936] = "printer_input_empty",
	[0xa98d] = "printer_input_sequence",
	[0xa9e5] = "printer_input_reset",
	[0xae37] = "printer_reset",
	[0xaf82] = "printer_queue_byte",
	[0xb942] = "printer_stream_reset",
	[0xb95f] = "printer_queue_st",
	[0xb969] = "printer_stream_start"
}
local printer_route_taps = {}
local early_points = {
	[0x7299] = "stream_state_clear_boot",
	[0x729f] = "stream_state_sample_boot",
	[0x8996] = "stream_state_clear_setup",
	[0x8999] = "stream_state_sample_setup",
	[0xbff7] = "stream_state_clear_reset",
	[0xbffa] = "stream_state_sample_reset",
	[0xc00d] = "stream_state_clear"
}
local early_taps = {}
for address, _ in pairs(early_points) do
	early_taps[address] = cpu1.debug:bpset(address)
end

emu.register_periodic(function()
	if debugger.execution_state ~= "stop" then return end
	local pc = cpu1.state["PC"].value
	local name = printer_route_points[pc] or early_points[pc]
	if name and (ready or early_points[pc]) then
		print(string.format(
			'VT340_MEDIACOPY_JSON {"event":"printer_route","time":%.9f,"pc":"%04X","name":"%s","sp":"%02X","psw":"%02X","acc":"%02X","b":"%02X","state24":"%02X","state2b":"%02X","queue_count":"%02X"}',
			manager.machine.time:as_double(), pc, name,
			sfr:read_u8(0x81), sfr:read_u8(0xd0),
			sfr:read_u8(0xe0), sfr:read_u8(0xf0),
			idata:read_u8(0x24), idata:read_u8(0x2b),
			xdata:read_u8(0x7ccf)))
	end
	debugger.execution_state = "run"
end)

host_read_tap = xdata:install_read_tap(
	0xf043, 0xf043, "vt340_mediacopy_host_read",
	function(offset, data, mask)
		if ready then
			host_byte_count = host_byte_count + 1
			if #host_bytes < 96 then
				host_bytes[#host_bytes + 1] = string.format("%02X", data)
			end
		end
	end)

host_write_tap = xdata:install_write_tap(
	0xf043, 0xf043, "vt340_mediacopy_host_write",
	function(offset, data, mask)
		if ready then
			host_output_count = host_output_count + 1
			if host_output_count <= 32 then
				print(string.format(
					'VT340_MEDIACOPY_JSON {"event":"host_output","time":%.9f,"pc":"%04X","byte":%d,"data":"%02X"}',
					manager.machine.time:as_double(), cpu1.state["PC"].value,
					host_output_count, data))
			end
			if host_previous_byte == 0x1b and data == 0x50 then
				print(string.format(
					'VT340_MEDIACOPY_JSON {"event":"host_sixel_start","time":%.9f,"byte":%d}',
					manager.machine.time:as_double(), host_output_count))
			end
			host_previous_byte = data
		end
	end)

printer_dsr_tap = sfr:install_read_tap(
	0x90, 0x90, "vt340_mediacopy_printer_dsr",
	function(offset, data, mask)
		if ready and printer_dsr_reads < 128 then
			printer_dsr_reads = printer_dsr_reads + 1
			print(string.format(
				'VT340_MEDIACOPY_JSON {"event":"printer_dsr","time":%.9f,"pc":"%04X","p1":"%02X","dsr_l":%d}',
				manager.machine.time:as_double(), cpu1.state["PC"].value,
				data, (data >> 3) & 1))
		end
	end)

emu.register_frame_done(function()
	local now = manager.machine.time:as_double()
	while next_action <= #actions and now >= actions[next_action].time do
		local action = actions[next_action]
		if action.code then
			keyboard:post_coded(action.code)
		else
			action.field:set_value(action.value)
		end
		next_action = next_action + 1
	end
	if not ready and now >= (printer_setup ~= "none" and 173 or 140) then
		ready = true
		ready_time = now
		if not route_breakpoints_installed then
			route_breakpoints_installed = true
			for address, _ in pairs(printer_route_points) do
				printer_route_taps[address] = cpu1.debug:bpset(address)
			end
			debugger.execution_state = "run"
		end
		print(string.format(
			'VT340_MEDIACOPY_JSON {"event":"external_ready","time":%.9f,"p1":"%02X"}',
			now, cpu1.state["P1"].value))
	end
	if ready and idata and state_snapshots < 4 and now >= ready_time + (state_snapshots + 1) * 0.5 then
		state_snapshots = state_snapshots + 1
		print(string.format(
			'VT340_MEDIACOPY_JSON {"event":"state_snapshot","time":%.9f,"index":%d,"idata":"%s","xdata":"%s"}',
			now, state_snapshots, hex_range(idata, 0x20, 0x5f),
			hex_range(xdata, 0x7c90, 0x7cd0)))
	end
	if sixel_finished and now - last_byte_time >= 1 then
		print(string.format(
			'VT340_MEDIACOPY_PASS time=%.9f bytes=%d', now, byte_count))
		manager.machine:exit()
	elseif now >= timeout then
		print(string.format(
			'VT340_MEDIACOPY_FAIL time=%.9f bytes=%d sixel=%s host_bytes=%d host_output=%d host_data=%s',
			now, byte_count, tostring(sixel_started), host_byte_count,
			host_output_count, table.concat(host_bytes, "")))
		manager.machine:exit()
	end
end)

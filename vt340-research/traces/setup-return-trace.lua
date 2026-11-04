-- Trace the native color-map Set-Up exit and the bitmap restore commands.
-- Diagnostic only: input is limited to LK201 keys and no emulated state is
-- modified directly.

io.stdout:setvbuf("no")

local cpu2 = manager.machine.devices[":cpu2"]
local xdata = cpu2.spaces["xdata"]
local idata = cpu2.spaces["idata"]
local keyboard = manager.machine.natkeyboard
local screen = manager.machine.screens[":screen"]
local planes = manager.machine.memory.shares[":bitmap_planes"]
local cpu1_xdata = manager.machine.devices[":cpu1"].spaces["xdata"]
local cpu1 = manager.machine.devices[":cpu1"]
local setup_enter = manager.machine.ioport.ports[":keyboard:KBD17"].fields["Enter"]
local setup_down = manager.machine.ioport.ports[":keyboard:KBD16"].fields["Down"]
local setup_right = manager.machine.ioport.ports[":keyboard:KBD15"].fields["Right"]

keyboard.in_use = true
local simple_return = os.getenv("VT340_SETUP_RETURN_SIMPLE") == "1"
local breakpoint_trace = os.getenv("VT340_SETUP_RETURN_BREAKPOINTS") == "1"

local regs = {}
local viper = { {}, {}, {}, {} }
local viper_select = 0
local command_count = 0
local palette_writes = 0
local trace_start = simple_return and 135 or 260
local trace_end = simple_return and 165 or 272

local function bitmap_color(x, y)
	local address = y * 1024 + x
	local color = 0
	for plane = 0, 3 do
		color = color | ((planes:read_u8(plane * 1024 * 2048 + address) & 1) << plane)
	end
	return color
end

local function row_runs(y)
	local runs = {}
	local first = 0
	local color = bitmap_color(0, y)
	for x = 1, 800 do
		local next_color = x < 800 and bitmap_color(x, y) or -1
		if next_color ~= color then
			runs[#runs + 1] = string.format("%d-%d:%X", first, x - 1, color)
			first = x
			color = next_color
		end
	end
	return table.concat(runs, ",")
end

local function rectangle_nonzero(x0, y0, width, height)
	local counts = { 0, 0, 0, 0 }
	for plane = 0, 3 do
		for y = y0, y0 + height - 1 do
			for x = x0, x0 + width - 1 do
				if (planes:read_u8(plane * 1024 * 2048 + y * 1024 + x) & 1) ~= 0 then
					counts[plane + 1] = counts[plane + 1] + 1
				end
			end
		end
	end
	return counts
end

local function bitmap_byte(plane, x, y)
	local data = 0
	for bit = 0, 7 do
		data = data | ((planes:read_u8(plane * 1024 * 2048 + y * 1024 + x + bit) & 1) << bit)
	end
	return data
end

setup_return_xdata_tap = xdata:install_write_tap(
	0xf000, 0xffff, "setup_return_xdata_tap",
	function(offset, data, mask)
		local now = manager.machine.time:as_double()
		if (offset & 0xffe0) == 0xf080 or (offset & 0xffe0) == 0xf0a0 then
			if now >= trace_start then
				palette_writes = palette_writes + 1
				print(string.format(
					'VT340_SETUP_RETURN_JSON {"event":"palette","time":%.9f,"bank":"%s","index":%d,"data":"%02X"}',
					now, (offset & 0xffe0) == 0xf080 and "RG" or "GB", offset & 0x0f, data))
			end
			return
		end
		if offset >= 0xf060 and offset <= 0xf07f then
			viper_select = (((data >> 3) & 1) << 0) |
				(((data >> 2) & 1) << 1) |
				(((data >> 1) & 1) << 2) |
				(((data >> 0) & 1) << 3)
			return
		end
		if (offset & 0xf0c0) ~= 0xf000 then return end
		local reg = offset & 0x3f
		regs[reg] = (cpu2.state["P1"].value << 8) | data
		if reg == 0x08 and (regs[0x08] & 0xffe0) == 0x0180 then
			local viper_reg = regs[0x08] & 0x1f
			for plane = 0, 3 do
				if ((viper_select >> plane) & 1) ~= 0 then
					viper[plane + 1][viper_reg] = regs[0x07] or 0
				end
			end
		end
		if reg == 0x08 and now >= trace_start and now <= trace_end then
			local command = regs[0x08]
			if command == 0x07e1 then
				print(string.format(
					"VT340_SETUP_RETURN_PTB_CSR time=%.9f csr=[%04X,%04X,%04X,%04X] mask1=[%04X,%04X,%04X,%04X] mask2=[%04X,%04X,%04X,%04X]",
					now, viper[1][0x10 + (command & 7)] or 0,
					viper[2][0x10 + (command & 7)] or 0,
					viper[3][0x10 + (command & 7)] or 0,
					viper[4][0x10 + (command & 7)] or 0,
					viper[1][0x08] or 0, viper[2][0x08] or 0,
					viper[3][0x08] or 0, viper[4][0x08] or 0,
					viper[1][0x09] or 0, viper[2][0x09] or 0,
					viper[3][0x09] or 0, viper[4][0x09] or 0))
			end
			local operation = (command >> 8) & 3
			if operation ~= 2 and operation ~= 3 then return end
			command_count = command_count + 1
			if operation == 3 and (command & 0x0800) ~= 0 then
				local nonzero = { 0, 0, 0, 0 }
				local source_x = (regs[0x22] or 0) & 0x3fff
				local source_y = (regs[0x23] or 0) & 0x1fff
				local width = (regs[0x26] or 0) & 0x1fff
				local height = (regs[0x29] or 0) & 0x1fff
				if source_y < 0x1000 then
					for plane = 0, 3 do
						for y = source_y, math.min(source_y + height - 1, 2047) do
							for x = source_x, math.min(source_x + width - 1, 1023) do
								if (planes:read_u8(plane * 1024 * 2048 + y * 1024 + x) & 1) ~= 0 then
									nonzero[plane + 1] = nonzero[plane + 1] + 1
								end
							end
						end
					end
				end
				print(string.format(
					'VT340_SETUP_RETURN_JSON {"event":"btp_planes","time":%.9f,"source":[%d,%d],"extent":[%d,%d],"nonzero":[%d,%d,%d,%d]}',
					now, source_x, source_y, width, height,
					nonzero[1], nonzero[2], nonzero[3], nonzero[4]))
			end
			print(string.format(
				'VT340_SETUP_RETURN_JSON {"event":"command","id":%d,"time":%.9f,"pc":"%04X","raw":"%04X","operation":%d,"destination":%s,"source1":%s,"source2":%s,"x_control":"%04X","source":[%d,%d],"destination_origin":[%d,%d],"extent":[%d,%d],"deltas":["%04X","%04X","%04X","%04X"],"scale":["%04X","%04X"],"indexes":["%04X","%04X","%04X","%04X"],"viper_select":"%X","resolution":["%04X","%04X","%04X","%04X"],"bus_width":["%04X","%04X","%04X","%04X"],"logic":["%02X","%02X","%02X","%02X"],"csr4":["%04X","%04X","%04X","%04X"],"source_register":["%04X","%04X","%04X","%04X"],"background":["%04X","%04X","%04X","%04X"],"foreground":["%04X","%04X","%04X","%04X"]}',
				command_count, now, cpu2.state["PC"].value, command,
				operation, (command & 0x0400) ~= 0 and "true" or "false",
				(command & 0x0800) ~= 0 and "true" or "false",
				(command & 0x1000) ~= 0 and "true" or "false",
				regs[0x09] or 0, (regs[0x22] or 0) & 0x3fff, (regs[0x23] or 0) & 0x1fff,
				(regs[0x24] or 0) & 0x3fff, (regs[0x25] or 0) & 0x1fff,
				(regs[0x26] or 0) & 0x1fff, (regs[0x29] or 0) & 0x1fff,
				regs[0x20] or 0, regs[0x21] or 0, regs[0x27] or 0, regs[0x28] or 0,
				regs[0x2a] or 0, regs[0x2b] or 0,
				regs[0x17] or 0, regs[0x18] or 0, regs[0x19] or 0, regs[0x1a] or 0,
				viper_select,
				viper[1][0] or 0, viper[2][0] or 0, viper[3][0] or 0, viper[4][0] or 0,
				viper[1][1] or 0, viper[2][1] or 0, viper[3][1] or 0, viper[4][1] or 0,
				viper[1][4 + ((command >> 4) & 3)] or 0,
				viper[2][4 + ((command >> 4) & 3)] or 0,
				viper[3][4 + ((command >> 4) & 3)] or 0,
				viper[4][4 + ((command >> 4) & 3)] or 0,
				viper[1][0x14] or 0, viper[2][0x14] or 0,
				viper[3][0x14] or 0, viper[4][0x14] or 0,
				viper[1][0x0a] or 0, viper[2][0x0a] or 0,
				viper[3][0x0a] or 0, viper[4][0x0a] or 0,
				viper[1][0x0e] or 0, viper[2][0x0e] or 0,
				viper[3][0x0e] or 0, viper[4][0x0e] or 0,
				viper[1][0x0f] or 0, viper[2][0x0f] or 0,
				viper[3][0x0f] or 0, viper[4][0x0f] or 0))
		end
	end)

local function visible_hash()
	local hash = 0x811c9dc5
	local counts = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
	for y = 0, 499 do
		for x = 0, 799 do
			local address = y * 1024 + x
			local color = 0
			for plane = 0, 3 do
				color = color | ((planes:read_u8(plane * 1024 * 2048 + address) & 1) << plane)
			end
			counts[color + 1] = counts[color + 1] + 1
			hash = ((hash ~ color) * 0x01000193) & 0xffffffff
		end
	end
	return hash, counts
end

local actions = simple_return and {
	{ 130, "{TAB}", "leave_post" },
	{ 140, "{F3}", "enter_setup" },
	{ 160, "{F3}", "leave_setup" },
} or {
	{ 130, "{TAB}", "leave_post" },
	{ 140, "{F3}", "enter_setup" },
	{ 270, "{F3}", "leave_setup" },
}
local next_action = 1
local enter_pressed = false
local enter_released = false
local down_pulses = 0
local down_released = true
local right_pressed = false
local right_released = false
local capture_times = simple_return and { 135, 139, 150, 159, 160, 161, 162, 164 } or
	{ 260, 269, 270, 271, 272, 274, 276, 280, 284 }
local next_capture = 1

setup_return_attribute_tap = idata:install_write_tap(
	0x21, 0x21, "setup_return_attribute_tap",
	function(offset, data, mask)
		local now = manager.machine.time:as_double()
		if now >= trace_start and now <= trace_end then
			print(string.format(
				'VT340_SETUP_RETURN_ATTR time=%.9f pc=%04X value=%02X dptr=%04X r6=%02X r7=%02X',
				now, cpu2.state["PC"].value, data, cpu2.state["DPTR"].value,
				cpu2.state["R6"].value, cpu2.state["R7"].value))
		end
	end)

local function install_session_cell_taps(space, cpu, label)
	local taps = {}
	for _, base in ipairs({ 0x000c, 0x800c }) do
		taps[#taps + 1] = space:install_write_tap(
			base, base + 1, "setup_return_" .. label .. string.format("_%04x", base),
			function(offset, data, mask)
				print(string.format(
					"VT340_SETUP_RETURN_MODEL time=%.9f cpu=%s pc=%04X address=%04X data=%02X",
					manager.machine.time:as_double(), label, cpu.state["PC"].value, offset, data))
			end)
	end
	return taps
end

setup_return_cpu1_model_taps = install_session_cell_taps(cpu1_xdata, cpu1, "cpu1")
setup_return_cpu2_model_taps = install_session_cell_taps(xdata, cpu2, "cpu2")

if breakpoint_trace then
	local debugger = manager.machine.debugger
	local points = {
		[0xce04] = "session_model_saved",
		[0x11c8] = "buffered_cell_entry", [0x11cb] = "buffered_cell_done",
		[0xc194] = "normal_cell_entry", [0xc1bb] = "normal_cell_done",
		[0xc1bc] = "alternate_cell_entry", [0xc1bf] = "alternate_skip_decision",
		[0xc1fa] = "alternate_cell_done", [0xc217] = "raster_command_done"
	}
	local instruction_trace = false
	for pc, _ in pairs(points) do cpu2.debug:bpset(pc) end
	emu.register_periodic(function()
		if debugger.execution_state ~= "stop" then return end
		local now = manager.machine.time:as_double()
		local pc = cpu2.state["PC"].value
		local row = cpu2.state["R6"].value
		local column = cpu2.state["R7"].value
		local destination_x = (regs[0x24] or 0) & 0x3fff
		local destination_y = (regs[0x25] or 0) & 0x1fff
		if now >= 140 and now <= 141 and pc == 0xce04 then
			local dptr = cpu2.state["DPTR"].value
			if dptr >= 0x000c and dptr <= 0x000d or dptr >= 0x800c and dptr <= 0x800d then
				print(string.format(
					"VT340_SETUP_RETURN_SAVE_STEP time=%.9f dptr=%04X a=%02X p1=%02X cell12=[%02X,%02X] cell13=[%02X,%02X]",
					now, dptr, cpu2.state["A"].value, cpu2.state["P1"].value,
					bitmap_byte(0, 808, 382), bitmap_byte(0, 816, 382),
					bitmap_byte(0, 824, 382), bitmap_byte(0, 832, 382)))
			end
		end
		if now >= 160 and now <= 161 and pc == 0xc217 and destination_y == 0 and
			(destination_x == 110 or destination_x == 130) then
			print(string.format(
				'VT340_SETUP_RETURN_SESSION time=%.9f pc=%04X destination=[%d,%d] source=[%d,%d] row=%d column=%d a=%02X r3=%02X attr21=%02X attr28=%02X dptr=%04X',
				now, pc, destination_x, destination_y,
				(regs[0x22] or 0) & 0x3fff, (regs[0x23] or 0) & 0x1fff,
				row, column, cpu2.state["A"].value, cpu2.state["R3"].value,
				idata:read_u8(0x21), idata:read_u8(0x28), cpu2.state["DPTR"].value))
			if destination_x == 110 and not instruction_trace then
				instruction_trace = true
				debugger:command(
					'trace /tmp/vt340-setup-return-session-gap.tr,cpu2,,{tracelog "A=%02X B=%02X R3=%02X R6=%02X R7=%02X DPTR=%04X P1=%02X PSW=%02X ",a,b,r3,r6,r7,dptr,p1,psw}')
			elseif destination_x == 130 and instruction_trace then
				debugger:command("trace off,cpu2")
			end
		end
		if now >= 160 and now <= 161 and column >= 10 and column <= 14 then
			local dptr = cpu2.state["DPTR"].value
			print(string.format(
				'VT340_SETUP_RETURN_CELL time=%.9f event=%s pc=%04X row=%d column=%d a=%02X r3=%02X attr21=%02X attr28=%02X dptr=%04X table_char=%02X table_attribute=%02X',
				now, points[pc], pc, row, column, cpu2.state["A"].value,
				cpu2.state["R3"].value, idata:read_u8(0x21), idata:read_u8(0x28), dptr,
				xdata:read_u8(0x4ac6 + column), xdata:read_u8(0xcac6 + column)))
		end
		debugger.execution_state = "run"
	end)
	debugger.execution_state = "run"
end

emu.register_frame_done(function()
	local now = manager.machine.time:as_double()
	while next_action <= #actions and now >= actions[next_action][1] do
		local action = actions[next_action]
		keyboard:post_coded(action[2])
		print(string.format(
			'VT340_SETUP_RETURN_JSON {"event":"key","time":%.9f,"label":"%s","code":"%s"}',
			now, action[3], action[2]))
		next_action = next_action + 1
	end
	if not simple_return and not enter_pressed and now >= 142 then
		setup_enter:set_value(1)
		enter_pressed = true
	elseif enter_pressed and not enter_released and now >= 142.5 then
		setup_enter:set_value(0)
		enter_released = true
	end
	local next_down_time = 190 + down_pulses * 5
	if not simple_return and down_pulses < 7 and down_released and now >= next_down_time then
		setup_down:set_value(1)
		down_released = false
	elseif down_pulses < 7 and not down_released and now >= next_down_time + 0.5 then
		setup_down:set_value(0)
		down_released = true
		down_pulses = down_pulses + 1
	end
	if not simple_return and not right_pressed and now >= 235 then
		setup_right:set_value(1)
		right_pressed = true
	elseif right_pressed and not right_released and now >= 235.5 then
		setup_right:set_value(0)
		right_released = true
	end
	while next_capture <= #capture_times and now >= capture_times[next_capture] do
		local target = capture_times[next_capture]
		local hash, counts = visible_hash()
		local count_text = {}
		for index = 1, #counts do count_text[index] = tostring(counts[index]) end
		local path = string.format("/tmp/vt340-setup-return-%03d.png", target)
		screen:snapshot(path)
		print(string.format(
			'VT340_SETUP_RETURN_JSON {"event":"capture","time":%.9f,"target":%d,"hash":"%08X","counts":[%s],"state":"%02X","y_offset":"%04X","y_scroll":"%04X","path":"%s"}',
			now, target, hash, table.concat(count_text, ","), cpu1_xdata:read_u8(0x4c00),
			regs[0x13] or 0, regs[0x14] or 0, path))
		local saved = rectangle_nonzero(808, 381, 192, 264)
		print(string.format(
			"VT340_SETUP_RETURN_SAVED time=%.9f target=%d nonzero=[%d,%d,%d,%d] cell12=[%02X,%02X] cell13=[%02X,%02X]",
			now, target, saved[1], saved[2], saved[3], saved[4],
			bitmap_byte(0, 808, 382), bitmap_byte(0, 816, 382),
			bitmap_byte(0, 824, 382), bitmap_byte(0, 832, 382)))
		for y = 1504, 1530 do
			print(string.format(
				'VT340_SETUP_RETURN_ROW time=%.9f target=%d y=%d runs=%s',
				now, target, y, row_runs(y)))
		end
		next_capture = next_capture + 1
	end
end)

emu.add_machine_stop_notifier(function()
	print(string.format(
		'VT340_SETUP_RETURN_JSON {"event":"summary","commands":%d,"palette_writes":%d}',
		command_count, palette_writes))
end)

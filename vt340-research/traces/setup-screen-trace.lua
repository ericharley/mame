-- Exercise the native VT340 Set-Up path and record the DC323 completion
-- conditions that allow foreground firmware processing to continue.

io.stdout:setvbuf("no")

local cpu1 = manager.machine.devices[":cpu1"]
local cpu2 = manager.machine.devices[":cpu2"]
local cpu1_sfr = cpu1.spaces["sfr"]
local cpu1_xdata = cpu1.spaces["xdata"]
local cpu2_xdata = cpu2.spaces["xdata"]
local cpu2_idata = cpu2.spaces["idata"]
local keyboard = manager.machine.natkeyboard
local planes = manager.machine.memory.shares[":bitmap_planes"]
local screen = manager.machine.screens[":screen"]

keyboard.in_use = true

local setup_key_seen = false
local initialization_ready_seen = false
local fifo_ready_seen = false

if os.getenv("VT340_TRACE_MODEL_SELECT") == "1" then
	setup_model_p1_read_tap = cpu1_sfr:install_read_tap(
		0x90, 0x90, "setup_model_p1_read_tap",
		function(offset, data, mask)
			local pc = cpu1.state["PC"].value
			if pc >= 0x39d0 and pc <= 0x3a08 then
				print(string.format(
					'VT340_SETUP_JSON {"event":"model_p1_read","time":%.9f,"pc":"%04X","data":"%02X"}',
					manager.machine.time:as_double(), pc, data))
			end
			if os.getenv("VT340_FORCE_MODEL_SELECT") == "1" and pc == 0x3a06 then
				return data & ~0x40
			end
		end)
	setup_model_p1_write_tap = cpu1_sfr:install_write_tap(
		0x90, 0x90, "setup_model_p1_write_tap",
		function(offset, data, mask)
			local now = manager.machine.time:as_double()
			if now <= 9 then
				print(string.format(
					'VT340_SETUP_JSON {"event":"model_p1_write","time":%.9f,"pc":"%04X","data":"%02X"}',
					now, cpu1.state["PC"].value, data))
			end
		end)
	setup_model_value_tap = cpu1_xdata:install_write_tap(
		0xe795, 0xe795, "setup_model_value_tap",
		function(offset, data, mask)
			print(string.format(
				'VT340_SETUP_JSON {"event":"model_select","time":%.9f,"pc":"%04X","p1":"%02X","value":"%02X"}',
				manager.machine.time:as_double(), cpu1.state["PC"].value,
				cpu1.state["P1"].value, data))
		end)
end

setup_keyboard_tap = cpu1_sfr:install_read_tap(
	0x99, 0x99, "setup_keyboard_tap",
	function(offset, data, mask)
		if manager.machine.time:as_double() >= 139 and data == 0x58 then
			setup_key_seen = true
			print(string.format(
				'VT340_SETUP_JSON {"event":"setup_key","time":%.9f,"pc":"%04X","data":"%02X"}',
				manager.machine.time:as_double(), cpu1.state["PC"].value, data))
		end
	end)

setup_status_tap = cpu2_xdata:install_read_tap(
	0xf003, 0xf003, "setup_status_tap",
	function(offset, data, mask)
		local pc = cpu2.state["PC"].value
		if pc == 0xef12 and (data & 0x04) ~= 0 then
			initialization_ready_seen = true
		elseif pc == 0x2b30 and (data & 0x20) ~= 0 then
			fifo_ready_seen = true
		end
	end)

local function visible_state()
	local hash = 0x811c9dc5
	local lit = 0
	for y = 0, 499 do
		local row = y * 1024
		for x = 0, 799, 8 do
			local combined = 0
			for plane = 0, 3 do
				combined = combined | planes:read_u64(plane * 1024 * 2048 + row + x)
			end
			hash = ((hash ~ combined ~ (combined >> 32)) * 0x01000193) & 0xffffffff
			for bit = 0, 7 do
				if ((combined >> (bit * 8)) & 0xff) ~= 0 then
					lit = lit + 1
				end
			end
		end
	end
	return hash, lit
end

local actions = {
	{ time = 130, code = "{TAB}", label = "leave_post" },
	{ time = 140, code = "{F3}", label = "setup" }
}
local next_action = 1
local captured = false

emu.register_frame_done(function()
	local now = manager.machine.time:as_double()
	while next_action <= #actions and now >= actions[next_action].time do
		local action = actions[next_action]
		keyboard:post_coded(action.code)
		print(string.format(
			'VT340_SETUP_JSON {"event":"key_post","time":%.9f,"label":"%s","code":"%s"}',
			now, action.label, action.code))
		next_action = next_action + 1
	end
	if not captured and now >= 142 then
		if os.getenv("VT340_TRACE_MODEL_FLAG") == "1" then
			local model_state = cpu2_idata:read_u8(0x20)
			print(string.format(
				'VT340_SETUP_JSON {"event":"model_flag","time":%.9f,"iram20":"%02X","color":%s}',
				now, model_state, (model_state & 0x20) ~= 0 and "true" or "false"))
		end
		local hash, lit = visible_state()
		local path = "/tmp/vt340-setup-screen.png"
		screen:snapshot(path)
		print(string.format(
			'VT340_SETUP_JSON {"event":"summary","time":%.9f,"setup_key":%s,"initialization_ready":%s,"fifo_ready":%s,"visible_hash":"%08X","lit_pixels":%d,"cpu1_pc":"%04X","cpu2_pc":"%04X","barrier_4be5":"%02X","path":"%s"}',
			now,
			setup_key_seen and "true" or "false",
			initialization_ready_seen and "true" or "false",
			fifo_ready_seen and "true" or "false",
			hash, lit, cpu1.state["PC"].value, cpu2.state["PC"].value,
			cpu1_xdata:read_u8(0x4be5), path))
		captured = true
	end
end)

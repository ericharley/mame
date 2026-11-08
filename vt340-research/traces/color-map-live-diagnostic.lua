-- Exercise the native Color Set-Up palette editor and capture its immediate
-- redraw behavior using only ordinary LK201 key input.

io.stdout:setvbuf("no")

local keyboard = manager.machine.natkeyboard
local screen = manager.machine.screens[":screen"]
local cpu2 = manager.machine.devices[":cpu2"]
local cpu2_xdata = cpu2.spaces["xdata"]
local artifact_dir = os.getenv("VT340_TEST_ARTIFACT_DIR")
keyboard.in_use = true

local function artifact_path(name)
	if artifact_dir and artifact_dir ~= "" then return artifact_dir .. "/" .. name end
	return "/tmp/" .. name
end

local actions = {
	{ time = 18, code = "{TAB}", label = "leave_post" },
	{ time = 20, code = "{F3}", label = "setup" },
}

local function pulse(time, port, field, label)
	table.insert(actions, { time = time, port = port, field = field, value = 1, label = label })
	table.insert(actions, { time = time + 0.2, port = port, field = field, value = 0, label = label .. "_release" })
end

pulse(22, ":keyboard:KBD15", "Right", "right_column")
for index = 1, 5 do
	pulse(22 + index, ":keyboard:KBD16", "Down", "down_" .. index)
end
pulse(29, ":keyboard:KBD17", "Enter", "open_color")
pulse(31, ":keyboard:KBD16", "Down", "select_color_0")
pulse(33, ":keyboard:KBD16", "Down", "select_red")
pulse(35, ":keyboard:KBD15", "Right", "increase_red")
pulse(37, ":keyboard:KBD16", "Down", "select_green")

table.sort(actions, function(left, right) return left.time < right.time end)
local next_action = 1
local captures = { 30, 32, 34, 36, 38 }
local next_capture = 1

color_map_palette_tap = cpu2_xdata:install_write_tap(
	0xf080, 0xf0bf, "color_map_palette_tap",
	function(offset, data, mask)
		if manager.machine.time:as_double() >= 29 then
			print(string.format(
				"VT340_COLOR_MAP time=%.9f palette=%04X data=%02X pc=%04X",
				manager.machine.time:as_double(), offset, data, cpu2.state["PC"].value))
		end
	end)

emu.register_frame_done(function()
	local now = manager.machine.time:as_double()
	while next_action <= #actions and now >= actions[next_action].time do
		local action = actions[next_action]
		if action.code then
			keyboard:post_coded(action.code)
		else
			manager.machine.ioport.ports[action.port].fields[action.field]:set_value(action.value)
		end
		print(string.format("VT340_COLOR_MAP time=%.9f action=%s", now, action.label))
		next_action = next_action + 1
	end
	while next_capture <= #captures and now >= captures[next_capture] do
		local capture = captures[next_capture]
		local path = artifact_path(string.format("color-map-%02d.png", capture))
		screen:snapshot(path)
		print(string.format(
			'VT340_COLOR_MAP_JSON {"event":"capture","time":%.9f,"capture":%d,' ..
			'"color0":"%08X","red0":"%08X","red1":"%08X","green0":"%08X","path":"%s"}',
			now, capture, screen:pixel(12, 105), screen:pixel(101, 281),
			screen:pixel(130, 281), screen:pixel(101, 310), path))
		next_capture = next_capture + 1
	end
end)

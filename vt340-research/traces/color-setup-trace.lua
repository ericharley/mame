-- Exercise the native VT340 Global Set-Up color-map selection.  This script
-- drives only LK201 keys and observes the firmware-owned configuration state.

io.stdout:setvbuf("no")

local keyboard = manager.machine.natkeyboard
local screen = manager.machine.screens[":screen"]
local cpu1_xdata = manager.machine.devices[":cpu1"].spaces["xdata"]
local setup_enter = manager.machine.ioport.ports[":keyboard:KBD17"].fields["Enter"]
local setup_down = manager.machine.ioport.ports[":keyboard:KBD16"].fields["Down"]
local setup_right = manager.machine.ioport.ports[":keyboard:KBD15"].fields["Right"]

keyboard.in_use = true

local actions = {
	{ 130, "{TAB}", "leave_post" },
	{ 140, "{F3}", "setup" },
	{ 270, "{F3}", "leave_setup" },
}
local next_action = 1
local captured = false
local global_captured = false
local color_captured = false
local enter_pressed = false
local enter_released = false
local down_pulses = 0
local down_released = true
local right_pressed = false
local right_released = false

emu.register_frame_done(function()
	local now = manager.machine.time:as_double()
	if not enter_pressed and now >= 142 then
		setup_enter:set_value(1)
		enter_pressed = true
		print(string.format(
			'VT340_COLOR_SETUP_JSON {"event":"key","time":%.9f,"label":"open_global","code":"LK201_ENTER"}',
			now))
	end
	if enter_pressed and not enter_released and now >= 142.5 then
		setup_enter:set_value(0)
		enter_released = true
	end
	local next_down_time = 190 + down_pulses * 5
	if down_pulses < 7 and down_released and now >= next_down_time then
		setup_down:set_value(1)
		down_released = false
		print(string.format(
			'VT340_COLOR_SETUP_JSON {"event":"key","time":%.9f,"label":"down_%d","code":"LK201_DOWN"}',
			now, down_pulses + 1))
	end
	if not down_released and now >= next_down_time + 0.5 then
		setup_down:set_value(0)
		down_released = true
		down_pulses = down_pulses + 1
	end
	if not right_pressed and now >= 235 then
		setup_right:set_value(1)
		right_pressed = true
		print(string.format(
			'VT340_COLOR_SETUP_JSON {"event":"key","time":%.9f,"label":"select_color","code":"LK201_RIGHT"}',
			now))
	end
	if right_pressed and not right_released and now >= 235.5 then
		setup_right:set_value(0)
		right_released = true
	end
	while next_action <= #actions and now >= actions[next_action][1] do
		local action = actions[next_action]
		keyboard:post_coded(action[2])
		print(string.format(
			'VT340_COLOR_SETUP_JSON {"event":"key","time":%.9f,"label":"%s","code":"%s"}',
			now, action[3], action[2]))
		next_action = next_action + 1
	end
	if not global_captured and now >= 185 then
		screen:snapshot("/tmp/vt340-global-setup.png")
		global_captured = true
	end
	if not color_captured and now >= 260 then
		screen:snapshot("/tmp/vt340-global-color.png")
		color_captured = true
	end
	if not captured and now >= 280 then
		screen:snapshot("/tmp/vt340-color-setup.png")
		print(string.format(
			'VT340_COLOR_SETUP_JSON {"event":"capture","time":%.9f,"config_7b00":"%02X","state_4c00":"%02X"}',
			now, cpu1_xdata:read_u8(0x7b00), cpu1_xdata:read_u8(0x4c00)))
		captured = true
	end
end)

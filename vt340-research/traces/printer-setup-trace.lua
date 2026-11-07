-- Enter the native Printer Set-Up screen and capture its current choices.

io.stdout:setvbuf("no")

local keyboard = manager.machine.natkeyboard
local screen = manager.machine.screens[":screen"]
local down = manager.machine.ioport.ports[":keyboard:KBD16"].fields["Down"]
local enter = manager.machine.ioport.ports[":keyboard:KBD17"].fields["Enter"]
local right = manager.machine.ioport.ports[":keyboard:KBD15"].fields["Right"]
local actions = {}
local next_action = 1
local captured = false

keyboard.in_use = true

local function key(time, field)
	table.insert(actions, { time = time, field = field, value = 1 })
	table.insert(actions, { time = time + 0.2, field = field, value = 0 })
end

table.insert(actions, { time = 130, code = "{TAB}" })
table.insert(actions, { time = 140, code = "{F3}" })
for index = 0, 3 do
	key(142 + index, down)
end
key(147, enter)
for index = 0, 5 do
	key(152 + index, down)
end
key(159, right)
key(160, right)

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
	if not captured and now >= 162 then
		screen:snapshot("/tmp/vt340-printer-setup.png")
		print("VT340_PRINTER_SETUP_CAPTURE")
		captured = true
	end
	if now >= 163 then
		manager.machine:exit()
	end
end)

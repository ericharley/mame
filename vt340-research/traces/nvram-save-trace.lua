-- Change one native Set-Up value and save it through the firmware's E80 path.

io.stdout:setvbuf("no")

local cpu1 = manager.machine.devices[":cpu1"]
local cpu1_xdata = cpu1.spaces["xdata"]
local keyboard = manager.machine.natkeyboard

keyboard.in_use = true

local writes = {}
nvram_save_write_tap = cpu1_xdata:install_write_tap(
	0xf000, 0xf1ff, "nvram_save_write_tap",
	function(offset, data, mask)
		if (cpu1.state["P1"].value & 0x08) == 0 then
			writes[offset] = data
			print(string.format(
				"VT340_NVRAM_WRITE time=%.9f pc=%04X offset=%04X data=%02X",
				manager.machine.time:as_double(), cpu1.state["PC"].value, offset, data))
		end
	end)

local actions = {}

local function coded(time, code)
	table.insert(actions, { time = time, kind = "coded", code = code })
end

local function key(time, port, field)
	table.insert(actions, { time = time, kind = "field", port = port, field = field, value = 1 })
	table.insert(actions, { time = time + 0.2, kind = "field", port = port, field = field, value = 0 })
end

coded(130, "{TAB}")
coded(140, "{F3}")
key(143, ":keyboard:KBD17", "Enter") -- open Global Set-Up
key(148, ":keyboard:KBD15", "Right") -- on-line -> local
key(152, ":keyboard:KBD12", "Select") -- return to directory
key(157, ":keyboard:KBD15", "Right") -- right-hand directory column
for index = 1, 5 do
	key(157 + index, ":keyboard:KBD16", "Down")
end
key(165, ":keyboard:KBD17", "Enter") -- Save Current Settings

local next_action = 1
local reported = false

emu.register_frame_done(function()
	local now = manager.machine.time:as_double()
	while next_action <= #actions and now >= actions[next_action].time do
		local action = actions[next_action]
		if action.kind == "coded" then
			keyboard:post_coded(action.code)
		else
			manager.machine.ioport.ports[action.port].fields[action.field]:set_value(action.value)
		end
		next_action = next_action + 1
	end

	if not reported and now >= 170 then
		print(string.format(
			"VT340_NVRAM_SAVE_SUMMARY byte_06c=%02X byte_06d=%02X",
			writes[0xf06c] or 0xff, writes[0xf06d] or 0xff))
		reported = true
	end
end)

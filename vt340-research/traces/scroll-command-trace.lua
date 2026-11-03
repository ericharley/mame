-- Observe native VT340 scroll programming while host text is received.
-- This script posts only the key that leaves the POST screen; it does not
-- alter graphics registers or framebuffer memory.

io.stdout:setvbuf("no")

local cpu2 = manager.machine.devices[":cpu2"]
local xdata = cpu2.spaces["xdata"]
local keyboard = manager.machine.natkeyboard
local screen = manager.machine.screens[":screen"]
local registers = {}
local viper = {}
local left_post = false
local captures = {
	{ time = 140, name = "before-host" },
	{ time = 170, name = "after-host" },
	{ time = 200, name = "settled" }
}
local next_capture = 1

keyboard.in_use = true

scroll_trace = xdata:install_write_tap(
	0xf000, 0xffff, "vt340_scroll_command_trace",
	function(offset, data, mask)
		if (offset & 0xf0c0) ~= 0xf000 then
			return
		end

		local register = offset & 0x3f
		local value = (cpu2.state["P1"].value << 8) | data
		registers[register] = value

		if register == 0x08 and (value & 0xffe0) == 0x0180 then
			viper[value & 0x1f] = registers[0x07] or 0
		elseif register == 0x14 and manager.machine.time:as_double() >= 125 then
			print(string.format(
				'SCROLL_JSON {"time":%.9f,"pc":"%04X","x":[%d,%d],"y":[%d,%d],"y_offset":%d,"constant":"%04X","distance":%d,"down":%s,"erase":%s,"viper_constant":"%04X","fill":"%04X","left_mask":"%04X","right_mask":"%04X","indexes":["%04X","%04X","%04X","%04X","%04X","%04X"]}',
				manager.machine.time:as_double(), cpu2.state["PC"].value,
				(registers[0x0e] or 0) & 0x3fff, (registers[0x0f] or 0) & 0x3fff,
				(registers[0x10] or 0) & 0x1fff, (registers[0x11] or 0) & 0x1fff,
				(registers[0x13] or 0) & 0x1fff, value,
				value & 0x0fff,
				(value & 0x1000) ~= 0 and "true" or "false",
				(value & 0x2000) ~= 0 and "true" or "false",
				viper[0x02] or 0,
				viper[0x0b] or 0,
				viper[0x0c] or 0, viper[0x0d] or 0,
				registers[0x15] or 0, registers[0x16] or 0,
				registers[0x17] or 0, registers[0x18] or 0,
				registers[0x19] or 0, registers[0x1a] or 0))
		end
	end)

emu.register_frame_done(function()
	local now = manager.machine.time:as_double()
	if not left_post and now >= 130 then
		keyboard:post_coded("{TAB}")
		left_post = true
		print(string.format('SCROLL_JSON {"time":%.9f,"event":"leave_post"}', now))
	end

	while next_capture <= #captures and now >= captures[next_capture].time do
		local capture = captures[next_capture]
		local path = string.format("/tmp/vt340-scroll-%s.png", capture.name)
		screen:snapshot(path)
		print(string.format(
			'SCROLL_JSON {"time":%.9f,"event":"snapshot","path":"%s"}',
			now, path))
		next_capture = next_capture + 1
	end
end)

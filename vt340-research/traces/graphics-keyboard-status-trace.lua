-- Reproduce status-line behavior using the ROM-driven LK201 and native CPU1
-- UART.  This script posts ordinary emulated keys and only observes results.

dofile("vt340-research/traces/graphics-command-trace.lua")

local cpu1 = manager.machine.devices[":cpu1"]
local sfr = cpu1.spaces["sfr"]
local screen = manager.machine.screens[":screen"]
local planes = manager.machine.memory.shares[":bitmap_planes"]
local keyboard = manager.machine.natkeyboard

keyboard.in_use = true
print(string.format(
	'VT340_KEY_JSON {"event":"keyboard_ready","can_post":%s,"dump":%q}',
	keyboard.can_post and "true" or "false", keyboard:dump()))

local function status_hash()
	local hash = 0x811c9dc5
	for plane = 0, 3 do
		local plane_base = plane * 1024 * 2048
		for y = 480, 499 do
			local row = plane_base + y * 1024
			for x = 0, 799, 8 do
				local word = planes:read_u64(row + x)
				hash = ((hash ~ word ~ (word >> 32)) * 0x01000193) & 0xffffffff
			end
		end
	end
	return hash
end

graphics_keyboard_sbuf = sfr:install_read_tap(
	0x99, 0x99, "graphics_keyboard_sbuf",
	function(offset, data, mask)
		if manager.machine.time:as_double() < 125 then return end
		print(string.format(
			'VT340_KEY_JSON {"event":"cpu1_sbuf_read","time":%.9f,"pc":"%04X","data":"%02X"}',
			manager.machine.time:as_double(), cpu1.state["PC"].value, data))
	end)

local actions = {
	{ time = 130, code = "{TAB}", label = "tab_1" },
	{ time = 140, code = "{TAB}", label = "tab_2" },
	{ time = 150, code = "a",     label = "a" },
	{ time = 160, code = "{ESC}", label = "escape" }
}
local captures = { 129, 132, 139, 142, 149, 152, 159, 162, 180 }
local next_action = 1
local next_capture = 1

emu.register_frame_done(function()
	local now = manager.machine.time:as_double()
	while next_action <= #actions and now >= actions[next_action].time do
		local action = actions[next_action]
		keyboard:post_coded(action.code)
		print(string.format(
			'VT340_KEY_JSON {"event":"key_post","time":%.9f,"label":"%s","code":"%s","status_hash":"%08X"}',
			now, action.label, action.code, status_hash()))
		next_action = next_action + 1
	end
	while next_capture <= #captures and now >= captures[next_capture] do
		local capture = captures[next_capture]
		local path = string.format("/tmp/vt340-keyboard-status-%03d.png", capture)
		screen:snapshot(path)
		print(string.format(
			'VT340_KEY_JSON {"event":"snapshot","time":%.9f,"target_time":%d,"status_hash":"%08X","path":"%s"}',
			now, capture, status_hash(), path))
		next_capture = next_capture + 1
	end
end)

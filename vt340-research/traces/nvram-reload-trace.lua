-- Verify that a later cold boot reads the settings saved in E80.

io.stdout:setvbuf("no")

local cpu1 = manager.machine.devices[":cpu1"]
local cpu1_xdata = cpu1.spaces["xdata"]
local keyboard = manager.machine.natkeyboard
local planes = manager.machine.memory.shares[":bitmap_planes"]

keyboard.in_use = true

local reads = {}
nvram_reload_read_tap = cpu1_xdata:install_read_tap(
	0xf000, 0xf1ff, "nvram_reload_read_tap",
	function(offset, data, mask)
		if (cpu1.state["P1"].value & 0x08) == 0 then
			if offset == 0xf06c or offset == 0xf06d then
				reads[offset] = data
			end
		end
	end)

local function visible_hash()
	local hash = 0x811c9dc5
	for y = 0, 499 do
		local row = y * 1024
		for x = 0, 799, 8 do
			local combined = 0
			for plane = 0, 3 do
				combined = combined | planes:read_u64(plane * 1024 * 2048 + row + x)
			end
			hash = ((hash ~ combined ~ (combined >> 32)) * 0x01000193) & 0xffffffff
		end
	end
	return hash
end

local actions = {
	{ time = 130, kind = "coded", code = "{TAB}" },
	{ time = 140, kind = "coded", code = "{F3}" },
	{ time = 143, kind = "field", value = 1 },
	{ time = 143.2, kind = "field", value = 0 }
}
local next_action = 1
local reported = false

emu.register_frame_done(function()
	local now = manager.machine.time:as_double()
	while next_action <= #actions and now >= actions[next_action].time do
		local action = actions[next_action]
		if action.kind == "coded" then
			keyboard:post_coded(action.code)
		else
			manager.machine.ioport.ports[":keyboard:KBD17"].fields["Enter"]:set_value(action.value)
		end
		next_action = next_action + 1
	end

	if not reported and now >= 148 then
		print(string.format(
			"VT340_NVRAM_RELOAD_SUMMARY byte_06c=%02X byte_06d=%02X visible_hash=%08X",
			reads[0xf06c] or 0xff, reads[0xf06d] or 0xff, visible_hash()))
		reported = true
	end
end)

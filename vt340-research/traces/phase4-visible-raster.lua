-- Capture the DC323 state used by the first post-command-32 visible rasterops.

local cpu2 = manager.machine.devices[":cpu2"]
local xdata = cpu2.spaces["xdata"]
local regs = {}
local commands = 0

phase4_visible_raster_tap = xdata:install_write_tap(
	0xf000, 0xffff, "phase4_visible_raster",
	function(offset, data, mask)
		if (offset & 0xf0c0) ~= 0xf000 then return end
		local reg = offset & 0x3f
		local value = (cpu2.state["P1"].value << 8) | data
		regs[reg] = value
		local now = manager.machine.time:as_double()
		if reg ~= 0x08 or now < 121.7 or commands >= 256 then return end
		local rasterop = ((value >> 8) & 3) == 2
		if not rasterop then return end
		commands = commands + 1
		local sx = (regs[0x22] or 0) & 0x3fff
		local sy = (regs[0x23] or 0) & 0x1fff
		local glyph = -1
		if (sy & 0x1000) ~= 0 then
			glyph = ((sy & 0x0fff) // 20) * 16 + (sx // 16)
		end
		print(string.format(
			"PHASE4_VISIBLE_RASTER t=%.9f pc=%04X command=%04X mode=%04X sx=%04X sy=%04X glyph=%02X dx=%04X dy=%04X width=%04X height=%04X",
			now, cpu2.state["PC"].value, value, regs[0x09] or 0,
			sx, sy, glyph, regs[0x24] or 0, regs[0x25] or 0,
			regs[0x26] or 0, regs[0x29] or 0))
	end)

phase4_visible_raster_stop = emu.add_machine_stop_notifier(function()
	print(string.format("PHASE4_VISIBLE_RASTER_DONE commands=%d", commands))
end)

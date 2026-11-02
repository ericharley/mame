-- Inventory writers of the first shared display-buffer byte.

local cpu1 = manager.machine.devices[":cpu1"]
local cpu2 = manager.machine.devices[":cpu2"]
local xdata1 = cpu1.spaces["xdata"]
local xdata2 = cpu2.spaces["xdata"]
local writes34 = 0

local function log_write(owner, offset, value)
	local now = manager.machine.time:as_double()
	print(string.format(
		"PHASE4_SHARED0000 t=%.9f event=write owner=%s cpu1=%04X cpu2=%04X value=%02X",
		now, owner, cpu1.state["PC"].value, cpu2.state["PC"].value,
		value))
	if value == 0x34 then writes34 = writes34 + 1 end
end

phase4_shared0000_cpu1_write = xdata1:install_write_tap(
	0x0000, 0x0000, "phase4_shared0000_cpu1_write",
	function(offset, value, mask) log_write("cpu1", offset, value) end)

phase4_shared0000_cpu2_write = xdata2:install_write_tap(
	0x0000, 0x0000, "phase4_shared0000_cpu2_write",
	function(offset, value, mask) log_write("cpu2", offset, value) end)

phase4_shared0000_cpu2_read = xdata2:install_read_tap(
	0x0000, 0x0000, "phase4_shared0000_cpu2_read",
	function(offset, value, mask)
		if cpu2.state["PC"].value == 0xdec3 then
			print(string.format(
				"PHASE4_SHARED0000 t=%.9f event=glyph_read cpu1=%04X cpu2=%04X value=%02X",
				manager.machine.time:as_double(), cpu1.state["PC"].value,
				cpu2.state["PC"].value, value))
		end
	end)

phase4_shared0000_stop = emu.add_machine_stop_notifier(function()
	print(string.format("PHASE4_SHARED0000_DONE writes34=%d final=%02X",
		writes34, xdata2:read_u8(0x0000)))
end)

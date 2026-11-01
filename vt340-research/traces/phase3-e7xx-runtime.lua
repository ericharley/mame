local cpu1 = manager.machine.devices[":cpu1"]
local xdata = cpu1.spaces["xdata"]
local accesses = 0

local function report(kind, offset, data)
	if manager.machine.time:as_double() < 8.0 then
		return
	end
	accesses = accesses + 1
	if accesses <= 256 then
		print(string.format(
			"PHASE3_E7XX_%s t=%.9f pc=%04X address=%04X data=%02X P1=%02X",
			kind, manager.machine.time:as_double(), cpu1.state["PC"].value,
			offset, data, cpu1.state["P1"].value))
	end
end

phase3_e7xx_read_tap = xdata:install_read_tap(
	0xe600, 0xe7ff, "phase3_e7xx_read",
	function(offset, data, mask)
		report("READ", offset, data)
	end)

phase3_e7xx_write_tap = xdata:install_write_tap(
	0xe600, 0xe7ff, "phase3_e7xx_write",
	function(offset, data, mask)
		report("WRITE", offset, data)
	end)

phase3_e7xx_stop_subscription = emu.add_machine_stop_notifier(function()
	print(string.format("PHASE3_E7XX_SUMMARY accesses=%d", accesses))
end)

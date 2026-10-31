local cpu = manager.machine.devices[":cpu2"]
local reported = false

emu.register_periodic(function()
	if not reported and cpu.state["PC"].value == 0x2900 then
		emu.print_info(string.format(
			"CPU2 ready wait A=%02X DPTR=%04X P1=%02X P3=%02X IE=%02X TCON=%02X",
			cpu.state["A"].value,
			cpu.state["DPTR"].value,
			cpu.state["P1"].value,
			cpu.state["P3"].value,
			cpu.state["IE"].value,
			cpu.state["TCON"].value))
		reported = true
	end
end)

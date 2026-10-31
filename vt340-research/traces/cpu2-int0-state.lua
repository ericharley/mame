local cpu = manager.machine.devices[":cpu2"]
local reported = false

emu.register_periodic(function()
	if not reported and cpu.state["PC"].value == 0x3106 then
		emu.print_info(string.format(
			"CPU2 wait PC=%04X IE=%02X TCON=%02X PSW=%02X SP=%02X",
			cpu.state["PC"].value,
			cpu.state["IE"].value,
			cpu.state["TCON"].value,
			cpu.state["PSW"].value,
			cpu.state["SP"].value))
		reported = true
	end
end)

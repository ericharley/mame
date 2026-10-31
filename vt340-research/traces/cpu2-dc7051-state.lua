local cpu = manager.machine.devices[":cpu2"]
local reported_wait = false
local reported_failure = false

emu.register_periodic(function()
	if not reported_wait and cpu.state["PC"].value == 0xbbb3 then
		emu.print_info(string.format(
			"CPU2 DC7051 wait A=%02X R0=%02X P1=%02X P2=%02X P3=%02X PC=%04X",
			cpu.state["A"].value,
			cpu.state["R0"].value,
			cpu.state["P1"].value,
			cpu.state["P2"].value,
			cpu.state["P3"].value,
			cpu.state["PC"].value))
		reported_wait = true
	end
	if not reported_failure and cpu.state["PC"].value == 0x197b then
		emu.print_info(string.format(
			"CPU2 DC7051 mismatch A=%02X",
			cpu.state["A"].value))
		reported_failure = true
	end
end)

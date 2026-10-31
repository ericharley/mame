local cpu = manager.machine.devices[":cpu2"]
local reported = false

emu.register_periodic(function()
	if not reported and cpu.state["PC"].value == 0x15a0 then
		emu.print_info(string.format(
			"CPU2 video timing failure R2=%02X R3=%02X A=%02X P1=%02X",
			cpu.state["R2"].value,
			cpu.state["R3"].value,
			cpu.state["A"].value,
			cpu.state["P1"].value))
		reported = true
	end
end)

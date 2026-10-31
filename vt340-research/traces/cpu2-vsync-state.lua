local cpu = manager.machine.devices[":cpu2"]
local reported = false

emu.register_periodic(function()
	if not reported and cpu.state["PC"].value == 0x13b4 then
		emu.print_info(string.format(
			"CPU2 VSYNC check A=%02X TH0=%02X TL0=%02X",
			cpu.state["A"].value,
			cpu.state["TH0"].value,
			cpu.state["TL0"].value))
		reported = true
	end
end)

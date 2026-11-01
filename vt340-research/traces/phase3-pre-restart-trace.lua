local cpu2 = manager.machine.devices[":cpu2"]
local debugger = manager.machine.debugger
local reset_breakpoint = cpu2.debug:bpset(0x0000)
local tracing = false
local reset_hits = 0

emu.register_periodic(function()
	if not tracing and manager.machine.time:as_double() >= 12.70 then
		debugger:command("trace /tmp/vt340-phase3-pre-restart.tr,cpu2")
		tracing = true
	end
	if debugger.execution_state ~= "stop" then
		return
	end
	if cpu2.state["PC"].value == 0x0000 then
		reset_hits = reset_hits + 1
		print(string.format(
			"PHASE3_PRE_RESTART t=%.9f hit=%d pc=%04X A=%02X B=%02X SP=%02X IE=%02X P1=%02X P2=%02X P3=%02X",
			manager.machine.time:as_double(), reset_hits, cpu2.state["PC"].value,
			cpu2.state["A"].value, cpu2.state["B"].value,
			cpu2.state["SP"].value, cpu2.state["IE"].value,
			cpu2.state["P1"].value, cpu2.state["P2"].value,
			cpu2.state["P3"].value))
		debugger:command("trace off,cpu2")
		cpu2.debug:bpclear(reset_breakpoint)
	end
	debugger.execution_state = "run"
end)

debugger.execution_state = "run"

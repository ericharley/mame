local cpu1 = manager.machine.devices[":cpu1"]
local debugger = manager.machine.debugger

debugger:command("observe 0,1 ; trace vt340-research/traces/wait-to-ok/phase2-command32-full.tr,cpu2")
cpu1.debug:bpset(0x41f7, "1", "b = 0 ; g")
debugger.execution_state = "run"

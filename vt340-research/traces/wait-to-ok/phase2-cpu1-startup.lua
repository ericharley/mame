local cpu = manager.machine.devices[":cpu1"]
local debugger = manager.machine.debugger

debugger:command("focus cpu1 ; temp0 = 0 ; temp1 = 0")
cpu.debug:bpset(0x4551, "++temp0 == 1", "trace vt340-research/traces/wait-to-ok/phase2-cpu1-startup.tr,cpu1 ; g")
cpu.debug:bpset(0x4589, "temp0 == 1 && ++temp1 == 1", "trace off,cpu1 ; g")
debugger.execution_state = "run"

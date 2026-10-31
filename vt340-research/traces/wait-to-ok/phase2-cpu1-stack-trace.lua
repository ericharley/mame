local cpu = manager.machine.devices[":cpu1"]
local debugger = manager.machine.debugger

debugger:command("focus cpu1 ; temp0 = 0")
cpu.debug:bpset(0x72ce, "++temp0 == 1", "trace vt340-research/traces/wait-to-ok/phase2-cpu1-stack.tr,cpu1,,{tracelog \"SP=%02X IE=%02X \",sp,ie} ; g")
cpu.debug:bpset(0xa032, "temp0 == 1", "trace off,cpu1 ; g")
debugger.execution_state = "run"

local cpu = manager.machine.devices[":cpu1"]
local debugger = manager.machine.debugger

debugger:command("focus cpu1 ; temp0 = 0")
cpu.debug:bpset(0x4589, "++temp0 == 1", "trace vt340-research/traces/wait-to-ok/phase2-cpu1-decision.tr,cpu1,,{tracelog \"A=%02X B=%02X SP=%02X PSW=%02X \",a,b,sp,psw} ; g")
cpu.debug:bpset(0x42b0, "temp0 == 1", "trace off,cpu1 ; g")
debugger.execution_state = "run"

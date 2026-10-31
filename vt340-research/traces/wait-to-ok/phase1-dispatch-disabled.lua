local cpu = manager.machine.devices[":cpu2"]
local debugger = manager.machine.debugger

debugger:command("focus cpu2 ; temp0 = 0")
cpu.debug:bpset(0x92d3, "++temp0 == 1", "trace vt340-research/traces/wait-to-ok/phase1-dispatch-disabled.tr,cpu2 ; g")
debugger.execution_state = "run"

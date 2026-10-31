local cpu1 = manager.machine.devices[":cpu1"]
local cpu2 = manager.machine.devices[":cpu2"]
local debugger = manager.machine.debugger

debugger:command("temp0 = 0")
cpu1.debug:bpset(0x41f7, "temp0 == 0", "temp0 = 1 ; b = 0 ; g")
cpu2.debug:bpset(0xdb98, "1", "trace vt340-research/traces/wait-to-ok/phase2-command32-handler.tr,cpu2 ; g")
cpu2.debug:bpset(0xdc02, "1", "trace off,cpu2 ; printf \"reached CPU2 DC02\\n\" ; g")
debugger.execution_state = "run"

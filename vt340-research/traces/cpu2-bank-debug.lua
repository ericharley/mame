local cpu = manager.machine.devices[":cpu2"]
local debugger = manager.machine.debugger

debugger:command("focus cpu2 ; temp0 = 0 ; temp1 = 0")
cpu.debug:bpset(0x0212, "++temp0 == 1", "printf \"CPU2 before CLR P3.3: P3=%02X PC=%04X\\n\",p3,pc ; g")
cpu.debug:bpset(0x0214, "++temp1 == 1", "printf \"CPU2 after CLR P3.3: P3=%02X PC=%04X\\n\",p3,pc ; g")
debugger.execution_state = "run"

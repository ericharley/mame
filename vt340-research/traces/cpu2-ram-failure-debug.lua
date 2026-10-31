local cpu = manager.machine.devices[":cpu2"]
local debugger = manager.machine.debugger

debugger:command('trace /tmp/vt340-cpu2-ram-failure.tr,cpu2,,{ tracelog "A=%02X DPTR=%04X R0=%02X R1=%02X ",a,dptr,r0,r1 }')
cpu.debug:bpset(0xbae6, "1", "trace off ; quit")
debugger.execution_state = "run"

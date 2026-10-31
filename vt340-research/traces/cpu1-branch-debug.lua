local cpu = manager.machine.devices[":cpu1"]
local debugger = manager.machine.debugger

debugger:command("temp0 = 0")
cpu.debug:bpset(
    0x09e4,
    "++temp0 <= 24",
    "printf \"CPU1 09E4 hit=%X SP=%02X A=%02X B=%02X DPTR=%04X R0=%02X R1=%02X R6=%02X PSW=%02X\\n\",temp0,sp,a,b,dptr,r0,r1,r6,psw ; g")
debugger.execution_state = "run"

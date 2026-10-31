local cpu = manager.machine.devices[":cpu2"]
local debugger = manager.machine.debugger

debugger:command("temp0 = 0")
cpu.debug:bpset(
    0xe6bb,
    "++temp0 <= 32",
    "printf \"CPU2 E6BB hit=%X SP=%02X A=%02X B=%02X DPTR=%04X R0=%02X R1=%02X R2=%02X R3=%02X R4=%02X R5=%02X R6=%02X R7=%02X PSW=%02X IE=%02X TCON=%02X\\n\",temp0,sp,a,b,dptr,r0,r1,r2,r3,r4,r5,r6,r7,psw,ie,tcon ; g")
debugger.execution_state = "run"

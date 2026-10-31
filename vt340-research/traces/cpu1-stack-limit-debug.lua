local cpu = manager.machine.devices[":cpu1"]
local debugger = manager.machine.debugger

debugger:command("temp0 = 0 ; temp1 = 0")
cpu.debug:bpset(
    0x099c,
    "sp >= 0x7e && ++temp0 == 1",
    "printf \"CPU1 stack limit at 099C SP=%02X A=%02X B=%02X DPTR=%04X R1=%02X PSW=%02X\\n\",sp,a,b,dptr,r1,psw ; g")
cpu.debug:bpset(
    0x2743,
    "r1 >= 0x80 && ++temp1 == 1",
    "printf \"CPU1 indirect limit at 2743 SP=%02X A=%02X B=%02X DPTR=%04X R1=%02X PSW=%02X\\n\",sp,a,b,dptr,r1,psw ; g")
debugger.execution_state = "run"

local cpu1 = manager.machine.devices[":cpu1"]
local cpu2 = manager.machine.devices[":cpu2"]
local debugger = manager.machine.debugger
local labels = {
	[0x38da] = "P1_FF",
	[0x3906] = "UART_TEST_READ",
	[0x3909] = "UART_TEST_COMPARE",
	[0x390b] = "UART_TEST_PASS",
	[0x390e] = "RESET_RELEASE_BEFORE",
	[0x3910] = "RESET_RELEASE_AFTER",
	[0x3919] = "RENDEZVOUS_BEGIN",
	[0x3922] = "RENDEZVOUS_WAIT_HIGH",
	[0x3925] = "RENDEZVOUS_HIGH_TIMEOUT",
	[0x3929] = "RENDEZVOUS_WAIT_LOW",
	[0x3930] = "RENDEZVOUS_FAIL",
	[0x3952] = "RENDEZVOUS_SUCCESS",
	[0x395b] = "DAT9_LOW_BEFORE",
	[0x395d] = "DAT9_LOW_AFTER",
	[0x398d] = "STATUS_HIGH_BEFORE",
	[0x398f] = "STATUS_HIGH_AFTER",
	[0x3990] = "STATUS_LOW_BEFORE",
	[0x3992] = "STATUS_LOW_AFTER",
	[0x3a0d] = "REQUEST",
	[0x41f7] = "DECISION",
	[0x4293] = "P1_FF_LATE",
}
local breakpoints = {}
local hits = {}

for pc, _ in pairs(labels) do
	breakpoints[pc] = cpu1.debug:bpset(pc)
end

emu.register_periodic(function()
	if debugger.execution_state ~= "stop" then
		return
	end
	local pc = cpu1.state["PC"].value
	local label = labels[pc]
	if label then
		hits[pc] = (hits[pc] or 0) + 1
		print(string.format(
			"PHASE3_RESET t=%.9f label=%s hit=%d pc=%04X A=%02X R0=%02X B=%02X SBUF=%02X P1=%02X cpu2=%04X",
			manager.machine.time:as_double(), label, hits[pc], pc,
			cpu1.state["A"].value, cpu1.state["R0"].value,
			cpu1.state["B"].value, cpu1.spaces["sfr"]:read_u8(0x99),
			cpu1.state["P1"].value, cpu2.state["PC"].value))
		if hits[pc] == 4 then
			cpu1.debug:bpclear(breakpoints[pc])
		end
	end
	debugger.execution_state = "run"
end)

debugger.execution_state = "run"

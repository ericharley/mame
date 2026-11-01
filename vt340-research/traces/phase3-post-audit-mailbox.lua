local cpu1 = manager.machine.devices[":cpu1"]
local cpu2 = manager.machine.devices[":cpu2"]
local xdata = cpu1.spaces["xdata"]
local debugger = manager.machine.debugger
local labels = {
	[0x3a21] = "ACK_EXIT",
	[0x3a3a] = "RESULT_READ",
	[0x41f7] = "DECISION",
	[0x4293] = "CPU2_RESET",
}
local breakpoints = {}
local reads = 0

for pc, _ in pairs(labels) do
	breakpoints[pc] = cpu1.debug:bpset(pc)
end

phase3_post_audit_mailbox_tap = xdata:install_read_tap(
	0x7ff2, 0x7ff2, "phase3_post_audit_mailbox",
	function(offset, value, mask)
		if manager.machine.time:as_double() >= 13.0 then
			reads = reads + 1
			if reads <= 32 then
				print(string.format(
					"PHASE3_POST_AUDIT_READ t=%.9f pc=%04X value=%02X cpu2=%04X",
					manager.machine.time:as_double(), cpu1.state["PC"].value,
					value, cpu2.state["PC"].value))
			end
		end
	end)

emu.register_periodic(function()
	if debugger.execution_state ~= "stop" then
		return
	end
	local pc = cpu1.state["PC"].value
	local label = labels[pc]
	if label then
		print(string.format(
			"PHASE3_POST_AUDIT_POINT t=%.9f label=%s pc=%04X A=%02X B=%02X P1=%02X 7FF2=%02X cpu2=%04X",
			manager.machine.time:as_double(), label, pc, cpu1.state["A"].value,
			cpu1.state["B"].value, cpu1.state["P1"].value,
			xdata:read_u8(0x7ff2), cpu2.state["PC"].value))
		cpu1.debug:bpclear(breakpoints[pc])
	end
	debugger.execution_state = "run"
end)

phase3_post_audit_stop_subscription = emu.add_machine_stop_notifier(function()
	print(string.format("PHASE3_POST_AUDIT_SUMMARY reads=%d cpu1=%04X cpu2=%04X value=%02X",
		reads, cpu1.state["PC"].value, cpu2.state["PC"].value, xdata:read_u8(0x7ff2)))
end)

debugger.execution_state = "run"

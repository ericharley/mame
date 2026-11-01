local cpu1 = manager.machine.devices[":cpu1"]
local cpu2 = manager.machine.devices[":cpu2"]
local xdata1 = cpu1.spaces["xdata"]
local xdata2 = cpu2.spaces["xdata"]
local debugger = manager.machine.debugger
local forced = 0
local labels = {
	[0x3a21] = "ACK_EXIT",
	[0x3a3a] = "RESULT",
	[0x41f7] = "DECISION",
	[0x4293] = "CPU2_RESET_ASSERT",
	[0x48f6] = "COMMAND32",
}
local breakpoints = {}

for pc, _ in pairs(labels) do
	breakpoints[pc] = cpu1.debug:bpset(pc)
end

phase3_force_ordered_ack_tap = xdata1:install_read_tap(
	0x7ff2, 0x7ff2, "phase3_force_ordered_ack",
	function(offset, value, mask)
		if cpu1.state["PC"].value == 0x3a19 and value == 0x80 then
			forced = forced + 1
			if forced == 1 then
				print(string.format(
					"PHASE3_ORDER_FORCE t=%.9f pc=%04X actual=%02X presented=00 cpu2=%04X",
					manager.machine.time:as_double(), cpu1.state["PC"].value,
					value, cpu2.state["PC"].value))
			end
			return 0x00
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
			"PHASE3_ORDER_POINT t=%.9f label=%s pc=%04X A=%02X B=%02X P1=%02X 7FF2=%02X cpu2=%04X",
			manager.machine.time:as_double(), label, pc, cpu1.state["A"].value,
			cpu1.state["B"].value, cpu1.state["P1"].value,
			xdata2:read_u8(0x7ff2), cpu2.state["PC"].value))
		cpu1.debug:bpclear(breakpoints[pc])
	end
	debugger.execution_state = "run"
end)

phase3_force_ordered_ack_stop_subscription = emu.add_machine_stop_notifier(function()
	print(string.format(
		"PHASE3_ORDER_SUMMARY forced=%d cpu1=%04X cpu2=%04X 7FF2=%02X",
		forced, cpu1.state["PC"].value, cpu2.state["PC"].value,
		xdata2:read_u8(0x7ff2)))
end)

debugger.execution_state = "run"

local cpu1 = manager.machine.devices[":cpu1"]
local cpu2 = manager.machine.devices[":cpu2"]
local xdata = cpu1.spaces["xdata"]
local debugger = manager.machine.debugger

-- Diagnostic only.  Repeat CPU2's authentic first 17CF table group before
-- its native second group.  This preserves table contents and command paths
-- while bounding how much additional pre-136D table activity is sufficient
-- for CPU1's unchanged report/pulse sequence.  Select the repeat count with
-- VT340_EXTRA_TABLE_GROUPS; the default is the predicted threshold of five.
local extra_target = tonumber(os.getenv("VT340_EXTRA_TABLE_GROUPS") or "5")
local extra_done = 0
local hits = {}

local points = {
	[":cpu1:3BC8"] = "response_ok",
	[":cpu1:3B8E"] = "cpu1_pulse",
	[":cpu1:3A0D"] = "request_10",
	[":cpu1:3A21"] = "ack_zero",
	[":cpu1:3A3A"] = "result",
	[":cpu2:133D"] = "first_group_done",
	[":cpu2:136D"] = "cpu2_ack_write",
	[":cpu2:163F"] = "cpu2_result_write",
}

for key, _ in pairs(points) do
	local tag, address = key:match("^(:cpu%d):(%x+)$")
	manager.machine.devices[tag].debug:bpset(tonumber(address, 16))
end

emu.register_periodic(function()
	if debugger.execution_state ~= "stop" then
		return
	end

	local key1 = string.format(":cpu1:%04X", cpu1.state["PC"].value)
	local key2 = string.format(":cpu2:%04X", cpu2.state["PC"].value)
	local key = points[key1] and key1 or key2
	local event = points[key]

	if event then
		hits[event] = (hits[event] or 0) + 1
		print(string.format(
			"PHASE4_TABLE_DURATION t=%.9f event=%s hit=%d extra=%d/%d cpu1=%04X cpu2=%04X P1=%02X 7FF2=%02X",
			manager.machine.time:as_double(), event, hits[event], extra_done,
			extra_target, cpu1.state["PC"].value, cpu2.state["PC"].value,
			cpu2.state["P1"].value, xdata:read_u8(0x7ff2)))

		if event == "first_group_done" and extra_done < extra_target then
			extra_done = extra_done + 1
			cpu2.state["PC"].value = 0x133a
		end
	end

	debugger.execution_state = "run"
end)

debugger.execution_state = "run"

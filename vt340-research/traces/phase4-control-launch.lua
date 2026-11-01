local cpu1 = manager.machine.devices[":cpu1"]
local cpu2 = manager.machine.devices[":cpu2"]
local xdata = cpu1.spaces["xdata"]
local debugger = manager.machine.debugger

local points = {
	[":cpu1:39EA"] = "cpu1_post_tests_done",
	[":cpu1:39FB"] = "cpu1_config_prepare",
	[":cpu1:3A07"] = "cpu1_config_write",
	[":cpu1:3A0D"] = "cpu1_pending_write",
	[":cpu1:3B8E"] = "cpu1_pulse",
	[":cpu1:3BC8"] = "cpu1_response",
	[":cpu2:131F"] = "cpu2_rendezvous_5",
	[":cpu2:1322"] = "cpu2_rendezvous_6",
	[":cpu2:1325"] = "cpu2_config_read",
	[":cpu2:136D"] = "cpu2_checkpoint_write",
}

for key, _ in pairs(points) do
	local tag, address = key:match("^(:cpu%d):(%x+)$")
	manager.machine.devices[tag].debug:bpset(tonumber(address, 16))
end

local hits = { cpu1_pulse = 0, cpu1_response = 0 }

emu.register_periodic(function()
	if debugger.execution_state ~= "stop" then
		return
	end

	local key1 = string.format(":cpu1:%04X", cpu1.state["PC"].value)
	local key2 = string.format(":cpu2:%04X", cpu2.state["PC"].value)
	local event = points[key1] or points[key2]
	if event then
		hits[event] = (hits[event] or 0) + 1
		local suffix = ""
		if event == "cpu1_pulse" or event == "cpu1_response" then
			suffix = string.format("_%d", hits[event])
		end
		print(string.format(
			"PHASE4_CONTROL t=%.9f event=%s%s cpu1=%04X cpu2=%04X A1=%02X A2=%02X P1=%02X P3=%02X E795=%02X 7FF2=%02X",
			manager.machine.time:as_double(), event, suffix,
			cpu1.state["PC"].value, cpu2.state["PC"].value,
			cpu1.state["A"].value, cpu2.state["A"].value,
			cpu2.state["P1"].value, cpu1.state["P3"].value,
			xdata:read_u8(0xe795), xdata:read_u8(0x7ff2)))
		if event == "cpu1_pending_write" then
			manager.machine:exit()
			return
		end
	end
	debugger.execution_state = "run"
end)

debugger.execution_state = "run"

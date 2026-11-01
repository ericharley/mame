local cpu1 = manager.machine.devices[":cpu1"]
local cpu2 = manager.machine.devices[":cpu2"]
local xdata = cpu1.spaces["xdata"]
local debugger = manager.machine.debugger

local points = {
	[":cpu1:3A07"] = "cpu1_config_write",
	[":cpu1:3A0D"] = "cpu1_pending_write",
	[":cpu1:3A21"] = "cpu1_checkpoint_seen",
	[":cpu1:3A3A"] = "cpu1_result_seen",
	[":cpu1:3B8E"] = "cpu1_pulse",
	[":cpu1:3BC8"] = "cpu1_response",
	[":cpu2:1325"] = "cpu2_config_read",
	[":cpu2:132F"] = "cpu2_zero_config",
	[":cpu2:1334"] = "cpu2_nonzero_config",
	[":cpu2:136D"] = "cpu2_checkpoint_write",
	[":cpu2:163E"] = "cpu2_result_write",
}

for key, _ in pairs(points) do
	local tag, address = key:match("^(:cpu%d):(%x+)$")
	manager.machine.devices[tag].debug:bpset(tonumber(address, 16))
end

local hits = { cpu1_pulse = 0, cpu1_response = 0 }
local forced = false
local finished = false

emu.register_periodic(function()
	if finished or debugger.execution_state ~= "stop" then
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

		if event == "cpu2_config_read" and not forced then
			xdata:write_u8(0xe795, 0x01)
			forced = true
		end

		print(string.format(
			"PHASE4_CONFIG_RACE t=%.9f event=%s%s forced=%d cpu1=%04X cpu2=%04X A1=%02X A2=%02X E795=%02X 7FF2=%02X",
			manager.machine.time:as_double(), event, suffix, forced and 1 or 0,
			cpu1.state["PC"].value, cpu2.state["PC"].value,
			cpu1.state["A"].value, cpu2.state["A"].value,
			xdata:read_u8(0xe795), xdata:read_u8(0x7ff2)))

		if event == "cpu1_result_seen" or event == "cpu2_result_write" then
			finished = true
			manager.machine:exit()
			return
		end
	end
	debugger.execution_state = "run"
end)

debugger.execution_state = "run"

local cpu1 = manager.machine.devices[":cpu1"]
local cpu2 = manager.machine.devices[":cpu2"]
local xdata = cpu1.spaces["xdata"]
local debugger = manager.machine.debugger
local hits = { response = 0, pulse = 0 }
local breakpoints = {}
local masked = false

local points = {
	[":cpu1:3BC8"] = "response",
	[":cpu1:3B8E"] = "pulse",
	[":cpu1:3A0D"] = "request",
	[":cpu1:3A18"] = "ack_wait",
	[":cpu1:3A21"] = "ack_exit",
	[":cpu1:3A3A"] = "result",
	[":cpu2:136D"] = "ack",
	[":cpu2:1639"] = "result_write",
}

for key, _ in pairs(points) do
	local tag, address = key:match("^(:cpu%d):(%x+)$")
	breakpoints[key] = manager.machine.devices[tag].debug:bpset(tonumber(address, 16))
end

emu.register_periodic(function()
	if debugger.execution_state ~= "stop" then
		return
	end
	local key1 = string.format(":cpu1:%04X", cpu1.state["PC"].value)
	local key2 = string.format(":cpu2:%04X", cpu2.state["PC"].value)
	local key = points[key1] and key1 or key2
	local label = points[key]
	if label then
		hits[label] = (hits[label] or 0) + 1
		local name = label
		if label == "response" or label == "pulse" then
			name = string.format("%s_%d", label, hits[label])
		end
		if label ~= "response" or hits.response >= 5 then
			print(string.format(
				"PHASE4_TIMER_MASK t=%.9f event=%s cpu1=%04X cpu2=%04X IE=%02X 7FF2=%02X",
				manager.machine.time:as_double(), name,
				cpu1.state["PC"].value, cpu2.state["PC"].value,
				cpu1.state["IE"].value, xdata:read_u8(0x7ff2)))
		end
		if label == "response" and hits.response == 5 then
			local old_ie = cpu1.state["IE"].value
			cpu1.state["IE"].value = old_ie & 0xfd
			masked = true
			print(string.format(
				"PHASE4_TIMER_MASK t=%.9f event=mask_et0 old=%02X new=%02X",
				manager.machine.time:as_double(), old_ie,
				cpu1.state["IE"].value))
		end
		if label == "ack_wait" and hits.ack_wait == 1 then
			cpu1.debug:bpclear(breakpoints[key])
		end
		if label == "result" then
			manager.machine:exit()
			return
		end
	end
	debugger.execution_state = "run"
end)

phase4_timer_mask_stop_subscription = emu.add_machine_stop_notifier(function()
	print(string.format(
		"PHASE4_TIMER_MASK_SUMMARY masked=%d response=%d pulse=%d ack=%d request=%d ack_exit=%d result=%d value=%02X",
		masked and 1 or 0, hits.response or 0, hits.pulse or 0,
		hits.ack or 0, hits.request or 0, hits.ack_exit or 0,
		hits.result or 0, xdata:read_u8(0x7ff2)))
end)

debugger.execution_state = "run"

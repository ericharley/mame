local cpu1 = manager.machine.devices[":cpu1"]
local cpu2 = manager.machine.devices[":cpu2"]
local xdata = cpu1.spaces["xdata"]
local debugger = manager.machine.debugger
local breakpoints = {}
local hits = { pulse = 0, response = 0, cpu2_return = 0 }
local times = {}

local points = {
	[":cpu1:3B8E"] = "pulse",
	[":cpu1:3BC8"] = "response",
	[":cpu1:3A0D"] = "request",
	[":cpu1:3A18"] = "ack_wait",
	[":cpu2:1711"] = "cpu2_return",
	[":cpu2:1325"] = "config",
	[":cpu2:136D"] = "ack",
	[":cpu2:1376"] = "dat9_low",
	[":cpu2:137C"] = "dat9_high",
}

for key, _ in pairs(points) do
	local tag, address = key:match("^(:cpu%d):(%x+)$")
	breakpoints[key] = manager.machine.devices[tag].debug:bpset(tonumber(address, 16))
end

local function record(label, hit)
	local name = label
	if label == "pulse" or label == "response" or label == "cpu2_return" then
		name = string.format("%s_%d", label, hit)
	end
	local now = manager.machine.time:as_double()
	times[name] = times[name] or now
	print(string.format(
		"PHASE4_SYNC t=%.9f event=%s cpu1=%04X cpu2=%04X P1=%02X P3=%02X 7FF2=%02X",
		now, name, cpu1.state["PC"].value, cpu2.state["PC"].value,
		cpu2.state["P1"].value, cpu1.state["P3"].value,
		xdata:read_u8(0x7ff2)))
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
		local hit = hits[label]
		if label == "pulse" or label == "response" or label == "cpu2_return" then
			if hit >= 5 then
				record(label, hit)
			end
		else
			record(label, hit)
			if label == "ack_wait" then
				cpu1.debug:bpclear(breakpoints[key])
				manager.machine:exit()
				return
			end
		end
	end
	debugger.execution_state = "run"
end)

phase4_sync_stop_subscription = emu.add_machine_stop_notifier(function()
	local ack_before_request = times.ack and times.request and
		(times.request - times.ack) or -1
	local pulse6_after_ack = times.pulse_6 and times.ack and
		(times.pulse_6 - times.ack) or -1
	print(string.format(
		"PHASE4_SYNC_SUMMARY ack_before_request=%.9f pulse6_after_ack=%.9f",
		ack_before_request, pulse6_after_ack))
end)

debugger.execution_state = "run"

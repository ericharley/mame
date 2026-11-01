local cpu1 = manager.machine.devices[":cpu1"]
local cpu2 = manager.machine.devices[":cpu2"]
local xdata1 = cpu1.spaces["xdata"]
local debugger = manager.machine.debugger
local forced = false
local points = {
	[":cpu1:3A0E"] = "request_written",
	[":cpu1:3A21"] = "zero_accepted",
	[":cpu1:3A31"] = "result_wait",
	[":cpu1:3A3A"] = "result_observed",
	[":cpu1:4551"] = "startup_continues",
	[":cpu1:41F7"] = "success_decision",
	[":cpu2:136D"] = "early_zero",
	[":cpu2:163F"] = "result_80",
}
local breakpoints = {}
local hits = {}

for key, _ in pairs(points) do
	local tag, address = key:match("^(:cpu%d):(%x+)$")
	breakpoints[key] = manager.machine.devices[tag].debug:bpset(
		tonumber(address, 16))
end

local function record(label)
	hits[label] = (hits[label] or 0) + 1
	print(string.format(
		"PHASE4_VISIBILITY t=%.9f event=%s hit=%d cpu1=%04X cpu2=%04X value=%02X B=%02X SP=%02X",
		manager.machine.time:as_double(), label, hits[label],
		cpu1.state["PC"].value, cpu2.state["PC"].value,
		xdata1:read_u8(0x7ff2), cpu1.state["B"].value,
		cpu1.state["SP"].value))
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
		record(label)
		if label == "request_written" and not forced and
			manager.machine.time:as_double() > 8.0 then
			forced = true
			xdata1:write_u8(0x7ff2, 0x00)
			print(string.format(
				"PHASE4_VISIBILITY_FORCE t=%.9f address=7FF2 written=10 visible=00",
				manager.machine.time:as_double()))
		end
		if (hits[label] or 0) >= 8 then
			local device = key:match("^(:cpu%d)") == ":cpu1" and cpu1 or cpu2
			device.debug:bpclear(breakpoints[key])
		end
	end
	debugger.execution_state = "run"
end)

phase4_visibility_stop_subscription = emu.add_machine_stop_notifier(function()
	print(string.format(
		"PHASE4_VISIBILITY_SUMMARY forced=%s cpu1=%04X cpu2=%04X value=%02X B=%02X SP=%02X",
		tostring(forced), cpu1.state["PC"].value, cpu2.state["PC"].value,
		xdata1:read_u8(0x7ff2), cpu1.state["B"].value,
		cpu1.state["SP"].value))
end)

debugger.execution_state = "run"

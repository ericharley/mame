-- Verify the optional CPU1 ROM patch takes the checkpoint fast path while
-- preserving CPU2's native result write and CPU1's success classification.

local cpu1 = manager.machine.devices[":cpu1"]
local cpu2 = manager.machine.devices[":cpu2"]
local program = cpu1.spaces["program"]
local xdata = cpu1.spaces["xdata"]
local cpu2_xdata = cpu2.spaces["xdata"]
local debugger = manager.machine.debugger
local finished = false
local result_write = false

local points = {
	[0x3a0b] = "checkpoint_value",
	[0x3a18] = "checkpoint_wait",
	[0x3a21] = "checkpoint_exit",
	[0x3a31] = "result_wait",
	[0x3a3a] = "result_classify",
	[0x4551] = "success_path",
}

local breakpoints = {}
for address, _ in pairs(points) do
	breakpoints[address] = cpu1.debug:bpset(address)
end

fast_start_result_write = cpu2_xdata:install_write_tap(
	0x7ff2, 0x7ff2, "fast_start_result_write",
	function(offset, value, mask)
		if cpu2.state["PC"].value == 0x163f and value == 0x80 then
			result_write = true
			print(string.format(
				"FAST_START t=%.9f event=native_result value=%02X",
				manager.machine.time:as_double(), value))
		end
	end)

emu.register_periodic(function()
	if finished or debugger.execution_state ~= "stop" then
		return
	end

	local pc = cpu1.state["PC"].value
	local label = points[pc]
	if label then
		print(string.format(
			"FAST_START t=%.9f event=%s A=%02X value=%02X patch=%02X",
			manager.machine.time:as_double(), label, cpu1.state["A"].value,
			xdata:read_u8(0x7ff2), program:read_u8(0x3a0c)))

		-- Each loop-entry breakpoint is needed only once. Leaving either active
		-- would stop on every iteration and perturb the timing being checked.
		cpu1.debug:bpclear(breakpoints[pc])

		if pc == 0x4551 then
			finished = true
			print(string.format(
				"FAST_START_PASS native_result=%d elapsed=%.9f",
				result_write and 1 or 0, manager.machine.time:as_double()))
			manager.machine:exit()
			return
		end
	end

	debugger.execution_state = "run"
end)

debugger.execution_state = "run"

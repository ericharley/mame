-- Diagnostic-only long-run trace for the bounded CPU1 7FF2 wait loops.

local cpu1 = manager.machine.devices[":cpu1"]
local cpu2 = manager.machine.devices[":cpu2"]
local xdata = cpu1.spaces["xdata"]
local debugger = manager.machine.debugger
local finished = false

local points = {
	[0x3a18]="checkpoint_wait_entry",
	[0x3a21]="checkpoint_wait_exit",
	[0x3a31]="result_wait",
	[0x3a3a]="result_classify",
	[0x4551]="success_path"
}

local breakpoints = {}
for address, _ in pairs(points) do
	breakpoints[address] = cpu1.debug:bpset(address)
end

phase4_mailbox_timeout_write = xdata:install_write_tap(
	0x7ff2, 0x7ff2, "phase4_mailbox_timeout_write",
	function(offset, value, mask)
		print(string.format(
			"PHASE4_MAILBOX_TIMEOUT t=%.9f event=write cpu1=%04X cpu2=%04X value=%02X",
			manager.machine.time:as_double(), cpu1.state["PC"].value,
			cpu2.state["PC"].value, value))
	end)

emu.register_periodic(function()
	if finished or debugger.execution_state ~= "stop" then return end
	local pc = cpu1.state["PC"].value
	local label = points[pc]
	if label then
		print(string.format(
			"PHASE4_MAILBOX_TIMEOUT t=%.9f event=%s cpu1=%04X cpu2=%04X A=%02X value=%02X",
			manager.machine.time:as_double(), label, pc,
			cpu2.state["PC"].value, cpu1.state["A"].value,
			xdata:read_u8(0x7ff2)))
		if pc == 0x3a18 then
			cpu1.debug:bpclear(breakpoints[0x3a18])
		end
		if pc == 0x4551 then
			finished = true
			manager.machine:exit()
			return
		end
	end
	debugger.execution_state = "run"
end)

debugger.execution_state = "run"

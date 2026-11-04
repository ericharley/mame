-- Diagnostic-only measurement of the bare 3a18-3a1f checkpoint timeout.
-- Timer 0 is masked only after the first wait-loop entry, so this cannot
-- change the already-missed 7ff2 checkpoint or the pre-wait ordering.

local cpu1 = manager.machine.devices[":cpu1"]
local cpu2 = manager.machine.devices[":cpu2"]
local xdata = cpu1.spaces["xdata"]
local debugger = manager.machine.debugger
local entry_bp = cpu1.debug:bpset(0x3a18)
local exit_bp = cpu1.debug:bpset(0x3a21)
local start_time = nil
local old_ie = nil
local finished = false

emu.register_periodic(function()
	if finished or debugger.execution_state ~= "stop" then
		return
	end

	local pc = cpu1.state["PC"].value
	if pc == 0x3a18 and not start_time then
		start_time = manager.machine.time:as_double()
		old_ie = cpu1.state["IE"].value
		cpu1.state["IE"].value = old_ie & 0xfd
		cpu1.debug:bpclear(entry_bp)
		print(string.format(
			"PHASE4_TIMEOUT_COST t=%.9f event=entry old_ie=%02X new_ie=%02X value=%02X cpu2=%04X",
			start_time, old_ie, cpu1.state["IE"].value,
			xdata:read_u8(0x7ff2), cpu2.state["PC"].value))
	elseif pc == 0x3a21 and start_time then
		local now = manager.machine.time:as_double()
		finished = true
		print(string.format(
			"PHASE4_TIMEOUT_COST t=%.9f event=exit elapsed_s=%.9f value=%02X cpu2=%04X",
			now, now - start_time, xdata:read_u8(0x7ff2),
			cpu2.state["PC"].value))
		manager.machine:exit()
		return
	end

	debugger.execution_state = "run"
end)

debugger.execution_state = "run"

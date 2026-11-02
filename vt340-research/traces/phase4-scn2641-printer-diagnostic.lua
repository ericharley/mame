-- Trace CPU1's native SCN2641 printer-port diagnostic without changing state.

local cpu1 = manager.machine.devices[":cpu1"]
local debugger = manager.machine.debugger
local xdata = cpu1.spaces["xdata"]
local idata = cpu1.spaces["idata"]

local points = {
	[0xf6f0] = "printer_entry",
	[0xf703] = "first_sweep_result",
	[0xf706] = "variant_check",
	[0xf70c] = "second_sweep_result",
	[0xf717] = "modem_test_1",
	[0xf722] = "modem_test_2",
	[0xf725] = "printer_pass_return",
	[0xf729] = "printer_bit6_set",
	[0xf760] = "loopback_iteration",
	[0xf767] = "status_txrdy_branch",
	[0xf77f] = "status_rxrdy_branch",
	[0xf784] = "status_error_branch",
	[0xf789] = "receive_read",
	[0xf7a2] = "iteration_fail",
	[0x48f6] = "command32_submit"
}

for pc, _ in pairs(points) do cpu1.debug:bpset(pc) end

local accesses = 0
local active = false
local complete = false

local function trace_io(op, offset, data)
	if not active then return end
	accesses = accesses + 1
	print(string.format(
		"PHASE4_SCN2641_IO t=%.9f n=%d op=%s pc=%04X address=%04X data=%02X A=%02X B=%02X DPTR=%04X R0=%02X R1=%02X R2=%02X R3=%02X R4=%02X P1=%02X P2=%02X PSW=%02X",
		manager.machine.time:as_double(), accesses, op,
		cpu1.state["PC"].value, offset, data, cpu1.state["A"].value,
		cpu1.state["B"].value, cpu1.state["DPTR"].value,
		cpu1.state["R0"].value, cpu1.state["R1"].value,
		cpu1.state["R2"].value, cpu1.state["R3"].value,
		cpu1.state["R4"].value, cpu1.state["P1"].value,
		cpu1.state["P2"].value, cpu1.state["PSW"].value))
end

phase4_scn2641_read = xdata:install_read_tap(
	0xf000, 0xf1ff, "phase4_scn2641_read",
	function(offset, data, mask) trace_io("R", offset, data) end)

phase4_scn2641_write = xdata:install_write_tap(
	0xf000, 0xf1ff, "phase4_scn2641_write",
	function(offset, data, mask) trace_io("W", offset, data) end)

emu.register_periodic(function()
	if debugger.execution_state ~= "stop" then return end
	local pc = cpu1.state["PC"].value
	local name = points[pc]
	if name then
		if pc == 0xf6f0 then active = true end
		print(string.format(
			"PHASE4_SCN2641 t=%.9f pc=%04X event=%s result=%02X A=%02X B=%02X DPTR=%04X R0=%02X R1=%02X R2=%02X R3=%02X R4=%02X P1=%02X P2=%02X PSW=%02X",
			manager.machine.time:as_double(), pc, name, idata:read_u8(0x1f),
			cpu1.state["A"].value, cpu1.state["B"].value,
			cpu1.state["DPTR"].value, cpu1.state["R0"].value,
			cpu1.state["R1"].value, cpu1.state["R2"].value,
			cpu1.state["R3"].value, cpu1.state["R4"].value,
			cpu1.state["P1"].value, cpu1.state["P2"].value,
			cpu1.state["PSW"].value))
		if pc == 0x48f6 then
			complete = true
			manager.machine:exit()
			return
		end
	end
	debugger.execution_state = "run"
end)

phase4_scn2641_stop = emu.add_machine_stop_notifier(function()
	print(string.format("PHASE4_SCN2641_%s accesses=%d result=%02X",
		complete and "PASS" or "FAIL", accesses, idata:read_u8(0x1f)))
end)

debugger.execution_state = "run"

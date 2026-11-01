local cpu2 = manager.machine.devices[":cpu2"]
local cpu1 = manager.machine.devices[":cpu1"]
local xdata = cpu2.spaces["xdata"]
local debugger = manager.machine.debugger
local addresses = {
	[0x125f] = "reset",
	[0x30f9] = "setup",
	[0x3119] = "table",
	[0x3106] = "bad_wait",
	[0x14fc] = "pattern_boundary",
	[0x1501] = "pattern_continue",
	[0x1639] = "result",
	[0x16ef] = "operational",
}
local breakpoints = {}
local hits = {}
local uart_latches_ok = false
local uart_breakpoint = cpu1.debug:bpset(0x390e)

for address, _ in pairs(addresses) do
	breakpoints[address] = cpu2.debug:bpset(address)
end

emu.register_periodic(function()
	if debugger.execution_state ~= "stop" then
		return
	end
	if cpu1.state["PC"].value == 0x390e then
		local receive = cpu1.spaces["sfr"]:read_u8(0x99)
		uart_latches_ok = cpu1.state["B"].value == 0x40 and receive ~= 0x55
		print(string.format(
			"PHASE3_LOWROM event=uart_latches B=%02X SBUF=%02X ok=%d",
			cpu1.state["B"].value, receive, uart_latches_ok and 1 or 0))
		cpu1.debug:bpclear(uart_breakpoint)
		debugger.execution_state = "run"
		return
	end
	local pc = cpu2.state["PC"].value
	local label = addresses[pc]
	if label then
		hits[label] = (hits[label] or 0) + 1
		if label ~= "reset" or hits[label] > 1 then
			print(string.format("PHASE3_LOWROM event=%s hit=%d t=%.9f pc=%04X 7FF2=%02X",
				label, hits[label], manager.machine.time:as_double(), pc,
				xdata:read_u8(0x7ff2)))
		end
		if label ~= "reset" or hits[label] == 2 then
			cpu2.debug:bpclear(breakpoints[pc])
		end
	end
	debugger.execution_state = "run"
end)

phase3_lowrom_stop_subscription = emu.add_machine_stop_notifier(function()
	local pass = uart_latches_ok and (hits.reset or 0) == 1 and
		(hits.setup or 0) >= 1 and (hits.table or 0) >= 1 and
		(hits.bad_wait or 0) == 0 and
		(hits.pattern_boundary or 0) >= 1 and
		(hits.pattern_continue or 0) >= 1 and
		(hits.result or 0) >= 1 and (hits.operational or 0) >= 1
	print(string.format(
		"PHASE3_LOWROM_%s uart=%d reset=%d setup=%d table=%d bad_wait=%d boundary=%d continue=%d result=%d operational=%d",
		pass and "PASS" or "FAIL", uart_latches_ok and 1 or 0,
		hits.reset or 0, hits.setup or 0,
		hits.table or 0, hits.bad_wait or 0, hits.pattern_boundary or 0,
		hits.pattern_continue or 0, hits.result or 0, hits.operational or 0))
end)

debugger.execution_state = "run"

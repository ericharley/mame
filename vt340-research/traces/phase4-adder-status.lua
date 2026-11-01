local cpu1 = manager.machine.devices[":cpu1"]
local cpu2 = manager.machine.devices[":cpu2"]
local xdata = cpu2.spaces["xdata"]
local debugger = manager.machine.debugger
local stop_breakpoint = cpu2.debug:bpset(0x136d)
local ready_breakpoint = cpu2.debug:bpset(0xbba9)
local status_reads = 0
local commands = 0

phase4_adder_status_read_tap = xdata:install_read_tap(
	0xf003, 0xf003, "phase4_adder_status_read",
	function(offset, value, mask)
		local now = manager.machine.time:as_double()
		if now >= 8.20 and now < 8.24 then
			status_reads = status_reads + 1
			print(string.format(
				"PHASE4_ADDER t=%.9f event=status_read pc=%04X value=%02X P1=%02X cpu1=%04X",
				now, cpu2.state["PC"].value, value,
				cpu2.state["P1"].value, cpu1.state["PC"].value))
		end
	end)

phase4_adder_command_tap = xdata:install_write_tap(
	0xf008, 0xf008, "phase4_adder_command",
	function(offset, value, mask)
		local now = manager.machine.time:as_double()
		if now >= 8.20 and now < 8.24 then
			commands = commands + 1
			print(string.format(
				"PHASE4_ADDER t=%.9f event=command pc=%04X value=%02X%02X cpu1=%04X",
				now, cpu2.state["PC"].value, cpu2.state["P1"].value,
				value, cpu1.state["PC"].value))
		end
	end)

emu.register_periodic(function()
	if debugger.execution_state ~= "stop" then
		return
	end
	if cpu2.state["PC"].value == 0x136d then
		cpu2.debug:bpclear(stop_breakpoint)
		manager.machine:exit()
		return
	end
	if cpu2.state["PC"].value == 0xbba9 then
		print(string.format(
			"PHASE4_ADDER t=%.9f event=address_ready_poll value=%02X P1=%02X cpu1=%04X",
			manager.machine.time:as_double(), xdata:read_u8(0xf003),
			cpu2.state["P1"].value, cpu1.state["PC"].value))
	end
	debugger.execution_state = "run"
end)

phase4_adder_status_stop_subscription = emu.add_machine_stop_notifier(function()
	print(string.format(
		"PHASE4_ADDER_SUMMARY status_reads=%d commands=%d cpu1=%04X cpu2=%04X",
		status_reads, commands, cpu1.state["PC"].value,
		cpu2.state["PC"].value))
end)

debugger.execution_state = "run"

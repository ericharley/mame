-- Record the CPU1 POST result bits that become command-32's payload.

local cpu1 = manager.machine.devices[":cpu1"]
local debugger = manager.machine.debugger
local idata = cpu1.spaces["idata"]

local points = {
	[0x41d3] = "result_clear",
	[0x4270] = "mailbox_or",
	[0x430f] = "serial_test_fail",
	[0x4329] = "graphics_common_fail",
	[0x4378] = "graphics_bit_1_fail",
	[0x437c] = "graphics_bit_4_fail",
	[0x438a] = "graphics_bit_5_fail",
	[0xf729] = "graphics_bit_6_fail",
	[0x48f6] = "command32_submit"
}

for pc, _ in pairs(points) do
	cpu1.debug:bpset(pc)
end

local complete = false
local result_writes = 0

phase4_cpu1_post_result_tap = idata:install_write_tap(
	0x1f, 0x1f, "phase4_cpu1_post_result",
	function(offset, data, mask)
		if manager.machine.time:as_double() < 100 then return end
		result_writes = result_writes + 1
		print(string.format(
			"PHASE4_CPU1_POST t=%.9f pc=%04X event=result_write value=%02X PSW=%02X",
			manager.machine.time:as_double(), cpu1.state["PC"].value,
			data, cpu1.state["PSW"].value))
	end)

emu.register_periodic(function()
	if debugger.execution_state ~= "stop" then return end
	local pc = cpu1.state["PC"].value
	local name = points[pc]
	if name then
		print(string.format(
			"PHASE4_CPU1_POST t=%.9f pc=%04X event=%s result=%02X A=%02X B=%02X R0=%02X R1=%02X R2=%02X R3=%02X DPTR=%04X P1=%02X",
			manager.machine.time:as_double(), pc, name,
			idata:read_u8(0x1f), cpu1.state["A"].value,
			cpu1.state["B"].value, cpu1.state["R0"].value,
			cpu1.state["R1"].value, cpu1.state["R2"].value,
			cpu1.state["R3"].value, cpu1.state["DPTR"].value,
			cpu1.state["P1"].value))
		if pc == 0x48f6 then
			complete = true
			manager.machine:exit()
			return
		end
	end
	debugger.execution_state = "run"
end)

phase4_cpu1_post_stop = emu.add_machine_stop_notifier(function()
	print(string.format("PHASE4_CPU1_POST_%s result_writes=%d",
		complete and "PASS" or "FAIL", result_writes))
end)

debugger.execution_state = "run"

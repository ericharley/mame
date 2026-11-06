-- Trace CPU1's DUART/Comm-1 diagnostic and the path which sets result bit 1.

local cpu1 = manager.machine.devices[":cpu1"]
local debugger = manager.machine.debugger
local xdata = cpu1.spaces["xdata"]
local idata = cpu1.spaces["idata"]

local points = {
	[0x4313] = "channel_a_entry",
	[0x431b] = "channel_b_entry",
	[0x432d] = "test_entry",
	[0x4340] = "mode_8f_result",
	[0x4350] = "mode_07_result",
	[0x4365] = "counter_result",
	[0x4369] = "failure_classify",
	[0x4372] = "firmware_variant",
	[0x4378] = "bit1_set",
	[0x438a] = "bit5_set",
	[0x48f6] = "command32_submit"
}

for pc, _ in pairs(points) do cpu1.debug:bpset(pc) end

local accesses = 0
local complete = false

phase4_comm1_read = xdata:install_read_tap(
	0xf040, 0xf04f, "phase4_comm1_read",
	function(offset, data, mask)
		local now = manager.machine.time:as_double()
		accesses = accesses + 1
		if accesses <= 2000 then
			print(string.format(
				"PHASE4_COMM1_IO t=%.9f op=R pc=%04X address=%04X data=%02X DPTR=%04X R0=%02X R3=%02X R4=%02X F0=%d",
				now, cpu1.state["PC"].value, offset, data,
				cpu1.state["DPTR"].value, cpu1.state["R0"].value,
				cpu1.state["R3"].value, cpu1.state["R4"].value,
				(cpu1.state["PSW"].value >> 5) & 1))
		end
	end)

phase4_comm1_write = xdata:install_write_tap(
	0xf040, 0xf04f, "phase4_comm1_write",
	function(offset, data, mask)
		local now = manager.machine.time:as_double()
		accesses = accesses + 1
		if accesses <= 2000 then
			print(string.format(
				"PHASE4_COMM1_IO t=%.9f op=W pc=%04X address=%04X data=%02X DPTR=%04X R0=%02X R3=%02X R4=%02X F0=%d",
				now, cpu1.state["PC"].value, offset, data,
				cpu1.state["DPTR"].value, cpu1.state["R0"].value,
				cpu1.state["R3"].value, cpu1.state["R4"].value,
				(cpu1.state["PSW"].value >> 5) & 1))
		end
	end)

emu.register_periodic(function()
	if debugger.execution_state ~= "stop" then return end
	local pc = cpu1.state["PC"].value
	local name = points[pc]
	if name then
		print(string.format(
			"PHASE4_COMM1 t=%.9f pc=%04X event=%s result=%02X A=%02X B=%02X DPTR=%04X R0=%02X R1=%02X R2=%02X R3=%02X R4=%02X PSW=%02X P1=%02X",
			manager.machine.time:as_double(), pc, name, idata:read_u8(0x1f),
			cpu1.state["A"].value, cpu1.state["B"].value,
			cpu1.state["DPTR"].value, cpu1.state["R0"].value,
			cpu1.state["R1"].value, cpu1.state["R2"].value,
			cpu1.state["R3"].value, cpu1.state["R4"].value,
			cpu1.state["PSW"].value, cpu1.state["P1"].value))
		if pc == 0x48f6 then
			complete = true
			manager.machine:exit()
			return
		end
	end
	debugger.execution_state = "run"
end)

phase4_comm1_stop = emu.add_machine_stop_notifier(function()
	print(string.format("PHASE4_COMM1_%s accesses=%d result=%02X",
		complete and "PASS" or "FAIL", accesses, idata:read_u8(0x1f)))
end)

debugger.execution_state = "run"

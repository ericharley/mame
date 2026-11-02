-- Trace the two CPU1 diagnostics which control POST result bit 0.
-- This is observational only: no values or timing are changed.

local cpu1 = manager.machine.devices[":cpu1"]
local debugger = manager.machine.debugger
local xdata = cpu1.spaces["xdata"]
local idata = cpu1.spaces["idata"]

local points = {
	[0x3c05] = "first_call",
	[0x3c27] = "first_entry",
	[0x3c38] = "first_stage1_sum",
	[0x3c5c] = "first_return",
	[0x3d49] = "checksum_call_1",
	[0x3d5a] = "checksum_entry",
	[0x3d85] = "checksum_page_end",
	[0x3d97] = "checksum_return",
	[0x3d4e] = "bit0_set",
	[0x3d52] = "checksum_call_2",
	[0x48f6] = "command32_submit"
}

for pc, _ in pairs(points) do
	cpu1.debug:bpset(pc)
end

local reads = 0
local first_reads = {}
local last_reads = {}
local complete = false

phase4_bit0_read_tap = xdata:install_read_tap(
	0xf000, 0xf1ff, "phase4_bit0_read",
	function(offset, data, mask)
		local pc = cpu1.state["PC"].value
		if pc >= 0x3d5a and pc <= 0x3d98 then
			reads = reads + 1
			local record = string.format(
				"t=%.9f n=%d pc=%04X address=%04X data=%02X P1=%02X PSW=%02X R3=%02X",
				manager.machine.time:as_double(), reads, pc, offset, data,
				cpu1.state["P1"].value, cpu1.state["PSW"].value,
				cpu1.state["R3"].value)
			if reads <= 12 then first_reads[#first_reads + 1] = record end
			last_reads[#last_reads + 1] = record
			if #last_reads > 12 then table.remove(last_reads, 1) end
		end
	end)

emu.register_periodic(function()
	if debugger.execution_state ~= "stop" then return end
	local pc = cpu1.state["PC"].value
	local name = points[pc]
	if name then
		print(string.format(
			"PHASE4_BIT0 t=%.9f pc=%04X event=%s result=%02X A=%02X B=%02X DPTR=%04X R1=%02X R2=%02X R3=%02X R4=%02X P1=%02X P2=%02X PSW=%02X",
			manager.machine.time:as_double(), pc, name, idata:read_u8(0x1f),
			cpu1.state["A"].value, cpu1.state["B"].value,
			cpu1.state["DPTR"].value, cpu1.state["R1"].value,
			cpu1.state["R2"].value, cpu1.state["R3"].value,
			cpu1.state["R4"].value, cpu1.state["P1"].value,
			cpu1.state["P2"].value, cpu1.state["PSW"].value))
		if pc == 0x48f6 then
			complete = true
			manager.machine:exit()
			return
		end
	end
	debugger.execution_state = "run"
end)

phase4_bit0_stop = emu.add_machine_stop_notifier(function()
	for _, record in ipairs(first_reads) do print("PHASE4_BIT0_READ_FIRST " .. record) end
	for _, record in ipairs(last_reads) do print("PHASE4_BIT0_READ_LAST " .. record) end
	print(string.format("PHASE4_BIT0_%s reads=%d",
		complete and "PASS" or "FAIL", reads))
end)

debugger.execution_state = "run"

local cpu1 = manager.machine.devices[":cpu1"]
local cpu2 = manager.machine.devices[":cpu2"]
local idata = cpu1.spaces["idata"]
local xdata = cpu1.spaces["xdata"]
local debugger = manager.machine.debugger
local breakpoints = {}
local hits = {}

local labels = {
	[0x8439] = "EVENT_07",
	[0x8442] = "LOAD_B_37",
	[0x8445] = "CLEAR_STATE_CALL",
	[0x8448] = "STARTUP_JUMP",
	[0xd70b] = "ALTERNATE_0",
	[0xd70f] = "ALTERNATE_1",
	[0x4174] = "CONFIG_START",
	[0x4196] = "NO_CONFIG_START",
	[0x4198] = "COMMON_START",
	[0x41bf] = "TEMP_B_ZERO",
	[0x41c8] = "RESTORE_B",
	[0x41ca] = "RESTORED_B",
	[0x41d0] = "RESET_SP",
	[0x41f7] = "DECISION",
	[0x3a00] = "REPEAT_ENTRY",
	[0x3a07] = "TYPE_WRITE",
	[0x3a0d] = "REQUEST_WRITE",
	[0x3a11] = "PULSE_CALL",
	[0x3a18] = "ACK_WAIT",
	[0x3b8e] = "PULSE_LOW",
	[0x3b90] = "PULSE_DELAY",
	[0x3b96] = "PULSE_HIGH",
}

for address, _ in pairs(labels) do
	breakpoints[address] = cpu1.debug:bpset(address)
end

local function stack_bytes(sp)
	local values = {}
	for i = 0, 7 do
		local address = (sp - i) & 0xff
		values[#values + 1] = string.format("%02X", idata:read_u8(address))
	end
	return table.concat(values, ":")
end

emu.register_periodic(function()
	if debugger.execution_state ~= "stop" then
		return
	end

	local pc = cpu1.state["PC"].value
	local label = labels[pc]
	if label then
		hits[pc] = (hits[pc] or 0) + 1
		local sp = cpu1.state["SP"].value
		print(string.format(
			"PHASE3_ENTRY t=%.9f label=%s hit=%d pc=%04X A=%02X B=%02X PSW=%02X " ..
			"R0=%02X R1=%02X SP=%02X stack=%s P1=%02X P3=%02X 7FF2=%02X 7FF4=%02X cpu2=%04X",
			manager.machine.time:as_double(), label, hits[pc], pc,
			cpu1.state["A"].value, cpu1.state["B"].value,
			cpu1.state["PSW"].value, cpu1.state["R0"].value,
			cpu1.state["R1"].value, sp, stack_bytes(sp),
			cpu1.state["P1"].value, cpu1.state["P3"].value,
			xdata:read_u8(0x7ff2), xdata:read_u8(0x7ff4),
			cpu2.state["PC"].value))
		local limit = pc == 0x3a18 and 2 or 4
		if hits[pc] == limit then
			cpu1.debug:bpclear(breakpoints[pc])
		end
	else
		print(string.format("PHASE3_ENTRY_UNEXPECTED_STOP pc=%04X", pc))
	end
	debugger.execution_state = "run"
end)

phase3_entry_stop_subscription = emu.add_machine_stop_notifier(function()
	print(string.format(
		"PHASE3_ENTRY_SUMMARY event07=%d config=%d no_config=%d decision=%d cpu1=%04X cpu2=%04X",
		hits[0x8439] or 0, hits[0x4174] or 0, hits[0x4196] or 0,
		hits[0x41f7] or 0, cpu1.state["PC"].value, cpu2.state["PC"].value))
end)

debugger.execution_state = "run"

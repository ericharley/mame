local cpu1 = manager.machine.devices[":cpu1"]
local cpu2 = manager.machine.devices[":cpu2"]
local xdata1 = cpu1.spaces["xdata"]
local xdata2 = cpu2.spaces["xdata"]
local debugger = manager.machine.debugger
local breakpoints = {}
local hits = {}
local reads = 0
local writes = 0

local labels = {
	[0xd70b] = "D70B",
	[0xd70f] = "D70F",
	[0xd711] = "D711",
	[0xd719] = "D719",
	[0xd723] = "D723",
	[0x41f7] = "41F7",
	[0x48f6] = "48F6",
}

for address, _ in pairs(labels) do
	breakpoints[address] = cpu1.debug:bpset(address)
end

phase3_e789_read_tap = xdata1:install_read_tap(
	0xe789, 0xe789, "phase3_e789_read",
	function(offset, data, mask)
		reads = reads + 1
		if reads <= 16 then
			print(string.format(
				"PHASE3_E789_READ t=%.9f pc=%04X data=%02X",
				manager.machine.time:as_double(), cpu1.state["PC"].value, data))
		end
	end)

phase3_e789_write_tap = xdata1:install_write_tap(
	0xe789, 0xe789, "phase3_e789_write",
	function(offset, data, mask)
		writes = writes + 1
		if writes <= 16 then
			print(string.format(
				"PHASE3_E789_WRITE t=%.9f pc=%04X data=%02X",
				manager.machine.time:as_double(), cpu1.state["PC"].value, data))
		end
	end)

emu.register_periodic(function()
	if debugger.execution_state ~= "stop" then
		return
	end

	local pc = cpu1.state["PC"].value
	local label = labels[pc]
	if label then
		hits[pc] = (hits[pc] or 0) + 1
		print(string.format(
			"PHASE3_CPU1 t=%.9f pc=%s hit=%d B=%02X PSW=%02X SP=%02X 7FF4=%02X ring=%02X/%02X cpu2=%04X",
			manager.machine.time:as_double(), label, hits[pc],
			cpu1.state["B"].value, cpu1.state["PSW"].value,
			cpu1.state["SP"].value, xdata1:read_u8(0x7ff4),
			xdata1:read_u8(0x7e7e), xdata1:read_u8(0x7e7f),
			cpu2.state["PC"].value))
		if hits[pc] == 1 then
			cpu1.debug:bpclear(breakpoints[pc])
		end
	else
		print(string.format("PHASE3_UNEXPECTED_STOP cpu1=%04X cpu2=%04X", pc, cpu2.state["PC"].value))
	end
	debugger.execution_state = "run"
end)

phase3_e789_stop_subscription = emu.add_machine_stop_notifier(function()
	print(string.format(
		"PHASE3_E789_SUMMARY reads=%d writes=%d D70B=%d D70F=%d D711=%d D723=%d 41F7=%d 48F6=%d",
		reads, writes, hits[0xd70b] or 0, hits[0xd70f] or 0,
		hits[0xd711] or 0, hits[0xd723] or 0, hits[0x41f7] or 0,
		hits[0x48f6] or 0))
end)

debugger.execution_state = "run"

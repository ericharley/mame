local cpu1 = manager.machine.devices[":cpu1"]
local xdata = cpu1.spaces["xdata"]
local debugger = manager.machine.debugger
local breakpoints = {}
local hits = {}
local selected_reads = 0
local selected_writes = 0

local labels = {
	[0x38da] = "RESET_P1",
	[0x3af4] = "NVREN_TEST",
	[0x3b27] = "NVREN_CLEAR_1",
	[0x3b2e] = "NVREN_SET_1",
	[0x3b39] = "NVREN_CLEAR_2",
	[0x3b40] = "NVREN_SET_2",
	[0x3b47] = "NVREN_CLEAR_3",
	[0x4156] = "NVR_SEQUENCE",
	[0x4166] = "NVR_STEP",
	[0x4174] = "CONFIG_ENTRY",
	[0x41f7] = "DECISION",
}

for address, _ in pairs(labels) do
	breakpoints[address] = cpu1.debug:bpset(address)
end

phase3_nvr_read_tap = xdata:install_read_tap(
	0xe600, 0xe7ff, "phase3_nvr_read",
	function(offset, data, mask)
		local p1 = cpu1.state["P1"].value
		if (p1 & 0x10) == 0 then
			selected_reads = selected_reads + 1
			if selected_reads <= 64 then
				print(string.format(
					"PHASE3_NVR_READ t=%.9f pc=%04X address=%04X data=%02X P1=%02X",
					manager.machine.time:as_double(), cpu1.state["PC"].value,
					offset, data, p1))
			end
		end
	end)

phase3_nvr_write_tap = xdata:install_write_tap(
	0xe600, 0xe7ff, "phase3_nvr_write",
	function(offset, data, mask)
		local p1 = cpu1.state["P1"].value
		if (p1 & 0x10) == 0 then
			selected_writes = selected_writes + 1
			if selected_writes <= 64 then
				print(string.format(
					"PHASE3_NVR_WRITE t=%.9f pc=%04X address=%04X data=%02X P1=%02X",
					manager.machine.time:as_double(), cpu1.state["PC"].value,
					offset, data, p1))
			end
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
		if hits[pc] <= 12 then
			print(string.format(
				"PHASE3_NVR_STATE t=%.9f pc=%s hit=%d P1=%02X B=%02X IE=%02X",
				manager.machine.time:as_double(), label, hits[pc],
				cpu1.state["P1"].value, cpu1.state["B"].value,
				cpu1.state["IE"].value))
		end
		if hits[pc] == 12 then
			cpu1.debug:bpclear(breakpoints[pc])
		end
	else
		print(string.format("PHASE3_NVR_UNEXPECTED_STOP pc=%04X", pc))
	end
	debugger.execution_state = "run"
end)

phase3_nvr_stop_subscription = emu.add_machine_stop_notifier(function()
	print(string.format(
		"PHASE3_NVR_SUMMARY selected_reads=%d selected_writes=%d config_entry=%d decision=%d",
		selected_reads, selected_writes, hits[0x4174] or 0, hits[0x41f7] or 0))
end)

debugger.execution_state = "run"

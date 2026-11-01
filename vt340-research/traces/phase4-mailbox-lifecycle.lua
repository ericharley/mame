local cpu1 = manager.machine.devices[":cpu1"]
local cpu2 = manager.machine.devices[":cpu2"]
local xdata1 = cpu1.spaces["xdata"]
local xdata2 = cpu2.spaces["xdata"]
local counts = {}

local function access(cpu_name, operation, pc, value)
	local key = string.format("%s_%s_%04X_%02X", cpu_name, operation, pc, value)
	counts[key] = (counts[key] or 0) + 1
	if counts[key] == 1 then
		print(string.format(
			"PHASE4_MAILBOX t=%.9f cpu=%s operation=%s pc=%04X value=%02X cpu1=%04X cpu2=%04X",
			manager.machine.time:as_double(), cpu_name, operation, pc, value,
			cpu1.state["PC"].value, cpu2.state["PC"].value))
	end
end

phase4_mailbox_cpu1_read_tap = xdata1:install_read_tap(
	0x7ff2, 0x7ff2, "phase4_mailbox_cpu1_read",
	function(offset, value, mask)
		access("cpu1", "read", cpu1.state["PC"].value, value)
	end)

phase4_mailbox_cpu1_write_tap = xdata1:install_write_tap(
	0x7ff2, 0x7ff2, "phase4_mailbox_cpu1_write",
	function(offset, value, mask)
		access("cpu1", "write", cpu1.state["PC"].value, value)
	end)

phase4_mailbox_cpu2_read_tap = xdata2:install_read_tap(
	0x7ff2, 0x7ff2, "phase4_mailbox_cpu2_read",
	function(offset, value, mask)
		access("cpu2", "read", cpu2.state["PC"].value, value)
	end)

phase4_mailbox_cpu2_write_tap = xdata2:install_write_tap(
	0x7ff2, 0x7ff2, "phase4_mailbox_cpu2_write",
	function(offset, value, mask)
		access("cpu2", "write", cpu2.state["PC"].value, value)
	end)

phase4_mailbox_stop_subscription = emu.add_machine_stop_notifier(function()
	local keys = {}
	for key, _ in pairs(counts) do
		table.insert(keys, key)
	end
	table.sort(keys)
	for _, key in ipairs(keys) do
		print(string.format("PHASE4_MAILBOX_COUNT key=%s count=%d", key, counts[key]))
	end
end)


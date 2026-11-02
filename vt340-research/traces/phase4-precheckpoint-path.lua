-- Bounded CPU2 control-flow and hardware-access trace from 1325 through the
-- instruction after the 136D checkpoint write.  At 12 MHz, one classic 8031
-- machine cycle is one microsecond, so 1 MHz emulation-time ticks are exact
-- integer machine-cycle coordinates for this interval.

local cpu1 = manager.machine.devices[":cpu1"]
local cpu2 = manager.machine.devices[":cpu2"]
local xdata = cpu2.spaces["xdata"]
local idata = cpu2.spaces["idata"]
local debugger = manager.machine.debugger
local active = false
local origin = 0
local points = {}
local breakpoints = {}
local stats = {}
local events = {}

local function add(address, label)
	points[address] = label
end

-- Main path and every conditional/loop boundary.
add(0x0003, "external_interrupt_0_vector")
add(0x000b, "timer_0_interrupt_vector")
add(0x1325, "config_entry")
add(0x1329, "config_value_loaded")
add(0x132b, "config_branch")
add(0x132d, "zero_path")
add(0x132f, "zero_setup_call")
add(0x1332, "zero_setup_return")
add(0x1334, "nonzero_path")
add(0x133a, "table_group_1_call")
add(0x133d, "table_group_2_call")
add(0x1340, "timer_setup")
add(0x134f, "t0_wait_low")
add(0x1352, "t0_wait_high")
add(0x1355, "t0_wait_low_2")
add(0x1358, "timer_start")
add(0x135a, "timer_count_loop")
add(0x135c, "timer_outer_loop")
add(0x135e, "timer_stop")
add(0x1360, "th0_check")
add(0x1362, "th0_branch")
add(0x1364, "tl0_check")
add(0x1366, "tl0_branch")
add(0x1369, "checkpoint_prepare")
add(0x136d, "checkpoint_write")
add(0x136e, "trace_end")

-- Zero-configuration setup, including its hardware-derived branches.
add(0x30f9, "zero_setup_entry")
add(0x3102, "frame_request")
add(0x3104, "frame_wait_set")
add(0x3106, "frame_wait_branch")
add(0x3109, "frame_wait_done")
add(0x310f, "config_source_read")
add(0x3112, "config_table_default")
add(0x3116, "config_table_branch")
add(0x3119, "config_table_alternate")
add(0x311c, "config_table_selected")
add(0x3127, "config_low_table_call")
add(0x312a, "config_low_table_done")
add(0x3131, "config_high_table_call")
add(0x3134, "config_high_table_done")
add(0x3141, "zero_setup_exit")

-- Two 17CF groups and all called table helpers.
for address, label in pairs({
	[0x17cf]="group_entry", [0x17d2]="group_reset_done",
	[0x17d7]="group_mode_write_done", [0x17d9]="group_zero_command",
	[0x17dc]="group_table_1", [0x17df]="group_table_1_call",
	[0x17e2]="group_table_2", [0x17e5]="group_table_2_call",
	[0x17e8]="group_table_3", [0x17eb]="group_table_3_call",
	[0x17ee]="group_table_4", [0x17f1]="group_table_4_call",
	[0x17f4]="reset_entry", [0x17fc]="reset_delay",
	[0x17fe]="reset_second_write", [0x17ff]="reset_bookkeeping",
	[0x1801]="reset_release", [0x1803]="reset_release_write",
	[0x1804]="reset_exit", [0x2f51]="config_copy_loop",
	[0x2f54]="config_copy_increment", [0x2f56]="config_copy_branch",
	[0x2f58]="config_copy_exit", [0xbb5f]="direct_table_entry",
	[0xbb63]="direct_table_record", [0xbb6b]="direct_table_value",
	[0xbb70]="direct_table_branch", [0xbb72]="direct_table_exit",
	[0xbb76]="id_table_entry", [0xbb7e]="id_table_record",
	[0xbb86]="id_table_command_done", [0xbb8e]="id_table_branch",
	[0xbb90]="id_table_exit", [0xbb91]="zero_command_entry",
	[0xbb99]="zero_command_exit", [0xbbb8]="control_write_entry",
	[0xbbbc]="control_write_exit"
}) do
	add(address, label)
end

local function cycles()
	return manager.machine.time:as_ticks(1000000) - origin
end

local function snapshot(label, pc)
	local stat = stats[pc]
	if not stat then
		stat = { label=label, count=0, first=cycles(), last=cycles() }
		stats[pc] = stat
	end
	stat.count = stat.count + 1
	stat.last = cycles()

	if label == "config_branch" or label == "frame_wait_branch" or
		label == "config_table_branch" or label == "t0_wait_low" or
		label == "t0_wait_high" or label == "t0_wait_low_2" or
		label == "th0_branch" or label == "tl0_branch" then
		table.insert(events, string.format(
			"BRANCH cycle=%d pc=%04X label=%s A=%02X idata21=%02X TCON=%02X TH0=%02X TL0=%02X P1=%02X P2=%02X P3=%02X",
			cycles(), pc, label, cpu2.state["A"].value,
			idata:read_u8(0x21), cpu2.state["TCON"].value,
			cpu2.state["TH0"].value, cpu2.state["TL0"].value,
			cpu2.state["P1"].value, cpu2.state["P2"].value,
			cpu2.state["P3"].value))
	end
end

for address, _ in pairs(points) do
	breakpoints[address] = cpu2.debug:bpset(address)
end

phase4_precheckpoint_read_tap = xdata:install_read_tap(
	0x0000, 0xffff, "phase4_precheckpoint_read",
	function(offset, value, mask)
		if active and (offset == 0xe795 or offset == 0x4c00 or
			(offset >= 0xf000 and offset <= 0xf0ff)) then
			table.insert(events, string.format(
				"XREAD cycle=%d pc=%04X address=%04X value=%02X P1=%02X P2=%02X P3=%02X",
				cycles(), cpu2.state["PC"].value, offset, value,
				cpu2.state["P1"].value, cpu2.state["P2"].value,
				cpu2.state["P3"].value))
		end
	end)

phase4_precheckpoint_write_tap = xdata:install_write_tap(
	0x0000, 0xffff, "phase4_precheckpoint_write",
	function(offset, value, mask)
		if active and ((offset >= 0xf000 and offset <= 0xf0ff) or
			offset == 0x7ff2) then
			table.insert(events, string.format(
				"XWRITE cycle=%d pc=%04X address=%04X value=%02X P1=%02X P2=%02X P3=%02X",
				cycles(), cpu2.state["PC"].value, offset, value,
				cpu2.state["P1"].value, cpu2.state["P2"].value,
				cpu2.state["P3"].value))
		end
	end)

local function finish()
	local addresses = {}
	for address, _ in pairs(stats) do table.insert(addresses, address) end
	table.sort(addresses)
	for _, address in ipairs(addresses) do
		local stat = stats[address]
		print(string.format(
			"PHASE4_PATH_BLOCK pc=%04X label=%s count=%d first_cycle=%d last_cycle=%d",
			address, stat.label, stat.count, stat.first, stat.last))
	end
	for _, event in ipairs(events) do
		print("PHASE4_PATH_" .. event)
	end
	print(string.format(
		"PHASE4_PATH_END total_cycles=%d cpu1_pc=%04X cpu2_pc=%04X",
		cycles(), cpu1.state["PC"].value, cpu2.state["PC"].value))
end

emu.register_periodic(function()
	if debugger.execution_state ~= "stop" then return end
	local pc = cpu2.state["PC"].value
	local label = points[pc]
	if not label then
		print(string.format("PHASE4_PATH_UNEXPECTED pc=%04X", pc))
		debugger.execution_state = "run"
		return
	end
	if pc == 0x1325 and not active then
		origin = manager.machine.time:as_ticks(1000000)
		active = true
	end
	if active then snapshot(label, pc) end
	if pc == 0x136e and active then
		finish()
		active = false
		manager.machine:exit()
		return
	end
	debugger.execution_state = "run"
end)

debugger.execution_state = "run"

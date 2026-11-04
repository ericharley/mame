-- Trace CPU2 from CPU1's reset release through its first DAT9 rendezvous.
-- This script is read-only and exits when CPU2 reaches 1701.

local cpu1 = manager.machine.devices[":cpu1"]
local cpu2 = manager.machine.devices[":cpu2"]
local debugger = manager.machine.debugger
local start_time = nil
local active = false
local accesses = 0
local sbuf_writes = 0
local finished = false

local points = {
	[":cpu1:390E"] = "cpu1_reset_release",
	[":cpu1:3910"] = "cpu1_keyboard_block_call",
	[":cpu1:3AC9"] = "cpu1_keyboard_block_entry",
	[":cpu1:3913"] = "cpu1_board_probe_setup",
	[":cpu1:3916"] = "cpu1_board_probe_call",
	[":cpu1:3919"] = "cpu1_request_low",
	[":cpu1:391E"] = "cpu1_request_release",
	[":cpu1:3922"] = "cpu1_response_wait_low",
	[":cpu1:3929"] = "cpu1_response_low_seen",
	[":cpu1:3952"] = "cpu1_response_complete",
	[":cpu2:0000"] = "cpu2_reset_vector",
	[":cpu2:125F"] = "cpu2_post_entry",
	[":cpu2:126B"] = "cpu2_first_board_read",
	[":cpu2:126C"] = "cpu2_wait_board_low",
	[":cpu2:126F"] = "cpu2_board_low_seen",
	[":cpu2:1271"] = "cpu2_startup_turnaround",
	[":cpu2:127A"] = "cpu2_board_init_1",
	[":cpu2:127D"] = "cpu2_dc323_reset_1",
	[":cpu2:1280"] = "cpu2_table_setup",
	[":cpu2:1288"] = "cpu2_table_write",
	[":cpu2:128B"] = "cpu2_board_init_2",
	[":cpu2:1291"] = "cpu2_status_wait_entry",
	[":cpu2:1294"] = "cpu2_wait_status_high",
	[":cpu2:1297"] = "cpu2_wait_status_low",
	[":cpu2:129A"] = "cpu2_iram_test",
	[":cpu2:12BA"] = "cpu2_iram_test_done",
	[":cpu2:12BD"] = "cpu2_first_rendezvous_call",
	[":cpu2:1701"] = "cpu2_first_dat9_low",
	[":cpu2:1709"] = "cpu2_first_dat9_release",
	[":cpu2:170E"] = "cpu2_wait_cpu1_low",
	[":cpu2:1711"] = "cpu2_cpu1_low_seen",
}

local breakpoints = {}
for key, _ in pairs(points) do
	local tag, address = key:match("^(:cpu%d):(%x+)$")
	breakpoints[key] = manager.machine.devices[tag].debug:bpset(tonumber(address, 16))
end

local function elapsed(now)
	if not start_time then
		return -1
	end
	return (now - start_time) * 1000000
end

phase4_reset_cpu2_xdata_read = cpu2.spaces["xdata"]:install_read_tap(
	0x0000, 0xffff, "phase4_reset_cpu2_xdata_read",
	function(offset, value, mask)
		if active then
			accesses = accesses + 1
			print(string.format(
				"RESET_TO_DAT9_IO us=%.3f op=R pc=%04X address=%04X value=%02X",
				elapsed(manager.machine.time:as_double()), cpu2.state["PC"].value,
				offset, value))
		end
	end)

phase4_reset_cpu2_xdata_write = cpu2.spaces["xdata"]:install_write_tap(
	0x0000, 0xffff, "phase4_reset_cpu2_xdata_write",
	function(offset, value, mask)
		if active then
			accesses = accesses + 1
			print(string.format(
				"RESET_TO_DAT9_IO us=%.3f op=W pc=%04X address=%04X value=%02X",
				elapsed(manager.machine.time:as_double()), cpu2.state["PC"].value,
				offset, value))
		end
	end)

phase4_reset_cpu1_sbuf_write = cpu1.spaces["sfr"]:install_write_tap(
	0x99, 0x99, "phase4_reset_cpu1_sbuf_write",
	function(offset, value, mask)
		if active then
			sbuf_writes = sbuf_writes + 1
			print(string.format(
				"RESET_TO_DAT9_UART us=%.3f byte=%d value=%02X pc=%04X",
				elapsed(manager.machine.time:as_double()), sbuf_writes, value,
				cpu1.state["PC"].value))
		end
	end)

emu.register_periodic(function()
	if debugger.execution_state ~= "stop" then
		return
	end
	if finished then
		return
	end

	local key1 = string.format(":cpu1:%04X", cpu1.state["PC"].value)
	local key2 = string.format(":cpu2:%04X", cpu2.state["PC"].value)
	local key = points[key1] and key1 or key2
	local label = points[key]
	if label then
		local now = manager.machine.time:as_double()
		local tag = key:match("^(:cpu%d)")
		manager.machine.devices[tag].debug:bpclear(breakpoints[key])
		if label == "cpu1_reset_release" and not start_time then
			start_time = now
			active = true
		end
		if active then
			print(string.format(
				"RESET_TO_DAT9 us=%.3f event=%s cpu1=%04X cpu2=%04X p1=%02X p3=%02X",
				elapsed(now), label, cpu1.state["PC"].value,
				cpu2.state["PC"].value, cpu2.state["P1"].value,
				cpu1.state["P3"].value))
		end
		if label == "cpu1_response_complete" then
			finished = true
			print(string.format(
				"RESET_TO_DAT9_SUMMARY us=%.3f accesses=%d sbuf_writes=%d",
				elapsed(now), accesses, sbuf_writes))
			manager.machine:exit()
			return
		end
	end
	debugger.execution_state = "run"
end)

debugger.execution_state = "run"

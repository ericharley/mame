-- Diagnostic-only cold-boot capture across CPU1's native 7FF2 timeout path.
-- This script observes execution and screen output; it does not alter state.

local cpu1 = manager.machine.devices[":cpu1"]
local cpu2 = manager.machine.devices[":cpu2"]
local cpu1_xdata = cpu1.spaces["xdata"]
local cpu2_xdata = cpu2.spaces["xdata"]
local screen = manager.machine.screens[":screen"]
local debugger = manager.machine.debugger

local cpu1_points = {
	[0x3a21] = "checkpoint_wait_exit",
	[0x3a31] = "result_wait",
	[0x3a3a] = "result_classify",
	[0x4551] = "startup_entry",
	[0x455d] = "startup_after_4fa8",
	[0x4567] = "startup_after_4faa",
	[0x456d] = "startup_after_3bee",
	[0x4570] = "startup_after_3d2b",
	[0x4575] = "startup_after_a5a8",
	[0x4578] = "startup_after_ea39",
	[0x457b] = "startup_after_7289_1",
	[0x457e] = "startup_after_fcb9_1",
	[0x4581] = "startup_after_eadc",
	[0x4584] = "startup_after_7289_2",
	[0x4587] = "startup_restore",
	[0x7289] = "init_7289_entry",
	[0x728c] = "init_after_fc62",
	[0x7296] = "init_after_446x",
	[0x7299] = "init_after_7399",
	[0x729c] = "init_after_c00d",
	[0x729f] = "init_after_b8d1",
	[0x72a2] = "init_after_ae02",
	[0x72a7] = "init_after_a4b0",
	[0x72aa] = "init_after_a477",
	[0x72ad] = "init_after_a486",
	[0x72b3] = "init_a301_poll",
	[0x72b8] = "init_a301_complete",
	[0x72bb] = "init_after_a500",
	[0x72be] = "init_after_a52c",
	[0x72c1] = "init_after_a537",
	[0x72c4] = "init_after_f2a7",
	[0x72c9] = "init_after_7150",
	[0x72ce] = "init_after_641e",
	[0x72d1] = "init_after_3f36",
	[0x72d4] = "init_after_dbd0",
	[0x41f7] = "startup_decision",
	[0x42b0] = "normal_transition",
	[0x48f6] = "command32_submit"
}

local cpu2_points = {
	[0xdb98] = "command32_handler",
	[0xdc02] = "command32_ring_poll",
	[0xdc18] = "wait_latch_clear_path",
	[0xdc1d] = "wait_latch_cleared"
}

local cpu1_breakpoints = {}
local cpu2_breakpoints = {}
for address, _ in pairs(cpu1_points) do
	cpu1_breakpoints[address] = cpu1.debug:bpset(address)
end
for address, _ in pairs(cpu2_points) do
	cpu2_breakpoints[address] = cpu2.debug:bpset(address)
end

local capture_times = { 115, 119, 120, 121, 125, 130, 140, 160, 180, 240, 300 }
local next_capture = 1
local late_dc323_commands = 0
local dc02_hits = 0

phase4_post_timeout_dc323 = cpu2_xdata:install_write_tap(
	0xf000, 0xffff, "phase4_post_timeout_dc323",
	function(offset, value, mask)
		local now = manager.machine.time:as_double()
		local register = offset & 0x3f
		if now >= 115 and ((offset & 0xf0c0) == 0xf000) and
			(register == 0x07 or register == 0x08) then
			late_dc323_commands = late_dc323_commands + 1
			print(string.format(
				"PHASE4_POST_TIMEOUT t=%.9f event=dc323_write cpu2=%04X address=%04X data=%02X p1=%02X",
				now, cpu2.state["PC"].value, offset, value,
				cpu2.state["P1"].value))
		end
	end)

phase4_post_timeout_shared = cpu2_xdata:install_write_tap(
	0x7e7e, 0x7ff7, "phase4_post_timeout_shared",
	function(offset, value, mask)
		local now = manager.machine.time:as_double()
		if now >= 119.9 and
			(offset == 0x7e7e or offset == 0x7e7f or offset == 0x7ff7) then
			print(string.format(
				"PHASE4_POST_TIMEOUT t=%.9f event=shared_write cpu1=%04X cpu2=%04X address=%04X data=%02X",
				now, cpu1.state["PC"].value, cpu2.state["PC"].value,
				offset, value))
		end
	end)

phase4_post_timeout_shared_cpu1 = cpu1_xdata:install_write_tap(
	0x7e7e, 0x7ff7, "phase4_post_timeout_shared_cpu1",
	function(offset, value, mask)
		local now = manager.machine.time:as_double()
		if now >= 119.9 and
			(offset == 0x7e7e or offset == 0x7e7f or offset == 0x7ff7) then
			print(string.format(
				"PHASE4_POST_TIMEOUT t=%.9f event=shared_write_cpu1 cpu1=%04X cpu2=%04X address=%04X data=%02X",
				now, cpu1.state["PC"].value, cpu2.state["PC"].value,
				offset, value))
		end
	end)

emu.register_frame_done(function()
	local now = manager.machine.time:as_double()
	while next_capture <= #capture_times and now >= capture_times[next_capture] do
		local capture = capture_times[next_capture]
		local path = string.format("/tmp/vt340-post-timeout-%03d.png", capture)
		screen:snapshot(path)
		print(string.format(
			"PHASE4_POST_TIMEOUT t=%.9f event=snapshot path=%s cpu1=%04X cpu2=%04X",
			now, path, cpu1.state["PC"].value, cpu2.state["PC"].value))
		next_capture = next_capture + 1
	end
end)

emu.register_periodic(function()
	if debugger.execution_state ~= "stop" then return end

	local cpu1_pc = cpu1.state["PC"].value
	local cpu2_pc = cpu2.state["PC"].value
	local cpu1_label = cpu1_points[cpu1_pc]
	local cpu2_label = cpu2_points[cpu2_pc]
	if cpu1_label then
		print(string.format(
			"PHASE4_POST_TIMEOUT t=%.9f event=%s cpu1=%04X cpu2=%04X A=%02X B=%02X SP=%02X value7ff2=%02X producer=%02X consumer=%02X",
			manager.machine.time:as_double(), cpu1_label, cpu1_pc, cpu2_pc,
			cpu1.state["A"].value, cpu1.state["B"].value,
			cpu1.state["SP"].value, cpu2_xdata:read_u8(0x7ff2),
			cpu2_xdata:read_u8(0x7e7e), cpu2_xdata:read_u8(0x7e7f)))
		cpu1.debug:bpclear(cpu1_breakpoints[cpu1_pc])
	elseif cpu2_label then
		if cpu2_pc == 0xdc02 then dc02_hits = dc02_hits + 1 end
		print(string.format(
			"PHASE4_POST_TIMEOUT t=%.9f event=%s cpu1=%04X cpu2=%04X SP=%02X producer=%02X consumer=%02X wait=%02X",
			manager.machine.time:as_double(), cpu2_label, cpu1_pc, cpu2_pc,
			cpu2.state["SP"].value, cpu2_xdata:read_u8(0x7e7e),
			cpu2_xdata:read_u8(0x7e7f), cpu2_xdata:read_u8(0x60bb)))
		-- DC02 may poll repeatedly; retain only five representative hits.
		if cpu2_pc ~= 0xdc02 or dc02_hits >= 5 then
			cpu2.debug:bpclear(cpu2_breakpoints[cpu2_pc])
		end
	end
	debugger.execution_state = "run"
end)

phase4_post_timeout_stop = emu.add_machine_stop_notifier(function()
	print(string.format(
		"PHASE4_POST_TIMEOUT_DONE t=%.9f cpu1=%04X cpu2=%04X producer=%02X consumer=%02X wait=%02X dc323_commands=%d",
		manager.machine.time:as_double(), cpu1.state["PC"].value,
		cpu2.state["PC"].value, cpu2_xdata:read_u8(0x7e7e),
		cpu2_xdata:read_u8(0x7e7f), cpu2_xdata:read_u8(0x60bb),
		late_dc323_commands))
end)

debugger.execution_state = "run"

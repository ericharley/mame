local cpu1 = manager.machine.devices[":cpu1"]
local cpu2 = manager.machine.devices[":cpu2"]
local cpu2_xdata = cpu2.spaces["xdata"]
local debugger = manager.machine.debugger
local breakpoints = {}
local hits = {}
local active = false
local start_time = nil
local response_time = nil
local ack_time = nil
local pulse_time = nil

local points = {
	[":cpu1:000B"] = "cpu1_timer0_vector",
	[":cpu1:3AC9"] = "cpu1_uart_block",
	[":cpu1:3B8E"] = "cpu1_pulse",
	[":cpu1:3BC8"] = "cpu1_response",
	[":cpu1:3BCE"] = "cpu1_response_return",
	[":cpu2:0003"] = "cpu2_int0_vector",
	[":cpu2:000B"] = "cpu2_timer0_vector",
	[":cpu2:1325"] = "cpu2_config",
	[":cpu2:132F"] = "cpu2_zero_config_call",
	[":cpu2:30F9"] = "cpu2_zero_config_entry",
	[":cpu2:3106"] = "cpu2_frame_wait",
	[":cpu2:3127"] = "cpu2_table1",
	[":cpu2:3131"] = "cpu2_table2",
	[":cpu2:3141"] = "cpu2_zero_config_return",
	[":cpu2:1332"] = "cpu2_zero_config_done",
	[":cpu2:133A"] = "cpu2_tables1_call",
	[":cpu2:133D"] = "cpu2_tables2_call",
	[":cpu2:1340"] = "cpu2_timer_setup",
	[":cpu2:134F"] = "cpu2_t0_wait_low",
	[":cpu2:1352"] = "cpu2_t0_wait_high",
	[":cpu2:1355"] = "cpu2_t0_wait_low2",
	[":cpu2:1358"] = "cpu2_timer_start",
	[":cpu2:135A"] = "cpu2_timer_delay",
	[":cpu2:135E"] = "cpu2_timer_stop",
	[":cpu2:1360"] = "cpu2_th0_check",
	[":cpu2:1364"] = "cpu2_tl0_check",
	[":cpu2:1369"] = "cpu2_ack_prepare",
	[":cpu2:136D"] = "cpu2_ack",
	[":cpu2:17CF"] = "cpu2_table_group",
	[":cpu2:17F4"] = "cpu2_table_reset",
}

for key, _ in pairs(points) do
	local tag, address = key:match("^(:cpu%d):(%x+)$")
	breakpoints[key] = manager.machine.devices[tag].debug:bpset(tonumber(address, 16))
end

local function elapsed(now, origin)
	if not origin then
		return -1
	end
	return (now - origin) * 1000000
end

local function record(label)
	local now = manager.machine.time:as_double()
	hits[label] = (hits[label] or 0) + 1
	print(string.format(
		"PHASE4_INTERVAL t=%.9f from_config_us=%.3f from_response_us=%.3f event=%s hit=%d cpu1=%04X cpu2=%04X SP1=%02X SP2=%02X P1=%02X P3=%02X TCON1=%02X TCON2=%02X",
		now, elapsed(now, start_time), elapsed(now, response_time), label,
		hits[label], cpu1.state["PC"].value, cpu2.state["PC"].value,
		cpu1.state["SP"].value, cpu2.state["SP"].value,
		cpu2.state["P1"].value, cpu1.state["P3"].value,
		cpu1.state["TCON"].value, cpu2.state["TCON"].value))
end

phase4_interval_video_write_tap = cpu2_xdata:install_write_tap(
	0xf000, 0xf0ff, "phase4_interval_video_write",
	function(offset, value, mask)
		if active and not ack_time then
			local now = manager.machine.time:as_double()
			print(string.format(
				"PHASE4_INTERVAL_IO t=%.9f from_config_us=%.3f pc=%04X address=%04X value=%02X P1=%02X",
				now, elapsed(now, start_time), cpu2.state["PC"].value,
				offset, value, cpu2.state["P1"].value))
		end
	end)

phase4_interval_sbuf_write_tap = cpu1.spaces["sfr"]:install_write_tap(
	0x99, 0x99, "phase4_interval_sbuf_write",
	function(offset, value, mask)
		if active then
			local now = manager.machine.time:as_double()
			hits.cpu1_sbuf_write = (hits.cpu1_sbuf_write or 0) + 1
			print(string.format(
				"PHASE4_INTERVAL_UART t=%.9f from_config_us=%.3f from_response_us=%.3f byte=%d value=%02X cpu1=%04X cpu2=%04X",
				now, elapsed(now, start_time), elapsed(now, response_time),
				hits.cpu1_sbuf_write, value, cpu1.state["PC"].value,
				cpu2.state["PC"].value))
		end
	end)

emu.register_periodic(function()
	if debugger.execution_state ~= "stop" then
		return
	end

	local key1 = string.format(":cpu1:%04X", cpu1.state["PC"].value)
	local key2 = string.format(":cpu2:%04X", cpu2.state["PC"].value)
	local key = points[key1] and key1 or key2
	local label = points[key]
	if label then
		if label == "cpu2_config" then
			start_time = manager.machine.time:as_double()
			active = true
		end

		if active then
			if label == "cpu1_response" then
				response_time = manager.machine.time:as_double()
			end
			record(label)
			if label == "cpu2_timer_delay" or label == "cpu2_t0_wait_low2" then
				cpu2.debug:bpclear(breakpoints[key])
			end

			if label == "cpu2_ack" then
				ack_time = manager.machine.time:as_double()
			end
			if label == "cpu1_pulse" then
				pulse_time = manager.machine.time:as_double()
				active = false
				manager.machine:exit()
				return
			end
		end
	end
	debugger.execution_state = "run"
end)

phase4_interval_stop_subscription = emu.add_machine_stop_notifier(function()
	print(string.format(
		"PHASE4_INTERVAL_SUMMARY config_to_ack_us=%.3f response_to_ack_us=%.3f response_to_pulse_us=%.3f ack_to_pulse_us=%.3f cpu1_timer0=%d cpu2_int0=%d cpu2_timer0=%d uart_blocks=%d sbuf_writes=%d table_groups=%d",
		elapsed(ack_time, start_time), elapsed(ack_time, response_time),
		elapsed(pulse_time, response_time), elapsed(pulse_time, ack_time),
		hits.cpu1_timer0_vector or 0, hits.cpu2_int0_vector or 0,
		hits.cpu2_timer0_vector or 0, hits.cpu1_uart_block or 0,
		hits.cpu1_sbuf_write or 0, hits.cpu2_table_group or 0))
end)

debugger.execution_state = "run"

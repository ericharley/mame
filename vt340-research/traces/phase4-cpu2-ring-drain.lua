-- Regression trace for DC323 interrupt acknowledgement and CPU2 ring drain.

local cpu1 = manager.machine.devices[":cpu1"]
local cpu2 = manager.machine.devices[":cpu2"]
local xdata1 = cpu1.spaces["xdata"]
local xdata2 = cpu2.spaces["xdata"]
local debugger = manager.machine.debugger

local points1 = {
	[0x72c4] = "first_ring_drained",
	[0x4587] = "startup_restore",
	[0x41f7] = "startup_decision",
	[0x48f6] = "command32_submit"
}
local points2 = {
	[0xdb98] = "command32_handler",
	[0xdc02] = "command32_ring_poll"
}
local bp1 = {}
local bp2 = {}
for address, _ in pairs(points1) do bp1[address] = cpu1.debug:bpset(address) end
for address, _ in pairs(points2) do bp2[address] = cpu2.debug:bpset(address) end

local producer_writes = 0
local consumer_writes = 0
local ack_fe = 0
local ack_fd = 0
local ack_other = 0
local first_ack_time = nil
local last_ack_time = nil
local completed = false

phase4_ring_drain_producer = xdata1:install_write_tap(
	0x7e7e, 0x7e7e, "phase4_ring_drain_producer",
	function(offset, value, mask)
		if manager.machine.time:as_double() >= 119.9 then
			producer_writes = producer_writes + 1
		end
	end)

phase4_ring_drain_consumer = xdata2:install_write_tap(
	0x7e7f, 0x7e7f, "phase4_ring_drain_consumer",
	function(offset, value, mask)
		if manager.machine.time:as_double() >= 119.9 then
			consumer_writes = consumer_writes + 1
		end
	end)

phase4_ring_drain_ack = xdata2:install_write_tap(
	0xf003, 0xf003, "phase4_ring_drain_ack",
	function(offset, value, mask)
		if cpu2.state["PC"].value ~= 0x0053 and
			cpu2.state["PC"].value ~= 0x03ec then return end
		local now = manager.machine.time:as_double()
		if now < 110 then return end
		if value == 0xfe then
			ack_fe = ack_fe + 1
		elseif value == 0xfd then
			ack_fd = ack_fd + 1
		else
			ack_other = ack_other + 1
		end
		if not first_ack_time then first_ack_time = now end
		last_ack_time = now
	end)

local function report(label)
	print(string.format(
		"PHASE4_RING_DRAIN t=%.9f event=%s cpu1=%04X cpu2=%04X producer=%02X consumer=%02X wait=%02X",
		manager.machine.time:as_double(), label, cpu1.state["PC"].value,
		cpu2.state["PC"].value, xdata2:read_u8(0x7e7e),
		xdata2:read_u8(0x7e7f), xdata2:read_u8(0x60bb)))
end

emu.register_periodic(function()
	if debugger.execution_state ~= "stop" then return end
	local pc1 = cpu1.state["PC"].value
	local pc2 = cpu2.state["PC"].value
	if points1[pc1] then
		report(points1[pc1])
		cpu1.debug:bpclear(bp1[pc1])
	elseif points2[pc2] then
		report(points2[pc2])
		cpu2.debug:bpclear(bp2[pc2])
		if pc2 == 0xdc02 then
			completed = true
			manager.machine:exit()
			return
		end
	end
	debugger.execution_state = "run"
end)

phase4_ring_drain_stop = emu.add_machine_stop_notifier(function()
	local interval = 0
	if first_ack_time and last_ack_time and (ack_fe + ack_fd + ack_other) > 1 then
		interval = (last_ack_time - first_ack_time) /
			(ack_fe + ack_fd + ack_other - 1)
	end
	print(string.format(
		"PHASE4_RING_DRAIN_%s producer_writes=%d consumer_writes=%d ack_fe=%d ack_fd=%d ack_other=%d mean_ack_interval=%.9f",
		completed and "PASS" or "FAIL", producer_writes, consumer_writes,
		ack_fe, ack_fd, ack_other, interval))
end)

debugger.execution_state = "run"

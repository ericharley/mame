local cpu1 = manager.machine.devices[":cpu1"]
local cpu2 = manager.machine.devices[":cpu2"]
local data = cpu2.spaces["xdata"]
local debugger = manager.machine.debugger
local wait_latched = false
local request_seen = false
local result_seen = false
local ack_wait_seen = false
local command32_seen = false
local wait_bp
local request_bp
local result_bp
local ack_wait_bp
local command32_bp

wait_bp = cpu2.debug:bpset(0x17b3)
request_bp = cpu1.debug:bpset(0x3a0d)
result_bp = cpu2.debug:bpset(0x1639)
ack_wait_bp = cpu1.debug:bpset(0x3a18)
command32_bp = cpu1.debug:bpset(0x48f6)

emu.register_periodic(function()
	if debugger.execution_state ~= "stop" then
		return
	end

	local cpu1_pc = cpu1.state["PC"].value
	local cpu2_pc = cpu2.state["PC"].value
	if cpu2_pc == 0x17b3 and not wait_latched then
		wait_latched = data:read_u8(0x60bb) == 0x01
		cpu2.debug:bpclear(wait_bp)
		print(string.format("PHASE2_NORMAL wait_latch=%02X", data:read_u8(0x60bb)))
	elseif cpu1_pc == 0x3a0d and not request_seen then
		request_seen = true
		cpu1.debug:bpclear(request_bp)
		print("PHASE2_NORMAL request=3A0D")
	elseif cpu2_pc == 0x1639 and not result_seen then
		result_seen = true
		cpu2.debug:bpclear(result_bp)
		print("PHASE2_NORMAL result=1639")
	elseif cpu1_pc == 0x3a18 and not ack_wait_seen then
		ack_wait_seen = true
		cpu1.debug:bpclear(ack_wait_bp)
		print("PHASE2_NORMAL ack_wait=3A18")
	elseif cpu1_pc == 0x48f6 then
		command32_seen = true
		cpu1.debug:bpclear(command32_bp)
		print("PHASE2_NORMAL unexpected_command32=1")
	end
	debugger.execution_state = "run"
end)

phase2_stop_subscription = emu.add_machine_stop_notifier(function()
	if wait_latched and request_seen and result_seen and ack_wait_seen and not command32_seen then
		print("PHASE2_NORMAL_PASS wait=1 request=1 result=1 ack_wait=1 command32=0")
	else
		print(string.format(
			"PHASE2_NORMAL_FAIL wait=%d request=%d result=%d ack_wait=%d command32=%d",
			wait_latched and 1 or 0,
			request_seen and 1 or 0,
			result_seen and 1 or 0,
			ack_wait_seen and 1 or 0,
			command32_seen and 1 or 0))
	end
end)

debugger.execution_state = "run"

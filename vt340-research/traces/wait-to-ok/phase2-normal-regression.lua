local cpu1 = manager.machine.devices[":cpu1"]
local cpu2 = manager.machine.devices[":cpu2"]
local data = cpu2.spaces["xdata"]
local debugger = manager.machine.debugger
local wait_latched = false
local b6_observed = false
local command32_seen = false
local wait_bp
local decision_bp
local command32_bp

wait_bp = cpu2.debug:bpset(0x17b3)
decision_bp = cpu1.debug:bpset(0x41f7)
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
	elseif cpu1_pc == 0x41f7 and not b6_observed then
		local b = cpu1.state["B"].value
		b6_observed = (b & 0x40) ~= 0
		cpu1.debug:bpclear(decision_bp)
		print(string.format("PHASE2_NORMAL decision=41F7 B=%02X", b))
	elseif cpu1_pc == 0x48f6 then
		command32_seen = true
		cpu1.debug:bpclear(command32_bp)
		print("PHASE2_NORMAL unexpected_command32=1")
	end
	debugger.execution_state = "run"
end)

phase2_stop_subscription = emu.add_machine_stop_notifier(function()
	if wait_latched and b6_observed and not command32_seen then
		print("PHASE2_NORMAL_PASS wait=1 b6=1 command32=0")
	else
		print(string.format(
			"PHASE2_NORMAL_FAIL wait=%d b6=%d command32=%d",
			wait_latched and 1 or 0,
			b6_observed and 1 or 0,
			command32_seen and 1 or 0))
	end
end)

debugger.execution_state = "run"

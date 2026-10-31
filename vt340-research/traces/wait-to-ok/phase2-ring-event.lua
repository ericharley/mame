local cpu1 = manager.machine.devices[":cpu1"]
local cpu2 = manager.machine.devices[":cpu2"]
local data = cpu2.spaces["xdata"]
local debugger = manager.machine.debugger
local stage = 0
local breakpoint

debugger:command("temp0 = 0")
cpu1.debug:bpset(0x41f7, "temp0 == 0", "temp0 = 1 ; b = 0 ; g")
breakpoint = cpu2.debug:bpset(0xdc02)

emu.register_periodic(function()
	if debugger.execution_state ~= "stop" then
		return
	end

	local pc = cpu2.state["PC"].value
	if stage == 0 and pc == 0xdc02 then
		local producer = data:read_u8(0x7e7e)
		local consumer = data:read_u8(0x7e7f)
		local next_producer = (producer + 1) % 0x7e
		if producer ~= consumer then
			print(string.format(
				"PHASE2_RING_FAIL initial producer=%02X consumer=%02X", producer, consumer))
			debugger:command("quit")
			return
		end

		-- Diagnostic only: make one queue slot visible.  Execution stops after
		-- DC1C clears 60BB, before the decoder can interpret the sentinel byte.
		data:write_u8(0x7e00 + producer, 0xa5)
		data:write_u8(0x7e7e, next_producer)
		print(string.format(
			"PHASE2_RING_INJECT t=%.9f slot=%02X data=A5 producer=%02X->%02X consumer=%02X latch=%02X",
			manager.machine.time:as_double(), producer, producer, next_producer,
			consumer, data:read_u8(0x60bb)))
		cpu2.debug:bpclear(breakpoint)
		breakpoint = cpu2.debug:bpset(0xdc18)
		stage = 1
		debugger.execution_state = "run"
	elseif stage == 1 and pc == 0xdc18 then
		print(string.format(
			"PHASE2_RING_BRANCH t=%.9f pc=DC18 producer=%02X consumer=%02X latch_before=%02X",
			manager.machine.time:as_double(), data:read_u8(0x7e7e),
			data:read_u8(0x7e7f), data:read_u8(0x60bb)))
		cpu2.debug:bpclear(breakpoint)
		breakpoint = cpu2.debug:bpset(0xdc1d)
		stage = 2
		debugger.execution_state = "run"
	elseif stage == 2 and pc == 0xdc1d then
		local latch = data:read_u8(0x60bb)
		print(string.format(
			"PHASE2_RING_PASS t=%.9f pc=DC1D latch_after=%02X",
			manager.machine.time:as_double(), latch))
		cpu2.debug:bpclear(breakpoint)
		stage = 3
		debugger:command("quit")
	else
		print(string.format("PHASE2_RING_FAIL stage=%d cpu2_pc=%04X", stage, pc))
		debugger:command("quit")
	end
end)

debugger.execution_state = "run"

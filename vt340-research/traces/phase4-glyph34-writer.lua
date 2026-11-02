-- Bounded CPU2 instruction trace from command 32 to the first R3=34 glyph.

local cpu2 = manager.machine.devices[":cpu2"]
local debugger = manager.machine.debugger
local trace_started = false
local captured = false
local start_bp = cpu2.debug:bpset(0xdb98)
local glyph_bp = cpu2.debug:bpset(0xc267)

emu.register_periodic(function()
	if debugger.execution_state ~= "stop" then return end
	local pc = cpu2.state["PC"].value
	if pc == 0xdb98 and not trace_started then
		trace_started = true
		cpu2.debug:bpclear(start_bp)
		debugger:command(
			"trace /tmp/vt340-glyph34-writer.tr,cpu2,,{tracelog \"A=%02X B=%02X R3=%02X R6=%02X R7=%02X DPTR=%04X PSW=%02X \",a,b,r3,r6,r7,dptr,psw}")
		print(string.format("PHASE4_GLYPH34_WRITER t=%.9f event=trace_start",
			manager.machine.time:as_double()))
	elseif pc == 0xc267 and trace_started and
		manager.machine.time:as_double() >= 121.7 and
		cpu2.state["R3"].value == 0x34 then
		captured = true
		cpu2.debug:bpclear(glyph_bp)
		debugger:command("trace off,cpu2")
		print(string.format(
			"PHASE4_GLYPH34_WRITER t=%.9f event=trace_stop R3=%02X DPTR=%04X",
			manager.machine.time:as_double(), cpu2.state["R3"].value,
			cpu2.state["DPTR"].value))
		manager.machine:exit()
		return
	end
	debugger.execution_state = "run"
end)

phase4_glyph34_writer_stop = emu.add_machine_stop_notifier(function()
	print(string.format("PHASE4_GLYPH34_WRITER_%s",
		captured and "PASS" or "FAIL"))
end)

debugger.execution_state = "run"

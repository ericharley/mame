-- Trace the first post-command-32 glyph back to ring data and CPU2 R3.

local cpu1 = manager.machine.devices[":cpu1"]
local cpu2 = manager.machine.devices[":cpu2"]
local xdata1 = cpu1.spaces["xdata"]
local xdata2 = cpu2.spaces["xdata"]
local debugger = manager.machine.debugger
local captured = false

phase4_glyph34_producer = xdata1:install_write_tap(
	0x7e00, 0x7e7d, "phase4_glyph34_producer",
	function(offset, value, mask)
		local now = manager.machine.time:as_double()
		if now >= 121.6 then
			print(string.format(
				"PHASE4_GLYPH34 t=%.9f event=produce pc=%04X slot=%02X value=%02X producer=%02X consumer=%02X",
				now, cpu1.state["PC"].value, offset & 0x7f, value,
				xdata1:read_u8(0x7e7e), xdata1:read_u8(0x7e7f)))
		end
	end)

phase4_glyph34_consumer = xdata2:install_read_tap(
	0x7e00, 0x7e7d, "phase4_glyph34_consumer",
	function(offset, value, mask)
		local now = manager.machine.time:as_double()
		if now >= 121.6 then
			print(string.format(
				"PHASE4_GLYPH34 t=%.9f event=consume pc=%04X slot=%02X value=%02X producer=%02X consumer=%02X",
				now, cpu2.state["PC"].value, offset & 0x7f, value,
				xdata2:read_u8(0x7e7e), xdata2:read_u8(0x7e7f)))
		end
	end)

local c194_bp = cpu2.debug:bpset(0xc194)
local c267_bp = cpu2.debug:bpset(0xc267)

emu.register_periodic(function()
	if debugger.execution_state ~= "stop" then return end
	local now = manager.machine.time:as_double()
	local pc = cpu2.state["PC"].value
	local r3 = cpu2.state["R3"].value
	if now >= 121.7 and r3 == 0x34 and (pc == 0xc194 or pc == 0xc267) then
		print(string.format(
			"PHASE4_GLYPH34 t=%.9f event=glyph_entry pc=%04X R3=%02X R6=%02X R7=%02X DPTR=%04X P1=%02X producer=%02X consumer=%02X",
			now, pc, r3, cpu2.state["R6"].value,
			cpu2.state["R7"].value, cpu2.state["DPTR"].value,
			cpu2.state["P1"].value, xdata2:read_u8(0x7e7e),
			xdata2:read_u8(0x7e7f)))
		captured = true
		cpu2.debug:bpclear(c194_bp)
		cpu2.debug:bpclear(c267_bp)
	elseif now >= 121.7 and pc == 0xc194 then
		-- Keep looking until the repeated 34 cell is reached.
	elseif now >= 121.7 and pc == 0xc267 then
		-- Keep looking until the repeated 34 cell is reached.
	end
	debugger.execution_state = "run"
end)

phase4_glyph34_stop = emu.add_machine_stop_notifier(function()
	print(string.format("PHASE4_GLYPH34_%s", captured and "PASS" or "FAIL"))
end)

debugger.execution_state = "run"

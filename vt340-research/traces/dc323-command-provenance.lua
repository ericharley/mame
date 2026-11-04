-- Trace where native CPU2 firmware emits DC323 commands.
--
-- This is an observer only.  It groups command-register writes by active ROM
-- bank, emitting PC, command value, X-control mode, most recently selected
-- CPU1-to-CPU2 packet handler, and the raw top of the CPU2 stack.  The stack
-- bytes make calls through the shared low-ROM helpers (notably 28cd/28da)
-- distinguishable from direct command writes.

io.stdout:setvbuf("no")

local cpu2 = manager.machine.devices[":cpu2"]
local xdata = cpu2.spaces["xdata"]
local idata = cpu2.spaces["idata"]

local regs = {}
local groups = {}
local total = 0

local function bank_name()
	-- P3.3 is ROMBANK1 L at the board interface; the reconstructed cartridge
	-- establishes high = E4 and low = E5.
	return (cpu2.state["P3"].value & 0x08) ~= 0 and "E4" or "E5"
end

local function packet_handler()
	return xdata:read_u8(0x60ab) | (xdata:read_u8(0x60ac) << 8)
end

local function stack_bytes()
	local sp = cpu2.state["SP"].value
	local bytes = {}
	for depth = 0, math.min(sp, 23) do
		bytes[#bytes + 1] = string.format("%02X", idata:read_u8((sp - depth) & 0xff))
	end
	return sp, table.concat(bytes, "")
end

dc323_command_provenance_tap = xdata:install_write_tap(
	0xf000, 0xf03f, "dc323_command_provenance",
	function(offset, data, mask)
		local reg = offset & 0x3f
		local value = (cpu2.state["P1"].value << 8) | data
		regs[reg] = value
		if reg ~= 0x08 then
			return
		end

		total = total + 1
		local pc = cpu2.state["PC"].value
		local bank = bank_name()
		local handler = packet_handler()
		local length = xdata:read_u8(0x60ad)
		local xcon = regs[0x09] or 0
		local sp, stack = stack_bytes()
		local dispatched = stack:find("930E", 1, true) ~= nil
		local key = string.format("%s:%04X:%04X:%04X:%04X:%s",
			bank, pc, value, xcon, handler, dispatched and "D" or "-")
		local group = groups[key]
		if group then
			group.count = group.count + 1
		else
			groups[key] = {
				bank = bank,
				pc = pc,
				command = value,
				xcon = xcon,
				handler = handler,
				length = length,
				sp = sp,
				stack = stack,
				dispatched = dispatched,
				first = manager.machine.time:as_double(),
				count = 1
			}
		end
	end)

dc323_command_provenance_stop = emu.add_machine_stop_notifier(function()
	local ordered = {}
	for _, group in pairs(groups) do
		ordered[#ordered + 1] = group
	end
	table.sort(ordered, function(a, b)
		if a.first ~= b.first then return a.first < b.first end
		if a.bank ~= b.bank then return a.bank < b.bank end
		if a.pc ~= b.pc then return a.pc < b.pc end
		return a.command < b.command
	end)

	for _, group in ipairs(ordered) do
		print(string.format(
			"DC323_PROVENANCE first=%.9f count=%d bank=%s pc=%04X command=%04X xcon=%04X handler=%04X packet_len=%02X dispatched=%s sp=%02X stack=%s",
			group.first, group.count, group.bank, group.pc, group.command,
			group.xcon, group.handler, group.length,
			group.dispatched and "yes" or "no", group.sp, group.stack))
	end
	print(string.format("DC323_PROVENANCE_SUMMARY commands=%d groups=%d", total, #ordered))
end)

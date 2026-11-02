-- Decode the command-32 bitmap-to-processor transfer that fills CC00-CFFF.

local cpu2 = manager.machine.devices[":cpu2"]
local xdata = cpu2.spaces["xdata"]
local debugger = manager.machine.debugger
local regs = {}
local active = false
local fifo_reads = 0
local stored = 0
local first_fifo = -1
local last_fifo = -1

local start_bp = cpu2.debug:bpset(0xdb98)
local setup_bp = cpu2.debug:bpset(0xbd23)
local done_bp = cpu2.debug:bpset(0xbd36)

phase4_pbt_write_tap = xdata:install_write_tap(
	0xf000, 0xffff, "phase4_pbt_registers",
	function(offset, data, mask)
		if not active or (offset & 0xf0c0) ~= 0xf000 then return end
		local reg = offset & 0x3f
		regs[reg] = (cpu2.state["P1"].value << 8) | data
	end)

phase4_pbt_fifo_tap = xdata:install_read_tap(
	0xf007, 0xff07, "phase4_pbt_fifo",
	function(offset, data, mask)
		if not active or cpu2.state["PC"].value ~= 0xbd30 then return end
		fifo_reads = fifo_reads + 1
		if first_fifo < 0 then first_fifo = data end
		last_fifo = data
	end)

phase4_pbt_store_tap = xdata:install_write_tap(
	0xcc00, 0xcfff, "phase4_pbt_store",
	function(offset, data, mask)
		if active then stored = stored + 1 end
	end)

local function dump_regs()
	local keys = {}
	for reg, _ in pairs(regs) do table.insert(keys, reg) end
	table.sort(keys)
	local values = {}
	for _, reg in ipairs(keys) do
		table.insert(values, string.format("%02X=%04X", reg, regs[reg]))
	end
	print("PHASE4_PBT registers=" .. table.concat(values, " "))
end

local complete = false

emu.register_periodic(function()
	if debugger.execution_state ~= "stop" then return end
	local pc = cpu2.state["PC"].value
	if pc == 0xdb98 then
		active = true
		cpu2.debug:bpclear(start_bp)
		print(string.format("PHASE4_PBT t=%.9f event=command32",
			manager.machine.time:as_double()))
	elseif pc == 0xbd23 then
		cpu2.debug:bpclear(setup_bp)
		dump_regs()
	elseif pc == 0xbd36 then
		if complete then
			debugger.execution_state = "run"
			return
		end
		cpu2.debug:bpclear(done_bp)
		complete = fifo_reads == 1024 and stored == 1024
		local text = {}
		for address = 0xccc0, 0xcccf do
			table.insert(text, string.format("%02X", xdata:read_u8(address)))
		end
		print(string.format(
			"PHASE4_PBT t=%.9f event=transfer_done fifo_reads=%d stored=%d first=%02X last=%02X text=%s",
			manager.machine.time:as_double(), fifo_reads, stored,
			first_fifo, last_fifo, table.concat(text)))
		manager.machine:exit()
		return
	end
	debugger.execution_state = "run"
end)

phase4_pbt_stop = emu.add_machine_stop_notifier(function()
	print(string.format("PHASE4_PBT_%s", complete and "PASS" or "FAIL"))
end)

debugger.execution_state = "run"

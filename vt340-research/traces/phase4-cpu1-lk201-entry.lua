-- Bounded trace of the CPU1 decision path into the two final LK201/DAT9
-- exchanges.  This is diagnostic-only and does not alter CPU or device state.

local cpu1 = manager.machine.devices[":cpu1"]
local cpu2 = manager.machine.devices[":cpu2"]
local idata1 = cpu1.spaces["idata"]
local xdata1 = cpu1.spaces["xdata"]
local debugger = manager.machine.debugger

local points1 = {
	[0x39d3]="ram_pattern_entry", [0x39d8]="ram_pattern_result",
	[0x39dd]="ram_pattern_rotate_branch", [0x39e0]="ram_zero_entry",
	[0x39e5]="ram_zero_result", [0x39e7]="ram_failure",
	[0x39ea]="final_exchange_setup", [0x39ec]="exchange_1_call",
	[0x39ef]="exchange_2_call", [0x39f2]="post_exchange_branch",
	[0x3a0d]="pending_write", [0x3a59]="ram_test_entry",
	[0x3a61]="ram_page_test_call", [0x3a64]="ram_page_result",
	[0x3a6c]="ram_page_loop", [0x3a7a]="ram_page_test_entry",
	[0x3a93]="ram_page_test_return",
	[0x3b9a]="exchange_entry", [0x3ac9]="lk201_block_entry",
	[0x3ad3]="fixed_byte_loop", [0x3ad5]="fixed_byte_send",
	[0x3ade]="variable_byte_send", [0x3b64]="sbuf_send",
	[0x3b8e]="dat9_pulse", [0x3ba0]="response_wait_entry",
	[0x3bab]="response_wait_low", [0x3bbc]="response_wait_high",
	[0x3bc8]="response_accepted", [0x3bce]="exchange_return"
}

-- Install only the activation breakpoint during the long destructive POST.
-- Adding the inner RAM-loop points before 39D3 would stop the debugger on
-- millions of unrelated earlier iterations and perturb the diagnostic run.
cpu1.debug:bpset(0x39d3)
local bounded_breakpoints_installed = false

local function install_bounded_breakpoints()
	if bounded_breakpoints_installed then return end
	bounded_breakpoints_installed = true
	for address, _ in pairs(points1) do
		if address ~= 0x39d3 then cpu1.debug:bpset(address) end
	end
end

local active = false
local final_exchanges = false
local exchange = 0
local block = 0
local byte = 0
local wait_low_count = 0
local wait_high_count = 0
local finished = false

local function reg(n)
	local bank = (cpu1.state["PSW"].value >> 3) & 3
	return idata1:read_u8(bank * 8 + n)
end

local function line(tag, owner, label)
	print(string.format(
		"PHASE4_CPU1_ENTRY t=%.9f owner=%s event=%s cpu1=%04X cpu2=%04X " ..
		"A=%02X B=%02X PSW=%02X R0=%02X R1=%02X R2=%02X R3=%02X R4=%02X " ..
		"P1=%02X P3=%02X CPU2P1=%02X E795=%02X 7FF2=%02X exchange=%d block=%d byte=%d%s",
		manager.machine.time:as_double(), owner, label,
		cpu1.state["PC"].value, cpu2.state["PC"].value,
		cpu1.state["A"].value, cpu1.state["B"].value,
		cpu1.state["PSW"].value, reg(0), reg(1), reg(2), reg(3), reg(4),
		cpu1.state["P1"].value, cpu1.state["P3"].value,
		cpu2.state["P1"].value, xdata1:read_u8(0xe795),
		xdata1:read_u8(0x7ff2), exchange, block, byte,
		tag and (" note=" .. tag) or ""))
end

emu.register_periodic(function()
	if finished or debugger.execution_state ~= "stop" then return end
	local pc1 = cpu1.state["PC"].value
	local label1 = points1[pc1]

	if pc1 == 0x39d3 and not active then
		active = true
		install_bounded_breakpoints()
		line(nil, "cpu1", "trace_start")
	end

	if active and label1 then
		local emit = true
		local note = nil
		if pc1 == 0x39ea then final_exchanges = true end
		if pc1 == 0x3b9a and final_exchanges then
			exchange = exchange + 1
			wait_low_count = 0
			wait_high_count = 0
		end
		if pc1 == 0x3ac9 and final_exchanges then
			block = block + 1
			byte = 0
		end
		if pc1 == 0x3b64 and final_exchanges then
			byte = byte + 1
			note = string.format("sbuf_value_%02X", cpu1.state["A"].value)
		end
		if pc1 == 0x3bab and final_exchanges then
			wait_low_count = wait_low_count + 1
			local low = (cpu1.state["P3"].value & 0x20) == 0
			emit = wait_low_count == 1 or low
			if low then note = string.format("low_seen_after_%d_samples", wait_low_count) end
		end
		if pc1 == 0x3bbc and final_exchanges then
			wait_high_count = wait_high_count + 1
			local high = (cpu1.state["P3"].value & 0x20) ~= 0
			emit = wait_high_count == 1 or high
			if high then note = string.format("high_seen_after_%d_samples", wait_high_count) end
		end
		if not final_exchanges and (pc1 == 0x3ac9 or pc1 == 0x3ad3 or
			pc1 == 0x3ad5 or pc1 == 0x3ade or pc1 == 0x3b64 or
			pc1 == 0x3b8e or pc1 == 0x3ba0 or pc1 == 0x3bab or
			pc1 == 0x3bbc or pc1 == 0x3bc8 or pc1 == 0x3bce or
			pc1 == 0x3b9a) then
			emit = false
		end
		if emit then line(note, "cpu1", label1) end
		if pc1 == 0x3a0d then
			line(nil, "cpu1", "trace_end")
			finished = true
			manager.machine:exit()
			return
		end
	end

	debugger.execution_state = "run"
end)

debugger.execution_state = "run"

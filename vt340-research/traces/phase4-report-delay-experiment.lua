local cpu1 = manager.machine.devices[":cpu1"]
local cpu2 = manager.machine.devices[":cpu2"]
local xdata = cpu1.spaces["xdata"]
local debugger = manager.machine.debugger

local points = {
	[":cpu1:3BC8"] = "response_ok",
	[":cpu1:3B64"] = "report_byte",
	[":cpu1:3B6E"] = "delay_inner_1",
	[":cpu1:3B70"] = "delay_inner_2",
	[":cpu1:3AE1"] = "report_done",
	[":cpu1:3B8E"] = "cpu1_pulse",
	[":cpu1:3A0D"] = "request_10",
	[":cpu1:3A21"] = "ack_zero",
	[":cpu1:3A3A"] = "result",
	[":cpu2:136D"] = "cpu2_ack_write",
	[":cpu2:163F"] = "cpu2_result_write",
}

local breakpoints = {}
for key, event in pairs(points) do
	local tag, address = key:match("^(:cpu%d):(%x+)$")
	if event ~= "delay_inner_1" and event ~= "delay_inner_2" then
		breakpoints[key] = manager.machine.devices[tag].debug:bpset(tonumber(address, 16))
	end
end

local responses = 0
local shortened = 0
local report_bytes = 0
local shorten_report = false

emu.register_periodic(function()
	if debugger.execution_state ~= "stop" then
		return
	end

	local key1 = string.format(":cpu1:%04X", cpu1.state["PC"].value)
	local key2 = string.format(":cpu2:%04X", cpu2.state["PC"].value)
	local key = points[key1] and key1 or key2
	local event = points[key]

	if event == "response_ok" then
		responses = responses + 1
		if responses == 5 then
			shorten_report = true
			breakpoints[":cpu1:3B6E"] = cpu1.debug:bpset(0x3b6e)
			breakpoints[":cpu1:3B70"] = cpu1.debug:bpset(0x3b70)
		end
	elseif event == "report_byte" and shorten_report then
		report_bytes = report_bytes + 1
	elseif (event == "delay_inner_1" or event == "delay_inner_2") and shorten_report then
		-- Diagnostic only: preserve the firmware's calls, pushes, pops, and
		-- A=3 outer loop, but make each of its two 256-iteration DJNZ loops
		-- execute once for the four-byte LK201 command block after response 5.
		cpu1.state["R0"].value = 1
		shortened = shortened + 1
	elseif event == "report_done" and shorten_report then
		shorten_report = false
		cpu1.debug:bpclear(breakpoints[":cpu1:3B6E"])
		cpu1.debug:bpclear(breakpoints[":cpu1:3B70"])
	end

	if event then
		print(string.format(
			"PHASE4_REPORT_DELAY t=%.9f event=%s responses=%d bytes=%d shortened=%d cpu1=%04X cpu2=%04X A=%02X P1=%02X 7FF2=%02X",
			manager.machine.time:as_double(), event, responses, report_bytes, shortened,
			cpu1.state["PC"].value, cpu2.state["PC"].value,
			cpu1.state["A"].value, cpu2.state["P1"].value,
			xdata:read_u8(0x7ff2)))
	end

	debugger.execution_state = "run"
end)

debugger.execution_state = "run"

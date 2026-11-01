local cpu1 = manager.machine.devices[":cpu1"]
local cpu2 = manager.machine.devices[":cpu2"]
local idata1 = cpu1.spaces["idata"]
local idata2 = cpu2.spaces["idata"]
local xdata = cpu1.spaces["xdata"]
local debugger = manager.machine.debugger
local points = {
	[":cpu1:3B8E"] = "CPU1_PULSE",
	[":cpu1:3A0D"] = "CPU1_REQUEST",
	[":cpu1:3BB4"] = "CPU1_RESPONSE_TIMEOUT",
	[":cpu1:3BC8"] = "CPU1_RESPONSE_OK",
	[":cpu1:0003"] = "CPU1_INT0",
	[":cpu1:000B"] = "CPU1_TIMER0",
	[":cpu1:0013"] = "CPU1_INT1",
	[":cpu1:001B"] = "CPU1_TIMER1",
	[":cpu1:0023"] = "CPU1_SERIAL",
	[":cpu2:1701"] = "CPU2_RENDEZVOUS",
	[":cpu2:1711"] = "CPU2_RETURN",
	[":cpu2:1325"] = "CPU2_CONFIG",
	[":cpu2:1369"] = "CPU2_ACK",
	[":cpu2:1376"] = "CPU2_DAT9_LOW",
	[":cpu2:137C"] = "CPU2_DAT9_HIGH",
}
local breakpoints = {}
local hits = {}

for key, _ in pairs(points) do
	local tag, address = key:match("^(:cpu%d):(%x+)$")
	breakpoints[key] = manager.machine.devices[tag].debug:bpset(tonumber(address, 16))
end

local function return_address(cpu, idata)
	local sp = cpu.state["SP"].value
	return (idata:read_u8(sp) << 8) | idata:read_u8((sp - 1) & 0xff)
end

local function caller_address(cpu, idata)
	local sp = cpu.state["SP"].value
	return (idata:read_u8((sp - 2) & 0xff) << 8) | idata:read_u8((sp - 3) & 0xff)
end

emu.register_periodic(function()
	if debugger.execution_state ~= "stop" then
		return
	end
	local key1 = string.format(":cpu1:%04X", cpu1.state["PC"].value)
	local cpu = points[key1] and cpu1 or cpu2
	local idata = cpu == cpu1 and idata1 or idata2
	local key = string.format("%s:%04X", cpu.tag, cpu.state["PC"].value)
	local label = points[key]
	if label then
		hits[key] = (hits[key] or 0) + 1
		print(string.format(
			"PHASE3_HANDSHAKE t=%.9f label=%s hit=%d return=%04X caller=%04X P1=%02X P3=%02X 7FF2=%02X peer=%04X",
			manager.machine.time:as_double(), label, hits[key],
			return_address(cpu, idata), caller_address(cpu, idata), cpu.state["P1"].value,
			cpu.state["P3"].value, xdata:read_u8(0x7ff2),
			(cpu == cpu1 and cpu2 or cpu1).state["PC"].value))
		if hits[key] == 20 then
			cpu.debug:bpclear(breakpoints[key])
		end
	end
	debugger.execution_state = "run"
end)

debugger.execution_state = "run"

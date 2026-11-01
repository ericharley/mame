local cpu1 = manager.machine.devices[":cpu1"]
local cpu2 = manager.machine.devices[":cpu2"]
local data = cpu2.spaces["xdata"]
local debugger = manager.machine.debugger
local breakpoints = {}
local hits = {}

local points = {
	[":cpu1:3A0D"] = "REQUEST",
	[":cpu1:3B8E"] = "PULSE_LOW",
	[":cpu1:3B90"] = "PULSE_DELAY",
	[":cpu1:3B96"] = "PULSE_HIGH",
	[":cpu1:3A18"] = "ACK_WAIT",
	[":cpu1:3A3A"] = "RESULT",
	[":cpu2:1325"] = "CONFIG_READ",
	[":cpu2:125F"] = "POST_RESTART",
	[":cpu2:132F"] = "CONFIG_SETUP_CALL",
	[":cpu2:30F9"] = "CONFIG_SETUP",
	[":cpu2:3119"] = "TABLE_SELECT",
	[":cpu2:3141"] = "CONFIG_SETUP_RET",
	[":cpu2:48FF"] = "TRANSFER_BOUNDARY",
	[":cpu2:1BD2"] = "PAUSE_8_ENTRY",
	[":cpu2:1BE9"] = "PAUSE_COMPLETE_WAIT",
	[":cpu2:1BF1"] = "PAUSE_8_DONE",
	[":cpu2:1701"] = "DAT9_ENTRY",
	[":cpu2:170E"] = "DAT9_WAIT",
	[":cpu2:1711"] = "DAT9_SAMPLE",
	[":cpu2:1369"] = "ACKNOWLEDGE",
	[":cpu2:1639"] = "RESULT_WRITE",
	[":cpu2:16EF"] = "OPERATIONAL_JUMP",
}

for key, _ in pairs(points) do
	local tag, address = key:match("^(:cpu%d):(%x+)$")
	local cpu = manager.machine.devices[tag]
	breakpoints[key] = cpu.debug:bpset(tonumber(address, 16))
end

emu.register_periodic(function()
	if debugger.execution_state ~= "stop" then
		return
	end
	local pc1 = cpu1.state["PC"].value
	local pc2 = cpu2.state["PC"].value
	local key1 = string.format(":cpu1:%04X", pc1)
	local cpu = points[key1] and cpu1 or cpu2
	local pc = cpu == cpu1 and pc1 or pc2
	local key = string.format("%s:%04X", cpu.tag, pc)
	local label = points[key]
	if label then
		hits[key] = (hits[key] or 0) + 1
		if hits[key] <= 16 then
			print(string.format(
				"PHASE3_ZERO t=%.9f cpu=%s label=%s hit=%d pc=%04X A=%02X P1=%02X P3=%02X SP=%02X 7FF2=%02X",
				manager.machine.time:as_double(), cpu.tag, label, hits[key], pc,
				cpu.state["A"].value, cpu.state["P1"].value,
				cpu.state["P3"].value, cpu.state["SP"].value,
				data:read_u8(0x7ff2)))
		end
		if hits[key] == 16 then
			cpu.debug:bpclear(breakpoints[key])
		end
	else
		print(string.format("PHASE3_ZERO_UNEXPECTED cpu=%s pc=%04X", cpu.tag, pc))
	end
	debugger.execution_state = "run"
end)

phase3_zero_stop_subscription = emu.add_machine_stop_notifier(function()
	print(string.format("PHASE3_ZERO_SUMMARY cpu1=%04X cpu2=%04X 7FF2=%02X",
		cpu1.state["PC"].value, cpu2.state["PC"].value, data:read_u8(0x7ff2)))
end)

debugger.execution_state = "run"

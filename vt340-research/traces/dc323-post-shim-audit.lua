-- Read-only audit of the remaining PC-qualified DC323 POST adapter.

local cpu2 = manager.machine.devices[":cpu2"]
local xdata = cpu2.spaces["xdata"]
local recent_writes = {}
local hits = {}
local failures = {}

local target = {
	[0x1bd1] = "id_data_diagnostic",
	[0x2900] = "address_complete_lowrom",
	[0xbba0] = "rasterop_initialized",
	[0xbbaa] = "address_complete_banked",
	[0xbbb4] = "id_data_ready",
}

local required_mask = {
	address_complete_lowrom = 0x10,
	rasterop_initialized = 0x04,
	address_complete_banked = 0x10,
	id_data_ready = 0x20,
}

local function remember_write(pc, reg, value, p1)
	table.insert(recent_writes, {
		time = manager.machine.time:as_double(),
		pc = pc,
		reg = reg,
		value = value,
		p1 = p1,
	})
	if #recent_writes > 32 then
		table.remove(recent_writes, 1)
	end
end

dc323_post_audit_read = xdata:install_read_tap(
	0xf000, 0xff3f, "dc323_post_audit_read",
	function(offset, value, mask)
		local pc = cpu2.state["PC"].value
		local label = target[pc]
		if not label then
			return
		end

		hits[label] = (hits[label] or 0) + 1
		local failed = required_mask[label] and (value & required_mask[label]) == 0
		if failed then
			failures[label] = (failures[label] or 0) + 1
		end
		if hits[label] <= 16 or (failed and failures[label] <= 16) then
			print(string.format(
				"DC323_POST_AUDIT t=%.9f event=%s hit=%d op=R pc=%04X reg=%02X value=%02X p1=%02X",
				manager.machine.time:as_double(), label, hits[label], pc,
				offset & 0x3f, value, cpu2.state["P1"].value))
			if hits[label] == 1 or (failed and failures[label] == 1) then
				for _, entry in ipairs(recent_writes) do
					print(string.format(
						"DC323_POST_CONTEXT t=%.9f for=%s pc=%04X reg=%02X word=%02X%02X",
						entry.time, label, entry.pc, entry.reg, entry.p1,
						entry.value))
				end
			end
		end
	end)

dc323_post_audit_write = xdata:install_write_tap(
	0xf000, 0xff3f, "dc323_post_audit_write",
	function(offset, value, mask)
		remember_write(cpu2.state["PC"].value, offset & 0x3f, value,
			cpu2.state["P1"].value)
	end)

dc323_post_audit_stop = emu.add_machine_stop_notifier(function()
	print(string.format(
		"DC323_POST_AUDIT_SUMMARY id_data=%d initialized=%d address_low=%d address_bank=%d id_ready=%d failures=%d/%d/%d/%d",
		hits.id_data_diagnostic or 0, hits.rasterop_initialized or 0,
		hits.address_complete_lowrom or 0, hits.address_complete_banked or 0,
		hits.id_data_ready or 0, failures.rasterop_initialized or 0,
		failures.address_complete_lowrom or 0,
		failures.address_complete_banked or 0, failures.id_data_ready or 0))
end)

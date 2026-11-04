-- Read-only correlation of screen frames, DC7051 frame events, and the
-- firmware-visible DC323 control path.  This script does not alter emulated
-- state or timing.

io.stdout:setvbuf("no")

local cpu2 = manager.machine.devices[":cpu2"]
local dc7051 = manager.machine.devices[":dc7051"]
local dc323 = manager.machine.devices[":dc323"]
local screen = manager.machine.screens[":screen"]
local xdata = cpu2.spaces["xdata"]
local frames_seen = 0
local last_dc7051_frame = 0
local writes = { enable = 0, acknowledge = 0, scroll = 0, selector = 0 }

local function saved_scalar(device, suffix)
	for name, index in pairs(device.items) do
		if name == "0/" .. suffix or name == suffix then
			return emu.item(index)
		end
	end
	error(string.format("saved item %s not found on %s", suffix, device.tag))
end

local dc7051_frames = saved_scalar(dc7051, "m_frame_events")
local dc323_status = saved_scalar(dc323, "m_status")

local function emit(event, detail)
	print(string.format(
		"DC7051_SYNC time=%.9f event=%s screen_frame=%d dc7051_frame=%d dc323_status=%04X %s",
		manager.machine.time:as_double(), event, screen:frame_number(),
		dc7051_frames:read(0), dc323_status:read(0), detail or ""))
end

dc7051_sync_writes = xdata:install_write_tap(
	0xf000, 0xf0ff, "dc7051_sync_writes",
	function(offset, data, mask)
		if offset == 0xf0e0 then
			writes.selector = writes.selector + 1
			emit("test_selector", string.format("value=%02X pc=%04X", data, cpu2.state["PC"].value))
			return
		end
		if (offset & 0xf0c0) ~= 0xf000 then
			return
		end

		local reg = offset & 0x3f
		local value = (cpu2.state["P1"].value << 8) | data
		if reg == 0x02 then
			writes.enable = writes.enable + 1
			emit("interrupt_enable", string.format("value=%04X pc=%04X", value, cpu2.state["PC"].value))
		elseif reg == 0x03 then
			writes.acknowledge = writes.acknowledge + 1
			emit("status_ack", string.format("value=%04X pc=%04X", value, cpu2.state["PC"].value))
		elseif reg == 0x14 then
			writes.scroll = writes.scroll + 1
			emit("scroll_request", string.format("value=%04X pc=%04X", value, cpu2.state["PC"].value))
		end
	end)

emu.register_frame_done(function()
	frames_seen = frames_seen + 1
	local device_frame = dc7051_frames:read(0)
	local delta = device_frame - last_dc7051_frame
	if frames_seen <= 5 or delta ~= 1 or (frames_seen % 300) == 0 then
		emit("screen_frame", string.format("device_delta=%d", delta))
	end
	last_dc7051_frame = device_frame
end)

dc7051_sync_stop = emu.add_machine_stop_notifier(function()
	emit("summary", string.format(
		"frames_seen=%d enable_writes=%d acknowledgements=%d scroll_requests=%d selector_writes=%d",
		frames_seen, writes.enable, writes.acknowledge, writes.scroll, writes.selector))
end)

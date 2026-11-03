-- Exercise the external Comm 1 callbacks through a MAME RS-232 endpoint.
-- The firmware and SCN2681 perform all character translation and
-- serialization; this script only posts LK201 keys and observes DUART data.

io.stdout:setvbuf("no")

local cpu1 = manager.machine.devices[":cpu1"]
local xdata = cpu1.spaces["xdata"]
local idata = cpu1.spaces["idata"]
local keyboard = manager.machine.natkeyboard
local screen = manager.machine.screens[":screen"]

keyboard.in_use = true

serial_read_tap = xdata:install_read_tap(
	0xf040, 0xf07f, "vt340_serial_connector_read",
	function(offset, data, mask)
		if manager.machine.time:as_double() >= 125 and (offset & 0x0f) == 0x03 then
			print(string.format(
				'VT340_SERIAL_JSON {"event":"comm1_receive","time":%.9f,"pc":"%04X","data":"%02X","psw":"%02X","scheduler":"%02X","terminal_flags":"%02X","session_select":"%02X","session_flags":"%02X","comm1_mode":"%02X","comm2_mode":"%02X","receive_flags":"%02X"}',
				manager.machine.time:as_double(), cpu1.state["PC"].value, data,
				cpu1.state["PSW"].value, idata:read_u8(0x25), idata:read_u8(0x46),
				xdata:read_u8(0x5f23),
				xdata:read_u8(0x4c01), xdata:read_u8(0x4c03),
				xdata:read_u8(0x4c07), xdata:read_u8(0x4d2b)))
		end
	end)

serial_write_tap = xdata:install_write_tap(
	0xf040, 0xf07f, "vt340_serial_connector_write",
	function(offset, data, mask)
		local now = manager.machine.time:as_double()
		local reg = offset & 0x0f
		if now >= 120 and reg ~= 0x03 then
			print(string.format(
				'VT340_SERIAL_JSON {"event":"duart_write","time":%.9f,"pc":"%04X","register":"%X","data":"%02X"}',
				now, cpu1.state["PC"].value, reg, data))
		elseif now >= 125 and reg == 0x03 then
			print(string.format(
				'VT340_SERIAL_JSON {"event":"comm1_transmit","time":%.9f,"pc":"%04X","data":"%02X"}',
				now, cpu1.state["PC"].value, data))
		end
	end)

serial_video_ring_tap = xdata:install_write_tap(
	0x7e7e, 0x7e7e, "vt340_serial_video_ring",
	function(offset, data, mask)
		if manager.machine.time:as_double() >= 125 then
			print(string.format(
				'VT340_SERIAL_JSON {"event":"video_ring_producer","time":%.9f,"pc":"%04X","data":"%02X"}',
				manager.machine.time:as_double(), cpu1.state["PC"].value, data))
		end
	end)

local actions = {
	{ time = 130, code = "{TAB}", label = "leave_post" },
	{ time = 140, code = "a", label = "a" }
}
local next_action = 1
local captured = false

emu.register_frame_done(function()
	local now = manager.machine.time:as_double()
	while next_action <= #actions and now >= actions[next_action].time do
		local action = actions[next_action]
		keyboard:post_coded(action.code)
		print(string.format(
			'VT340_SERIAL_JSON {"event":"key_post","time":%.9f,"label":"%s"}',
			now, action.label))
		next_action = next_action + 1
	end
	if not captured and now >= 132 then
		screen:snapshot("/tmp/vt340-serial-connector-132.png")
		print(string.format(
			'VT340_SERIAL_JSON {"event":"snapshot","time":%.9f,"pc":"%04X","scheduler":"%02X","terminal_flags":"%02X","receive_count":["%02X","%02X"],"receive_read":["%02X","%02X"],"receive_write":["%02X","%02X"],"video_ring":["%02X","%02X"],"path":"/tmp/vt340-serial-connector-132.png"}',
			now, cpu1.state["PC"].value, idata:read_u8(0x25), idata:read_u8(0x46),
			xdata:read_u8(0x5fd5), xdata:read_u8(0x5fd6),
			xdata:read_u8(0x5fd3), xdata:read_u8(0x5fd4),
			xdata:read_u8(0x5fd1), xdata:read_u8(0x5fd2),
			xdata:read_u8(0x7e7e), xdata:read_u8(0x7e7f)))
		captured = true
	end
end)

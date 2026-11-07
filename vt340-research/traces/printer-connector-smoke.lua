-- Verify the external SCN2641 TxD path independently of terminal firmware.

io.stdout:setvbuf("no")

local cpu1 = manager.machine.devices[":cpu1"]
local xdata = cpu1.spaces["xdata"]
local payload = "VT340 PRINTER\r\n"
local payload_index = 1
local configured = false

-- Use an emulation-time callback rather than a video frame callback.  This
-- regression deliberately runs with -video none, and a headless run is not
-- required to produce frames while the UART is still advancing normally.
emu.register_periodic(function()
	local now = manager.machine.time:as_double()
	-- Wait until native POST has finished using the printer UART before taking
	-- temporary direct control for this connector-only byte-path check.
	if not configured and now >= 14.25 then
		-- Reading CR resets the mode pointer.  Program 8N1, 16X clocks,
		-- 9600 baud, normal operation, receiver/transmitter and RTS enabled.
		xdata:read_u8(0xf003)
		xdata:write_u8(0xf002, 0x0e)
		xdata:write_u8(0xf002, 0x7e)
		xdata:write_u8(0xf003, 0x27)
		configured = true
	end

	if configured and payload_index <= #payload and (xdata:read_u8(0xf001) & 0x01) ~= 0 then
		local value = payload:byte(payload_index)
		xdata:write_u8(0xf000, value)
		print(string.format(
			'VT340_PRINTER_JSON {"event":"transmit","time":%.9f,"index":%d,"data":"%02X"}',
			now, payload_index, value))
		payload_index = payload_index + 1
	elseif payload_index > #payload and (xdata:read_u8(0xf001) & 0x04) ~= 0 then
		print(string.format(
			'VT340_PRINTER_PASS time=%.9f bytes=%d', now, #payload))
		manager.machine:exit()
	end
end)

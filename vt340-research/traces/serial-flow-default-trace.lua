-- Verify that the host-side Comm 1 connector honors the VT340 firmware's
-- software flow control without a test harness having to enable it.

io.stdout:setvbuf("no")

local flow_port = manager.machine.ioport.ports[":comm1:pty:FLOW_CONTROL"]
assert(flow_port, "Comm 1 PTY flow-control setting is unavailable")

local flow = flow_port:read() & 0x07
assert(flow == 0x04, string.format("Comm 1 flow control is %02X, expected XON/XOFF", flow))
print(string.format("VT340_SERIAL_DEFAULT_PASS flow=%02X", flow))

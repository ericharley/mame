-- Capture the native cold-boot display at regular emulation-time intervals.
-- This observes the screen only and does not accelerate or alter firmware.

local screen = manager.machine.screens[":screen"]
local output = assert(os.getenv("VT340_GALLERY_FRAME_DIR"), "VT340_GALLERY_FRAME_DIR is not set")
local interval = tonumber(os.getenv("VT340_GALLERY_INTERVAL")) or 2
local stop_time = tonumber(os.getenv("VT340_GALLERY_STOP_TIME")) or 132
local next_time = 0
local frame = 0

emu.register_frame_done(function()
	local now = manager.machine.time:as_double()
	while now >= next_time and next_time <= stop_time do
		local path = string.format("%s/boot-%03d.png", output, frame)
		screen:snapshot(path)
		print(string.format("VT340_GALLERY frame=%03d target=%.3f actual=%.9f path=%s",
			frame, next_time, now, path))
		frame = frame + 1
		next_time = next_time + interval
	end
end)

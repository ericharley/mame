local screen = manager.machine.screens[":screen"]
local frames = 0
local startup_frames = { 60, 120, 180, 240, 300, 360, 600 }

emu.register_frame_done(function()
	frames = frames + 1
	for _, frame in ipairs(startup_frames) do
		if frames == frame then
			screen:snapshot(string.format("/tmp/vt340-screen-%03d.png", frame))
		end
	end
	-- Normal video initialization and the first E49 text rasterops complete
	-- after the POST interval, approximately six and a half seconds into this model.
	if frames == 390 then
		screen:snapshot("/tmp/vt340-screen.png")
	end
	if frames == 1200 then
		screen:snapshot("/tmp/vt340-screen-late.png")
	end
end)

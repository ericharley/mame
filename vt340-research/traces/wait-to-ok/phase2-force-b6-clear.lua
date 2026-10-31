local cpu = manager.machine.devices[":cpu1"]
local screen = manager.machine.screens[":screen"]
local debugger = manager.machine.debugger
local frames = 0

debugger:command("focus cpu1 ; temp0 = 0")
cpu.debug:bpset(0x41f7, "temp0 == 0", "temp0 = 1 ; b = 0 ; g")
emu.register_frame_done(function()
	frames = frames + 1
	if frames == 600 or frames == 900 or frames == 1200 then
		screen:snapshot(string.format("/tmp/vt340-phase2-force-b6-clear-%04d.png", frames))
	end
end)
debugger.execution_state = "run"

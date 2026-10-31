local cpu = manager.machine.devices[":cpu2"]
local debugger = manager.machine.debugger

debugger:command("trace /tmp/vt340-rotated-post.tr,cpu2")
cpu.debug:bpset(0x0f26, "1", "trace off ; quit")
cpu.debug:bpset(0x0f3b, "1", "trace off ; quit")
debugger.execution_state = "run"

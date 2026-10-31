local debugger = manager.machine.debugger

debugger:command("focus cpu1")
debugger:command("dasm vt340-research/traces/wait-to-ok/phase2-cpu1-dasm.txt,0,10000,,cpu1")
debugger:command("focus cpu2")
debugger:command("dasm vt340-research/traces/wait-to-ok/phase2-cpu2-low-dasm.txt,0,8000,,cpu2")
debugger:command("dasm vt340-research/traces/wait-to-ok/phase2-cpu2-e4-dasm.txt,8000,8000,,cpu2")
debugger.execution_state = "run"

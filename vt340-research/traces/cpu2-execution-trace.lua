local debugger = manager.machine.debugger

debugger:command('trace cpu2-execution.tr,cpu2')
debugger.execution_state = "run"

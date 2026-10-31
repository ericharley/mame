local debugger = manager.machine.debugger

debugger:command('trace cpu1-execution.tr,cpu1,,{ tracelog "SP=%02X A=%02X B=%02X ",sp,a,b }')
debugger.execution_state = "run"

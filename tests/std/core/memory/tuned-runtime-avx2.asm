// runtime tuned emitter 编译覆盖；state 在真实程序中必须位于可写区域。

import("std/core.inc");
x86.use64();

std_cpu_emit(std_core_abi_sysv64);
std_memory_emit_runtime_tuned(
    std_core_abi_sysv64,
    "memory_runtime_state",
    32 * 1024 * 1024
);

memory_runtime_state:
    rq(8);

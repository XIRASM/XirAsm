// 编译期负例：memory emitter 拒绝非 x86-64 位宽。

import("std/core.inc");
x86.use32();

std_memory_emit(std_core_abi_sysv64);

// 编译期负例：memory emitter 拒绝未知 ABI。

import("std/core.inc");
x86.use64();

std_memory_emit_tier("unknown", std_core_memory_tier_scalar);

// 编译期负例：memory emitter 拒绝未实现的 ISA tier。

import("std/core.inc");
x86.use64();

std_memory_emit_tier(std_core_abi_sysv64, "avx512");

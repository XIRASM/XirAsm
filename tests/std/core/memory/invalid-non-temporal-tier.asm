// non-temporal 阈值只允许用于固定 AVX2 tier。

import("std/core.inc");
x86.use64();

std_memory_emit_tier_tuned(std_core_abi_sysv64, std_core_memory_tier_sse2, 4096);

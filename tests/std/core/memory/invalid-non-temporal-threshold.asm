// non-temporal 阈值必须为 0 或至少 4096。

import("std/core.inc");
x86.use64();
std_memory_emit_tier_tuned(std_core_abi_sysv64, std_core_memory_tier_avx2, 1024);

// 固定 AVX2 tuned emitter 编译覆盖；32 MiB 只是保守示例阈值。

import("std/core.inc");
x86.use64();

std_memory_emit_tier_tuned(
    std_core_abi_sysv64,
    std_core_memory_tier_avx2,
    32 * 1024 * 1024
);

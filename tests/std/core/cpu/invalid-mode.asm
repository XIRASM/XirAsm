// 非法调度模式必须在生成任何入口前于汇编期拒绝。
import("std/core.inc");
x86.use64();
std_dispatch_emit_avx2(
    std_core_abi_sysv64,
    "invalid",
    "invalid_entry",
    "invalid_state",
    "invalid_baseline",
    "invalid_avx2"
);

// 非法 CPU emitter ABI 必须在汇编期拒绝。
import("std/core.inc");
x86.use64();
std_cpu_emit("invalid");

// CPU feature emitter 当前只允许 x86-64。
import("std/core.inc");
x86.use32();
std_cpu_emit(std_core_abi_sysv64);

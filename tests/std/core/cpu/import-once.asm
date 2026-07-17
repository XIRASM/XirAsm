// std/core 聚合入口重复导入不能重复声明 CPU/dispatch helper。
import("std/core.inc");
import("std/core.inc");
x86.use64();
std_cpu_emit(std_core_abi_sysv64);

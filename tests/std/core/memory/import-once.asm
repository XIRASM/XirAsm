// std/core 重复导入只声明一次，随后可正常生成默认 SSE2 入口。

import("std/core.inc");
import("std/core.inc");
x86.use64();

std_memory_emit(std_core_abi_sysv64);

// Linux x86-64 的 XIRASM 跨平台 IO 总入口。
//
// 使用方只需导入本文件；当前实现直接使用 Linux x86-64 syscall，
// 不依赖 libc。所有公开函数的寄存器契约写在对应功能模块中。

assert(target.bits == 64, "io/linux.inc currently supports x86-64 only");

import("contract.inc");
import("abi/linux64.inc");
import("console/linux64.inc");
import("console/contract.inc");
import("file/linux64.inc");
import("file/contract.inc");
import("stream/linux64.inc");
import("path/linux64.inc");
import("map/linux64.inc");
import("dir/linux64.inc");

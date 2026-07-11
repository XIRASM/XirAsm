// Windows x64 的 XIRASM 跨平台 IO 总入口。
//
// 使用方只需导入本文件，并按实际使用的功能调用对应 imports(map)
// 函数构造 PE 导入表。所有公开函数的寄存器契约写在对应功能模块中。

assert(target.bits == 64, "io/windows.inc currently supports x86-64 only");

import("contract.inc");
import("abi/windows64.inc");
import("console/windows64.inc");
import("console/contract.inc");
import("file/windows64.inc");
import("file/contract.inc");
import("stream/windows64.inc");
import("path/windows64.inc");
import("map/windows64.inc");
import("dir/windows64.inc");

// Windows x64 缓冲流入口。
//
// 缓冲算法完全建立在 Windows file/ 公共契约之上；本文件只固定依赖方向，
// 不新增 Win32 导入。程序继续使用 io_windows64_file_imports() 构造
// CreateFileW、ReadFile、WriteFile、FlushFileBuffers 和 CloseHandle 等导入。
// 调用方提供状态块和缓冲区，本模块不调用 GlobalAlloc/GlobalFree。

assert(target.bits == 64, "io/stream/windows64.inc currently supports x86-64 only");

// 依赖由公开总入口 io/windows.inc 先行导入，避免不同相对路径造成重复模块。
import("contract.inc");

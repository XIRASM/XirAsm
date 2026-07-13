// Linux x86-64 缓冲流入口。
//
// 缓冲算法完全建立在 Linux file/ 公共契约之上；本文件只固定依赖方向，
// 不复制 syscall、打开、读写或关闭实现。调用方提供状态块和缓冲区，
// 因此本模块不依赖 libc 或任何分配器。

assert(target.bits == 64, "io/stream/linux64.inc currently supports x86-64 only");

// 依赖由公开总入口 io/linux.inc 先行导入，避免不同相对路径造成重复模块。
import("contract.inc");

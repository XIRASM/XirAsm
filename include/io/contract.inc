// XIRASM 跨平台运行时 IO 的公共结果契约。
//
// 返回计数、句柄、文件位置或文件大小的操作统一使用：
//   成功：rax = 返回值，rdx = io_error_none
//   失败：rax = io_result_failure，rdx = 平台原生的正数错误码
//
// 短读和短写仍属于成功，rax 返回实际完成的字节数。调用方如果要求
// “全部完成”，必须根据实际计数继续调用。

const io_result_failure: u64 = 0xffffffffffffffff
const io_error_none: u64 = 0
const io_max_transfer_size: u64 = 0xffffffff
const io_max_read_size: u64 = io_max_transfer_size
const io_max_write_size: u64 = io_max_transfer_size

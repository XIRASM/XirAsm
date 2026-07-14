// Linux x86-64 的跨平台控制台 IO 入口。
//
// 写入函数的编译期参数：无。
// 写入函数的运行时输入：
//   rsi = 缓冲区地址
//   rdx = 请求写入字节数，最大为 io_max_write_size
// 返回：
//   成功：rax = 实际写入字节数，rdx = 0
//   失败：rax = -1，rdx = 正数 errno
// 所有权：不取得缓冲区或标准 fd 所有权。
// ABI：保持 rsi；syscall 破坏 rcx/r11，本函数破坏易失寄存器。
// 短写属于成功。

fn io_write_stdout() {
    io_linux64_write_fd(1);
}

// 写入 Linux fd 2。
// 编译期参数：无。
// 运行时输入：
//   rsi = 缓冲区地址
//   rdx = 请求写入字节数，最大为 io_max_write_size
// 返回：
//   成功：rax = 实际写入字节数，rdx = 0
//   失败：rax = -1，rdx = 正数 errno
// 错误：syscall 失败时返回正数 errno。
// 所有权：不取得缓冲区或标准 fd 所有权；短写属于成功。
// ABI：保持 rsi；syscall 破坏 rcx/r11，本函数破坏易失寄存器。
fn io_write_stderr() {
    io_linux64_write_fd(2);
}

// 从 Linux 标准输入读取一段字节。
// 编译期参数：无。
// 运行时输入：
//   rsi = 可写缓冲区地址
//   rdx = 请求读取字节数，最大为 io_max_read_size
// 返回：
//   成功：rax = 实际读取字节数，rdx = 0；EOF 时 rax = 0
//   失败：rax = -1，rdx = 正数 errno
// 所有权：缓冲区归调用方；短读属于成功。
// ABI：保持 rsi；syscall 破坏 rcx/r11，本函数破坏易失寄存器。
fn io_read_stdin() {
    io_linux64_read_fd(0);
}

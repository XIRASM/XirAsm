// Linux x86-64 的跨平台控制台写入入口。
//
// 两个函数的运行时参数：
//   rsi = 缓冲区地址
//   rdx = 请求写入字节数，最大为 io_max_write_size
// 返回：
//   成功：rax = 实际写入字节数，rdx = 0
//   失败：rax = -1，rdx = 正数 errno
// 短写属于成功。

fn io_write_stdout() {
    io_linux64_write_fd(1);
}

// 参数和返回值与 io_write_stdout 相同，写入 Linux fd 2。
fn io_write_stderr() {
    io_linux64_write_fd(2);
}

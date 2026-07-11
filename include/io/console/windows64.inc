// Windows x64 的跨平台控制台写入入口。
//
// 两个函数的运行时参数：
//   rsi = 缓冲区地址
//   rdx = 请求写入字节数，最大为 io_max_write_size
// 返回：
//   成功：rax = 实际写入字节数，rdx = 0
//   失败：rax = -1，rdx = GetLastError() 返回值
//
// 生成 PE 时必须调用 io_windows64_imports(imports) 加入所需导入。

fn io_write_stdout() {
    io_windows64_write_standard(io_windows64_std_output_handle);
}

// 参数和返回值与 io_write_stdout 相同，写入 Windows 标准错误句柄。
fn io_write_stderr() {
    io_windows64_write_standard(io_windows64_std_error_handle);
}

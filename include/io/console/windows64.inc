// Windows x64 的跨平台控制台 IO 入口。
//
// 写入函数的编译期参数：无。
// 写入函数的运行时输入：
//   rsi = 缓冲区地址
//   rdx = 请求写入字节数，最大为 io_max_write_size
// 返回：
//   成功：rax = 实际写入字节数，rdx = 0
//   失败：rax = -1，rdx = GetLastError() 返回值
// 所有权：不取得缓冲区或标准 HANDLE 所有权。
// ABI：保持 rsi 和 Win64 非易失寄存器；内部恢复 rsp。
//
// 生成 PE 时必须调用 io_windows64_imports(imports) 加入所需导入。

fn io_write_stdout() {
    io_windows64_write_standard(io_windows64_std_output_handle);
}

// 写入 Windows 标准错误句柄。
// 编译期参数：无。
// 运行时输入：
//   rsi = 缓冲区地址
//   rdx = 请求写入字节数，最大为 io_max_write_size
// 返回：
//   成功：rax = 实际写入字节数，rdx = 0
//   失败：rax = -1，rdx = GetLastError() 返回值
// 错误：GetStdHandle/WriteFile 失败时返回 Win32 错误码。
// 所有权：不取得缓冲区或标准 HANDLE 所有权。
// ABI：保持 rsi 和 Win64 非易失寄存器；内部恢复 rsp。
fn io_write_stderr() {
    io_windows64_write_standard(io_windows64_std_error_handle);
}

// 从 Windows 标准输入读取一段字节。
// 编译期参数：无。
// 运行时输入：
//   rsi = 可写缓冲区地址
//   rdx = 请求读取字节数，最大为 io_max_read_size
// 返回：
//   成功：rax = 实际读取字节数，rdx = 0；EOF 时 rax = 0
//   失败：rax = -1，rdx = GetLastError() 返回值
// 所有权：缓冲区归调用方；短读属于成功。
// ABI：保持 rsi 以及全部 Win64 非易失寄存器；内部恢复 rsp。
fn io_read_stdin() {
    io_windows64_read_standard(io_windows64_std_input_handle);
}

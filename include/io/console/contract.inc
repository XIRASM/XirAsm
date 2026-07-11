// 控制台 IO 的编译期标签便捷包装。
//
// 核心 io_write_stdout/io_write_stderr 接受运行时 rsi/rdx；下面两个函数
// 先把编译期标签和长度装入寄存器，再调用核心实现。

// 参数：
//   buffer_label = 编译期缓冲区标签名，不能为空
//   length       = 编译期字节数，最大为 io_max_write_size
// 返回：
//   成功：rax = 实际写入字节数，rdx = 0
//   失败：rax = -1，rdx = 平台原生错误码
fn io_write_stdout_label(buffer_label: string, length: u64) {
    assert(len(buffer_label) > 0, "stdout buffer label is empty");
    assert(length <= io_max_write_size, "stdout byte count exceeds the portable limit");

    isa(sym.join("lea rsi, [rel ", buffer_label, "]"));
    isa(sym.join("mov rdx, ", to_string(length)));
    io_write_stdout();
}

// 参数、返回值和错误语义与 io_write_stdout_label 相同，目标为标准错误。
fn io_write_stderr_label(buffer_label: string, length: u64) {
    assert(len(buffer_label) > 0, "stderr buffer label is empty");
    assert(length <= io_max_write_size, "stderr byte count exceeds the portable limit");

    isa(sym.join("lea rsi, [rel ", buffer_label, "]"));
    isa(sym.join("mov rdx, ", to_string(length)));
    io_write_stderr();
}

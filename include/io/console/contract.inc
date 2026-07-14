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
// 运行时输入：调用点无需预置；本函数生成 rsi/rdx 后转交。
// 所有权：不取得缓冲区所有权；buffer_label 指向的数据仍归调用方。
// ABI：保留/破坏寄存器及栈要求与当前平台的 io_write_stdout 相同。
fn io_write_stdout_label(buffer_label: string, length: u64) {
    assert(len(buffer_label) > 0, "stdout buffer label is empty");
    assert(length <= io_max_write_size, "stdout byte count exceeds the portable limit");

    isa(sym.join("lea rsi, [rel ", buffer_label, "]"));
    mov rdx, length
    io_write_stdout();
}

// 写入编译期标签指定的数据到标准错误。
// 编译期参数：
//   buffer_label = 编译期缓冲区标签名，不能为空
//   length       = 编译期字节数，最大为 io_max_write_size
// 运行时输入：调用点无需预置；本函数生成 rsi/rdx 后转交。
// 返回：
//   成功：rax = 实际写入字节数，rdx = 0
//   失败：rax = -1，rdx = 平台原生错误码
// 错误：标签为空或长度过大在汇编期诊断；运行时错误由平台实现返回。
// 所有权：不取得缓冲区所有权；buffer_label 指向的数据仍归调用方。
// ABI：保留/破坏寄存器及栈要求与当前平台的 io_write_stderr 相同。
fn io_write_stderr_label(buffer_label: string, length: u64) {
    assert(len(buffer_label) > 0, "stderr buffer label is empty");
    assert(length <= io_max_write_size, "stderr byte count exceeds the portable limit");

    isa(sym.join("lea rsi, [rel ", buffer_label, "]"));
    mov rdx, length
    io_write_stderr();
}

// 标准输入读取的编译期标签便捷包装。
//
// 参数：
//   buffer_label = 编译期可写缓冲区标签名，不能为空
//   length       = 编译期请求读取字节数，最大为 io_max_read_size
// 运行时效果：
//   把 buffer_label 装入 rsi，把 length 装入 rdx，然后调用 io_read_stdin。
// 运行时输入：无；调用方只需保证 buffer_label 对应的内存可写。
// 返回：
//   成功：rax = 实际读取字节数，rdx = 0；EOF 时 rax = 0
//   失败：rax = -1，rdx = 平台原生错误码
// 所有权：缓冲区归调用方；短读属于成功。
// 保留/破坏/栈：与当前平台的 io_read_stdin 相同。
fn io_read_stdin_label(buffer_label: string, length: u64) {
    assert(len(buffer_label) > 0, "stdin buffer label is empty");
    assert(length <= io_max_read_size, "stdin byte count exceeds the portable limit");

    isa(sym.join("lea rsi, [rel ", buffer_label, "]"));
    mov rdx, length
    io_read_stdin();
}

// IO 门面内部使用的 Linux x86-64 直接 syscall 辅助函数。
//
// 将 Linux syscall 的原始返回值归一化为公共 IO 结果契约。
// 编译期参数：无。
// 输入：
//   rax = syscall 原始返回值；非负数表示成功，负数表示 -errno
// 输出：
//   成功：rax 保留原始非负结果，rdx = 0
//   失败：rax = -1，rdx = 正数 errno
// 所有权：不取得、不关闭任何调用方资源，只改写返回寄存器。
// 破坏：rdx、r10、r11；同时保留 syscall 已经破坏 rcx/r11 的事实。
fn io_linux64_normalize_count_result() {
    mov rdx, rax
    neg rdx
    test rax, rax
    mov r10, 0xffffffffffffffff
    mov r11, 0
    cmovs rax, r10
    cmovns rdx, r11
}

// 向编译期指定的 Linux 文件描述符写入一段运行时缓冲区。
// 编译期参数：
//   fd = 编译期文件描述符，必须能放入 32 位无符号数
// 运行时输入：
//   rsi = 运行时缓冲区地址
//   rdx = 请求写入的字节数
// 返回：
//   遵循 include/io/contract.inc；短写返回实际写入字节数
// 错误：syscall 失败时返回 rax = -1、rdx = 正数 errno。
// 所有权：不取得缓冲区或 fd 所有权；fd 仍由调用方负责。
// 保留：rsi
// 破坏：rax、rcx、rdx、rdi、r10、r11
fn io_linux64_write_fd(fd: u64) {
    assert(fd <= 0xffffffff, "Linux file descriptor is out of range");

    mov eax, 1
    mov edi, fd
    syscall
    io_linux64_normalize_count_result();
}

// 从编译期指定的 Linux 文件描述符读取到运行时缓冲区。
// 编译期参数：
//   fd = 编译期文件描述符，必须能放入 32 位无符号数
// 运行时输入：
//   rsi = 运行时可写缓冲区地址
//   rdx = 请求读取的字节数
// 返回：
//   成功：rax = 实际读取字节数，rdx = 0；EOF 时 rax = 0
//   失败：rax = -1，rdx = 正数 errno
// 所有权：缓冲区归调用方；本函数只写入内核实际返回的字节数。
// 保留：rsi
// 破坏：rax、rcx、rdx、rdi、r10、r11
// 栈：不使用用户栈；直接执行 Linux x86-64 syscall。
fn io_linux64_read_fd(fd: u64) {
    assert(fd <= 0xffffffff, "Linux file descriptor is out of range");

    xor eax, eax
    mov edi, fd
    syscall
    io_linux64_normalize_count_result();
}

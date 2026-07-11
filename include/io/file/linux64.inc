// Linux x86-64 无状态文件操作，全部直接调用 syscall，不依赖 libc。
//
// 公共函数不保存任何 FILE 对象。句柄由调用方放在 rdi 并负责关闭。
// syscall 会破坏 rcx、r11；结果归一化还会使用 r10。

const io_linux64_sys_read: u64 = 0
const io_linux64_sys_write: u64 = 1
const io_linux64_sys_open: u64 = 2
const io_linux64_sys_close: u64 = 3
const io_linux64_sys_fstat: u64 = 5
const io_linux64_sys_lseek: u64 = 8
const io_linux64_sys_fsync: u64 = 74

const io_linux64_o_read_only: u64 = 0
const io_linux64_o_write_only: u64 = 1
const io_linux64_o_create: u64 = 0x40
const io_linux64_o_truncate: u64 = 0x200
const io_linux64_o_append: u64 = 0x400
const io_linux64_create_mode: u64 = 0x1b6
const io_linux64_stat_size: u64 = 144
const io_linux64_stat_size_offset: u64 = 48

// 内部 open(2) 包装。
// 参数：
//   flags = 编译期 open 标志
//   mode  = 编译期创建权限；未创建文件时传 0
//   rsi   = 运行时零结尾路径指针
// 返回：成功时 rax = fd、rdx = 0；失败时 rax = -1、rdx = errno
// 保留：rsi
fn io_linux64_open_path(flags: u64, mode: u64) {
    assert(flags <= 0xffffffff, "Linux open flags are out of range");
    assert(mode <= 0xffffffff, "Linux file mode is out of range");

    push rsi
    mov rdi, rsi
    isa(sym.join("mov esi, ", to_string(flags)));
    isa(sym.join("mov edx, ", to_string(mode)));
    isa(sym.join("mov eax, ", to_string(io_linux64_sys_open)));
    syscall
    pop rsi
    io_linux64_normalize_count_result();
}

// 只读打开文件。
// 输入：rsi = Linux 字节路径指针
// 返回：rax = fd 或 -1；rdx = 0 或 errno
fn io_file_open_read() {
    io_linux64_open_path(io_linux64_o_read_only, 0);
}

// 创建新文件或截断已有文件，并以只写方式打开。
// 输入：rsi = Linux 字节路径指针
// 权限：0666，再由进程 umask 收紧
// 返回：rax = fd 或 -1；rdx = 0 或 errno
fn io_file_create_truncate() {
    io_linux64_open_path(
        io_linux64_o_write_only | io_linux64_o_create | io_linux64_o_truncate,
        io_linux64_create_mode
    );
}

// 创建新文件或以 O_APPEND 只写方式打开已有文件。
// 输入：rsi = Linux 字节路径指针
// 返回：rax = fd 或 -1；rdx = 0 或 errno
fn io_file_open_append() {
    io_linux64_open_path(
        io_linux64_o_write_only | io_linux64_o_create | io_linux64_o_append,
        io_linux64_create_mode
    );
}

// 关闭文件描述符。
// 输入：rdi = fd
// 返回：成功 rax = 0、rdx = 0；失败 rax = -1、rdx = errno
// 所有权：调用即消费 fd；失败后也不得重试 close。
fn io_file_close() {
    isa(sym.join("mov eax, ", to_string(io_linux64_sys_close)));
    syscall
    io_linux64_normalize_count_result();
}

// 从文件描述符读取数据。
// 输入：rdi = fd，rsi = 可写缓冲区，rdx = 请求字节数
// 返回：rax = 实际读取字节数（0 表示 EOF）或 -1；rdx = 0 或 errno
fn io_file_read() {
    isa(sym.join("mov eax, ", to_string(io_linux64_sys_read)));
    syscall
    io_linux64_normalize_count_result();
}

// 向文件描述符写入数据。
// 输入：rdi = fd，rsi = 源缓冲区，rdx = 请求字节数
// 返回：rax = 实际写入字节数或 -1；rdx = 0 或 errno
fn io_file_write() {
    isa(sym.join("mov eax, ", to_string(io_linux64_sys_write)));
    syscall
    io_linux64_normalize_count_result();
}

// 使用 fsync(2) 把文件数据和必要元数据同步到存储设备。
// 输入：rdi = fd
// 返回：成功 rax = 0、rdx = 0；失败 rax = -1、rdx = errno
fn io_file_flush() {
    isa(sym.join("mov eax, ", to_string(io_linux64_sys_fsync)));
    syscall
    io_linux64_normalize_count_result();
}

// 使用 lseek(2) 修改文件位置。
// 参数：origin = io_file_seek_begin/current/end
// 输入：rdi = fd，rsi = 有符号 64 位位移
// 返回：rax = 新的绝对文件位置或 -1；rdx = 0 或 errno
fn io_file_seek(origin: u64) {
    assert(origin <= 2, "file seek origin is invalid");

    isa(sym.join("mov edx, ", to_string(origin)));
    isa(sym.join("mov eax, ", to_string(io_linux64_sys_lseek)));
    syscall
    io_linux64_normalize_count_result();
}

// 使用 fstat(2) 查询文件大小。
// 输入：rdi = fd
// 返回：rax = 文件字节数或 -1；rdx = 0 或 errno
// 保留：rsi；内部临时使用 144 字节 Linux x86-64 struct stat 栈空间
fn io_file_size() {
    push rsi
    isa(sym.join("sub rsp, ", to_string(io_linux64_stat_size)));
    mov rsi, rsp
    isa(sym.join("mov eax, ", to_string(io_linux64_sys_fstat)));
    syscall
    mov r8, rax
    isa(sym.join("mov r9, [rsp + ", to_string(io_linux64_stat_size_offset), "]"));
    isa(sym.join("add rsp, ", to_string(io_linux64_stat_size)));
    pop rsi

    io_linux64_normalize_count_result();
    test r8, r8
    cmovns rax, r9
}

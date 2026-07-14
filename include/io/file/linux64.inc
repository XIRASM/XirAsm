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
// 编译期参数：
//   flags = 编译期 open 标志
//   mode  = 编译期创建权限；未创建文件时传 0
// 运行时输入：
//   rsi = Linux 零结尾字节路径指针
// 返回：成功时 rax = fd、rdx = 0；失败时 rax = -1、rdx = errno
// 错误：open(2) 失败时返回正数 errno。
// 所有权：成功返回的 fd 归调用方；不取得路径字符串所有权。
// 保留：rsi
// ABI：保持 rsi 和 rsp；syscall 破坏 rcx/r11，本函数破坏易失寄存器。
fn io_linux64_open_path(flags: u64, mode: u64) {
    assert(flags <= 0xffffffff, "Linux open flags are out of range");
    assert(mode <= 0xffffffff, "Linux file mode is out of range");

    push rsi
    mov rdi, rsi
    mov esi, flags
    mov edx, mode
    mov eax, io_linux64_sys_open
    syscall
    pop rsi
    io_linux64_normalize_count_result();
}

// 只读打开文件。
// 编译期参数：无。
// 运行时输入：rsi = Linux 字节路径指针。
// 返回：rax = fd 或 -1；rdx = 0 或 errno。
// 错误：open(2) 失败时返回正数 errno。
// 所有权：成功返回的 fd 归调用方；必须用 io_file_close 消费。
// ABI：保持 rsi 和 rsp；syscall 破坏 rcx/r11，本函数破坏易失寄存器。
fn io_file_open_read() {
    io_linux64_open_path(io_linux64_o_read_only, 0);
}

// 创建新文件或截断已有文件，并以只写方式打开。
// 编译期参数：无。
// 运行时输入：rsi = Linux 字节路径指针。
// 权限：0666，再由进程 umask 收紧
// 返回：rax = fd 或 -1；rdx = 0 或 errno。
// 错误：open(2) 失败时返回正数 errno。
// 所有权：成功返回的 fd 归调用方；必须用 io_file_close 消费。
// ABI：保持 rsi 和 rsp；syscall 破坏 rcx/r11，本函数破坏易失寄存器。
fn io_file_create_truncate() {
    io_linux64_open_path(
        io_linux64_o_write_only | io_linux64_o_create | io_linux64_o_truncate,
        io_linux64_create_mode
    );
}

// 创建新文件或以 O_APPEND 只写方式打开已有文件。
// 编译期参数：无。
// 运行时输入：rsi = Linux 字节路径指针。
// 返回：rax = fd 或 -1；rdx = 0 或 errno。
// 错误：open(2) 失败时返回正数 errno。
// 所有权：成功返回的 fd 归调用方；必须用 io_file_close 消费。
// ABI：保持 rsi 和 rsp；syscall 破坏 rcx/r11，本函数破坏易失寄存器。
fn io_file_open_append() {
    io_linux64_open_path(
        io_linux64_o_write_only | io_linux64_o_create | io_linux64_o_append,
        io_linux64_create_mode
    );
}

// 关闭文件描述符。
// 编译期参数：无。
// 运行时输入：rdi = fd。
// 返回：成功 rax = 0、rdx = 0；失败 rax = -1、rdx = errno
// 所有权：调用即消费 fd；失败后也不得重试 close。
// ABI：保持 rsp；syscall 破坏 rcx/r11，本函数破坏易失寄存器。
fn io_file_close() {
    mov eax, io_linux64_sys_close
    syscall
    io_linux64_normalize_count_result();
}

// 从文件描述符读取数据。
// 编译期参数：无。
// 运行时输入：rdi = fd，rsi = 可写缓冲区，rdx = 请求字节数。
// 返回：rax = 实际读取字节数（0 表示 EOF）或 -1；rdx = 0 或 errno
// 错误：read(2) 失败时返回正数 errno。
// 所有权：不取得 fd 或缓冲区所有权；短读属于成功。
// ABI：保持 rsp；syscall 破坏 rcx/r11，本函数破坏易失寄存器。
fn io_file_read() {
    mov eax, io_linux64_sys_read
    syscall
    io_linux64_normalize_count_result();
}

// 向文件描述符写入数据。
// 编译期参数：无。
// 运行时输入：rdi = fd，rsi = 源缓冲区，rdx = 请求字节数。
// 返回：rax = 实际写入字节数或 -1；rdx = 0 或 errno
// 错误：write(2) 失败时返回正数 errno。
// 所有权：不取得 fd 或缓冲区所有权；短写属于成功。
// ABI：保持 rsp；syscall 破坏 rcx/r11，本函数破坏易失寄存器。
fn io_file_write() {
    mov eax, io_linux64_sys_write
    syscall
    io_linux64_normalize_count_result();
}

// 使用 fsync(2) 把文件数据和必要元数据同步到存储设备。
// 编译期参数：无。
// 运行时输入：rdi = fd。
// 返回：成功 rax = 0、rdx = 0；失败 rax = -1、rdx = errno
// 错误：fsync(2) 失败时返回正数 errno。
// 所有权：不取得、不关闭 fd。
// ABI：保持 rsp；syscall 破坏 rcx/r11，本函数破坏易失寄存器。
fn io_file_flush() {
    mov eax, io_linux64_sys_fsync
    syscall
    io_linux64_normalize_count_result();
}

// 使用 lseek(2) 修改文件位置。
// 编译期参数：origin = io_file_seek_begin/current/end。
// 运行时输入：rdi = fd，rsi = 有符号 64 位位移。
// 返回：rax = 新的绝对文件位置或 -1；rdx = 0 或 errno
// 错误：origin 非法在汇编期诊断；lseek(2) 失败时返回正数 errno。
// 所有权：不取得、不关闭 fd。
// ABI：保持 rsp；syscall 破坏 rcx/r11，本函数破坏易失寄存器。
fn io_file_seek(origin: u64) {
    assert(origin <= 2, "file seek origin is invalid");

    mov edx, origin
    mov eax, io_linux64_sys_lseek
    syscall
    io_linux64_normalize_count_result();
}

// 使用 fstat(2) 查询文件大小。
// 编译期参数：无。
// 运行时输入：rdi = fd。
// 返回：rax = 文件字节数或 -1；rdx = 0 或 errno
// 错误：fstat(2) 失败时返回正数 errno。
// 所有权：不取得、不关闭 fd。
// 保留：rsi；内部临时使用 144 字节 Linux x86-64 struct stat 栈空间
// ABI：保持 rsi 和 rsp；syscall 破坏 rcx/r11，本函数破坏易失寄存器。
fn io_file_size() {
    push rsi
    sub rsp, io_linux64_stat_size
    mov rsi, rsp
    mov eax, io_linux64_sys_fstat
    syscall
    mov r8, rax
    mov r9, [rsp + io_linux64_stat_size_offset]
    add rsp, io_linux64_stat_size
    pop rsi

    io_linux64_normalize_count_result();
    test r8, r8
    cmovns rax, r9
}

// Windows x64 无状态文件操作，路径统一使用原生 UTF-16LE。
//
// 生成 PE 时必须调用 io_windows64_file_imports(imports) 加入所需导入。
// 公共函数不保存 FILE 对象；HANDLE 由调用方放在 rdi 并负责关闭。

const io_windows64_generic_read: u64 = 0x80000000
const io_windows64_generic_write: u64 = 0x40000000
const io_windows64_file_append_data: u64 = 0x00000004
const io_windows64_file_share_all: u64 = 0x00000007
const io_windows64_create_always: u64 = 2
const io_windows64_open_existing: u64 = 3
const io_windows64_open_always: u64 = 4
const io_windows64_file_attribute_normal: u64 = 0x00000080

// 把本文件模块所需的 KERNEL32 导入加入现有导入 map。
// 编译期参数：imports = pe_import_new() 或其他 pe_import_use64 返回的 map。
// 运行时输入寄存器：无；本函数只在汇编期构造导入描述。
// 返回：包含文件 API 的新 map；原 map 不被隐藏修改。
// 错误：无运行时错误；无效 map 或导入描述由格式 DSL 在汇编期诊断。
// 所有权：返回新 map，不修改原 map；调用方继续持有导入 map 值。
// ABI：不生成运行时代码，不影响寄存器、shadow space 或 rsp。
fn io_windows64_file_imports(imports: map) -> map {
    return pe_import_use64_many(
        imports,
        "KERNEL32.DLL",
        list.of(
            "CreateFileW",
            "CloseHandle",
            "ReadFile",
            "WriteFile",
            "FlushFileBuffers",
            "SetFilePointerEx",
            "GetFileSizeEx",
            "GetLastError"
        )
    );
}

// 内部 CreateFileW 包装。
// 编译期参数：
//   desired_access       = 编译期访问掩码
//   creation_disposition = 编译期创建方式
// 运行时输入：
//   rsi = UTF-16LE 零结尾路径
// 返回：成功时 rax = HANDLE、rdx = 0；失败时 rax = -1、
//       rdx = GetLastError() 返回值
// 错误：CreateFileW 失败时返回 Win32 错误码。
// 所有权：成功返回的 HANDLE 归调用方；不取得路径字符串所有权。
// 保留：rsi 及全部 Win64 非易失寄存器
// ABI：内部保留 shadow space，保持 call 前 16 字节对齐并恢复 rsp。
fn io_windows64_open_path(desired_access: u64, creation_disposition: u64) {
    assert(desired_access <= 0xffffffff, "Windows file access mask is out of range");
    assert(creation_disposition <= 0xffffffff, "Windows file creation disposition is out of range");

    // 32 字节 shadow space、三个栈参数和一个保存的 HANDLE。
    sub rsp, 72
    mov rcx, rsi
    mov edx, desired_access
    mov r8d, io_windows64_file_share_all
    xor r9d, r9d

    mov eax, creation_disposition
    mov [rsp + 32], rax
    mov eax, io_windows64_file_attribute_normal
    mov [rsp + 40], rax
    xor eax, eax
    mov [rsp + 48], rax

    call [rel CreateFileW]
    mov [rsp + 56], rax
    call [rel GetLastError]
    mov edx, eax
    mov rax, [rsp + 56]
    cmp rax, -1
    mov r10, 0
    cmovne rdx, r10
    add rsp, 72
}

// 内部单 HANDLE、BOOL 返回值 WinAPI 包装。
// 编译期参数：
//   api_name = 编译期 API 符号名，例如 CloseHandle
// 运行时输入：
//   rdi = Windows 文件句柄
// 返回：成功时 rax = 0、rdx = 0；失败时 rax = -1、
//       rdx = GetLastError() 返回值
// 错误：目标 API 返回 FALSE 时返回 Win32 错误码。
// 所有权：是否消费 HANDLE 由调用方语义决定；本函数只执行一次 API 调用。
// 保留：全部 Win64 非易失寄存器
// ABI：内部保留 shadow space，保持 call 前 16 字节对齐并恢复 rsp。
fn io_windows64_file_bool_handle(api_name: string) {
    assert(len(api_name) > 0, "Windows file API name is empty");

    // 32 字节 shadow space 和一个 BOOL 局部量。
    sub rsp, 40
    mov rcx, rdi
    isa(sym.join("call [rel ", api_name, "]"));
    mov [rsp + 32], eax
    call [rel GetLastError]
    mov edx, eax
    mov r11d, [rsp + 32]
    test r11d, r11d
    mov rax, -1
    mov r10, 0
    cmovne rax, r10
    cmovne rdx, r10
    add rsp, 40
}

// 只读打开文件。
// 编译期参数：无。
// 运行时输入：rsi = UTF-16LE 零结尾路径。
// 返回：rax = HANDLE 或 -1；rdx = 0 或 GetLastError() 返回值。
// 错误：CreateFileW 失败时返回 Win32 错误码。
// 所有权：成功返回的 HANDLE 归调用方；必须用 io_file_close 消费。
// ABI：保持 rsi、Win64 非易失寄存器和 rsp；内部使用 shadow space。
fn io_file_open_read() {
    io_windows64_open_path(io_windows64_generic_read, io_windows64_open_existing);
}

// 创建新文件或截断已有文件，并以只写方式打开。
// 编译期参数：无。
// 运行时输入：rsi = UTF-16LE 零结尾路径。
// 返回：rax = HANDLE 或 -1；rdx = 0 或 GetLastError() 返回值。
// 错误：CreateFileW 失败时返回 Win32 错误码。
// 所有权：成功返回的 HANDLE 归调用方；必须用 io_file_close 消费。
// ABI：保持 rsi、Win64 非易失寄存器和 rsp；内部使用 shadow space。
fn io_file_create_truncate() {
    io_windows64_open_path(io_windows64_generic_write, io_windows64_create_always);
}

// 创建新文件或以 FILE_APPEND_DATA 打开已有文件。
// 编译期参数：无。
// 运行时输入：rsi = UTF-16LE 零结尾路径。
// 返回：rax = HANDLE 或 -1；rdx = 0 或 GetLastError() 返回值。
// 错误：CreateFileW 失败时返回 Win32 错误码。
// 所有权：成功返回的 HANDLE 归调用方；必须用 io_file_close 消费。
// ABI：保持 rsi、Win64 非易失寄存器和 rsp；内部使用 shadow space。
fn io_file_open_append() {
    io_windows64_open_path(io_windows64_file_append_data, io_windows64_open_always);
}

// 关闭 HANDLE。
// 编译期参数：无。
// 运行时输入：rdi = HANDLE。
// 返回：成功 rax = 0、rdx = 0；失败 rax = -1、rdx = Win32 错误码
// 所有权：为保持跨平台一致，调用即视为消费 HANDLE，失败后不得复用。
// ABI：保持 Win64 非易失寄存器和 rsp；内部使用 shadow space。
fn io_file_close() {
    io_windows64_file_bool_handle("CloseHandle");
}

// 从 HANDLE 读取数据。
// 编译期参数：无。
// 运行时输入：rdi = HANDLE，rsi = 可写缓冲区，rdx = 请求字节数。
// 返回：rax = 实际读取字节数（0 表示 EOF）或 -1；
//       rdx = 0 或 GetLastError() 返回值
// 错误：ReadFile 失败时返回 Win32 错误码。
// 所有权：不取得 HANDLE 或缓冲区所有权；短读属于成功。
// 保留：rdi、rsi 及全部 Win64 非易失寄存器
// ABI：内部保留 shadow space，保持 call 前 16 字节对齐并恢复 rsp。
fn io_file_read() {
    // 32 字节 shadow space、一个栈参数、两个结果局部量和保存的长度。
    sub rsp, 72
    mov [rsp + 56], rdx
    mov rcx, rdi
    mov rdx, rsi
    mov r8d, [rsp + 56]
    lea r9, [rsp + 40]
    xor eax, eax
    mov [rsp + 40], rax
    mov [rsp + 32], rax
    call [rel ReadFile]
    mov [rsp + 48], eax

    call [rel GetLastError]
    mov edx, eax
    mov eax, [rsp + 40]
    mov r11d, [rsp + 48]
    test r11d, r11d
    mov r10, -1
    cmove rax, r10
    mov r10, 0
    cmovne rdx, r10
    add rsp, 72
}

// 向 HANDLE 写入数据。
// 编译期参数：无。
// 运行时输入：rdi = HANDLE，rsi = 源缓冲区，rdx = 请求字节数。
// 返回：rax = 实际写入字节数或 -1；rdx = 0 或 Win32 错误码
// 错误：WriteFile 失败时返回 Win32 错误码。
// 所有权：不取得 HANDLE 或缓冲区所有权；短写属于成功。
// 保留：rdi、rsi 及全部 Win64 非易失寄存器
// ABI：内部保留 shadow space，保持 call 前 16 字节对齐并恢复 rsp。
fn io_file_write() {
    mov rcx, rdi
    io_windows64_write_handle();
}

// 使用 FlushFileBuffers 把缓冲数据提交给系统存储栈。
// 编译期参数：无。
// 运行时输入：rdi = HANDLE。
// 返回：成功 rax = 0、rdx = 0；失败 rax = -1、rdx = Win32 错误码
// 错误：FlushFileBuffers 失败时返回 Win32 错误码。
// 所有权：不取得、不关闭 HANDLE。
// ABI：保持 Win64 非易失寄存器和 rsp；内部使用 shadow space。
fn io_file_flush() {
    io_windows64_file_bool_handle("FlushFileBuffers");
}

// 使用 SetFilePointerEx 修改文件位置。
// 编译期参数：origin = io_file_seek_begin/current/end。
// 运行时输入：rdi = HANDLE，rsi = 有符号 64 位位移。
// 返回：rax = 新的绝对文件位置或 -1；rdx = 0 或 Win32 错误码
// 错误：origin 非法在汇编期诊断；SetFilePointerEx 失败时返回 Win32 错误码。
// 所有权：不取得、不关闭 HANDLE。
// ABI：内部保留 shadow space，保持 call 前 16 字节对齐并恢复 rsp。
fn io_file_seek(origin: u64) {
    assert(origin <= 2, "file seek origin is invalid");

    // 32 字节 shadow space、一个 LARGE_INTEGER 结果和一个 BOOL 局部量。
    sub rsp, 56
    xor eax, eax
    mov [rsp + 40], rax
    mov rcx, rdi
    mov rdx, rsi
    lea r8, [rsp + 40]
    mov r9d, origin
    call [rel SetFilePointerEx]
    mov [rsp + 48], eax

    call [rel GetLastError]
    mov edx, eax
    mov rax, [rsp + 40]
    mov r11d, [rsp + 48]
    test r11d, r11d
    mov r10, -1
    cmove rax, r10
    mov r10, 0
    cmovne rdx, r10
    add rsp, 56
}

// 使用 GetFileSizeEx 查询文件大小。
// 编译期参数：无。
// 运行时输入：rdi = HANDLE。
// 返回：rax = 文件字节数或 -1；rdx = 0 或 Win32 错误码
// 错误：GetFileSizeEx 失败时返回 Win32 错误码。
// 所有权：不取得、不关闭 HANDLE。
// ABI：内部保留 shadow space，保持 call 前 16 字节对齐并恢复 rsp。
fn io_file_size() {
    // 32 字节 shadow space、一个 LARGE_INTEGER 结果和一个 BOOL 局部量。
    sub rsp, 56
    xor eax, eax
    mov [rsp + 40], rax
    mov rcx, rdi
    lea rdx, [rsp + 40]
    call [rel GetFileSizeEx]
    mov [rsp + 48], eax

    call [rel GetLastError]
    mov edx, eax
    mov rax, [rsp + 40]
    mov r11d, [rsp + 48]
    test r11d, r11d
    mov r10, -1
    cmove rax, r10
    mov r10, 0
    cmovne rdx, r10
    add rsp, 56
}

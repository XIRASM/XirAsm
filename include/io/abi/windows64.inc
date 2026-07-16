// IO 门面内部使用的 Windows x64 API 辅助函数。
//
// 这些函数会内联 WinAPI 调用序列。调用位置必须处于普通 Win64 函数体
// 栈状态（rsp % 16 == 8）；每个辅助函数都会分配 shadow space、保持
// call 前 16 字节对齐，并在结束时恢复 rsp。

const io_windows64_std_output_handle: u64 = 0xfffffff5
const io_windows64_std_error_handle: u64 = 0xfffffff4
const io_windows64_std_input_handle: u64 = 0xfffffff6
const io_windows64_error_handle_eof: u64 = 38
const io_windows64_error_broken_pipe: u64 = 109

// 把控制台读写所需的 KERNEL32 导入加入现有导入 map。
// 编译期参数：imports = pe_import_new() 或其他 pe_import_use64 返回的 map
// 运行时输入寄存器：无；本函数只在汇编期构造导入描述。
// 返回：包含 GetStdHandle、ReadFile、WriteFile、GetLastError 的新 map
// 错误：无运行时错误；无效 map 或导入描述由格式 DSL 在汇编期诊断。
// 所有权：返回新 map，不修改原 map；无运行时寄存器或栈副作用。
// ABI：不生成运行时代码，不影响寄存器、shadow space 或 rsp。
fn io_windows64_imports(imports: map) -> map {
    return pe_import_use64_many(
        imports,
        "KERNEL32.DLL",
        list.of("GetStdHandle", "ReadFile", "WriteFile", "GetLastError")
    );
}

// 调用 ReadFile 从一个运行时 HANDLE 读取数据。
// 编译期参数：无。
// 运行时输入：
//   rcx = Windows 文件或标准输入句柄
//   rsi = 可写缓冲区地址
//   rdx = 请求读取字节数，最大为 io_max_read_size
// 输出：
//   成功：rax = 实际读取字节数，rdx = 0；EOF 时 rax = 0
//   失败：rax = -1，rdx = GetLastError() 返回值
// 所有权：缓冲区归调用方；本函数只写入 ReadFile 实际返回的字节数。
// 保留：rsi 以及全部 Win64 非易失寄存器
// 破坏：Win64 易失整数寄存器
// 栈：内部保留 32 字节 shadow space，并恢复 rsp。
fn io_windows64_read_handle() {
    const success_label: string = sym.unique("__iow64_read_success_")
    const eof_label: string = sym.unique("__iow64_read_eof_")
    const end_label: string = sym.unique("__iow64_read_end_")

    // 32 字节 shadow space、一个栈参数、两个结果局部量和保存的长度。
    sub rsp, 72
    mov [rsp + 56], rdx
    mov rdx, rsi
    mov r8d, [rsp + 56]
    lea r9, [rsp + 40]
    xor eax, eax
    mov [rsp + 40], rax
    mov [rsp + 32], rax
    call [rel ReadFile]
    mov [rsp + 48], eax

    // 立即读取 GetLastError；ReadFile 成功时该值会被丢弃。
    call [rel GetLastError]
    mov edx, eax
    mov eax, [rsp + 40]
    mov r11d, [rsp + 48]
    test r11d, r11d
    isa(sym.join("jnz ", success_label));
    cmp edx, io_windows64_error_handle_eof
    isa(sym.join("je ", eof_label));
    cmp edx, io_windows64_error_broken_pipe
    isa(sym.join("je ", eof_label));
    mov rax, -1
    isa(sym.join("jmp ", end_label));

    label.define(success_label);
    xor edx, edx
    isa(sym.join("jmp ", end_label));

    label.define(eof_label);
    xor eax, eax
    xor edx, edx

    label.define(end_label);
    add rsp, 72
}

// 调用 WriteFile 写入一个运行时 HANDLE。
// 编译期参数：无。
// 运行时输入：
//   rcx = Windows 文件句柄
//   rsi = 缓冲区地址
//   rdx = 请求写入字节数，最大为 io_max_write_size
// 输出：
//   成功：rax = 实际写入字节数，rdx = 0
//   失败：rax = -1，rdx = GetLastError() 返回值
// 所有权：不取得 HANDLE 或缓冲区所有权；只执行一次 WriteFile。
// 保留：rsi 以及全部 Win64 非易失寄存器
// 破坏：Win64 易失整数寄存器
// 栈：内部保留 32 字节 shadow space，并恢复 rsp。
fn io_windows64_write_handle() {
    // 32 字节 shadow space、一个栈参数、两个结果局部量和保存的长度。
    sub rsp, 72
    mov [rsp + 56], rdx
    mov rdx, rsi
    mov r8d, [rsp + 56]
    lea r9, [rsp + 40]
    xor eax, eax
    mov [rsp + 40], rax
    mov [rsp + 32], rax
    call [rel WriteFile]
    mov [rsp + 48], eax

    // 立即读取 GetLastError；WriteFile 成功时该值会被丢弃。
    call [rel GetLastError]
    mov edx, eax
    mov eax, [rsp + 40]
    mov r11d, [rsp + 48]
    test r11d, r11d
    mov r10, 0xffffffffffffffff
    cmove rax, r10
    mov r10, 0
    cmovne rdx, r10
    add rsp, 72
}

// 取得标准输出/错误句柄并调用 io_windows64_write_handle。
// 编译期参数：
//   handle_kind = 编译期 STD_OUTPUT_HANDLE 或 STD_ERROR_HANDLE 常量
// 运行时输入：
//   rsi         = 缓冲区地址
//   rdx         = 请求写入字节数
// 返回：与 io_windows64_write_handle 相同
// 错误：GetStdHandle/WriteFile 失败时返回 rax = -1、rdx = GetLastError()。
// 所有权：不取得标准句柄或缓冲区所有权。
// 保留：rsi 以及全部 Win64 非易失寄存器
// 栈：内部恢复 rsp；调用点仍需处于普通 Win64 调用栈状态。
fn io_windows64_write_standard(handle_kind: u64) {
    assert(handle_kind <= 0xffffffff, "Windows standard handle selector is out of range");

    // GetStdHandle 会破坏易失寄存器，因此先保存跨平台长度参数。
    sub rsp, 56
    mov [rsp + 40], rdx
    mov ecx, handle_kind
    call [rel GetStdHandle]
    mov rdx, [rsp + 40]
    add rsp, 56

    mov rcx, rax
    io_windows64_write_handle();
}

// 取得标准输入句柄并调用 io_windows64_read_handle。
// 编译期参数：
//   handle_kind = 编译期 STD_INPUT_HANDLE 常量
// 运行时输入：
//   rsi         = 可写缓冲区地址
//   rdx         = 请求读取字节数
// 返回：与 io_windows64_read_handle 相同
// 错误：GetStdHandle/ReadFile 失败时返回 rax = -1、rdx = GetLastError()。
// 所有权：缓冲区归调用方；本函数只传递 HANDLE，不接管资源。
// 保留：rsi 以及全部 Win64 非易失寄存器
// 栈：内部恢复 rsp；调用点仍需处于普通 Win64 调用栈状态。
fn io_windows64_read_standard(handle_kind: u64) {
    assert(handle_kind <= 0xffffffff, "Windows standard handle selector is out of range");

    // GetStdHandle 会破坏易失寄存器，因此先保存跨平台长度参数。
    sub rsp, 56
    mov [rsp + 40], rdx
    mov ecx, handle_kind
    call [rel GetStdHandle]
    mov rdx, [rsp + 40]
    add rsp, 56

    mov rcx, rax
    io_windows64_read_handle();
}

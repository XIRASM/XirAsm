// IO 门面内部使用的 Windows x64 API 辅助函数。
//
// 这些函数会内联 WinAPI 调用序列。调用位置必须处于普通 Win64 函数体
// 栈状态（rsp % 16 == 8）；每个辅助函数都会分配 shadow space、保持
// call 前 16 字节对齐，并在结束时恢复 rsp。

const io_windows64_std_output_handle: u64 = 0xfffffff5
const io_windows64_std_error_handle: u64 = 0xfffffff4

// 把控制台写入所需的 KERNEL32 导入加入现有导入 map。
// 参数：imports = pe_import_new() 或其他 pe_import_use64 返回的 map
// 返回：包含 GetStdHandle、WriteFile、GetLastError 的新 map
fn io_windows64_imports(imports: map) -> map {
    const imports1: map = pe_import_use64(imports, "KERNEL32.DLL", "GetStdHandle");
    const imports2: map = pe_import_use64(imports1, "KERNEL32.DLL", "WriteFile");
    return pe_import_use64(imports2, "KERNEL32.DLL", "GetLastError");
}

// 调用 WriteFile 写入一个运行时 HANDLE。
// 输入：
//   rcx = Windows 文件句柄
//   rsi = 缓冲区地址
//   rdx = 请求写入字节数，最大为 io_max_write_size
// 输出：
//   成功：rax = 实际写入字节数，rdx = 0
//   失败：rax = -1，rdx = GetLastError() 返回值
// 保留：rsi 以及全部 Win64 非易失寄存器
// 破坏：Win64 易失整数寄存器
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
// 参数：
//   handle_kind = 编译期 STD_OUTPUT_HANDLE 或 STD_ERROR_HANDLE 常量
//   rsi         = 缓冲区地址
//   rdx         = 请求写入字节数
// 返回：与 io_windows64_write_handle 相同
// 保留：rsi 以及全部 Win64 非易失寄存器
fn io_windows64_write_standard(handle_kind: u64) {
    assert(handle_kind <= 0xffffffff, "Windows standard handle selector is out of range");

    // GetStdHandle 会破坏易失寄存器，因此先保存跨平台长度参数。
    sub rsp, 56
    mov [rsp + 40], rdx
    isa(sym.join("mov ecx, ", to_string(handle_kind)));
    call [rel GetStdHandle]
    mov rdx, [rsp + 40]
    add rsp, 56

    mov rcx, rax
    io_windows64_write_handle();
}

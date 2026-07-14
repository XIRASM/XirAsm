// Windows x64 目录枚举，路径统一使用 FindFirstFileW 搜索 pattern。
//
// 调用方传入 UTF-16LE pattern，例如 "目录\\*"。状态块由调用方分配，
// 本模块在其中保存 Find handle 和 WIN32_FIND_DATAW 结果缓冲。

assert(target.bits == 64, "io/dir/windows64.inc currently supports x86-64 only");

import("contract.inc");

const io_dir_windows64_invalid_handle: u64 = 0xffffffffffffffff
const io_dir_windows64_error_no_more_files: u64 = 18
const io_dir_windows64_file_attribute_directory: u64 = 0x10
const io_dir_windows64_find_data_file_name_offset: u64 = 44

// 把 Windows dir 模块所需的 KERNEL32 导入加入现有导入 map。
// 编译期参数：imports = pe_import_new() 或其他 pe_import_use64 返回的 map。
// 运行时输入寄存器：无；本函数只在汇编期构造导入描述。
// 返回：包含 FindFirstFileW、FindNextFileW、FindClose、GetLastError 的新 map。
// 错误：无运行时错误；无效 map 由格式 DSL 在汇编期诊断。
// 所有权：原 map 不被隐藏修改；返回 map 由调用方继续传给格式构造函数。
// ABI：不生成运行时调用，不影响运行时寄存器或栈。
fn io_windows64_dir_imports(imports: map) -> map {
    const imports1: map = pe_import_use64(imports, "KERNEL32.DLL", "FindFirstFileW");
    const imports2: map = pe_import_use64(imports1, "KERNEL32.DLL", "FindNextFileW");
    const imports3: map = pe_import_use64(imports2, "KERNEL32.DLL", "FindClose");
    return pe_import_use64(imports3, "KERNEL32.DLL", "GetLastError");
}

// 计算 UTF-16LE 零结尾字符串的字节长度。
// 编译期参数：无。
// 运行时输入：rsi = UTF-16LE 字符串地址。
// 返回：rax = 不含零结尾的字节数。
// 错误：不检测非法指针或缺失零结尾，调用方必须保证输入有效。
// 所有权：只读调用方或状态块中的字符串。
// ABI：保持 rsi；破坏 rax、r10。
fn io_dir_windows64_wstrlen_bytes() {
    xor eax, eax

    const loop_label: string = sym.unique("__iod_w_strlen_loop_")
    const end_label: string = sym.unique("__iod_w_strlen_end_")

    label.define(loop_label);
    mov r10w, [rsi + rax]
    test r10w, r10w
    isa(sym.join("jz ", end_label));
    add rax, 2
    isa(sym.join("jmp ", loop_label));

    label.define(end_label);
}

// 打开 Windows FindFirstFileW 搜索并保存首条记录。
// 编译期参数：无。
// 运行时输入：rdi = 状态块，rsi = UTF-16LE 零结尾搜索 pattern。
// 返回：成功 rax=0、rdx=0；失败 rax=-1、rdx=GetLastError 或 io_dir_error_*。
// 所有权：状态块归调用方；成功后 Find handle 由状态块持有，必须 close。
// ABI：保持 rdi、rsi 和 Win64 非易失寄存器；分配 shadow space 并保持对齐。
fn io_dir_open() {
    const invalid_label: string = sym.unique("__iod_wo_invalid_")
    const already_label: string = sym.unique("__iod_wo_already_")
    const failed_label: string = sym.unique("__iod_wo_failed_")
    const end_label: string = sym.unique("__iod_wo_end_")

    test rdi, rdi
    isa(sym.join("jz ", invalid_label));
    test rsi, rsi
    isa(sym.join("jz ", invalid_label));
    cmp qword [rdi + 40], 0
    isa(sym.join("jne ", already_label));

    sub rsp, 40
    mov rcx, rsi
    lea rdx, [rdi + 80]
    call [rel FindFirstFileW]
    mov [rdi], rax
    call [rel GetLastError]
    mov edx, eax
    add rsp, 40

    cmp qword [rdi], -1
    isa(sym.join("je ", failed_label));
    mov qword [rdi + 8], 0
    mov qword [rdi + 16], 0
    mov qword [rdi + 24], 0
    mov qword [rdi + 32], 0
    mov qword [rdi + 40], 1
    mov qword [rdi + 48], 1
    mov qword [rdi + 56], 0
    mov qword [rdi + 64], 0
    mov qword [rdi + 72], io_dir_buffer_size
    xor eax, eax
    xor edx, edx
    isa(sym.join("jmp ", end_label));

    label.define(failed_label);
    mov qword [rdi + 40], 0
    mov rax, -1
    isa(sym.join("jmp ", end_label));

    label.define(invalid_label);
    mov rax, -1
    mov edx, io_dir_error_invalid_state
    isa(sym.join("jmp ", end_label));

    label.define(already_label);
    mov rax, -1
    mov edx, io_dir_error_already_open

    label.define(end_label);
}

// 读取下一个 Windows 搜索结果。
// 编译期参数：无。
// 运行时输入：rdi = 已打开的状态块。
// 返回：有条目 rax=1、rdx=0；结束 rax=0、rdx=0；失败 rax=-1、rdx=错误码。
// 所有权：当前 name 指针指向状态块内部 WIN32_FIND_DATAW，到下次 next/close 前有效。
// ABI：保持 rdi、rsi 和 Win64 非易失寄存器；分配 shadow space 并保持对齐。
fn io_dir_next() {
    const invalid_label: string = sym.unique("__iod_wn_invalid_")
    const not_open_label: string = sym.unique("__iod_wn_not_open_")
    const use_current_label: string = sym.unique("__iod_wn_current_")
    const next_failed_label: string = sym.unique("__iod_wn_failed_")
    const no_more_label: string = sym.unique("__iod_wn_no_more_")
    const directory_label: string = sym.unique("__iod_wn_dir_")
    const success_label: string = sym.unique("__iod_wn_success_")
    const end_label: string = sym.unique("__iod_wn_end_")

    test rdi, rdi
    isa(sym.join("jz ", invalid_label));
    cmp qword [rdi + 40], 1
    isa(sym.join("jne ", not_open_label));
    cmp qword [rdi + 48], 1
    isa(sym.join("je ", use_current_label));

    sub rsp, 40
    mov rcx, [rdi]
    lea rdx, [rdi + 80]
    call [rel FindNextFileW]
    mov [rsp + 32], eax
    call [rel GetLastError]
    mov edx, eax
    mov r11d, [rsp + 32]
    add rsp, 40
    test r11d, r11d
    isa(sym.join("jz ", next_failed_label));

    label.define(use_current_label);
    mov qword [rdi + 48], 0
    push rsi
    lea rsi, [rdi + 124]
    io_dir_windows64_wstrlen_bytes();
    mov [rdi + 8], rsi
    mov [rdi + 16], rax
    pop rsi
    mov eax, [rdi + 80]
    test eax, io_dir_windows64_file_attribute_directory
    isa(sym.join("jnz ", directory_label));
    mov qword [rdi + 24], io_dir_kind_file
    isa(sym.join("jmp ", success_label));

    label.define(directory_label);
    mov qword [rdi + 24], io_dir_kind_directory

    label.define(success_label);
    mov qword [rdi + 32], 0
    mov eax, 1
    xor edx, edx
    isa(sym.join("jmp ", end_label));

    label.define(next_failed_label);
    cmp edx, io_dir_windows64_error_no_more_files
    isa(sym.join("je ", no_more_label));
    mov rax, -1
    mov [rdi + 32], rdx
    isa(sym.join("jmp ", end_label));

    label.define(no_more_label);
    xor eax, eax
    xor edx, edx
    isa(sym.join("jmp ", end_label));

    label.define(invalid_label);
    mov rax, -1
    mov edx, io_dir_error_invalid_state
    isa(sym.join("jmp ", end_label));

    label.define(not_open_label);
    mov rax, -1
    mov edx, io_dir_error_not_open

    label.define(end_label);
}

// 关闭 Windows Find handle 并清空状态。
// 编译期参数：无。
// 运行时输入：rdi = 状态块。
// 返回：成功 rax=0、rdx=0；关闭失败 rax=-1、rdx=GetLastError；关闭状态为成功 no-op。
// 所有权：调用后状态块不再持有 Find handle，即使 FindClose 报错也不得复用。
// ABI：保持 rdi 和 Win64 非易失寄存器；分配 shadow space 并保持对齐。
fn io_dir_close() {
    const invalid_label: string = sym.unique("__iod_wc_invalid_")
    const closed_label: string = sym.unique("__iod_wc_closed_")
    const end_label: string = sym.unique("__iod_wc_end_")

    test rdi, rdi
    isa(sym.join("jz ", invalid_label));
    cmp qword [rdi + 40], 0
    isa(sym.join("je ", closed_label));

    sub rsp, 40
    mov rcx, [rdi]
    call [rel FindClose]
    mov [rsp + 32], eax
    call [rel GetLastError]
    mov edx, eax
    mov r11d, [rsp + 32]
    add rsp, 40

    mov qword [rdi], -1
    mov qword [rdi + 40], 0
    test r11d, r11d
    mov rax, -1
    mov r10, 0
    cmovne rax, r10
    cmovne rdx, r10
    isa(sym.join("jmp ", end_label));

    label.define(closed_label);
    xor eax, eax
    xor edx, edx
    isa(sym.join("jmp ", end_label));

    label.define(invalid_label);
    mov rax, -1
    mov edx, io_dir_error_invalid_state

    label.define(end_label);
}

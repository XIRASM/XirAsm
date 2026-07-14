// Windows x64 路径操作，路径统一使用原生 UTF-16LE。
//
// 生成 PE 时必须调用 io_windows64_path_imports(imports) 加入所需导入。
// 本模块不分配、不保存或修改路径内存。

assert(target.bits == 64, "io/path/windows64.inc currently supports x86-64 only");

import("contract.inc");

const io_path_windows64_invalid_attributes: u64 = 0xffffffff
const io_path_windows64_attribute_directory: u64 = 0x10
const io_path_windows64_attribute_device: u64 = 0x40
const io_path_windows64_move_replace_existing: u64 = 1
const io_path_windows64_error_file_not_found: u64 = 2
const io_path_windows64_error_path_not_found: u64 = 3
const io_path_windows64_error_already_exists: u64 = 183

// 把 Windows path 模块所需的 KERNEL32 导入加入现有导入 map。
// 编译期参数：imports = pe_import_new() 或其他 pe_import_use64 返回的 map。
// 运行时输入寄存器：无；本函数只在汇编期构造导入描述。
// 返回：包含 GetFileAttributesW、CreateDirectoryW、DeleteFileW、
//       MoveFileExW、GetLastError 的新 map。
// 错误：无运行时错误；无效 map 或导入描述由格式 DSL 在汇编期诊断。
// 所有权：原 map 不被隐藏修改；返回 map 由调用方继续传给格式构造函数。
// ABI：不生成运行时调用，不影响运行时寄存器或栈。
fn io_windows64_path_imports(imports: map) -> map {
    const imports1: map = pe_import_use64(imports, "KERNEL32.DLL", "GetFileAttributesW");
    const imports2: map = pe_import_use64(imports1, "KERNEL32.DLL", "CreateDirectoryW");
    const imports3: map = pe_import_use64(imports2, "KERNEL32.DLL", "DeleteFileW");
    const imports4: map = pe_import_use64(imports3, "KERNEL32.DLL", "MoveFileExW");
    return pe_import_use64(imports4, "KERNEL32.DLL", "GetLastError");
}

// 调用 UTF-16 路径、BOOL 返回值的 WinAPI。
// 编译期参数：api_name = CreateDirectoryW 或 DeleteFileW 的导入符号名。
// 运行时输入：rsi = UTF-16LE 零结尾路径。
// 返回：成功 rax=0、rdx=0；失败 rax=-1、rdx=GetLastError() 返回值。
// 参数约定：始终传 rcx=路径、rdx=0。CreateDirectoryW 把 rdx 作为
//          lpSecurityAttributes；DeleteFileW 会忽略这个额外寄存器参数。
// 所有权：路径内存始终归调用方。
// ABI：保持 rsi 和全部 Win64 非易失寄存器；分配 32 字节 shadow space，
//      保持 call 前 16 字节对齐；破坏 Win64 易失整数寄存器。
fn io_windows64_path_bool1(api_name: string) {
    assert(len(api_name) > 0, "Windows path API name is empty");

    sub rsp, 40
    mov rcx, rsi
    xor edx, edx
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

// 使用 GetFileAttributesW 查询路径类型。
// 编译期参数：无。
// 运行时输入：rsi = UTF-16LE 零结尾路径。
// 返回：文件/目录/其他对象时 rax=io_path_kind_*、rdx=0；
//       ERROR_FILE_NOT_FOUND/ERROR_PATH_NOT_FOUND 时 rax=0、rdx=0；
//       其他失败时 rax=-1、rdx=GetLastError() 返回值。
// 所有权：路径内存始终归调用方。
// ABI：保持 rsi 和全部 Win64 非易失寄存器；分配 32 字节 shadow space，
//      保持 call 前 16 字节对齐；破坏 Win64 易失整数寄存器。
fn io_path_query() {
    const classify_label: string = sym.unique("__iop_wq_classify_")
    const directory_label: string = sym.unique("__iop_wq_directory_")
    const other_label: string = sym.unique("__iop_wq_other_")
    const missing_label: string = sym.unique("__iop_wq_missing_")
    const end_label: string = sym.unique("__iop_wq_end_")

    sub rsp, 56
    mov rcx, rsi
    call [rel GetFileAttributesW]
    mov [rsp + 40], eax
    call [rel GetLastError]
    mov edx, eax
    mov r11d, [rsp + 40]

    cmp r11d, io_path_windows64_invalid_attributes
    isa(sym.join("jne ", classify_label));
    cmp edx, io_path_windows64_error_file_not_found
    isa(sym.join("je ", missing_label));
    cmp edx, io_path_windows64_error_path_not_found
    isa(sym.join("je ", missing_label));
    mov rax, -1
    isa(sym.join("jmp ", end_label));

    label.define(classify_label);
    test r11d, io_path_windows64_attribute_directory
    isa(sym.join("jnz ", directory_label));
    test r11d, io_path_windows64_attribute_device
    isa(sym.join("jnz ", other_label));
    mov eax, io_path_kind_file
    xor edx, edx
    isa(sym.join("jmp ", end_label));

    label.define(directory_label);
    mov eax, io_path_kind_directory
    xor edx, edx
    isa(sym.join("jmp ", end_label));

    label.define(other_label);
    mov eax, io_path_kind_other
    xor edx, edx
    isa(sym.join("jmp ", end_label));

    label.define(missing_label);
    xor eax, eax
    xor edx, edx

    label.define(end_label);
    add rsp, 56
}

// 查询路径布尔存在性。
// 编译期参数：无。
// 运行时输入：rsi = UTF-16LE 零结尾路径。
// 返回：存在时 rax=1、rdx=0；缺失时 rax=0、rdx=0；
//       查询失败时 rax=-1、rdx=GetLastError() 返回值。
// 所有权：路径内存始终归调用方。
// ABI：保持 rsi 和全部 Win64 非易失寄存器；栈要求与 io_path_query 相同。
fn io_path_exists() {
    const end_label: string = sym.unique("__iop_we_end_")

    io_path_query();
    cmp rax, -1
    isa(sym.join("je ", end_label));
    test rax, rax
    isa(sym.join("jz ", end_label));
    mov eax, 1

    label.define(end_label);
}

// 使用 CreateDirectoryW 创建一个目录组件。
// 编译期参数：无。
// 运行时输入：rsi = UTF-16LE 零结尾目录路径。
// 返回：新建或已存在目录时 rax=0、rdx=0；失败时 rax=-1、
//       rdx=GetLastError() 返回值。ERROR_ALREADY_EXISTS 只有在查询确认
//       对象是目录时才视为成功。
// 所有权：路径内存始终归调用方；本函数不递归创建父目录。
// ABI：保持 rsi 和全部 Win64 非易失寄存器；每个 API 调用分配 shadow
//      space 并保持 call 前 16 字节对齐；破坏 Win64 易失整数寄存器。
fn io_path_make_dir() {
    const existed_label: string = sym.unique("__iop_wmd_existed_")
    const success_label: string = sym.unique("__iop_wmd_success_")
    const end_label: string = sym.unique("__iop_wmd_end_")

    io_windows64_path_bool1("CreateDirectoryW");
    cmp edx, io_path_windows64_error_already_exists
    isa(sym.join("je ", existed_label));
    isa(sym.join("jmp ", end_label));

    label.define(existed_label);
    io_path_query();
    cmp rax, io_path_kind_directory
    isa(sym.join("je ", success_label));
    cmp rax, -1
    isa(sym.join("je ", end_label));
    mov rax, -1
    mov edx, io_path_windows64_error_already_exists
    isa(sym.join("jmp ", end_label));

    label.define(success_label);
    xor eax, eax
    xor edx, edx

    label.define(end_label);
}

// 使用 DeleteFileW 严格删除普通文件。
// 编译期参数：无。
// 运行时输入：rsi = UTF-16LE 零结尾文件路径。
// 返回：成功 rax=0、rdx=0；缺失、目录、权限等失败时 rax=-1、
//       rdx=GetLastError() 返回值。
// 所有权：路径内存始终归调用方；本函数不删除目录。
// ABI：保持 rsi 和全部 Win64 非易失寄存器；分配 shadow space，
//      保持 call 前 16 字节对齐；破坏 Win64 易失整数寄存器。
fn io_path_remove_file() {
    io_windows64_path_bool1("DeleteFileW");
}

// 使用 MoveFileExW 替换重命名文件。
// 编译期参数：无。
// 运行时输入：rsi = UTF-16LE 源路径，rdi = UTF-16LE 目标路径。
// 返回：成功 rax=0、rdx=0；失败 rax=-1、rdx=GetLastError() 返回值。
// 所有权：两个路径始终归调用方；不创建父目录，也不启用跨卷复制。
// ABI：保持 rsi、rdi 和全部 Win64 非易失寄存器；分配 32 字节 shadow
//      space，保持 call 前 16 字节对齐；破坏 Win64 易失整数寄存器。
fn io_path_rename_replace() {
    sub rsp, 40
    mov rcx, rsi
    mov rdx, rdi
    mov r8d, io_path_windows64_move_replace_existing
    call [rel MoveFileExW]
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

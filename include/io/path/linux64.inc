// Linux x86-64 路径操作，直接使用 syscall，不依赖 libc。
//
// 依赖 io/linux.inc 已先导入 abi/linux64.inc，因此错误结果通过
// io_linux64_normalize_count_result() 归一化。

assert(target.bits == 64, "io/path/linux64.inc currently supports x86-64 only");

import("contract.inc");

const io_path_linux64_sys_stat: u64 = 4
const io_path_linux64_sys_rename: u64 = 82
const io_path_linux64_sys_mkdir: u64 = 83
const io_path_linux64_sys_unlink: u64 = 87

const io_path_linux64_stat_size: u64 = 144
const io_path_linux64_stat_mode_offset: u64 = 24
const io_path_linux64_mode_mask: u64 = 0xf000
const io_path_linux64_mode_file: u64 = 0x8000
const io_path_linux64_mode_directory: u64 = 0x4000
const io_path_linux64_create_mode: u64 = 0x1ff

const io_path_linux64_enoent: u64 = 2
const io_path_linux64_eexist: u64 = 17
const io_path_linux64_enotdir: u64 = 20

// 使用 stat(2) 查询路径类型。
// 编译期参数：无。
// 运行时输入：rsi = Linux 零结尾字节路径。
// 返回：文件/目录/其他对象时 rax=io_path_kind_*、rdx=0；
//       ENOENT/ENOTDIR 时 rax=io_path_kind_missing、rdx=0；
//       其他失败时 rax=-1、rdx=正数 errno。
// 所有权：路径内存归调用方；内部仅使用 144 字节 struct stat 栈空间。
// ABI：保持 rsi、rsp；syscall 破坏 rcx/r11，本函数还破坏易失寄存器。
fn io_path_query() {
    const classify_label: string = sym.unique("__iop_lq_classify_")
    const file_label: string = sym.unique("__iop_lq_file_")
    const directory_label: string = sym.unique("__iop_lq_directory_")
    const missing_label: string = sym.unique("__iop_lq_missing_")
    const end_label: string = sym.unique("__iop_lq_end_")

    push rsi
    isa(sym.join("sub rsp, ", to_string(io_path_linux64_stat_size)));
    mov rdi, rsi
    mov rsi, rsp
    isa(sym.join("mov eax, ", to_string(io_path_linux64_sys_stat)));
    syscall
    mov r8, rax
    isa(sym.join("mov r9d, [rsp + ", to_string(io_path_linux64_stat_mode_offset), "]"));
    isa(sym.join("add rsp, ", to_string(io_path_linux64_stat_size)));
    pop rsi

    test r8, r8
    isa(sym.join("jns ", classify_label));
    isa(sym.join("cmp r8, -", to_string(io_path_linux64_enoent)));
    isa(sym.join("je ", missing_label));
    isa(sym.join("cmp r8, -", to_string(io_path_linux64_enotdir)));
    isa(sym.join("je ", missing_label));
    mov rax, r8
    io_linux64_normalize_count_result();
    isa(sym.join("jmp ", end_label));

    label.define(classify_label);
    mov eax, r9d
    isa(sym.join("and eax, ", to_string(io_path_linux64_mode_mask)));
    isa(sym.join("cmp eax, ", to_string(io_path_linux64_mode_file)));
    isa(sym.join("je ", file_label));
    isa(sym.join("cmp eax, ", to_string(io_path_linux64_mode_directory)));
    isa(sym.join("je ", directory_label));
    isa(sym.join("mov eax, ", to_string(io_path_kind_other)));
    xor edx, edx
    isa(sym.join("jmp ", end_label));

    label.define(file_label);
    isa(sym.join("mov eax, ", to_string(io_path_kind_file)));
    xor edx, edx
    isa(sym.join("jmp ", end_label));

    label.define(directory_label);
    isa(sym.join("mov eax, ", to_string(io_path_kind_directory)));
    xor edx, edx
    isa(sym.join("jmp ", end_label));

    label.define(missing_label);
    xor eax, eax
    xor edx, edx

    label.define(end_label);
}

// 查询路径布尔存在性。
// 编译期参数：无。
// 运行时输入：rsi = Linux 零结尾字节路径。
// 返回：存在时 rax=1、rdx=0；缺失时 rax=0、rdx=0；
//       查询失败时 rax=-1、rdx=正数 errno。
// 所有权：路径内存始终归调用方。
// ABI：保持 rsi、rsp；破坏与 io_path_query 相同的易失寄存器。
fn io_path_exists() {
    const end_label: string = sym.unique("__iop_le_end_")

    io_path_query();
    cmp rax, -1
    isa(sym.join("je ", end_label));
    test rax, rax
    isa(sym.join("jz ", end_label));
    mov eax, 1

    label.define(end_label);
}

// 使用 mkdir(2) 创建一个目录组件。
// 编译期参数：无。
// 运行时输入：rsi = Linux 零结尾字节目录路径。
// 返回：新建或已存在目录时 rax=0、rdx=0；失败时 rax=-1、
//       rdx=正数 errno。EEXIST 只有在 stat 确认为目录时才视为成功。
// 所有权：路径内存始终归调用方；权限 0777 再由进程 umask 收紧。
// ABI：保持 rsi、rsp；syscall 破坏 rcx/r11，本函数破坏易失寄存器。
fn io_path_make_dir() {
    const existed_label: string = sym.unique("__iop_lmd_existed_")
    const success_label: string = sym.unique("__iop_lmd_success_")
    const end_label: string = sym.unique("__iop_lmd_end_")

    push rsi
    mov rdi, rsi
    isa(sym.join("mov esi, ", to_string(io_path_linux64_create_mode)));
    isa(sym.join("mov eax, ", to_string(io_path_linux64_sys_mkdir)));
    syscall
    pop rsi

    isa(sym.join("cmp rax, -", to_string(io_path_linux64_eexist)));
    isa(sym.join("je ", existed_label));
    io_linux64_normalize_count_result();
    isa(sym.join("jmp ", end_label));

    label.define(existed_label);
    io_path_query();
    isa(sym.join("cmp rax, ", to_string(io_path_kind_directory)));
    isa(sym.join("je ", success_label));
    cmp rax, -1
    isa(sym.join("je ", end_label));
    mov rax, -1
    isa(sym.join("mov edx, ", to_string(io_path_linux64_eexist)));
    isa(sym.join("jmp ", end_label));

    label.define(success_label);
    xor eax, eax
    xor edx, edx

    label.define(end_label);
}

// 使用 unlink(2) 严格删除普通文件。
// 编译期参数：无。
// 运行时输入：rsi = Linux 零结尾字节文件路径。
// 返回：成功 rax=0、rdx=0；缺失、目录、权限等失败时 rax=-1、
//       rdx=正数 errno。
// 所有权：路径内存始终归调用方；本函数不删除目录。
// ABI：保持 rsi、rsp；syscall 破坏 rcx/r11，本函数破坏易失寄存器。
fn io_path_remove_file() {
    push rsi
    mov rdi, rsi
    isa(sym.join("mov eax, ", to_string(io_path_linux64_sys_unlink)));
    syscall
    pop rsi
    io_linux64_normalize_count_result();
}

// 使用 rename(2) 替换重命名文件。
// 编译期参数：无。
// 运行时输入：rsi = 源路径，rdi = 目标路径，均为 Linux 零结尾字节路径。
// 返回：成功 rax=0、rdx=0；失败 rax=-1、rdx=正数 errno。
// 所有权：两个路径始终归调用方；不创建父目录、不承诺跨文件系统移动。
// ABI：保持 rsi、rdi 寄存器和 rsp 栈位置；syscall 破坏 rcx/r11，
//      并使用 r10 暂存目标路径。
fn io_path_rename_replace() {
    push rdi
    push rsi
    mov r10, rdi
    mov rdi, rsi
    mov rsi, r10
    isa(sym.join("mov eax, ", to_string(io_path_linux64_sys_rename)));
    syscall
    pop rsi
    pop rdi
    io_linux64_normalize_count_result();
}

// Linux x86-64 文件内存映射入口。
//
// 本文件直接使用 Linux syscall，不依赖 libc。映射只覆盖完整文件且偏移为
// 0；普通 IO 数据映射只使用读/写页权限，不继承 EASM 参考里的可执行页权限。
// 调用方提供状态块，关闭时由状态块消费 fd 和 mmap 视图。

assert(target.bits == 64, "io/map/linux64.inc currently supports x86-64 only");

// 依赖由公开总入口 io/linux.inc 先行导入，避免不同相对路径造成重复模块。
import("contract.inc");

const io_map_linux64_sys_close: u64 = 3
const io_map_linux64_sys_fstat: u64 = 5
const io_map_linux64_sys_mmap: u64 = 9
const io_map_linux64_sys_munmap: u64 = 11
const io_map_linux64_sys_msync: u64 = 26
const io_map_linux64_sys_ftruncate: u64 = 77

const io_map_linux64_o_read_write: u64 = 2
const io_map_linux64_o_create: u64 = 0x40
const io_map_linux64_o_truncate: u64 = 0x200
const io_map_linux64_create_mode: u64 = 0x1b6

const io_map_linux64_prot_read: u64 = 0x1
const io_map_linux64_prot_write: u64 = 0x2
const io_map_linux64_map_shared: u64 = 0x1
const io_map_linux64_ms_sync: u64 = 0x4

const io_map_linux64_stat_size: u64 = 144
const io_map_linux64_stat_size_offset: u64 = 48

// 把状态块恢复成关闭状态。
// 编译期参数：无。
// 运行时输入：rbx = 状态块地址。
// 返回：不设置 rax/rdx；调用方负责最终结果。
// 所有权：仅清空记录，不关闭任何原生资源。
// ABI：保持 rbx 和 rsp；只写状态块内 48 字节。
fn io_map_linux64_clear_state() {
    mov qword [rbx], -1
    mov qword [rbx + 8], 0
    mov qword [rbx + 16], 0
    mov qword [rbx + 24], 0
    mov qword [rbx + 32], 0
    mov qword [rbx + 40], 0
}

// 使用 fstat(2) 读取 fd 的当前文件大小。
// 编译期参数：无。
// 运行时输入：rdi = Linux fd。
// 返回：成功 rax=文件大小、rdx=0；失败 rax=-1、rdx=正数 errno。
// 所有权：不取得、不关闭 fd；内部只用栈上 144 字节 struct stat。
// ABI：保持 rdi、rsp；syscall 破坏 rcx/r11，本函数破坏易失寄存器。
fn io_map_linux64_file_size() {
    push rdi
    isa(sym.join("sub rsp, ", to_string(io_map_linux64_stat_size)));
    mov rsi, rsp
    isa(sym.join("mov eax, ", to_string(io_map_linux64_sys_fstat)));
    syscall
    mov r8, rax
    isa(sym.join("mov r9, [rsp + ", to_string(io_map_linux64_stat_size_offset), "]"));
    isa(sym.join("add rsp, ", to_string(io_map_linux64_stat_size)));
    pop rdi

    io_linux64_normalize_count_result();
    test r8, r8
    cmovns rax, r9
}

// 打开现有文件并建立只读完整映射。
// 编译期参数：无。
// 运行时输入：rdi = 48 字节关闭状态块，rsi = Linux 零结尾字节路径。
// 返回：成功 rax=视图指针，空文件为 0，rdx=0；
//       失败 rax=-1，rdx=正数 errno 或 io_map_error_invalid_state。
// 所有权：成功后状态块拥有 fd 和视图；空文件只拥有 fd。
// ABI：保持 rbx、r12、r13、rsi 和 rsp；syscall 破坏 rcx/r11，本函数破坏易失寄存器。
fn io_map_open_read() {
    const invalid_state_label: string = sym.unique("__iom_lor_bad_state_")
    const open_failed_label: string = sym.unique("__iom_lor_open_failed_")
    const size_failed_label: string = sym.unique("__iom_lor_size_failed_")
    const empty_label: string = sym.unique("__iom_lor_empty_")
    const map_failed_label: string = sym.unique("__iom_lor_map_failed_")
    const restore_label: string = sym.unique("__iom_lor_restore_")
    const end_label: string = sym.unique("__iom_lor_end_")

    test rdi, rdi
    isa(sym.join("jz ", invalid_state_label));
    cmp qword [rdi + 32], 0
    isa(sym.join("jne ", invalid_state_label));

    push rbx
    push r12
    push r13
    push rsi
    mov rbx, rdi
    io_map_linux64_clear_state();

    io_file_open_read();
    cmp rax, -1
    isa(sym.join("je ", open_failed_label));
    mov [rbx], rax
    mov r12, rax

    mov rdi, r12
    io_map_linux64_file_size();
    cmp rax, -1
    isa(sym.join("je ", size_failed_label));
    mov [rbx + 24], rax
    test rax, rax
    isa(sym.join("jz ", empty_label));

    xor edi, edi
    mov rsi, rax
    isa(sym.join("mov edx, ", to_string(io_map_linux64_prot_read)));
    isa(sym.join("mov r10d, ", to_string(io_map_linux64_map_shared)));
    mov r8, r12
    xor r9d, r9d
    isa(sym.join("mov eax, ", to_string(io_map_linux64_sys_mmap)));
    syscall
    io_linux64_normalize_count_result();
    cmp rax, -1
    isa(sym.join("je ", map_failed_label));

    mov [rbx + 16], rax
    mov qword [rbx + 32], 1
    xor edx, edx
    isa(sym.join("jmp ", restore_label));

    label.define(empty_label);
    mov qword [rbx + 16], 0
    mov qword [rbx + 32], 1
    xor eax, eax
    xor edx, edx
    isa(sym.join("jmp ", restore_label));

    label.define(size_failed_label);
    mov r13, rdx
    mov rdi, [rbx]
    isa(sym.join("mov eax, ", to_string(io_map_linux64_sys_close)));
    syscall
    io_map_linux64_clear_state();
    mov rax, -1
    mov rdx, r13
    isa(sym.join("jmp ", restore_label));

    label.define(map_failed_label);
    mov r13, rdx
    mov rdi, [rbx]
    isa(sym.join("mov eax, ", to_string(io_map_linux64_sys_close)));
    syscall
    io_map_linux64_clear_state();
    mov rax, -1
    mov rdx, r13
    isa(sym.join("jmp ", restore_label));

    label.define(open_failed_label);
    io_map_linux64_clear_state();

    label.define(restore_label);
    pop rsi
    pop r13
    pop r12
    pop rbx
    isa(sym.join("jmp ", end_label));

    label.define(invalid_state_label);
    mov rax, -1
    mov edx, 0x7fff2001

    label.define(end_label);
}

// 创建或截断文件并建立读写完整映射。
// 编译期参数：无。
// 运行时输入：rdi = 48 字节关闭状态块，rsi = Linux 路径，rcx = 映射长度。
// 返回：成功 rax=可写视图、rdx=0；失败 rax=-1、rdx=正数 errno 或 io_map_error_*。
// 所有权：成功后状态块拥有 fd 和视图；失败时状态保持关闭。
// ABI：保持 rbx、r12、r13、rsi 和 rsp；syscall 破坏 rcx/r11，本函数破坏易失寄存器。
fn io_map_create() {
    const invalid_state_label: string = sym.unique("__iom_lc_bad_state_")
    const invalid_length_label: string = sym.unique("__iom_lc_bad_length_")
    const open_failed_label: string = sym.unique("__iom_lc_open_failed_")
    const truncate_failed_label: string = sym.unique("__iom_lc_trunc_failed_")
    const map_failed_label: string = sym.unique("__iom_lc_map_failed_")
    const restore_label: string = sym.unique("__iom_lc_restore_")
    const end_label: string = sym.unique("__iom_lc_end_")

    test rdi, rdi
    isa(sym.join("jz ", invalid_state_label));
    cmp qword [rdi + 32], 0
    isa(sym.join("jne ", invalid_state_label));
    test rcx, rcx
    isa(sym.join("jz ", invalid_length_label));
    mov r10, rcx
    shr r10, 63
    test r10, r10
    isa(sym.join("jnz ", invalid_length_label));

    push rbx
    push r12
    push r13
    push rsi
    mov rbx, rdi
    mov r12, rcx
    io_map_linux64_clear_state();

    io_linux64_open_path(
        io_map_linux64_o_read_write | io_map_linux64_o_create | io_map_linux64_o_truncate,
        io_map_linux64_create_mode
    );
    cmp rax, -1
    isa(sym.join("je ", open_failed_label));
    mov [rbx], rax
    mov r13, rax

    mov rdi, r13
    mov rsi, r12
    isa(sym.join("mov eax, ", to_string(io_map_linux64_sys_ftruncate)));
    syscall
    io_linux64_normalize_count_result();
    cmp rax, -1
    isa(sym.join("je ", truncate_failed_label));

    xor edi, edi
    mov rsi, r12
    isa(sym.join("mov edx, ", to_string(io_map_linux64_prot_read | io_map_linux64_prot_write)));
    isa(sym.join("mov r10d, ", to_string(io_map_linux64_map_shared)));
    mov r8, r13
    xor r9d, r9d
    isa(sym.join("mov eax, ", to_string(io_map_linux64_sys_mmap)));
    syscall
    io_linux64_normalize_count_result();
    cmp rax, -1
    isa(sym.join("je ", map_failed_label));

    mov [rbx + 16], rax
    mov [rbx + 24], r12
    mov qword [rbx + 32], 2
    xor edx, edx
    isa(sym.join("jmp ", restore_label));

    label.define(truncate_failed_label);
    mov r12, rdx
    mov rdi, [rbx]
    isa(sym.join("mov eax, ", to_string(io_map_linux64_sys_close)));
    syscall
    io_map_linux64_clear_state();
    mov rax, -1
    mov rdx, r12
    isa(sym.join("jmp ", restore_label));

    label.define(map_failed_label);
    mov r12, rdx
    mov rdi, [rbx]
    isa(sym.join("mov eax, ", to_string(io_map_linux64_sys_close)));
    syscall
    io_map_linux64_clear_state();
    mov rax, -1
    mov rdx, r12
    isa(sym.join("jmp ", restore_label));

    label.define(open_failed_label);
    io_map_linux64_clear_state();

    label.define(restore_label);
    pop rsi
    pop r13
    pop r12
    pop rbx
    isa(sym.join("jmp ", end_label));

    label.define(invalid_state_label);
    mov rax, -1
    mov edx, 0x7fff2001
    isa(sym.join("jmp ", end_label));

    label.define(invalid_length_label);
    mov rax, -1
    mov edx, 0x7fff2002

    label.define(end_label);
}

// 刷新写映射到后端存储。
// 编译期参数：无。
// 运行时输入：rdi = 已打开的映射状态块。
// 返回：成功或只读映射 rax=0、rdx=0；失败 rax=-1、rdx=错误码。
// 所有权：不关闭 fd 或视图；只提交写映射页面。
// ABI：保持 rbx 和 rsp；syscall 破坏 rcx/r11，本函数破坏易失寄存器。
fn io_map_flush() {
    const read_label: string = sym.unique("__iom_lf_read_")
    const invalid_state_label: string = sym.unique("__iom_lf_bad_state_")
    const end_label: string = sym.unique("__iom_lf_end_")

    test rdi, rdi
    isa(sym.join("jz ", invalid_state_label));
    mov r10, [rdi + 32]
    cmp r10, 1
    isa(sym.join("je ", read_label));
    cmp r10, 2
    isa(sym.join("jne ", invalid_state_label));

    mov rsi, [rdi + 24]
    test rsi, rsi
    isa(sym.join("jz ", read_label));
    mov rdi, [rdi + 16]
    isa(sym.join("mov edx, ", to_string(io_map_linux64_ms_sync)));
    isa(sym.join("mov eax, ", to_string(io_map_linux64_sys_msync)));
    syscall
    io_linux64_normalize_count_result();
    isa(sym.join("jmp ", end_label));

    label.define(read_label);
    xor eax, eax
    xor edx, edx
    isa(sym.join("jmp ", end_label));

    label.define(invalid_state_label);
    mov rax, -1
    mov edx, 0x7fff2001

    label.define(end_label);
}

// 关闭映射并消费状态块拥有的 fd 和 mmap 视图。
// 编译期参数：无。
// 运行时输入：rdi = 已打开的映射状态块。
// 返回：成功 rax=0、rdx=0；失败 rax=-1、rdx=首个刷新/解除映射/关闭错误。
// 所有权：调用后状态块清空；即使返回失败也不再拥有原生资源。
// ABI：保持 rbx、r12-r13 和 rsp；syscall 破坏 rcx/r11，本函数破坏易失寄存器。
fn io_map_close() {
    const skip_flush_label: string = sym.unique("__iom_lclose_skip_flush_")
    const skip_unmap_label: string = sym.unique("__iom_lclose_skip_unmap_")
    const keep_unmap_error_label: string = sym.unique("__iom_lclose_keep_unmap_")
    const keep_close_error_label: string = sym.unique("__iom_lclose_keep_close_")
    const success_label: string = sym.unique("__iom_lclose_success_")
    const invalid_state_label: string = sym.unique("__iom_lclose_bad_state_")
    const restore_invalid_state_label: string = sym.unique("__iom_lclose_restore_bad_state_")
    const restore_label: string = sym.unique("__iom_lclose_restore_")

    test rdi, rdi
    isa(sym.join("jz ", invalid_state_label));

    push rbx
    push r12
    push r13
    mov rbx, rdi
    xor r12d, r12d
    mov r10, [rbx + 32]
    cmp r10, 1
    isa(sym.join("je ", skip_flush_label));
    cmp r10, 2
    isa(sym.join("jne ", restore_invalid_state_label));

    mov rdi, rbx
    io_map_flush();
    test rdx, rdx
    isa(sym.join("jz ", skip_flush_label));
    mov r12, rdx

    label.define(skip_flush_label);
    mov rdi, [rbx + 16]
    mov rsi, [rbx + 24]
    test rdi, rdi
    isa(sym.join("jz ", skip_unmap_label));
    test rsi, rsi
    isa(sym.join("jz ", skip_unmap_label));
    isa(sym.join("mov eax, ", to_string(io_map_linux64_sys_munmap)));
    syscall
    io_linux64_normalize_count_result();
    test rdx, rdx
    isa(sym.join("jz ", skip_unmap_label));
    test r12, r12
    isa(sym.join("jnz ", keep_unmap_error_label));
    mov r12, rdx

    label.define(keep_unmap_error_label);
    label.define(skip_unmap_label);
    mov rdi, [rbx]
    isa(sym.join("mov eax, ", to_string(io_map_linux64_sys_close)));
    syscall
    io_linux64_normalize_count_result();
    test rdx, rdx
    isa(sym.join("jz ", keep_close_error_label));
    test r12, r12
    isa(sym.join("jnz ", keep_close_error_label));
    mov r12, rdx

    label.define(keep_close_error_label);
    io_map_linux64_clear_state();
    test r12, r12
    isa(sym.join("jz ", success_label));
    mov rax, -1
    mov rdx, r12
    isa(sym.join("jmp ", restore_label));

    label.define(success_label);
    xor eax, eax
    xor edx, edx

    label.define(restore_label);
    pop r13
    pop r12
    pop rbx
    isa(sym.join("jmp ", invalid_state_label, "_end"));

    label.define(restore_invalid_state_label);
    mov rax, -1
    mov edx, 0x7fff2001
    isa(sym.join("jmp ", restore_label));

    label.define(invalid_state_label);
    mov rax, -1
    mov edx, 0x7fff2001

    label.define(sym.join(invalid_state_label, "_end"));
}

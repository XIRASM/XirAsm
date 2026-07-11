// 跨平台 x86-64 缓冲流公共实现。
//
// 本模块只建立在已经归一化的 file/ 层之上，不直接调用 syscall 或 WinAPI，
// 也不分配、扩容或释放内存。调用方必须提供一个清零的 64 字节可写状态块，
// 以及一个容量大于 0 的可写缓冲区；缓冲区在流关闭后仍归调用方所有。
//
// 状态块布局（全部字段均为 64 位）：
//   +0  原生文件句柄
//   +8  调用方缓冲区地址
//   +16 缓冲区容量
//   +24 读游标或待写字节数
//   +32 读缓冲区中的有效字节数
//   +40 模式：0=关闭，1=读取，2=写入
//   +48 已交付给调用方或已接受自调用方的逻辑字节数
//   +56 EOF 标记
//
// 所有原生错误继续使用 file/ 层契约：rdx 保存正数 errno 或 Win32 错误码。
// 在尚未进入操作系统时发现的状态错误使用本模块定义的 io_stream_error_*。

const io_stream_state_handle_offset: u64 = 0
const io_stream_state_buffer_offset: u64 = 8
const io_stream_state_capacity_offset: u64 = 16
const io_stream_state_cursor_offset: u64 = 24
const io_stream_state_length_offset: u64 = 32
const io_stream_state_mode_offset: u64 = 40
const io_stream_state_position_offset: u64 = 48
const io_stream_state_eof_offset: u64 = 56
const io_stream_state_size: u64 = 64

const io_stream_mode_closed: u64 = 0
const io_stream_mode_read: u64 = 1
const io_stream_mode_write: u64 = 2

const io_stream_error_invalid_state: u64 = 0x7fff0001
const io_stream_error_invalid_buffer: u64 = 0x7fff0002
const io_stream_error_wrong_mode: u64 = 0x7fff0003
const io_stream_error_no_progress: u64 = 0x7fff0004

// 以只读模式打开缓冲流。
// 编译期参数：无。
// 运行时输入：
//   rdi = 已清零且当前关闭的 64 字节状态块
//   rsi = 平台原生零结尾路径
//   rcx = 调用方可写缓冲区
//   r8  = 缓冲区容量，范围 1..0xffffffff
// 返回：
//   成功：rax = 原生句柄，rdx = 0，状态块取得句柄所有权
//   失败：rax = -1，rdx = 原生错误码或 io_stream_error_*，状态仍关闭
// 所有权：只在成功时取得句柄；从不取得缓冲区所有权。
// ABI：保持 rbx、r12 和 rsp；破坏普通易失寄存器。
fn io_stream_open_read() {
    const invalid_state_label: string = sym.unique("__ios_or_bad_state_")
    const invalid_buffer_label: string = sym.unique("__ios_or_bad_buffer_")
    const open_failed_label: string = sym.unique("__ios_or_failed_")
    const restore_label: string = sym.unique("__ios_or_restore_")
    const end_label: string = sym.unique("__ios_or_end_")

    test rdi, rdi
    isa(sym.join("jz ", invalid_state_label));
    cmp qword [rdi + 40], 0
    isa(sym.join("jne ", invalid_state_label));

    test rcx, rcx
    isa(sym.join("jz ", invalid_buffer_label));
    test r8, r8
    isa(sym.join("jz ", invalid_buffer_label));
    mov r10, r8
    shr r10, 32
    test r10, r10
    isa(sym.join("jnz ", invalid_buffer_label));

    // 保存两个非易失寄存器，因此嵌套的 Win64 file/ 调用仍看到
    // 普通函数体所要求的 rsp % 16 == 8。
    push rbx
    push r12
    mov rbx, rdi
    mov [rbx + 8], rcx
    mov [rbx + 16], r8

    io_file_open_read();

    cmp rax, -1
    isa(sym.join("je ", open_failed_label));

    mov [rbx], rax
    mov qword [rbx + 24], 0
    mov qword [rbx + 32], 0
    mov qword [rbx + 40], 1
    mov qword [rbx + 48], 0
    mov qword [rbx + 56], 0
    isa(sym.join("jmp ", restore_label));

    label.define(open_failed_label);
    mov qword [rbx], -1
    mov qword [rbx + 24], 0
    mov qword [rbx + 32], 0
    mov qword [rbx + 40], 0
    mov qword [rbx + 48], 0
    mov qword [rbx + 56], 0

    label.define(restore_label);
    pop r12
    pop rbx
    isa(sym.join("jmp ", end_label));

    label.define(invalid_state_label);
    mov rax, -1
    mov edx, 0x7fff0001
    isa(sym.join("jmp ", end_label));

    label.define(invalid_buffer_label);
    mov rax, -1
    mov edx, 0x7fff0002

    label.define(end_label);
}

// 创建或截断文件并以写模式打开缓冲流。
// 编译期参数：无。
// 运行时输入：
//   rdi = 已清零且当前关闭的 64 字节状态块
//   rsi = 平台原生零结尾路径
//   rcx = 调用方可写缓冲区
//   r8  = 缓冲区容量，范围 1..0xffffffff
// 返回：
//   成功：rax = 原生句柄，rdx = 0，状态块取得句柄所有权
//   失败：rax = -1，rdx = 原生错误码或 io_stream_error_*，状态仍关闭
// 所有权：只在成功时取得句柄；从不取得缓冲区所有权。
// ABI：保持 rbx、r12 和 rsp；破坏普通易失寄存器。
fn io_stream_create_truncate() {
    const invalid_state_label: string = sym.unique("__ios_oc_bad_state_")
    const invalid_buffer_label: string = sym.unique("__ios_oc_bad_buffer_")
    const open_failed_label: string = sym.unique("__ios_oc_failed_")
    const restore_label: string = sym.unique("__ios_oc_restore_")
    const end_label: string = sym.unique("__ios_oc_end_")

    test rdi, rdi
    isa(sym.join("jz ", invalid_state_label));
    cmp qword [rdi + 40], 0
    isa(sym.join("jne ", invalid_state_label));
    test rcx, rcx
    isa(sym.join("jz ", invalid_buffer_label));
    test r8, r8
    isa(sym.join("jz ", invalid_buffer_label));
    mov r10, r8
    shr r10, 32
    test r10, r10
    isa(sym.join("jnz ", invalid_buffer_label));

    push rbx
    push r12
    mov rbx, rdi
    mov [rbx + 8], rcx
    mov [rbx + 16], r8

    io_file_create_truncate();

    cmp rax, -1
    isa(sym.join("je ", open_failed_label));
    mov [rbx], rax
    mov qword [rbx + 24], 0
    mov qword [rbx + 32], 0
    mov qword [rbx + 40], 2
    mov qword [rbx + 48], 0
    mov qword [rbx + 56], 0
    isa(sym.join("jmp ", restore_label));

    label.define(open_failed_label);
    mov qword [rbx], -1
    mov qword [rbx + 24], 0
    mov qword [rbx + 32], 0
    mov qword [rbx + 40], 0
    mov qword [rbx + 48], 0
    mov qword [rbx + 56], 0

    label.define(restore_label);
    pop r12
    pop rbx
    isa(sym.join("jmp ", end_label));

    label.define(invalid_state_label);
    mov rax, -1
    mov edx, 0x7fff0001
    isa(sym.join("jmp ", end_label));

    label.define(invalid_buffer_label);
    mov rax, -1
    mov edx, 0x7fff0002

    label.define(end_label);
}

// 创建文件或以追加模式打开现有文件，并建立写缓冲流。
// 编译期参数：无。
// 运行时输入：
//   rdi = 已清零且当前关闭的 64 字节状态块
//   rsi = 平台原生零结尾路径
//   rcx = 调用方可写缓冲区
//   r8  = 缓冲区容量，范围 1..0xffffffff
// 返回：
//   成功：rax = 原生句柄，rdx = 0，状态块取得句柄所有权
//   失败：rax = -1，rdx = 原生错误码或 io_stream_error_*，状态仍关闭
// 所有权：只在成功时取得句柄；从不取得缓冲区所有权。
// ABI：保持 rbx、r12 和 rsp；破坏普通易失寄存器。
fn io_stream_open_append() {
    const invalid_state_label: string = sym.unique("__ios_oa_bad_state_")
    const invalid_buffer_label: string = sym.unique("__ios_oa_bad_buffer_")
    const open_failed_label: string = sym.unique("__ios_oa_failed_")
    const restore_label: string = sym.unique("__ios_oa_restore_")
    const end_label: string = sym.unique("__ios_oa_end_")

    test rdi, rdi
    isa(sym.join("jz ", invalid_state_label));
    cmp qword [rdi + 40], 0
    isa(sym.join("jne ", invalid_state_label));
    test rcx, rcx
    isa(sym.join("jz ", invalid_buffer_label));
    test r8, r8
    isa(sym.join("jz ", invalid_buffer_label));
    mov r10, r8
    shr r10, 32
    test r10, r10
    isa(sym.join("jnz ", invalid_buffer_label));

    push rbx
    push r12
    mov rbx, rdi
    mov [rbx + 8], rcx
    mov [rbx + 16], r8

    io_file_open_append();

    cmp rax, -1
    isa(sym.join("je ", open_failed_label));
    mov [rbx], rax
    mov qword [rbx + 24], 0
    mov qword [rbx + 32], 0
    mov qword [rbx + 40], 2
    mov qword [rbx + 48], 0
    mov qword [rbx + 56], 0
    isa(sym.join("jmp ", restore_label));

    label.define(open_failed_label);
    mov qword [rbx], -1
    mov qword [rbx + 24], 0
    mov qword [rbx + 32], 0
    mov qword [rbx + 40], 0
    mov qword [rbx + 48], 0
    mov qword [rbx + 56], 0

    label.define(restore_label);
    pop r12
    pop rbx
    isa(sym.join("jmp ", end_label));

    label.define(invalid_state_label);
    mov rax, -1
    mov edx, 0x7fff0001
    isa(sym.join("jmp ", end_label));

    label.define(invalid_buffer_label);
    mov rax, -1
    mov edx, 0x7fff0002

    label.define(end_label);
}

// 把写流当前缓冲的全部字节提交给 file/ 层，自动处理短写。
// 编译期参数：无。
// 运行时输入：rdi = 写模式状态块。
// 返回：
//   成功：rax = 本次实际刷新的字节数，rdx = 0
//   失败：rax = -1，rdx = 原生错误码或 io_stream_error_no_progress
// 失败保留：尚未写出的字节会被压回缓冲区起始位置，可再次尝试刷新。
// 所有权：不关闭句柄，不改变缓冲区所有权。
// ABI：保持 rbx、rsi、rdi、r12-r14 和 rsp；破坏易失寄存器。
fn io_stream_flush() {
    const loop_label: string = sym.unique("__io_stream_flush_loop_")
    const empty_label: string = sym.unique("__io_stream_flush_empty_")
    const error_label: string = sym.unique("__io_stream_flush_error_")
    const no_progress_label: string = sym.unique("__io_stream_flush_no_progress_")
    const compact_label: string = sym.unique("__io_stream_flush_compact_")
    const compact_copy_label: string = sym.unique("__io_stream_flush_compact_copy_")
    const error_result_label: string = sym.unique("__io_stream_flush_error_result_")
    const wrong_mode_label: string = sym.unique("__io_stream_flush_wrong_mode_")
    const restore_label: string = sym.unique("__io_stream_flush_restore_")

    // 六次压栈保持 Win64 调用前的原始 16 字节对齐关系。
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14

    mov rbx, rdi
    cmp qword [rbx + 40], 2
    isa(sym.join("jne ", wrong_mode_label));

    mov r13, [rbx + 24]
    test r13, r13
    isa(sym.join("jz ", empty_label));
    mov r12, [rbx + 8]
    xor r14d, r14d

    label.define(loop_label);
    mov rdi, [rbx]
    mov rsi, r12
    mov rdx, r13
    io_file_write();
    cmp rax, -1
    isa(sym.join("je ", error_label));
    test rax, rax
    isa(sym.join("jz ", no_progress_label));

    add r12, rax
    sub r13, rax
    add r14, rax
    test r13, r13
    isa(sym.join("jnz ", loop_label));

    mov qword [rbx + 24], 0
    mov rax, r14
    xor edx, edx
    isa(sym.join("jmp ", restore_label));

    label.define(error_label);
    mov r11, rdx
    isa(sym.join("jmp ", compact_label));

    label.define(no_progress_label);
    mov r11d, 0x7fff0004

    label.define(compact_label);
    test r14, r14
    isa(sym.join("jz ", error_result_label));
    mov rsi, r12
    mov rdi, [rbx + 8]
    mov rcx, r13
    // 当前 x86 后端尚不接受 REP MOVSB，因此使用等价的显式字节循环。
    label.define(compact_copy_label);
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rcx
    isa(sym.join("jnz ", compact_copy_label));
    mov [rbx + 24], r13

    label.define(error_result_label);
    mov rax, -1
    mov rdx, r11
    isa(sym.join("jmp ", restore_label));

    label.define(empty_label);
    xor eax, eax
    xor edx, edx
    isa(sym.join("jmp ", restore_label));

    label.define(wrong_mode_label);
    mov rax, -1
    mov edx, 0x7fff0003

    label.define(restore_label);
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
}

// 向写流缓冲区接受一个字节；缓冲区满时先自动刷新。
// 编译期参数：无。
// 运行时输入：rdi = 写模式状态块，al = 待写字节。
// 返回：成功 rax=1、rdx=0；失败 rax=-1、rdx=原生或流错误码。
// 所有权：成功只表示字节已被流接受；持久化由 flush/close 完成。
// ABI：保持 rbx、rdi、r12-r13 和 rsp；破坏普通易失寄存器。
fn io_stream_write_byte() {
    const store_label: string = sym.unique("__io_stream_write_byte_store_")
    const wrong_mode_label: string = sym.unique("__io_stream_write_byte_wrong_mode_")
    const restore_label: string = sym.unique("__io_stream_write_byte_restore_")

    push rbx
    push rdi
    push r12
    push r13

    mov rbx, rdi
    mov r12b, al
    cmp qword [rbx + 40], 2
    isa(sym.join("jne ", wrong_mode_label));

    mov rcx, [rbx + 24]
    cmp rcx, [rbx + 16]
    isa(sym.join("jb ", store_label));

    mov rdi, rbx
    io_stream_flush();
    test rdx, rdx
    isa(sym.join("jnz ", restore_label));
    mov rcx, [rbx + 24]

    label.define(store_label);
    mov r10, [rbx + 8]
    mov byte [r10 + rcx], r12b
    inc rcx
    mov [rbx + 24], rcx
    add qword [rbx + 48], 1
    mov eax, 1
    xor edx, edx
    isa(sym.join("jmp ", restore_label));

    label.define(wrong_mode_label);
    mov rax, -1
    mov edx, 0x7fff0003

    label.define(restore_label);
    pop r13
    pop r12
    pop rdi
    pop rbx
}

// 把调用方字节序列完整接受到写流；缓冲区满时反复自动刷新。
// 编译期参数：无。
// 运行时输入：rdi=写模式状态块，rsi=源地址，rdx=请求字节数。
// 返回：
//   成功：rax = 请求字节数，rdx = 0
//   刷新失败：rax = 失败前已经被流接受的字节数，rdx = 错误码
//   模式错误：rax = -1，rdx = io_stream_error_wrong_mode
// 所有权：源缓冲区仍归调用方；已接受字节可能仍停留在流缓冲区。
// ABI：保持 rbx、rbp、rsi、rdi、r12-r15 和 rsp；破坏易失寄存器。
fn io_stream_write() {
    const loop_label: string = sym.unique("__io_stream_write_loop_")
    const copy_label: string = sym.unique("__io_stream_write_copy_")
    const copy_loop_label: string = sym.unique("__io_stream_write_copy_loop_")
    const chunk_ready_label: string = sym.unique("__io_stream_write_chunk_ready_")
    const success_label: string = sym.unique("__io_stream_write_success_")
    const flush_error_label: string = sym.unique("__io_stream_write_flush_error_")
    const wrong_mode_label: string = sym.unique("__io_stream_write_wrong_mode_")
    const restore_label: string = sym.unique("__io_stream_write_restore_")

    // 八次压栈同时保存所有 Win64 非易失寄存器并维持调用对齐。
    push rbx
    push rbp
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    xor r14d, r14d

    cmp qword [rbx + 40], 2
    isa(sym.join("jne ", wrong_mode_label));

    label.define(loop_label);
    test r13, r13
    isa(sym.join("jz ", success_label));

    mov rcx, [rbx + 24]
    mov r15, [rbx + 16]
    sub r15, rcx
    test r15, r15
    isa(sym.join("jnz ", copy_label));

    mov rdi, rbx
    io_stream_flush();
    test rdx, rdx
    isa(sym.join("jnz ", flush_error_label));
    isa(sym.join("jmp ", loop_label));

    label.define(copy_label);
    cmp r15, r13
    isa(sym.join("jbe ", chunk_ready_label));
    mov r15, r13

    label.define(chunk_ready_label);
    mov rdi, [rbx + 8]
    add rdi, rcx
    mov rsi, r12
    mov rcx, r15
    // 当前 x86 后端尚不接受 REP MOVSB，因此使用等价的显式字节循环。
    label.define(copy_loop_label);
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rcx
    isa(sym.join("jnz ", copy_loop_label));

    add [rbx + 24], r15
    add [rbx + 48], r15
    add r12, r15
    sub r13, r15
    add r14, r15
    isa(sym.join("jmp ", loop_label));

    label.define(success_label);
    mov rax, r14
    xor edx, edx
    isa(sym.join("jmp ", restore_label));

    label.define(flush_error_label);
    mov rax, r14
    isa(sym.join("jmp ", restore_label));

    label.define(wrong_mode_label);
    mov rax, -1
    mov edx, 0x7fff0003

    label.define(restore_label);
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbp
    pop rbx
}

// 从读流复制最多 rdx 字节到调用方缓冲区，内部缓冲耗尽时自动补充。
// 编译期参数：无。
// 运行时输入：rdi=读模式状态块，rsi=可写目标地址，rdx=请求字节数。
// 返回：
//   成功或 EOF：rax = 实际复制字节数（可小于请求值），rdx = 0
//   原生错误：rax = 错误前已复制字节数，rdx = 正数原生错误码
//   模式错误：rax = -1，rdx = io_stream_error_wrong_mode
// 零长度：不访问目标地址，返回 rax=0、rdx=0。
// 所有权：目标缓冲区和内部缓冲区都始终归调用方。
// ABI：保持 rbx、rbp、rsi、rdi、r12-r15 和 rsp；破坏易失寄存器。
fn io_stream_read() {
    const loop_label: string = sym.unique("__ios_read_loop_")
    const copy_label: string = sym.unique("__ios_read_copy_")
    const copy_loop_label: string = sym.unique("__ios_read_copy_loop_")
    const chunk_ready_label: string = sym.unique("__ios_read_chunk_ready_")
    const mark_eof_label: string = sym.unique("__ios_read_mark_eof_")
    const native_error_label: string = sym.unique("__ios_read_native_error_")
    const success_label: string = sym.unique("__ios_read_success_")
    const wrong_mode_label: string = sym.unique("__ios_read_wrong_mode_")
    const restore_label: string = sym.unique("__ios_read_restore_")

    // 八次压栈保存 Win64 非易失寄存器，并保持嵌套 ReadFile 的调用对齐。
    push rbx
    push rbp
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    xor r14d, r14d

    cmp qword [rbx + 40], 1
    isa(sym.join("jne ", wrong_mode_label));

    label.define(loop_label);
    test r13, r13
    isa(sym.join("jz ", success_label));

    mov rcx, [rbx + 24]
    mov r15, [rbx + 32]
    sub r15, rcx
    test r15, r15
    isa(sym.join("jnz ", copy_label));

    cmp qword [rbx + 56], 0
    isa(sym.join("jne ", success_label));
    mov rdi, [rbx]
    mov rsi, [rbx + 8]
    mov rdx, [rbx + 16]
    io_file_read();
    cmp rax, -1
    isa(sym.join("je ", native_error_label));
    test rax, rax
    isa(sym.join("jz ", mark_eof_label));

    mov [rbx + 32], rax
    mov qword [rbx + 24], 0
    mov qword [rbx + 56], 0
    isa(sym.join("jmp ", loop_label));

    label.define(copy_label);
    cmp r15, r13
    isa(sym.join("jbe ", chunk_ready_label));
    mov r15, r13

    label.define(chunk_ready_label);
    mov rsi, [rbx + 8]
    add rsi, rcx
    mov rdi, r12
    mov rcx, r15
    // 当前 x86 后端尚不接受 REP MOVSB，使用等价的显式字节循环。
    label.define(copy_loop_label);
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rcx
    isa(sym.join("jnz ", copy_loop_label));

    add [rbx + 24], r15
    add [rbx + 48], r15
    add r12, r15
    sub r13, r15
    add r14, r15
    isa(sym.join("jmp ", loop_label));

    label.define(mark_eof_label);
    mov qword [rbx + 24], 0
    mov qword [rbx + 32], 0
    mov qword [rbx + 56], 1
    isa(sym.join("jmp ", success_label));

    label.define(native_error_label);
    mov rax, r14
    isa(sym.join("jmp ", restore_label));

    label.define(success_label);
    mov rax, r14
    xor edx, edx
    isa(sym.join("jmp ", restore_label));

    label.define(wrong_mode_label);
    mov rax, -1
    mov edx, 0x7fff0003

    label.define(restore_label);
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbp
    pop rbx
}

// 从读流取得一个字节；读缓冲耗尽时自动从 file/ 层补充一次。
// 编译期参数：无。
// 运行时输入：rdi = 读模式状态块。
// 返回：
//   成功：rax = 0..255 的字节值，rdx = 0
//   EOF： rax = -1，rdx = 0
//   失败：rax = -1，rdx = 原生错误码或 io_stream_error_wrong_mode
// 所有权：不关闭句柄；读取位置和 EOF 状态写回状态块。
// ABI：保持 rbx、rsi、rdi、r12 和 rsp；破坏普通易失寄存器。
fn io_stream_read_byte() {
    const available_label: string = sym.unique("__io_stream_read_byte_available_")
    const have_byte_label: string = sym.unique("__io_stream_read_byte_have_")
    const eof_label: string = sym.unique("__io_stream_read_byte_eof_")
    const native_error_label: string = sym.unique("__io_stream_read_byte_native_error_")
    const wrong_mode_label: string = sym.unique("__io_stream_read_byte_wrong_mode_")
    const restore_label: string = sym.unique("__io_stream_read_byte_restore_")

    push rbx
    push rsi
    push rdi
    push r12

    mov rbx, rdi
    cmp qword [rbx + 40], 1
    isa(sym.join("jne ", wrong_mode_label));

    label.define(available_label);
    mov rcx, [rbx + 24]
    cmp rcx, [rbx + 32]
    isa(sym.join("jb ", have_byte_label));
    cmp qword [rbx + 56], 0
    isa(sym.join("jne ", eof_label));

    mov rdi, [rbx]
    mov rsi, [rbx + 8]
    mov rdx, [rbx + 16]
    io_file_read();
    cmp rax, -1
    isa(sym.join("je ", native_error_label));
    test rax, rax
    isa(sym.join("jz ", eof_label));

    mov [rbx + 32], rax
    mov qword [rbx + 24], 0
    mov qword [rbx + 56], 0
    isa(sym.join("jmp ", available_label));

    label.define(have_byte_label);
    mov r10, [rbx + 8]
    movzx eax, byte [r10 + rcx]
    inc rcx
    mov [rbx + 24], rcx
    add qword [rbx + 48], 1
    xor edx, edx
    isa(sym.join("jmp ", restore_label));

    label.define(eof_label);
    mov qword [rbx + 24], 0
    mov qword [rbx + 32], 0
    mov qword [rbx + 56], 1
    mov rax, -1
    xor edx, edx
    isa(sym.join("jmp ", restore_label));

    label.define(native_error_label);
    isa(sym.join("jmp ", restore_label));

    label.define(wrong_mode_label);
    mov rax, -1
    mov edx, 0x7fff0003

    label.define(restore_label);
    pop r12
    pop rdi
    pop rsi
    pop rbx
}

// 关闭流并消费状态块当前拥有的原生句柄。
// 编译期参数：无。
// 运行时输入：rdi = 已打开的读流或写流状态块。
// 返回：
//   成功：rax = 0，rdx = 0
//   失败：rax = -1，rdx = 首个刷新或关闭错误
// 写流行为：先刷新，再无条件尝试关闭；刷新失败时仍消费句柄所有权。
// 缓冲区：从不释放，关闭后仍归调用方；未能刷新的数据可能丢失。
// ABI：保持 rbx、rdi、r12-r13 和 rsp；破坏普通易失寄存器。
fn io_stream_close() {
    const skip_flush_label: string = sym.unique("__io_stream_close_skip_flush_")
    const keep_first_error_label: string = sym.unique("__io_stream_close_keep_first_error_")
    const closed_label: string = sym.unique("__io_stream_close_closed_")
    const success_label: string = sym.unique("__io_stream_close_success_")
    const wrong_state_label: string = sym.unique("__io_stream_close_wrong_state_")
    const restore_label: string = sym.unique("__io_stream_close_restore_")

    push rbx
    push rdi
    push r12
    push r13

    mov rbx, rdi
    xor r12d, r12d
    mov r13, [rbx + 40]
    cmp r13, 1
    isa(sym.join("je ", skip_flush_label));
    cmp r13, 2
    isa(sym.join("jne ", wrong_state_label));

    mov rdi, rbx
    io_stream_flush();
    test rdx, rdx
    isa(sym.join("jz ", skip_flush_label));
    mov r12, rdx

    label.define(skip_flush_label);
    mov rdi, [rbx]
    io_file_close();
    test rdx, rdx
    isa(sym.join("jz ", closed_label));
    test r12, r12
    isa(sym.join("jnz ", keep_first_error_label));
    mov r12, rdx

    label.define(keep_first_error_label);
    label.define(closed_label);
    mov qword [rbx], -1
    mov qword [rbx + 24], 0
    mov qword [rbx + 32], 0
    mov qword [rbx + 40], 0
    mov qword [rbx + 48], 0
    mov qword [rbx + 56], 0

    test r12, r12
    isa(sym.join("jz ", success_label));
    mov rax, -1
    mov rdx, r12
    isa(sym.join("jmp ", restore_label));

    label.define(success_label);
    xor eax, eax
    xor edx, edx
    isa(sym.join("jmp ", restore_label));

    label.define(wrong_state_label);
    mov rax, -1
    mov edx, 0x7fff0001

    label.define(restore_label);
    pop r13
    pop r12
    pop rdi
    pop rbx
}

// 用编译期标签建立只读流。
// 编译期参数：
//   state_label  = 64 字节清零状态块标签
//   path_label   = 平台原生零结尾路径标签
//   buffer_label = 调用方可写缓冲区标签
//   capacity     = 编译期缓冲区容量，范围 1..0xffffffff
// 运行时输入寄存器：调用点无需预置；本函数生成 rdi/rsi/rcx/r8 后转交。
// 返回、错误、句柄与缓冲区所有权、保留/破坏寄存器及栈要求：
//   与 io_stream_open_read 相同。
fn io_stream_open_read_label(state_label: string, path_label: string, buffer_label: string, capacity: u64) {
    assert(len(state_label) > 0, "stream state label is empty");
    assert(len(path_label) > 0, "stream path label is empty");
    assert(len(buffer_label) > 0, "stream buffer label is empty");
    assert(capacity > 0, "stream buffer capacity must be positive");
    assert(capacity <= io_max_transfer_size, "stream buffer capacity exceeds the portable limit");

    isa(sym.join("lea rdi, [rel ", state_label, "]"));
    isa(sym.join("lea rsi, [rel ", path_label, "]"));
    isa(sym.join("lea rcx, [rel ", buffer_label, "]"));
    isa(sym.join("mov r8, ", to_string(capacity)));
    io_stream_open_read();
}

// 用编译期标签创建或截断文件并建立写流。
// 编译期参数：state_label=状态块，path_label=原生路径，
//             buffer_label=调用方缓冲区，capacity=1..0xffffffff。
// 运行时输入寄存器：调用点无需预置；本函数生成 rdi/rsi/rcx/r8 后转交。
// 返回、错误、句柄与缓冲区所有权、保留/破坏寄存器及栈要求：
//   与 io_stream_create_truncate 相同。
fn io_stream_create_truncate_label(state_label: string, path_label: string, buffer_label: string, capacity: u64) {
    assert(len(state_label) > 0, "stream state label is empty");
    assert(len(path_label) > 0, "stream path label is empty");
    assert(len(buffer_label) > 0, "stream buffer label is empty");
    assert(capacity > 0, "stream buffer capacity must be positive");
    assert(capacity <= io_max_transfer_size, "stream buffer capacity exceeds the portable limit");

    isa(sym.join("lea rdi, [rel ", state_label, "]"));
    isa(sym.join("lea rsi, [rel ", path_label, "]"));
    isa(sym.join("lea rcx, [rel ", buffer_label, "]"));
    isa(sym.join("mov r8, ", to_string(capacity)));
    io_stream_create_truncate();
}

// 用编译期标签以追加方式打开文件并建立写流。
// 编译期参数：state_label=状态块，path_label=原生路径，
//             buffer_label=调用方缓冲区，capacity=1..0xffffffff。
// 运行时输入寄存器：调用点无需预置；本函数生成 rdi/rsi/rcx/r8 后转交。
// 返回、错误、句柄与缓冲区所有权、保留/破坏寄存器及栈要求：
//   与 io_stream_open_append 相同。
fn io_stream_open_append_label(state_label: string, path_label: string, buffer_label: string, capacity: u64) {
    assert(len(state_label) > 0, "stream state label is empty");
    assert(len(path_label) > 0, "stream path label is empty");
    assert(len(buffer_label) > 0, "stream buffer label is empty");
    assert(capacity > 0, "stream buffer capacity must be positive");
    assert(capacity <= io_max_transfer_size, "stream buffer capacity exceeds the portable limit");

    isa(sym.join("lea rdi, [rel ", state_label, "]"));
    isa(sym.join("lea rsi, [rel ", path_label, "]"));
    isa(sym.join("lea rcx, [rel ", buffer_label, "]"));
    isa(sym.join("mov r8, ", to_string(capacity)));
    io_stream_open_append();
}

// 用编译期标签把一段数据交给写流。
// 编译期参数：state_label=状态块，data_label=源数据，length=请求字节数。
// 运行时输入寄存器：调用点无需预置；本函数生成 rdi/rsi/rdx 后转交。
// 返回：成功 rax=length、rdx=0；失败 rax=已接受字节数或 -1、
//       rdx=原生错误码或 io_stream_error_wrong_mode。
// 所有权：源数据和流缓冲区都仍归调用方。
// ABI：保留/破坏寄存器及栈要求与 io_stream_write 相同。
fn io_stream_write_label(state_label: string, data_label: string, length: u64) {
    assert(len(state_label) > 0, "stream state label is empty");
    assert(len(data_label) > 0, "stream data label is empty");

    isa(sym.join("lea rdi, [rel ", state_label, "]"));
    isa(sym.join("lea rsi, [rel ", data_label, "]"));
    isa(sym.join("mov rdx, ", to_string(length)));
    io_stream_write();
}

// 用编译期标签从读流复制一段数据。
// 编译期参数：state_label=读流状态块，buffer_label=可写目标，
//             length=请求字节数。
// 运行时输入寄存器：调用点无需预置；本函数生成 rdi/rsi/rdx 后转交。
// 返回：成功/EOF 时 rax=实际字节数、rdx=0；
//       原生错误时 rax=错误前已复制字节数、rdx=错误码。
//       模式错误时 rax=-1、rdx=io_stream_error_wrong_mode。
// 所有权、保留/破坏寄存器及栈要求：与 io_stream_read 相同。
fn io_stream_read_label(state_label: string, buffer_label: string, length: u64) {
    assert(len(state_label) > 0, "stream state label is empty");
    assert(len(buffer_label) > 0, "stream read buffer label is empty");

    isa(sym.join("lea rdi, [rel ", state_label, "]"));
    isa(sym.join("lea rsi, [rel ", buffer_label, "]"));
    isa(sym.join("mov rdx, ", to_string(length)));
    io_stream_read();
}

// 用编译期标签刷新写流。
// 编译期参数：state_label = 已打开的写流状态块。
// 运行时输入寄存器：调用点无需预置；本函数生成 rdi 后转交。
// 返回、错误、所有权、保留/破坏寄存器及栈要求：与 io_stream_flush 相同。
fn io_stream_flush_label(state_label: string) {
    assert(len(state_label) > 0, "stream state label is empty");
    isa(sym.join("lea rdi, [rel ", state_label, "]"));
    io_stream_flush();
}

// 用编译期标签关闭流。
// 编译期参数：state_label = 已打开的读流或写流状态块。
// 运行时输入寄存器：调用点无需预置；本函数生成 rdi 后转交。
// 返回、错误、句柄消费、缓冲区所有权、保留/破坏寄存器及栈要求：
//   与 io_stream_close 相同。
fn io_stream_close_label(state_label: string) {
    assert(len(state_label) > 0, "stream state label is empty");
    isa(sym.join("lea rdi, [rel ", state_label, "]"));
    io_stream_close();
}

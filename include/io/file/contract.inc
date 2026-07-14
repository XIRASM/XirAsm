// 跨平台、无隐藏全局文件状态的文件 IO 公共契约。
//
// 路径使用平台原生的零结尾字符串：
//   Linux x86-64：字节字符串
//   Windows x64：UTF-16LE 字符串（CreateFileW）
//
// 打开类操作：
//   输入：rsi = 平台原生路径指针
//   成功：rax = 平台原生句柄，rdx = 0
//   失败：rax = -1，rdx = 平台原生正数错误码
//
// 句柄类操作：
//   输入：rdi = 平台原生句柄
//
// 读写操作附加输入：
//   rsi = 缓冲区指针
//   rdx = 请求字节数，最大为 io_max_transfer_size
//
// 定位操作附加输入：
//   rsi    = 有符号 64 位位移
//   origin = 编译期 io_file_seek_* 常量
//
// 句柄所有权属于调用方；成功打开后必须调用 io_file_close()。
// io_file_close() 一经调用就消费该所有权，无论返回成功还是失败。
// 特别是 Linux close(2) 返回 EINTR 后不要重试，以免误关已经复用的 fd。

const io_file_seek_begin: u64 = 0
const io_file_seek_current: u64 = 1
const io_file_seek_end: u64 = 2

const io_file_error_invalid_buffer: u64 = 0x7fff1001
const io_file_error_buffer_too_small: u64 = 0x7fff1002
const io_file_error_no_progress: u64 = 0x7fff1003

// 使用编译期标签调用 io_file_open_read。
// 编译期参数：path_label = 平台原生零结尾路径的标签名。
// 运行时输入寄存器：调用点无需预置；本函数生成 rsi 后转交。
// 返回：与 io_file_open_read 相同。
// 错误：标签为空在汇编期诊断；运行时错误由平台实现返回。
// 所有权：不取得路径字符串所有权；成功返回的句柄归调用方。
// ABI：保留/破坏寄存器及栈要求与 io_file_open_read 相同。
fn io_file_open_read_label(path_label: string) {
    assert(len(path_label) > 0, "file path label is empty");
    isa(sym.join("lea rsi, [rel ", path_label, "]"));
    io_file_open_read();
}

// 使用编译期标签创建或截断文件。
// 编译期参数：path_label = 平台原生零结尾路径的标签名。
// 运行时输入寄存器：调用点无需预置；本函数生成 rsi 后转交。
// 返回：与 io_file_create_truncate 相同。
// 错误：标签为空在汇编期诊断；运行时错误由平台实现返回。
// 所有权：不取得路径字符串所有权；成功返回的句柄归调用方。
// ABI：保留/破坏寄存器及栈要求与 io_file_create_truncate 相同。
fn io_file_create_truncate_label(path_label: string) {
    assert(len(path_label) > 0, "file path label is empty");
    isa(sym.join("lea rsi, [rel ", path_label, "]"));
    io_file_create_truncate();
}

// 使用编译期标签创建文件或以追加模式打开现有文件。
// 编译期参数：path_label = 平台原生零结尾路径的标签名。
// 运行时输入寄存器：调用点无需预置；本函数生成 rsi 后转交。
// 返回：与 io_file_open_append 相同。
// 错误：标签为空在汇编期诊断；运行时错误由平台实现返回。
// 所有权：不取得路径字符串所有权；成功返回的句柄归调用方。
// ABI：保留/破坏寄存器及栈要求与 io_file_open_append 相同。
fn io_file_open_append_label(path_label: string) {
    assert(len(path_label) > 0, "file path label is empty");
    isa(sym.join("lea rsi, [rel ", path_label, "]"));
    io_file_open_append();
}

// 从 rdi 句柄读取到编译期指定的缓冲区标签。
// 编译期参数：
//   buffer_label = 可写缓冲区标签名
//   length       = 编译期请求字节数
// 运行时输入：rdi = 平台原生句柄；本函数生成 rsi/rdx 后转交。
// 返回：rax = 实际读取字节数或 -1；rdx = 0 或平台错误码
// 错误：标签为空或长度过大在汇编期诊断；运行时错误由平台实现返回。
// 所有权：不取得句柄或缓冲区所有权；短读属于成功。
// ABI：保留/破坏寄存器及栈要求与 io_file_read 相同。
fn io_file_read_label(buffer_label: string, length: u64) {
    assert(len(buffer_label) > 0, "file read buffer label is empty");
    assert(length <= io_max_transfer_size, "file read byte count exceeds the portable limit");

    isa(sym.join("lea rsi, [rel ", buffer_label, "]"));
    mov rdx, length
    io_file_read();
}

// 从编译期指定的缓冲区标签写入 rdi 句柄。
// 编译期参数：
//   buffer_label = 源缓冲区标签名
//   length       = 编译期请求字节数
// 运行时输入：rdi = 平台原生句柄；本函数生成 rsi/rdx 后转交。
// 返回：rax = 实际写入字节数或 -1；rdx = 0 或平台错误码
// 错误：标签为空或长度过大在汇编期诊断；运行时错误由平台实现返回。
// 所有权：不取得句柄或缓冲区所有权；短写属于成功。
// ABI：保留/破坏寄存器及栈要求与 io_file_write 相同。
fn io_file_write_label(buffer_label: string, length: u64) {
    assert(len(buffer_label) > 0, "file write buffer label is empty");
    assert(length <= io_max_transfer_size, "file write byte count exceeds the portable limit");

    isa(sym.join("lea rsi, [rel ", buffer_label, "]"));
    mov rdx, length
    io_file_write();
}

// 把 rdi 句柄的位置重置到文件开头。
// 编译期参数：无。
// 运行时输入：rdi = 句柄。
// 返回：成功时 rax = 0、rdx = 0；失败时 rax = -1、rdx = 错误码
// 错误：由 io_file_seek 返回平台错误码。
// 所有权：不取得、不关闭句柄。
// ABI：保留/破坏寄存器及栈要求与 io_file_seek 相同。
fn io_file_rewind() {
    mov rsi, 0
    io_file_seek(io_file_seek_begin);
}

// 把一个完整文件读入调用方提供的缓冲区。
// 编译期参数：无。
// 运行时输入：
//   rsi = 平台原生零结尾路径
//   rdi = 调用方可写缓冲区；只有 rcx=0 时才允许为 0
//   rcx = 缓冲区容量，最大 io_max_transfer_size
// 返回：
//   成功：rax = 文件大小/实际读取字节数，rdx = 0
//   失败：rax = -1，rdx = 原生错误码或 io_file_error_*。
// 行为：先打开文件并读取文件大小；若容量不足则关闭句柄后返回
//       io_file_error_buffer_too_small；读完或失败后总是尝试关闭句柄。
// 所有权：不取得缓冲区所有权；打开成功后的句柄在本函数内消费。
// ABI：保持 rbx、rbp、r12-r15、rsi、rdi 和 rsp；额外保存 rbp 是为了让
//      Windows x64 嵌套 API 调用前仍保持 16 字节栈对齐；内部调用 file/ 层，
//      破坏易失寄存器。
fn io_file_load() {
    const invalid_buffer_label: string = sym.unique("__io_file_load_bad_buffer_")
    const open_failed_label: string = sym.unique("__io_file_load_open_failed_")
    const size_failed_label: string = sym.unique("__io_file_load_size_failed_")
    const too_small_label: string = sym.unique("__io_file_load_too_small_")
    const empty_label: string = sym.unique("__io_file_load_empty_")
    const loop_label: string = sym.unique("__io_file_load_loop_")
    const read_error_label: string = sym.unique("__io_file_load_read_error_")
    const no_progress_label: string = sym.unique("__io_file_load_no_progress_")
    const close_label: string = sym.unique("__io_file_load_close_")
    const keep_close_error_label: string = sym.unique("__io_file_load_keep_close_")
    const success_label: string = sym.unique("__io_file_load_success_")
    const restore_label: string = sym.unique("__io_file_load_restore_")
    const end_label: string = sym.unique("__io_file_load_end_")

    test rdi, rdi
    isa(sym.join("jnz ", open_failed_label, "_entry_ok"));
    test rcx, rcx
    isa(sym.join("jnz ", invalid_buffer_label));

    label.define(sym.join(open_failed_label, "_entry_ok"));
    mov r10, rcx
    shr r10, 32
    test r10, r10
    isa(sym.join("jnz ", invalid_buffer_label));

    push rbx
    push r12
    push r13
    push r14
    push r15
    push rsi
    push rdi
    push rbp
    mov r12, rdi
    mov r13, rcx
    xor r14d, r14d
    xor r15d, r15d
    xor ebp, ebp

    io_file_open_read();
    cmp rax, -1
    isa(sym.join("je ", open_failed_label));
    mov rbx, rax

    mov rdi, rbx
    io_file_size();
    cmp rax, -1
    isa(sym.join("je ", size_failed_label));
    mov r14, rax
    cmp r14, r13
    isa(sym.join("ja ", too_small_label));
    test r14, r14
    isa(sym.join("jz ", empty_label));

    xor r15d, r15d

    label.define(loop_label);
    mov rdx, r14
    sub rdx, r15
    test rdx, rdx
    isa(sym.join("jz ", close_label));
    mov rdi, rbx
    mov rsi, r12
    add rsi, r15
    io_file_read();
    cmp rax, -1
    isa(sym.join("je ", read_error_label));
    test rax, rax
    isa(sym.join("jz ", no_progress_label));
    add r15, rax
    isa(sym.join("jmp ", loop_label));

    label.define(empty_label);
    xor r15d, r15d
    isa(sym.join("jmp ", close_label));

    label.define(size_failed_label);
    mov rbp, rdx
    isa(sym.join("jmp ", close_label));

    label.define(too_small_label);
    mov rbp, io_file_error_buffer_too_small
    isa(sym.join("jmp ", close_label));

    label.define(read_error_label);
    mov rbp, rdx
    isa(sym.join("jmp ", close_label));

    label.define(no_progress_label);
    mov rbp, io_file_error_no_progress

    label.define(close_label);
    mov rdi, rbx
    io_file_close();
    test rdx, rdx
    isa(sym.join("jz ", keep_close_error_label));
    test rbp, rbp
    isa(sym.join("jnz ", keep_close_error_label));
    mov rbp, rdx

    label.define(keep_close_error_label);
    test rbp, rbp
    isa(sym.join("jz ", success_label));
    mov rax, -1
    mov rdx, rbp
    isa(sym.join("jmp ", restore_label));

    label.define(success_label);
    mov rax, r14
    xor edx, edx
    isa(sym.join("jmp ", restore_label));

    label.define(open_failed_label);
    isa(sym.join("jmp ", restore_label));

    label.define(restore_label);
    pop rbp
    pop rdi
    pop rsi
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    isa(sym.join("jmp ", end_label));

    label.define(invalid_buffer_label);
    mov rax, -1
    mov edx, 0x7fff1001

    label.define(end_label);
}

// 把调用方提供的一段内存完整写入新建/截断文件。
// 编译期参数：无。
// 运行时输入：
//   rsi = 平台原生零结尾路径
//   rdi = 调用方只读数据缓冲区；只有 rcx=0 时才允许为 0
//   rcx = 要写入的字节数，最大 io_max_transfer_size
// 返回：
//   成功：rax = 写入字节数，rdx = 0
//   失败：rax = -1，rdx = 原生错误码或 io_file_error_*。
// 行为：创建或截断文件，循环写完整数据，刷新，再关闭；若写入无法前进
//       返回 io_file_error_no_progress；清理时保留首个错误。
// 所有权：不取得数据缓冲区所有权；打开成功后的句柄在本函数内消费。
// ABI：保持 rbx、rbp、r12-r15、rsi、rdi 和 rsp；额外保存 rbp 是为了让
//      Windows x64 嵌套 API 调用前仍保持 16 字节栈对齐；内部调用 file/ 层，
//      破坏易失寄存器。
fn io_file_store() {
    const invalid_buffer_label: string = sym.unique("__io_file_store_bad_buffer_")
    const open_failed_label: string = sym.unique("__io_file_store_open_failed_")
    const empty_label: string = sym.unique("__io_file_store_empty_")
    const loop_label: string = sym.unique("__io_file_store_loop_")
    const write_error_label: string = sym.unique("__io_file_store_write_error_")
    const no_progress_label: string = sym.unique("__io_file_store_no_progress_")
    const flush_label: string = sym.unique("__io_file_store_flush_")
    const flush_error_label: string = sym.unique("__io_file_store_flush_error_")
    const close_label: string = sym.unique("__io_file_store_close_")
    const keep_close_error_label: string = sym.unique("__io_file_store_keep_close_")
    const success_label: string = sym.unique("__io_file_store_success_")
    const restore_label: string = sym.unique("__io_file_store_restore_")
    const end_label: string = sym.unique("__io_file_store_end_")

    test rdi, rdi
    isa(sym.join("jnz ", open_failed_label, "_entry_ok"));
    test rcx, rcx
    isa(sym.join("jnz ", invalid_buffer_label));

    label.define(sym.join(open_failed_label, "_entry_ok"));
    mov r10, rcx
    shr r10, 32
    test r10, r10
    isa(sym.join("jnz ", invalid_buffer_label));

    push rbx
    push r12
    push r13
    push r14
    push r15
    push rsi
    push rdi
    push rbp
    mov r12, rdi
    mov r13, rcx
    xor r14d, r14d
    xor r15d, r15d

    io_file_create_truncate();
    cmp rax, -1
    isa(sym.join("je ", open_failed_label));
    mov rbx, rax
    test r13, r13
    isa(sym.join("jz ", empty_label));

    label.define(loop_label);
    mov rdx, r13
    sub rdx, r14
    test rdx, rdx
    isa(sym.join("jz ", flush_label));
    mov rdi, rbx
    mov rsi, r12
    add rsi, r14
    io_file_write();
    cmp rax, -1
    isa(sym.join("je ", write_error_label));
    test rax, rax
    isa(sym.join("jz ", no_progress_label));
    add r14, rax
    isa(sym.join("jmp ", loop_label));

    label.define(empty_label);
    xor r14d, r14d

    label.define(flush_label);
    mov rdi, rbx
    io_file_flush();
    test rdx, rdx
    isa(sym.join("jz ", close_label));

    label.define(flush_error_label);
    mov r15, rdx
    isa(sym.join("jmp ", close_label));

    label.define(write_error_label);
    mov r15, rdx
    isa(sym.join("jmp ", close_label));

    label.define(no_progress_label);
    mov r15, io_file_error_no_progress

    label.define(close_label);
    mov rdi, rbx
    io_file_close();
    test rdx, rdx
    isa(sym.join("jz ", keep_close_error_label));
    test r15, r15
    isa(sym.join("jnz ", keep_close_error_label));
    mov r15, rdx

    label.define(keep_close_error_label);
    test r15, r15
    isa(sym.join("jz ", success_label));
    mov rax, -1
    mov rdx, r15
    isa(sym.join("jmp ", restore_label));

    label.define(success_label);
    mov rax, r14
    xor edx, edx
    isa(sym.join("jmp ", restore_label));

    label.define(open_failed_label);
    isa(sym.join("jmp ", restore_label));

    label.define(restore_label);
    pop rbp
    pop rdi
    pop rsi
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    isa(sym.join("jmp ", end_label));

    label.define(invalid_buffer_label);
    mov rax, -1
    mov edx, 0x7fff1001

    label.define(end_label);
}

// 用编译期标签把完整文件读入调用方缓冲区。
// 编译期参数：
//   path_label   = 平台原生零结尾路径标签
//   buffer_label = 调用方可写缓冲区标签
//   capacity     = 缓冲区容量，最大 io_max_transfer_size
// 运行时输入寄存器：调用点无需预置；本函数生成 rsi/rdi/rcx 后转交。
// 返回：与 io_file_load 相同。
// 错误、所有权、保留/破坏寄存器及栈要求：与 io_file_load 相同。
fn io_file_load_label(path_label: string, buffer_label: string, capacity: u64) {
    assert(len(path_label) > 0, "file load path label is empty");
    assert(len(buffer_label) > 0, "file load buffer label is empty");
    assert(capacity <= io_max_transfer_size, "file load capacity exceeds the portable limit");

    isa(sym.join("lea rsi, [rel ", path_label, "]"));
    isa(sym.join("lea rdi, [rel ", buffer_label, "]"));
    mov rcx, capacity
    io_file_load();
}

// 用编译期标签把一段数据完整写入新建/截断文件。
// 编译期参数：
//   path_label = 平台原生零结尾路径标签
//   data_label = 调用方只读数据标签
//   size       = 写入字节数，最大 io_max_transfer_size
// 运行时输入寄存器：调用点无需预置；本函数生成 rsi/rdi/rcx 后转交。
// 返回：与 io_file_store 相同。
// 错误、所有权、保留/破坏寄存器及栈要求：与 io_file_store 相同。
fn io_file_store_label(path_label: string, data_label: string, size: u64) {
    assert(len(path_label) > 0, "file store path label is empty");
    assert(len(data_label) > 0, "file store data label is empty");
    assert(size <= io_max_transfer_size, "file store byte count exceeds the portable limit");

    isa(sym.join("lea rsi, [rel ", path_label, "]"));
    isa(sym.join("lea rdi, [rel ", data_label, "]"));
    mov rcx, size
    io_file_store();
}

// 跨平台目录枚举公共契约。
//
// 本模块把 EASM FileEach 的“回调 + 隐藏文件对象”模型改成显式状态机：
// 调用方分配状态块，依次 open、next、close。首版不在 IO 层实现通配符
// 匹配；Windows 直接接收 FindFirstFileW pattern，Linux 接收目录路径。

const io_dir_state_size: u64 = 704

const io_dir_handle_offset: u64 = 0
const io_dir_name_ptr_offset: u64 = 8
const io_dir_name_len_offset: u64 = 16
const io_dir_kind_offset: u64 = 24
const io_dir_error_offset: u64 = 32
const io_dir_mode_offset: u64 = 40
const io_dir_cursor_offset: u64 = 48
const io_dir_buffer_used_offset: u64 = 56
const io_dir_buffer_cursor_offset: u64 = 64
const io_dir_buffer_size_offset: u64 = 72
const io_dir_buffer_offset: u64 = 80
const io_dir_buffer_size: u64 = 624

const io_dir_mode_closed: u64 = 0
const io_dir_mode_open: u64 = 1

const io_dir_kind_missing: u64 = 0
const io_dir_kind_file: u64 = 1
const io_dir_kind_directory: u64 = 2
const io_dir_kind_other: u64 = 3

const io_dir_error_invalid_state: u64 = 0x7fff2001
const io_dir_error_already_open: u64 = 0x7fff2002
const io_dir_error_not_open: u64 = 0x7fff2003
const io_dir_error_bad_record: u64 = 0x7fff2004

// 初始化调用方提供的目录枚举状态块。
// 编译期参数：无。
// 运行时输入：rdi = 至少 io_dir_state_size 字节的可写状态块。
// 返回：成功 rax=0、rdx=0；失败 rax=-1、rdx=io_dir_error_invalid_state。
// 所有权：状态块始终归调用方；本函数不分配内存、不打开系统句柄。
// ABI：保持 rdi 和 rsp；破坏 rax、rdx、rcx、r10。
fn io_dir_init() {
    const invalid_label: string = sym.unique("__iod_init_invalid_")
    const end_label: string = sym.unique("__iod_init_end_")

    test rdi, rdi
    isa(sym.join("jz ", invalid_label));
    mov qword [rdi], -1
    mov qword [rdi + 8], 0
    mov qword [rdi + 16], 0
    mov qword [rdi + 24], 0
    mov qword [rdi + 32], 0
    mov qword [rdi + 40], 0
    mov qword [rdi + 48], 0
    mov qword [rdi + 56], 0
    mov qword [rdi + 64], 0
    isa(sym.join("mov qword [rdi + 72], ", to_string(io_dir_buffer_size)));
    xor eax, eax
    xor edx, edx
    isa(sym.join("jmp ", end_label));

    label.define(invalid_label);
    mov rax, -1
    isa(sym.join("mov edx, ", to_string(io_dir_error_invalid_state)));

    label.define(end_label);
}

// 使用编译期标签初始化目录枚举状态块。
// 编译期参数：state_label = 至少 io_dir_state_size 字节的状态块标签。
// 运行时输入寄存器：调用点无需预置；本函数生成 rdi 后转交。
// 返回、错误、所有权、保留/破坏寄存器及栈要求：与 io_dir_init 相同。
fn io_dir_init_label(state_label: string) {
    assert(len(state_label) > 0, "dir state label is empty");
    isa(sym.join("lea rdi, [rel ", state_label, "]"));
    io_dir_init();
}

// 使用编译期标签打开目录或平台搜索 pattern。
// 编译期参数：
//   state_label = 已初始化的状态块标签
//   path_label  = 平台原生零结尾目录路径或搜索 pattern 标签
// 运行时输入寄存器：调用点无需预置；本函数生成 rdi/rsi 后转交。
// 返回、错误、所有权、保留/破坏寄存器及栈要求：与 io_dir_open 相同。
fn io_dir_open_label(state_label: string, path_label: string) {
    assert(len(state_label) > 0, "dir state label is empty");
    assert(len(path_label) > 0, "dir path label is empty");
    isa(sym.join("lea rdi, [rel ", state_label, "]"));
    isa(sym.join("lea rsi, [rel ", path_label, "]"));
    io_dir_open();
}

// 使用编译期标签读取下一个目录项。
// 编译期参数：state_label = 打开的目录枚举状态块标签。
// 运行时输入寄存器：调用点无需预置；本函数生成 rdi 后转交。
// 返回、错误、所有权、保留/破坏寄存器及栈要求：与 io_dir_next 相同。
fn io_dir_next_label(state_label: string) {
    assert(len(state_label) > 0, "dir state label is empty");
    isa(sym.join("lea rdi, [rel ", state_label, "]"));
    io_dir_next();
}

// 使用编译期标签关闭目录枚举状态块。
// 编译期参数：state_label = 目录枚举状态块标签。
// 运行时输入寄存器：调用点无需预置；本函数生成 rdi 后转交。
// 返回、错误、所有权、保留/破坏寄存器及栈要求：与 io_dir_close 相同。
fn io_dir_close_label(state_label: string) {
    assert(len(state_label) > 0, "dir state label is empty");
    isa(sym.join("lea rdi, [rel ", state_label, "]"));
    io_dir_close();
}

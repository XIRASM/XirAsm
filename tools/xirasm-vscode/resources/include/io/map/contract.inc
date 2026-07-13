// 跨平台 x86-64 文件内存映射公共契约。
//
// 本模块把 EASM 的 FileMapOpen/FileMapCreate 生命周期清洗成显式状态块：
// 调用方提供 48 字节清零状态，IO 层只在成功后记录原生句柄和映射视图。
// 不复制旧式隐藏文件状态，不隐藏分配，也不把普通数据映射成可执行内存。
//
// 状态块布局（全部字段均为 64 位）：
//   +0  原生文件句柄
//   +8  原生映射句柄；Windows 使用，Linux 固定为 0
//   +16 映射视图指针；空文件只读映射成功时为 0
//   +24 映射长度
//   +32 模式：0=关闭，1=只读映射，2=读写映射
//   +40 保留，当前固定为 0
//
// 所有原生失败继续使用 include/io/contract.inc 的结果契约：
//   rax = -1，rdx = 正数 errno 或 Win32 错误码。
// 在调用操作系统之前发现的状态错误使用 io_map_error_*。

const io_map_state_file_handle_offset: u64 = 0
const io_map_state_mapping_handle_offset: u64 = 8
const io_map_state_view_offset: u64 = 16
const io_map_state_length_offset: u64 = 24
const io_map_state_mode_offset: u64 = 32
const io_map_state_reserved_offset: u64 = 40
const io_map_state_size: u64 = 48

const io_map_mode_closed: u64 = 0
const io_map_mode_read: u64 = 1
const io_map_mode_write: u64 = 2

const io_map_error_invalid_state: u64 = 0x7fff2001
const io_map_error_invalid_length: u64 = 0x7fff2002

// 用编译期标签打开只读完整文件映射。
// 编译期参数：
//   state_label = 48 字节清零状态块标签
//   path_label  = 平台原生零结尾路径标签
// 运行时输入寄存器：调用点无需预置；本函数生成 rdi/rsi 后转交。
// 返回：成功 rax=视图指针，空文件为 0，rdx=0；
//       失败 rax=-1，rdx=原生错误码或 io_map_error_*。
// 所有权：成功后状态块拥有文件句柄、映射句柄和视图；调用方必须关闭。
// ABI：保留/破坏寄存器及栈要求与平台 io_map_open_read 相同。
fn io_map_open_read_label(state_label: string, path_label: string) {
    assert(len(state_label) > 0, "map state label is empty");
    assert(len(path_label) > 0, "map path label is empty");

    isa(sym.join("lea rdi, [rel ", state_label, "]"));
    isa(sym.join("lea rsi, [rel ", path_label, "]"));
    io_map_open_read();
}

// 用编译期标签创建或截断文件并建立读写完整映射。
// 编译期参数：
//   state_label = 48 字节清零状态块标签
//   path_label  = 平台原生零结尾路径标签
//   length      = 要创建并映射的字节数，必须大于 0
// 运行时输入寄存器：调用点无需预置；本函数生成 rdi/rsi/rcx 后转交。
// 返回：成功 rax=可写视图指针、rdx=0；
//       失败 rax=-1，rdx=原生错误码或 io_map_error_*。
// 所有权：成功后状态块拥有文件句柄、映射句柄和视图；调用方必须关闭。
// ABI：保留/破坏寄存器及栈要求与平台 io_map_create 相同。
fn io_map_create_label(state_label: string, path_label: string, length: u64) {
    assert(len(state_label) > 0, "map state label is empty");
    assert(len(path_label) > 0, "map path label is empty");
    assert(length > 0, "map length must be positive");

    isa(sym.join("lea rdi, [rel ", state_label, "]"));
    isa(sym.join("lea rsi, [rel ", path_label, "]"));
    isa(sym.join("mov rcx, ", to_string(length)));
    io_map_create();
}

// 用编译期标签刷新映射。
// 编译期参数：state_label = 已打开的映射状态块。
// 运行时输入寄存器：调用点无需预置；本函数生成 rdi 后转交。
// 返回：成功 rax=0、rdx=0；失败 rax=-1、rdx=错误码。
// 所有权：不关闭映射；只提交写映射中已经修改的页面。
// ABI：保留/破坏寄存器及栈要求与平台 io_map_flush 相同。
fn io_map_flush_label(state_label: string) {
    assert(len(state_label) > 0, "map state label is empty");

    isa(sym.join("lea rdi, [rel ", state_label, "]"));
    io_map_flush();
}

// 用编译期标签关闭映射并消费状态块拥有的原生资源。
// 编译期参数：state_label = 已打开的映射状态块。
// 运行时输入寄存器：调用点无需预置；本函数生成 rdi 后转交。
// 返回：成功 rax=0、rdx=0；失败 rax=-1、rdx=首个清理错误。
// 所有权：调用后状态块不再拥有视图、映射句柄或文件句柄。
// ABI：保留/破坏寄存器及栈要求与平台 io_map_close 相同。
fn io_map_close_label(state_label: string) {
    assert(len(state_label) > 0, "map state label is empty");

    isa(sym.join("lea rdi, [rel ", state_label, "]"));
    io_map_close();
}

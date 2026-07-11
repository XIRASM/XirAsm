// 跨平台路径操作公共契约。
//
// 路径使用平台原生零结尾字符串：
//   Linux x86-64：字节字符串
//   Windows x64：UTF-16LE 字符串
//
// 本模块不分配、不保存、不修改路径内存，也不隐式关闭文件句柄。
// 首版不支持通配符、递归父目录创建、目录删除或跨文件系统/卷复制。

const io_path_kind_missing: u64 = 0
const io_path_kind_file: u64 = 1
const io_path_kind_directory: u64 = 2
const io_path_kind_other: u64 = 3

// 使用编译期标签查询路径类型。
// 编译期参数：path_label = 平台原生零结尾路径标签。
// 运行时输入寄存器：调用点无需预置；本函数生成 rsi 后转交。
// 返回：存在时 rax=io_path_kind_*、rdx=0；明确缺失时 rax=0、rdx=0；
//       其他失败时 rax=-1、rdx=正数原生错误码。
// 所有权：路径内存始终归调用方，本函数不修改或保存路径。
// ABI：保留/破坏寄存器及栈要求与 io_path_query 相同。
fn io_path_query_label(path_label: string) {
    assert(len(path_label) > 0, "path label is empty");
    isa(sym.join("lea rsi, [rel ", path_label, "]"));
    io_path_query();
}

// 使用编译期标签查询路径是否存在。
// 编译期参数：path_label = 平台原生零结尾路径标签。
// 运行时输入寄存器：调用点无需预置；本函数生成 rsi 后转交。
// 返回：存在时 rax=1、rdx=0；缺失时 rax=0、rdx=0；
//       查询失败时 rax=-1、rdx=正数原生错误码。
// 所有权：路径内存始终归调用方，本函数不修改或保存路径。
// ABI：保留/破坏寄存器及栈要求与 io_path_exists 相同。
fn io_path_exists_label(path_label: string) {
    assert(len(path_label) > 0, "path label is empty");
    isa(sym.join("lea rsi, [rel ", path_label, "]"));
    io_path_exists();
}

// 使用编译期标签创建一个目录组件。
// 编译期参数：path_label = 平台原生零结尾目录路径标签。
// 运行时输入寄存器：调用点无需预置；本函数生成 rsi 后转交。
// 返回：新建或已存在目录时 rax=0、rdx=0；失败时 rax=-1、
//       rdx=正数原生错误码。
// 所有权：路径内存始终归调用方；本函数不递归创建父目录。
// ABI：保留/破坏寄存器及栈要求与 io_path_make_dir 相同。
fn io_path_make_dir_label(path_label: string) {
    assert(len(path_label) > 0, "path label is empty");
    isa(sym.join("lea rsi, [rel ", path_label, "]"));
    io_path_make_dir();
}

// 使用编译期标签严格删除普通文件。
// 编译期参数：path_label = 平台原生零结尾文件路径标签。
// 运行时输入寄存器：调用点无需预置；本函数生成 rsi 后转交。
// 返回：成功 rax=0、rdx=0；缺失、目录、权限等失败时 rax=-1、
//       rdx=正数原生错误码。
// 所有权：路径内存始终归调用方；本函数不删除目录。
// ABI：保留/破坏寄存器及栈要求与 io_path_remove_file 相同。
fn io_path_remove_file_label(path_label: string) {
    assert(len(path_label) > 0, "path label is empty");
    isa(sym.join("lea rsi, [rel ", path_label, "]"));
    io_path_remove_file();
}

// 使用两个编译期标签替换重命名文件。
// 编译期参数：
//   source_label      = 平台原生零结尾源路径标签
//   destination_label = 平台原生零结尾目标路径标签
// 运行时输入寄存器：调用点无需预置；本函数生成 rsi=源、rdi=目标后转交。
// 返回：成功 rax=0、rdx=0；失败 rax=-1、rdx=正数原生错误码。
// 所有权：两个路径都始终归调用方；不创建父目录、不承诺跨卷复制。
// ABI：保留/破坏寄存器及栈要求与 io_path_rename_replace 相同。
fn io_path_rename_replace_label(source_label: string, destination_label: string) {
    assert(len(source_label) > 0, "path source label is empty");
    assert(len(destination_label) > 0, "path destination label is empty");
    isa(sym.join("lea rsi, [rel ", source_label, "]"));
    isa(sym.join("lea rdi, [rel ", destination_label, "]"));
    io_path_rename_replace();
}

# XIRASM IO 扩展库发布说明（实验）

`include/io` 是 XIRASM 当前提供的运行时 IO 扩展库。它面向 x86-64
Linux 和 Windows x64 程序，用一组接近同名的接口封装控制台、文件、
缓冲流、路径、目录枚举和整文件映射。

本库当前定位为**实验性扩展库**，不是最终标准库形态，也不是性能优化版。
它已经可以用于日常小工具、示例程序、测试程序和简单文件处理，但后续仍可能
随着 `std/`、`os/` 等库分层调整而扩展或整理接口。

## 当前可用性

当前实现部分可以临时使用。适合的场景包括：

- 控制台标准输入、标准输出、标准错误。
- 打开、创建、追加、读写、刷新、定位和关闭文件。
- 一次性读取完整文件到调用方缓冲区，或把调用方缓冲区完整写入文件。
- 使用调用方提供的状态块和缓冲区做顺序读写流。
- 查询路径类型、判断存在、创建单级目录、删除普通文件、替换重命名。
- 打开只读完整文件映射，或创建读写完整文件映射。
- 枚举目录项。

它不适合直接当作完整 OS 层使用。当前不覆盖 socket、pipe、异步 IO、
终端模式、文件锁、权限管理、符号链接、完整元数据、递归目录创建、
目录删除、复制文件、Linux 通配符展开、文本编码转换、部分文件映射偏移、
可执行内存映射或 32 位目标。

## 支持目标

Linux：

```asm
import("io/linux.inc");
x86.use64();
```

Linux 版本直接使用 x86-64 `syscall`，不依赖 libc。

Windows：

```asm
import("io/windows.inc");
x86.use64();
```

Windows 版本调用 WinAPI。生成 PE 时，必须按实际使用的模块把导入项加入
PE 导入表。常用导入辅助函数如下：

```asm
const imports0: map = pe_import_new()
const imports1: map = io_windows64_imports(imports0)
const imports2: map = io_windows64_file_imports(imports1)
const imports3: map = io_windows64_path_imports(imports2)
const imports4: map = io_windows64_map_imports(imports3)
const imports5: map = io_windows64_dir_imports(imports4)
```

只需要导入实际用到的模块。例如只写控制台时通常只需要
`io_windows64_imports`；只做文件和路径时通常需要
`io_windows64_file_imports` 与 `io_windows64_path_imports`。

## 返回值约定

除少数布尔式路径查询外，IO 操作统一使用 `rax` 和 `rdx` 返回：

```text
成功：rax = 返回值，rdx = 0
失败：rax = -1，rdx = 平台原生正数错误码或 io_*_error_* 自定义错误码
```

读写计数、句柄、文件位置、文件大小、映射视图指针等都放在 `rax`。
错误时 `rdx` 在 Linux 上通常是正数 `errno`，在 Windows 上通常是
`GetLastError()` 返回值。

短读和短写是成功结果。需要“读满”或“写满”时，调用方应根据 `rax`
返回的实际字节数继续调用。

单次传输上限为：

```asm
io_max_transfer_size
io_max_read_size
io_max_write_size
```

当前这些上限为 `0xffffffff` 字节。

## 路径和字符串

路径必须使用平台原生零结尾字符串：

- Linux x86-64：字节字符串，通常用 `db("path", 0)`。
- Windows x64：UTF-16LE 字符串，通常用 `dw(...)` 写入 16 位字符和结尾 0。

IO 层不分配、不转换编码、不保存路径指针。路径内存始终归调用方所有。

## 控制台 IO

运行时接口：

```asm
io_write_stdout()
io_write_stderr()
io_read_stdin()
```

标签便捷接口：

```asm
io_write_stdout_label(buffer_label, length)
io_write_stderr_label(buffer_label, length)
io_read_stdin_label(buffer_label, length)
```

运行时读写接口使用：

```text
rsi = 缓冲区地址
rdx = 请求字节数
```

标签接口会在汇编期生成 `rsi` 和 `rdx`。缓冲区仍归调用方所有。

示例：

```asm
io_write_stdout_label("message", message_length);
cmp rax, message_length
jne failed
test rdx, rdx
jne failed

message:
    db("hello", 10);
```

## 文件 IO

基础文件接口：

```asm
io_file_open_read()
io_file_create_truncate()
io_file_open_append()
io_file_close()
io_file_read()
io_file_write()
io_file_flush()
io_file_seek(origin)
io_file_size()
```

标签便捷接口：

```asm
io_file_open_read_label(path_label)
io_file_create_truncate_label(path_label)
io_file_open_append_label(path_label)
io_file_read_label(buffer_label, length)
io_file_write_label(buffer_label, length)
io_file_load_label(path_label, buffer_label, capacity)
io_file_store_label(path_label, data_label, size)
```

打开成功后，`rax` 返回原生文件句柄。调用方必须把句柄放入 `rdi`
并调用 `io_file_close()`。`io_file_close()` 一经调用就消费句柄所有权；
即使关闭返回失败，也不要复用或重试关闭同一个句柄。

`io_file_load_label` 和 `io_file_store_label` 是整文件便捷接口。它们不接管
调用方缓冲区；打开成功后的临时句柄会在函数内部消费。

示例：

```asm
io_file_store_label("file_path", "payload_data", payload_length);
cmp rax, payload_length
jne failed
test rdx, rdx
jne failed

io_file_load_label("file_path", "load_buffer", payload_length);
cmp rax, payload_length
jne failed
test rdx, rdx
jne failed
```

## 缓冲流

缓冲流建立在文件 IO 之上，不分配内存。调用方必须提供：

- 一个清零的 `io_stream_state_size` 字节状态块。
- 一个容量大于 0 的调用方缓冲区。

接口：

```asm
io_stream_open_read()
io_stream_create_truncate()
io_stream_open_append()
io_stream_write()
io_stream_write_byte()
io_stream_read()
io_stream_read_byte()
io_stream_flush()
io_stream_close()
```

常用标签包装：

```asm
io_stream_open_read_label(state_label, path_label, buffer_label, capacity)
io_stream_create_truncate_label(state_label, path_label, buffer_label, capacity)
io_stream_open_append_label(state_label, path_label, buffer_label, capacity)
io_stream_write_label(state_label, data_label, length)
io_stream_read_label(state_label, buffer_label, length)
io_stream_flush_label(state_label)
io_stream_close_label(state_label)
```

写流关闭时会尝试刷新，然后关闭句柄。刷新失败时仍会消费句柄所有权。
读流到达 EOF 时，`io_stream_read_byte()` 返回 `rax = -1, rdx = 0`。

## 路径操作

路径接口：

```asm
io_path_query_label(path_label)
io_path_exists_label(path_label)
io_path_make_dir_label(path_label)
io_path_remove_file_label(path_label)
io_path_rename_replace_label(source_label, destination_label)
```

返回的路径类型：

```asm
io_path_kind_missing
io_path_kind_file
io_path_kind_directory
io_path_kind_other
```

`io_path_make_dir_label` 只创建一个目录组件。已存在且确认为目录时返回成功。
它不递归创建父目录。`io_path_remove_file_label` 只删除普通文件，不删除目录。
`io_path_rename_replace_label` 不承诺跨文件系统或跨卷复制。

## 文件映射

文件映射使用调用方提供的 `io_map_state_size` 字节清零状态块。

接口：

```asm
io_map_open_read_label(state_label, path_label)
io_map_create_label(state_label, path_label, length)
io_map_flush_label(state_label)
io_map_close_label(state_label)
```

只读映射打开完整文件，空文件成功时视图指针为 0。读写映射会创建或截断文件，
并映射完整文件。当前只支持偏移 0 的完整文件映射，不提供部分映射、可执行页、
共享命名映射或跨进程协议。

映射成功后，状态块拥有文件句柄、映射句柄和视图。调用方必须调用
`io_map_close_label` 消费这些资源。

## 目录枚举

目录枚举使用调用方提供的 `io_dir_state_size` 字节状态块。

接口：

```asm
io_dir_init_label(state_label)
io_dir_open_label(state_label, path_or_pattern_label)
io_dir_next_label(state_label)
io_dir_close_label(state_label)
```

`io_dir_next_label` 的返回值：

```text
有条目：rax = 1，rdx = 0
结束：  rax = 0，rdx = 0
失败：  rax = -1，rdx = 错误码
```

当前条目的名称指针、长度和类型写在状态块中：

```asm
io_dir_name_ptr_offset
io_dir_name_len_offset
io_dir_kind_offset
```

类型使用：

```asm
io_dir_kind_file
io_dir_kind_directory
io_dir_kind_other
```

Linux 版本接收目录路径，不在 IO 层展开通配符。Windows 版本接收
`FindFirstFileW` 搜索 pattern，例如 UTF-16LE 的 `目录\*`。

## ABI 和寄存器注意事项

Linux 实现使用直接 syscall。`syscall` 会破坏 `rcx` 和 `r11`，公共函数也会
按各自注释破坏普通易失寄存器。

Windows 实现使用 Win64 ABI 调用 KERNEL32。库内调用会保留 shadow space、
保持调用前 16 字节栈对齐，并恢复 `rsp`。公共函数的保留和破坏寄存器写在
对应 `.inc` 文件的中文注释中。

调用方不要把跨调用必须保留的临时状态放在平台易失寄存器里，除非对应函数注释
明确承诺保留。

## 当前缺口

当前 IO 扩展库还没有覆盖：

- 32 位目标。
- System V C ABI/libc 包装。
- socket、pipe、异步 IO、overlapped IO、终端属性。
- 文件锁、权限修改、所有权修改、时间戳修改。
- 完整 `stat` 元数据、符号链接、硬链接。
- 递归目录创建、目录删除、目录树遍历封装。
- 文件复制、跨卷替代方案。
- 文本编码转换和 Windows UTF-16LE 字符串构造辅助。
- mmap/MapViewOfFile 的偏移映射、可执行页、命名映射。
- 面向高吞吐的优化拷贝路径和批量 IO API。

这些缺口不影响当前库在简单控制台和文件程序中的临时使用，但它们意味着本库
现在仍应被视为实验性扩展，而不是完整、稳定、最终优化的标准库。

## 建议使用方式

可以在当前阶段使用它来写小型工具和测试程序。建议遵守以下约定：

- 每次调用后同时检查 `rax` 和 `rdx`。
- 对短读、短写做循环处理。
- 所有状态块先清零，再 open/init，最后 close。
- Windows 程序只导入实际使用的 KERNEL32 API 集合。
- Linux 路径用零结尾字节串，Windows 路径用零结尾 UTF-16LE。
- 不依赖当前内部状态布局以外的未文档化字段。
- 把它当作实验性扩展库使用，等待后续 `std/`、`os/` 分层稳定。

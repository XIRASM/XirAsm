# XIRASM Win32 包含文件

[English](README.md)

这些包含文件为使用 `format/format.inc` 构建的 PE 程序提供 Win32
导入、常量、ABI 结构体、GUID 和 COM 接口信息。

## 按需导入

程序只需导入实际使用的 DLL 和命名空间分片：

```asm
import("format/format.inc")
import("os/win32/imports/kernel32.inc")
import("os/win32/imports/user32.inc")
import("os/win32/defs/foundation.inc")
```

`import("os/win32.inc")` 是包含常用 DLL 和命名空间的便利入口。
`imports.inc`、`defs.inc` 和 `comdefs.inc` 提供完整索引，普通程序使用较小的
分片文件可以获得更快的解析速度。

## 在 PE64 中导入 Win32 API

每个 DLL 分片都提供 API 名称常量和一个 `*_add_mut` 过程。一次调用可以从
同一个 DLL 选择多个 API：

```asm
import("format/format.inc")
import("os/win32/imports/kernel32.inc")
import("os/win32/imports/user32.inc")

let image: map = format_pe64(
    format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_auto,
    list.of(
        format_section(".text", format_code | format_readable | format_executable),
        format_section(".idata", format_imports | format_readable | format_writeable)
    )
)
let imports: map = format_pe_import_new()

win32_import_kernel32_add_mut(
    image,
    imports,
    list.of(
        win32_import_kernel32_GetCurrentProcessId,
        win32_import_kernel32_ExitProcess
    )
)
win32_import_user32_add_mut(
    image,
    imports,
    list.of(win32_import_user32_GetDesktopWindow)
)

format_begin(image)
format_section_begin(image, ".text")
start:
    sub rsp, 40
    call [rel GetCurrentProcessId]
    call [rel GetDesktopWindow]
    xor ecx, ecx
    call [rel ExitProcess]
format_section_end(image, ".text")

format_pe_import_section(image, ".idata", imports)
format_entry_mut(image, start)
format_finish(image)
```

`call [rel ...]` 使用的标签名与所选 API 名称相同。调用 Win64 API 时仍需遵守
Windows x64 的 shadow space 和栈对齐规则。

## 常量和结构体

定义分片包含常量、32/64 位 ABI 结构体及布局信息：

```asm
import("os/win32/defs/foundation.inc")

const point: win32_Foundation_POINT64 = win32_Foundation_POINT64 {
    x: -10,
    y: 20
}

assert(win32_Foundation_MAX_PATH == 260)
assert(sizeof(win32_Foundation_POINT64) == 8)
assert(offset_of(win32_Foundation_POINT64, y) == 4)
emit.struct(point)
```

结构体名称末尾的 `32` 或 `64` 必须与程序 ABI 一致。Win32 有符号字段使用
`i8`、`i16`、`i32` 或 `i64`，指针和句柄使用目标位宽的无符号槽类型。

## GUID 和 COM

`guid.inc` 可以从常见的五段数值写法构造 16 字节 Windows GUID 内存布局：

```asm
import("os/win32/guid.inc")

const iid_taskbar: bytes = win32_guid(
    0x56fdf342,
    0xfd6d,
    0x11d0,
    0x958a,
    0x006097c9a090
)
```

COM 分片同时提供规范文本和可直接写入映像的 bytes。接口使用 `_iid_text`、
`_iid_bytes`，COM 类使用 `_clsid_text`、`_clsid_bytes`：

```asm
import("format/com64.inc")
import("os/win32/comdefs/ui_shell.inc")

taskbar_clsid:
    emit.bytes(win32_com_UI_Shell_TaskbarList_clsid_bytes)
taskbar_iid:
    emit.bytes(win32_com_UI_Shell_ITaskbarList_iid_bytes)
taskbar_object:
    dq(0);
```

选择 `win32_import_ole32_CoCreateInstance` 后，GUID 标签按普通 Win64 指针参数
传入。第 5 个参数位于 shadow space 之后的第一个栈参数槽：

```asm
sub rsp, 40
lea rcx, [rel taskbar_clsid]
xor edx, edx
mov r8d, 1
lea r9, [rel taskbar_iid]
lea rax, [rel taskbar_object]
mov [rsp + 32], rax
call [rel CoCreateInstance]
add rsp, 40
```

获得接口指针后，可以使用生成的方法偏移调用 COM helper：

```asm
mov rcx, [rel taskbar_object]
sub rsp, 40
com64_call_rcx(win32_com_UI_Shell_ITaskbarList_HrInit_offset64)
add rsp, 40
```

COM helper 只负责 vtable 间接调用。参数寄存器、栈参数、shadow space、栈对齐
以及接口释放仍由调用者负责。

## 命名速查

| 用途 | 名称形式 |
| --- | --- |
| 导入 API 名称 | `win32_import_<dll>_<ApiName>` |
| 添加 DLL API | `win32_import_<dll>_add_mut(image, imports, names)` |
| 常量 | `win32_<Namespace>_<Name>` |
| ABI 结构体 | `win32_<Namespace>_<Type>32` 或 `...64` |
| 接口 IID | `win32_com_<Namespace>_<Interface>_iid_bytes` |
| COM 类 CLSID | `win32_com_<Namespace>_<Class>_clsid_bytes` |
| COM 方法偏移 | `win32_com_<Namespace>_<Interface>_<Method>_offset32/64` |

元数据来源与许可证信息见 `NOTICE.md`。

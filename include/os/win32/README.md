# XIRASM Win32 Includes

[简体中文](README.zh-CN.md)

These includes provide selected Win32 imports, constants, ABI structures,
GUIDs, and COM interface facts for PE programs built with `format/format.inc`.

## Choose What to Import

For a small source scan, import only the DLL and namespace partitions that the
program uses:

```asm
import("format/format.inc")
import("os/win32/imports/kernel32.inc")
import("os/win32/imports/user32.inc")
import("os/win32/defs/foundation.inc")
```

`import("os/win32.inc")` is a convenient starter containing common DLLs and
namespaces. The exhaustive `imports.inc`, `defs.inc`, and `comdefs.inc` indexes
are available for tools or unusual programs, but ordinary sources should use
the smaller partition files.

## Add Win32 Imports to a PE64 Image

Each DLL partition exposes API name constants and one `*_add_mut` procedure.
One call can select several APIs from the same DLL:

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

The local labels used by `call [rel ...]` match the selected API names. Keep
Windows x64 shadow space and stack alignment correct around API calls.

## Constants and Structures

Definition partitions contain constants, 32-bit and 64-bit aggregate types,
and layout facts:

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

Use the `32` or `64` suffix that matches the program ABI. Signed Win32 fields
use `i8`, `i16`, `i32`, or `i64`; pointers and handles use the target-sized
unsigned slot type.

## GUIDs and COM

`guid.inc` builds the 16-byte Windows memory representation of a GUID:

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

COM partitions provide canonical text and ready-to-emit bytes. Interfaces use
`_iid_text` and `_iid_bytes`; COM classes use `_clsid_text` and `_clsid_bytes`:

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

After selecting `win32_import_ole32_CoCreateInstance`, pass the GUID labels as
ordinary Windows x64 pointer arguments. The fifth argument occupies the first
stack-argument slot after shadow space:

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

After an interface pointer has been returned, generated method offsets work
with the COM helpers:

```asm
mov rcx, [rel taskbar_object]
sub rsp, 40
com64_call_rcx(win32_com_UI_Shell_ITaskbarList_HrInit_offset64)
add rsp, 40
```

The COM helper performs the vtable dispatch only. The caller remains
responsible for argument registers, stack arguments, shadow space, alignment,
and releasing acquired interfaces.

## Naming Summary

| Surface | Pattern |
| --- | --- |
| Imported API name | `win32_import_<dll>_<ApiName>` |
| Add selected DLL APIs | `win32_import_<dll>_add_mut(image, imports, names)` |
| Constant | `win32_<Namespace>_<Name>` |
| ABI aggregate | `win32_<Namespace>_<Type>32` or `...64` |
| Interface identifier | `win32_com_<Namespace>_<Interface>_iid_bytes` |
| COM class identifier | `win32_com_<Namespace>_<Class>_clsid_bytes` |
| Method offset | `win32_com_<Namespace>_<Interface>_<Method>_offset32/64` |

See `NOTICE.md` for metadata source and license information.

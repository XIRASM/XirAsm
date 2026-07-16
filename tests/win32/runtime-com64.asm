import("format/format.inc")
import("format/com64.inc")
import("os/win32/imports/kernel32.inc")
import("os/win32/imports/ole32.inc")
import("os/win32/comdefs/ui_shell.inc")

let image: map = format_pe64(
    format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_auto,
    list.of(
        format_section(".text", format_code | format_readable | format_executable),
        format_section(".rdata", format_data | format_readable),
        format_section(".data", format_data | format_readable | format_writeable),
        format_section(".idata", format_imports | format_readable | format_writeable)
    )
)
let imports: map = format_pe_import_new()

win32_import_kernel32_add_mut(
    image,
    imports,
    list.of(win32_import_kernel32_ExitProcess)
)
win32_import_ole32_add_mut(
    image,
    imports,
    list.of(
        win32_import_ole32_CoInitializeEx,
        win32_import_ole32_CoCreateInstance,
        win32_import_ole32_CoUninitialize
    )
)

format_begin(image)

format_section_begin(image, ".text")
start:
    sub rsp, 40
    xor ecx, ecx
    xor edx, edx
    call [rel CoInitializeEx]
    test eax, eax
    js initialize_failed

    lea rcx, [rel taskbar_clsid]
    xor edx, edx
    mov r8d, 1
    lea r9, [rel taskbar_iid]
    lea rax, [rel taskbar_object]
    mov [rsp + 32], rax
    call [rel CoCreateInstance]
    test eax, eax
    js create_failed

    mov rcx, [rel taskbar_object]
    com64_call_rcx(win32_com_UI_Shell_ITaskbarList_HrInit_offset64)
    test eax, eax
    js method_failed
    xor ebx, ebx
    jmp release_object

method_failed:
    mov ebx, 3
release_object:
    mov rcx, [rel taskbar_object]
    com64_call_rcx(win32_com_UI_Shell_ITaskbarList_Release_offset64)
    call [rel CoUninitialize]
    mov ecx, ebx
    call [rel ExitProcess]

create_failed:
    call [rel CoUninitialize]
    mov ecx, 2
    call [rel ExitProcess]

initialize_failed:
    mov ecx, 1
    call [rel ExitProcess]
format_section_end(image, ".text")

format_section_begin(image, ".rdata")
taskbar_clsid:
    emit.bytes(win32_com_UI_Shell_TaskbarList_clsid_bytes)
taskbar_iid:
    emit.bytes(win32_com_UI_Shell_ITaskbarList_iid_bytes)
format_section_end(image, ".rdata")

format_section_begin(image, ".data")
taskbar_object:
    dq(0);
format_section_end(image, ".data")

format_pe_import_section(image, ".idata", imports)
format_entry_mut(image, start)
format_finish(image)

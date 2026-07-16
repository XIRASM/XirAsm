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
    test eax, eax
    jz failed
    call [rel GetDesktopWindow]
    test rax, rax
    jz failed
    xor ecx, ecx
    jmp exit_process
failed:
    mov ecx, 1
exit_process:
    call [rel ExitProcess]
format_section_end(image, ".text")

format_pe_import_section(image, ".idata", imports)
format_entry_mut(image, start)
format_finish(image)

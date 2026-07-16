// Windows x64 map 失败路径测试。
// 覆盖运行时零长度、缺失文件打开和关闭未打开状态。

import("format/format.inc");
import("io/windows.inc");
x86.use64();

let imports: map = pe_import_new()
imports = io_windows64_map_imports(imports)
imports = pe_import_use64(imports, "KERNEL32.DLL", "ExitProcess")

fn test_exit(status: u64) {
    sub rsp, 40
    mov ecx, status
    call [rel ExitProcess]
    add rsp, 40
}

let image: map = format_pe64(
    format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_auto,
    list.of(
        format_section(".text", format_code | format_readable | format_executable),
        format_section(".rdata", format_data | format_readable),
        format_section(".data", format_data | format_readable | format_writeable),
        format_section(".idata", format_imports | format_readable | format_writeable)
    )
)
format_begin(image);

format_section_begin(image, ".text");
start:
    lea rdi, [rel state0]
    lea rsi, [rel missing_path]
    xor ecx, ecx
    io_map_create();
    cmp rax, -1
    jne failed
    cmp rdx, io_map_error_invalid_length
    jne failed

    io_map_open_read_label("state0", "missing_path");
    cmp rax, -1
    jne failed
    test rdx, rdx
    je failed

    io_map_close_label("state0");
    cmp rax, -1
    jne failed
    cmp rdx, io_map_error_invalid_state
    jne failed

    test_exit(0);
failed:
    test_exit(1);
format_section_end(image, ".text");

format_section_begin(image, ".rdata");
missing_path:
    dw(0x0078, 0x0069, 0x006f, 0x002d, 0x006d, 0x0061, 0x0070, 0x002d, 0x0077, 0x0036, 0x0034, 0x002d, 0x006d, 0x0069, 0x0073, 0x0073, 0x0069, 0x006e, 0x0067, 0x002e, 0x0074, 0x006d, 0x0070, 0);
format_section_end(image, ".rdata");

format_section_begin(image, ".data");
state0:
    dq(0, 0, 0, 0, 0, 0);
format_section_end(image, ".data");

format_pe_import_section(image, ".idata", imports);

format_entry_mut(image, start)
format_finish(image);

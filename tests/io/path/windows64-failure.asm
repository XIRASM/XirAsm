// Windows x64 path 失败路径测试。
// 已存在普通文件不能当目录，缺失删除和缺失源重命名必须保留原生错误。

import("format/format.inc");
import("io/windows.inc");
x86.use64();

let imports: map = pe_import_new()
imports = io_windows64_file_imports(imports)
imports = io_windows64_path_imports(imports)
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
        format_section(".idata", format_imports | format_readable | format_writeable)
    )
)
format_begin(image);

format_section_begin(image, ".text");
start:
    io_file_create_truncate_label("blocker_path");
    cmp rax, -1
    je failed
    mov rdi, rax
    io_file_close();
    cmp rax, 0
    jne failed

    io_path_make_dir_label("blocker_path");
    cmp rax, -1
    jne failed
    test rdx, rdx
    jz failed

    io_path_remove_file_label("missing_path");
    cmp rax, -1
    jne failed
    test rdx, rdx
    jz failed

    io_path_rename_replace_label("missing_path", "destination_path");
    cmp rax, -1
    jne failed
    test rdx, rdx
    jz failed

    io_path_remove_file_label("blocker_path");
    cmp rax, 0
    jne failed
    test_exit(0);
failed:
    test_exit(1);
format_section_end(image, ".text");

format_section_begin(image, ".rdata");
blocker_path:
    dw(0x0078, 0x0069, 0x006f, 0x002d, 0x0070, 0x0061, 0x0074, 0x0068, 0x002d, 0x0077, 0x0036, 0x0034, 0x002d, 0x0062, 0x006c, 0x006f, 0x0063, 0x006b, 0x0065, 0x0072, 0x002e, 0x0074, 0x006d, 0x0070, 0);
missing_path:
    dw(0x0078, 0x0069, 0x006f, 0x002d, 0x0070, 0x0061, 0x0074, 0x0068, 0x002d, 0x0077, 0x0036, 0x0034, 0x002d, 0x006d, 0x0069, 0x0073, 0x0073, 0x0069, 0x006e, 0x0067, 0x002e, 0x0074, 0x006d, 0x0070, 0);
destination_path:
    dw(0x0078, 0x0069, 0x006f, 0x002d, 0x0070, 0x0061, 0x0074, 0x0068, 0x002d, 0x0077, 0x0036, 0x0034, 0x002d, 0x0064, 0x0065, 0x0073, 0x0074, 0x0069, 0x006e, 0x0061, 0x0074, 0x0069, 0x006f, 0x006e, 0x002e, 0x0074, 0x006d, 0x0070, 0);
format_section_end(image, ".rdata");

format_pe_import_section(image, ".idata", imports);

format_entry_mut(image, start)
format_finish(image);

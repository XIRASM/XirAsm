// Windows x64 map 核心运行测试。
// 覆盖创建写映射、刷新关闭、只读重开、内容验证、长度记录和文件删除。

import("format/format.inc");
import("io/windows.inc");
x86.use64();

const map_length: u64 = 4096

let imports: map = pe_import_new()
imports = io_windows64_map_imports(imports)
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
        format_section(".data", format_data | format_readable | format_writeable),
        format_section(".idata", format_imports | format_readable | format_writeable)
    )
)
format_begin(image);

format_section_begin(image, ".text");
start:
    io_map_create_label("write_state", "map_path", map_length);
    cmp rax, -1
    je failed
    test rdx, rdx
    jne failed
    cmp qword [rel write_state + 24], map_length
    jne failed
    mov dword [rax], 0x2150414d

    io_map_flush_label("write_state");
    cmp rax, 0
    jne failed
    test rdx, rdx
    jne failed

    io_map_close_label("write_state");
    cmp rax, 0
    jne failed
    test rdx, rdx
    jne failed

    io_map_open_read_label("read_state", "map_path");
    cmp rax, -1
    je failed
    test rdx, rdx
    jne failed
    cmp qword [rel read_state + 24], map_length
    jne failed
    mov eax, [rax]
    cmp eax, 0x2150414d
    jne failed

    io_map_close_label("read_state");
    cmp rax, 0
    jne failed
    test rdx, rdx
    jne failed

    io_path_remove_file_label("map_path");
    cmp rax, 0
    jne failed
    test rdx, rdx
    jne failed

    test_exit(0);
failed:
    test_exit(1);
format_section_end(image, ".text");

format_section_begin(image, ".rdata");
map_path:
    dw(0x0078, 0x0069, 0x006f, 0x002d, 0x006d, 0x0061, 0x0070, 0x002d, 0x0077, 0x0036, 0x0034, 0x002e, 0x0074, 0x006d, 0x0070, 0);
format_section_end(image, ".rdata");

format_section_begin(image, ".data");
write_state:
    dq(0, 0, 0, 0, 0, 0);
read_state:
    dq(0, 0, 0, 0, 0, 0);
format_section_end(image, ".data");

format_pe_import_section(image, ".idata", imports);

format_entry_mut(image, start)
format_finish(image);

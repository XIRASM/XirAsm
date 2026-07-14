// Windows x64 path 核心运行测试。
// 覆盖缺失查询、幂等建目录、文件类型、替换重命名、内容验证和严格删除。

import("format/format.inc");
import("io/windows.inc");
x86.use64();

const payload: string = "ABCD"
const payload_length: u64 = len(payload)

const imports0: map = pe_import_new()
const imports1: map = io_windows64_file_imports(imports0)
const imports2: map = io_windows64_path_imports(imports1)
const imports: map = pe_import_use64(imports2, "KERNEL32.DLL", "ExitProcess")

fn test_exit(status: u64) {
    sub rsp, 40
    mov ecx, status
    call [rel ExitProcess]
    add rsp, 40
}

const image0: map = format_pe64(
    format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_auto,
    list.of(
        format_section(".text", format_code | format_readable | format_executable),
        format_section(".rdata", format_data | format_readable),
        format_section(".data", format_data | format_readable | format_writeable),
        format_section(".idata", format_imports | format_readable | format_writeable)
    )
)
format_begin(image0);

format_section_begin(image0, ".text");
start:
    io_path_query_label("dir_path");
    test rax, rax
    jne failed
    test rdx, rdx
    jne failed

    io_path_exists_label("dir_path");
    test rax, rax
    jne failed
    test rdx, rdx
    jne failed

    io_path_make_dir_label("dir_path");
    cmp rax, 0
    jne failed
    test rdx, rdx
    jne failed

    io_path_make_dir_label("dir_path");
    cmp rax, 0
    jne failed
    test rdx, rdx
    jne failed

    io_path_query_label("dir_path");
    cmp rax, 2
    jne failed
    test rdx, rdx
    jne failed

    io_file_create_truncate_label("source_path");
    cmp rax, -1
    je failed
    test rdx, rdx
    jne failed
    mov rdi, rax
    io_file_write_label("source_data", payload_length);
    cmp rax, payload_length
    jne failed
    test rdx, rdx
    jne failed
    io_file_close();
    cmp rax, 0
    jne failed

    io_file_create_truncate_label("destination_path");
    cmp rax, -1
    je failed
    test rdx, rdx
    jne failed
    mov rdi, rax
    io_file_close();
    cmp rax, 0
    jne failed

    io_path_query_label("source_path");
    cmp rax, 1
    jne failed
    io_path_exists_label("source_path");
    cmp rax, 1
    jne failed

    io_path_rename_replace_label("source_path", "destination_path");
    cmp rax, 0
    jne failed
    test rdx, rdx
    jne failed

    io_path_query_label("source_path");
    test rax, rax
    jne failed
    test rdx, rdx
    jne failed

    io_path_query_label("destination_path");
    cmp rax, 1
    jne failed
    test rdx, rdx
    jne failed

    io_file_open_read_label("destination_path");
    cmp rax, -1
    je failed
    mov rdi, rax
    io_file_read_label("read_buffer", payload_length);
    cmp rax, payload_length
    jne failed
    mov eax, [rel read_buffer]
    cmp eax, 0x44434241
    jne failed
    io_file_close();
    cmp rax, 0
    jne failed

    io_path_remove_file_label("destination_path");
    cmp rax, 0
    jne failed
    test rdx, rdx
    jne failed

    io_path_query_label("destination_path");
    test rax, rax
    jne failed
    test rdx, rdx
    jne failed

    test_exit(0);
failed:
    test_exit(1);
format_section_end(image0, ".text");

format_section_begin(image0, ".rdata");
dir_path:
    dw(0x0078, 0x0069, 0x006f, 0x002d, 0x0070, 0x0061, 0x0074, 0x0068, 0x002d, 0x0077, 0x0036, 0x0034, 0);
source_path:
    dw(0x0078, 0x0069, 0x006f, 0x002d, 0x0070, 0x0061, 0x0074, 0x0068, 0x002d, 0x0077, 0x0036, 0x0034, 0x005c, 0x0073, 0x0072, 0x0063, 0x002e, 0x0074, 0x006d, 0x0070, 0);
destination_path:
    dw(0x0078, 0x0069, 0x006f, 0x002d, 0x0070, 0x0061, 0x0074, 0x0068, 0x002d, 0x0077, 0x0036, 0x0034, 0x005c, 0x0064, 0x0073, 0x0074, 0x002e, 0x0074, 0x006d, 0x0070, 0);
source_data:
    db(payload);
format_section_end(image0, ".rdata");

format_section_begin(image0, ".data");
read_buffer:
    dq(0);
format_section_end(image0, ".data");

format_pe_import_section(image0, ".idata", imports);

const image: map = format_entry(image0, start)
format_finish(image);

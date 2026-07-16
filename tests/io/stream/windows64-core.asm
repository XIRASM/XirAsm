// Windows x64 缓冲流核心运行测试。
// 使用 3 字节调用方缓冲区，强制覆盖自动刷新、显式刷新、关闭刷新、
// 追加、自动补充、逐字节读取和 EOF。成功退出码为 0。

import("format/format.inc");
import("io/windows.inc");
x86.use64();

const first_text: string = "12345678"
const first_length: u64 = len(first_text)
const stream_capacity: u64 = 3

let imports: map = pe_import_new()
imports = io_windows64_file_imports(imports)
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
    io_stream_create_truncate_label(
        "stream_state",
        "file_path",
        "stream_buffer",
        stream_capacity
    );
    cmp rax, -1
    je failed
    test rdx, rdx
    jne failed

    io_stream_write_label("stream_state", "first_data", first_length);
    cmp rax, first_length
    jne failed
    test rdx, rdx
    jne failed

    lea rdi, [rel stream_state]
    io_stream_flush();
    cmp rax, 2
    jne failed
    test rdx, rdx
    jne failed

    lea rdi, [rel stream_state]
    mov al, 0x39
    io_stream_write_byte();
    cmp rax, 1
    jne failed
    test rdx, rdx
    jne failed

    io_stream_close_label("stream_state");
    test rax, rax
    jne failed
    test rdx, rdx
    jne failed

    io_stream_open_append_label(
        "stream_state",
        "file_path",
        "stream_buffer",
        stream_capacity
    );
    cmp rax, -1
    je failed
    test rdx, rdx
    jne failed

    lea rdi, [rel stream_state]
    mov al, 0x30
    io_stream_write_byte();
    cmp rax, 1
    jne failed
    test rdx, rdx
    jne failed

    io_stream_close_label("stream_state");
    test rax, rax
    jne failed
    test rdx, rdx
    jne failed

    io_stream_open_read_label(
        "stream_state",
        "file_path",
        "stream_buffer",
        stream_capacity
    );
    cmp rax, -1
    je failed
    test rdx, rdx
    jne failed

    io_stream_read_label("stream_state", "read_buffer", 4);
    cmp rax, 4
    jne failed_bulk_count
    test rdx, rdx
    jne failed_bulk_error
    mov eax, [rel read_buffer]
    cmp eax, 0x34333231
    jne failed_bulk_content

    lea rdi, [rel stream_state]
    io_stream_read_byte();
    cmp rax, 0x35
    jne failed_byte
    io_stream_read_byte();
    cmp rax, 0x36
    jne failed
    io_stream_read_byte();
    cmp rax, 0x37
    jne failed
    io_stream_read_byte();
    cmp rax, 0x38
    jne failed
    io_stream_read_byte();
    cmp rax, 0x39
    jne failed
    io_stream_read_byte();
    cmp rax, 0x30
    jne failed

    io_stream_read_byte();
    cmp rax, -1
    jne failed
    test rdx, rdx
    jne failed

    io_stream_close_label("stream_state");
    test rax, rax
    jne failed
    test rdx, rdx
    jne failed

    test_exit(0);
failed_bulk_count:
    test_exit(2);
failed_bulk_error:
    test_exit(4);
failed_bulk_content:
    test_exit(5);
failed_byte:
    test_exit(3);
failed:
    test_exit(1);
format_section_end(image, ".text");

format_section_begin(image, ".rdata");
file_path:
    dw(
        0x0078, 0x0069, 0x006f, 0x002d, 0x0073, 0x0074, 0x0072, 0x0065,
        0x0061, 0x006d, 0x002d, 0x0077, 0x0036, 0x0034, 0x002e, 0x0074,
        0x006d, 0x0070, 0
    );
first_data:
    db(first_text);
format_section_end(image, ".rdata");

format_section_begin(image, ".data");
stream_state:
    dq(0);
    dq(0);
    dq(0);
    dq(0);
    dq(0);
    dq(0);
    dq(0);
    dq(0);
stream_buffer:
    dq(0);
read_buffer:
    dq(0);
format_section_end(image, ".data");

format_pe_import_section(image, ".idata", imports);

format_entry_mut(image, start)
format_finish(image);

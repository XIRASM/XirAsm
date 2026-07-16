// Windows x64 文件核心运行测试。
// 覆盖：CreateFileW 创建/截断与追加、WriteFile、FlushFileBuffers、
// GetFileSizeEx、SetFilePointerEx、ReadFile、EOF 和 CloseHandle。
// 成功退出码为 0。

import("format/format.inc");
import("io/windows.inc");
x86.use64();

const first_text: string = "1234"
const second_text: string = "5678"
const first_length: u64 = len(first_text)
const second_length: u64 = len(second_text)
const total_length: u64 = first_length + second_length

let imports: map = pe_import_new()
imports = io_windows64_imports(imports)
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
    io_file_create_truncate_label("file_path");
    cmp rax, -1
    je failed
    test rdx, rdx
    jne failed
    mov r12, rax

    mov rdi, r12
    io_file_write_label("first_data", first_length);
    cmp rax, 4
    jne failed
    test rdx, rdx
    jne failed

    mov rdi, r12
    io_file_flush();
    test rax, rax
    jne failed
    test rdx, rdx
    jne failed

    mov rdi, r12
    io_file_size();
    cmp rax, 4
    jne failed
    test rdx, rdx
    jne failed

    mov rdi, r12
    io_file_close();
    test rax, rax
    jne failed
    test rdx, rdx
    jne failed

    io_file_open_append_label("file_path");
    cmp rax, -1
    je failed
    test rdx, rdx
    jne failed
    mov r12, rax

    mov rdi, r12
    io_file_write_label("second_data", second_length);
    cmp rax, 4
    jne failed
    test rdx, rdx
    jne failed

    mov rdi, r12
    io_file_flush();
    test rax, rax
    jne failed
    test rdx, rdx
    jne failed

    mov rdi, r12
    io_file_size();
    cmp rax, 8
    jne failed

    mov rdi, r12
    io_file_close();
    test rax, rax
    jne failed

    io_file_open_read_label("file_path");
    cmp rax, -1
    je failed
    test rdx, rdx
    jne failed
    mov r12, rax

    mov rdi, r12
    io_file_size();
    cmp rax, 8
    jne failed
    test rdx, rdx
    jne failed

    mov rdi, r12
    mov rsi, -4
    io_file_seek(io_file_seek_end);
    cmp rax, 4
    jne failed
    test rdx, rdx
    jne failed

    mov rdi, r12
    io_file_read_label("read_buffer", second_length);
    cmp rax, 4
    jne failed
    mov eax, [rel read_buffer]
    cmp eax, 0x38373635
    jne failed

    mov rdi, r12
    mov rsi, -4
    io_file_seek(io_file_seek_current);
    cmp rax, 4
    jne failed
    test rdx, rdx
    jne failed

    mov rdi, r12
    io_file_rewind();
    test rax, rax
    jne failed
    test rdx, rdx
    jne failed

    mov rdi, r12
    io_file_read_label("read_buffer", total_length);
    cmp rax, 8
    jne failed
    mov rax, [rel read_buffer]
    mov r10, 0x3837363534333231
    cmp rax, r10
    jne failed

    mov rdi, r12
    io_file_read_label("read_buffer", 1);
    test rax, rax
    jne failed
    test rdx, rdx
    jne failed

    mov rdi, r12
    io_file_close();
    test rax, rax
    jne failed
    test rdx, rdx
    jne failed

    test_exit(0);
failed:
    test_exit(1);
format_section_end(image, ".text");

format_section_begin(image, ".rdata");
file_path:
    dw(0x0078, 0x0069, 0x006f, 0x002d, 0x0077, 0x0036, 0x0034, 0x002e, 0x0074, 0x006d, 0x0070, 0);
first_data:
    db(first_text);
second_data:
    db(second_text);
format_section_end(image, ".rdata");

format_section_begin(image, ".data");
read_buffer:
    dq(0);
format_section_end(image, ".data");

format_pe_import_section(image, ".idata", imports);

format_entry_mut(image, start)
format_finish(image);

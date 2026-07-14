// Windows x64 目录枚举运行测试。
// 覆盖 FindFirstFileW/FindNextFileW 状态机、文件名和文件类型识别。

import("format/format.inc");
import("io/windows.inc");
x86.use64();

const payload: string = "D"
const payload_length: u64 = len(payload)

const imports0: map = pe_import_new()
const imports1: map = io_windows64_file_imports(imports0)
const imports2: map = io_windows64_path_imports(imports1)
const imports3: map = io_windows64_dir_imports(imports2)
const imports: map = pe_import_use64(imports3, "KERNEL32.DLL", "ExitProcess")

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
    io_path_make_dir_label("dir_path");
    cmp rax, 0
    jne failed
    test rdx, rdx
    jne failed

    io_file_store_label("file_a_path", "payload_data", payload_length);
    cmp rax, payload_length
    jne failed
    test rdx, rdx
    jne failed
    io_file_store_label("file_b_path", "payload_data", payload_length);
    cmp rax, payload_length
    jne failed
    test rdx, rdx
    jne failed

    io_dir_init_label("dir_state");
    cmp rax, 0
    jne failed
    test rdx, rdx
    jne failed
    io_dir_open_label("dir_state", "dir_pattern");
    cmp rax, 0
    jne failed
    test rdx, rdx
    jne failed

    xor r13d, r13d
    xor r14d, r14d
    mov r12d, 64

scan_loop:
    io_dir_next_label("dir_state");
    cmp rax, -1
    je failed
    test rax, rax
    jz scan_done

    cmp qword [rel dir_state + 24], io_dir_kind_file
    jne scan_continue
    cmp qword [rel dir_state + 16], 10
    jne scan_continue
    mov rsi, [rel dir_state + 8]

    cmp word [rsi], 0x0061
    jne check_b
    cmp word [rsi + 2], 0x002e
    jne check_b
    cmp word [rsi + 4], 0x0074
    jne check_b
    cmp word [rsi + 6], 0x006d
    jne check_b
    cmp word [rsi + 8], 0x0070
    jne check_b
    mov r13d, 1
    jmp scan_continue

check_b:
    cmp word [rsi], 0x0062
    jne scan_continue
    cmp word [rsi + 2], 0x002e
    jne scan_continue
    cmp word [rsi + 4], 0x0074
    jne scan_continue
    cmp word [rsi + 6], 0x006d
    jne scan_continue
    cmp word [rsi + 8], 0x0070
    jne scan_continue
    mov r14d, 1

scan_continue:
    sub r12d, 1
    jnz scan_loop
    jmp failed

scan_done:
    cmp r13d, 1
    jne failed
    cmp r14d, 1
    jne failed
    io_dir_close_label("dir_state");
    cmp rax, 0
    jne failed
    test rdx, rdx
    jne failed

    io_path_remove_file_label("file_a_path");
    cmp rax, 0
    jne failed
    io_path_remove_file_label("file_b_path");
    cmp rax, 0
    jne failed

    test_exit(0);
failed:
    test_exit(1);
format_section_end(image0, ".text");

format_section_begin(image0, ".rdata");
dir_path:
    dw(0x0078, 0x0069, 0x006f, 0x002d, 0x0064, 0x0069, 0x0072, 0x002d, 0x0077, 0x0036, 0x0034, 0);
dir_pattern:
    dw(0x0078, 0x0069, 0x006f, 0x002d, 0x0064, 0x0069, 0x0072, 0x002d, 0x0077, 0x0036, 0x0034, 0x005c, 0x002a, 0);
file_a_path:
    dw(0x0078, 0x0069, 0x006f, 0x002d, 0x0064, 0x0069, 0x0072, 0x002d, 0x0077, 0x0036, 0x0034, 0x005c, 0x0061, 0x002e, 0x0074, 0x006d, 0x0070, 0);
file_b_path:
    dw(0x0078, 0x0069, 0x006f, 0x002d, 0x0064, 0x0069, 0x0072, 0x002d, 0x0077, 0x0036, 0x0034, 0x005c, 0x0062, 0x002e, 0x0074, 0x006d, 0x0070, 0);
payload_data:
    db(payload);
format_section_end(image0, ".rdata");

format_section_begin(image0, ".data");
dir_state:
    db(bytes.repeat(io_dir_state_size, 0));
format_section_end(image0, ".data");

format_pe_import_section(image0, ".idata", imports);

const image: map = format_entry(image0, start)
format_finish(image);

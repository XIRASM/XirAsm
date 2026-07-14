// Linux x86-64 目录枚举运行测试。
// 覆盖目录状态初始化、open/next/close、文件名和文件类型识别。

import("format/format.inc");
import("io/linux.inc");
x86.use64();

const payload: string = "D"
const payload_length: u64 = len(payload)

fn test_exit(status: u64) {
    mov eax, 60
    mov edi, status
    syscall
}

const image0: map = format_elf64(
    format_elf_exec,
    list.of(
        format_segment(".text", format_load | format_readable | format_executable),
        format_segment(".rodata", format_load | format_readable),
        format_segment(".data", format_load | format_readable | format_writeable)
    )
)
format_begin(image0);

format_segment_begin(image0, ".text");
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
    io_dir_open_label("dir_state", "dir_path");
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
    cmp qword [rel dir_state + 16], 5
    jne scan_continue
    mov rsi, [rel dir_state + 8]

    mov eax, [rsi]
    cmp eax, 0x6d742e61
    jne check_b
    cmp byte [rsi + 4], 0x70
    jne check_b
    mov r13d, 1
    jmp scan_continue

check_b:
    cmp eax, 0x6d742e62
    jne scan_continue
    cmp byte [rsi + 4], 0x70
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
format_segment_end(image0, ".text");

format_segment_begin(image0, ".rodata");
dir_path:
    db("xio-dir-l64", 0);
file_a_path:
    db("xio-dir-l64/a.tmp", 0);
file_b_path:
    db("xio-dir-l64/b.tmp", 0);
payload_data:
    db(payload);
format_segment_end(image0, ".rodata");

format_segment_begin(image0, ".data");
dir_state:
    db(bytes.repeat(io_dir_state_size, 0));
format_segment_end(image0, ".data");

const image: map = format_entry(image0, start)
format_finish(image);

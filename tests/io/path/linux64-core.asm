// Linux x86-64 path 核心运行测试。
// 覆盖缺失查询、幂等建目录、文件类型、替换重命名、内容验证和严格删除。

import("format/format.inc");
import("io/linux.inc");
x86.use64();

const payload: string = "ABCD"
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
    io_path_query_label("dir_path");
    cmp rax, 0
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

    // 已存在的目录再次创建必须保持成功。
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
format_segment_end(image0, ".text");

format_segment_begin(image0, ".rodata");
dir_path:
    db("xio-path-l64", 0);
source_path:
    db("xio-path-l64/src.tmp", 0);
destination_path:
    db("xio-path-l64/dst.tmp", 0);
source_data:
    db(payload);
format_segment_end(image0, ".rodata");

format_segment_begin(image0, ".data");
read_buffer:
    dq(0);
format_segment_end(image0, ".data");

const image: map = format_entry(image0, start)
format_finish(image);

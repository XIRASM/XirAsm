// Linux x86-64 path 失败路径测试。
// 已存在普通文件不能当目录，缺失删除和缺失源重命名必须保留原生错误。

import("format/format.inc");
import("io/linux.inc");
x86.use64();

fn test_exit(status: u64) {
    mov eax, 60
    mov edi, status
    syscall
}

let image: map = format_elf64(
    format_elf_exec,
    list.of(
        format_segment(".text", format_load | format_readable | format_executable),
        format_segment(".rodata", format_load | format_readable)
    )
)
format_begin(image);

format_segment_begin(image, ".text");
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
format_segment_end(image, ".text");

format_segment_begin(image, ".rodata");
blocker_path:
    db("xio-path-l64-blocker.tmp", 0);
missing_path:
    db("xio-path-l64-missing.tmp", 0);
destination_path:
    db("xio-path-l64-destination.tmp", 0);
format_segment_end(image, ".rodata");

format_entry_mut(image, start)
format_finish(image);

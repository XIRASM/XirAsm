// Linux x86-64 map 核心运行测试。
// 覆盖创建写映射、刷新关闭、只读重开、内容验证、长度记录和文件删除。

import("format/format.inc");
import("io/linux.inc");
x86.use64();

const map_length: u64 = 4096

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
format_segment_end(image0, ".text");

format_segment_begin(image0, ".rodata");
map_path:
    db("xio-map-l64.tmp", 0);
format_segment_end(image0, ".rodata");

format_segment_begin(image0, ".data");
write_state:
    dq(0, 0, 0, 0, 0, 0);
read_state:
    dq(0, 0, 0, 0, 0, 0);
format_segment_end(image0, ".data");

const image: map = format_entry(image0, start)
format_finish(image);

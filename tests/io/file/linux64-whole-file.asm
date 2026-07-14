// Linux x86-64 整文件读写测试。
// 覆盖 caller-owned 缓冲区的 store/load、容量不足和零字节 store/load。

import("format/format.inc");
import("io/linux.inc");
x86.use64();

const payload: string = "WHOLE-FILE-IO"
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
    io_file_store_label("file_path", "payload_data", payload_length);
    cmp rax, payload_length
    jne failed
    test rdx, rdx
    jne failed

    io_file_load_label("file_path", "load_buffer", payload_length);
    cmp rax, payload_length
    jne failed
    test rdx, rdx
    jne failed
    // x86-64 没有 cmp r64, imm64 编码，这里按 dword/byte 分段检查内容。
    // 当前后端已支持 RIP-relative label + offset，直接检查缓冲区字段。
    mov eax, [rel load_buffer]
    cmp eax, 0x4c4f4857
    jne failed
    mov eax, [rel load_buffer + 4]
    cmp eax, 0x49462d45
    jne failed
    mov eax, [rel load_buffer + 8]
    cmp eax, 0x492d454c
    jne failed
    mov al, [rel load_buffer + 12]
    cmp al, 0x4f
    jne failed

    io_file_load_label("file_path", "small_buffer", 4);
    cmp rax, -1
    jne failed
    cmp rdx, io_file_error_buffer_too_small
    jne failed

    lea rsi, [rel empty_path]
    xor edi, edi
    xor ecx, ecx
    io_file_store();
    test rax, rax
    jne failed
    test rdx, rdx
    jne failed

    lea rsi, [rel empty_path]
    xor edi, edi
    xor ecx, ecx
    io_file_load();
    test rax, rax
    jne failed
    test rdx, rdx
    jne failed

    io_path_remove_file_label("file_path");
    cmp rax, 0
    jne failed
    io_path_remove_file_label("empty_path");
    cmp rax, 0
    jne failed

    test_exit(0);
failed:
    test_exit(1);
format_segment_end(image0, ".text");

format_segment_begin(image0, ".rodata");
file_path:
    db("xio-whole-l64.tmp", 0);
empty_path:
    db("xio-whole-empty-l64.tmp", 0);
payload_data:
    db(payload);
format_segment_end(image0, ".rodata");

format_segment_begin(image0, ".data");
load_buffer:
    dq(0, 0);
small_buffer:
    dq(0);
format_segment_end(image0, ".data");

const image: map = format_entry(image0, start)
format_finish(image);

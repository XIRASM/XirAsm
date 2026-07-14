// Windows x64 标准输入读取运行测试。
// 运行时从 stdin 重定向输入 4 字节 "ABCD"，验证实际读取内容和 EOF。

import("format/format.inc");
import("io/windows.inc");
x86.use64();

const input_length: u64 = 4

const imports0: map = pe_import_new()
const imports1: map = io_windows64_imports(imports0)
const imports: map = pe_import_use64(imports1, "KERNEL32.DLL", "ExitProcess")

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
        format_section(".data", format_data | format_readable | format_writeable),
        format_section(".idata", format_imports | format_readable | format_writeable)
    )
)
format_begin(image0);

format_section_begin(image0, ".text");
start:
    io_read_stdin_label("input_buffer", input_length);
    cmp rax, input_length
    jne failed
    test rdx, rdx
    jne failed
    mov eax, [rel input_buffer]
    cmp eax, 0x44434241
    jne failed

    io_read_stdin_label("extra_buffer", 1);
    test rax, rax
    jne failed
    test rdx, rdx
    jne failed

    test_exit(0);
failed:
    test_exit(1);
format_section_end(image0, ".text");

format_section_begin(image0, ".data");
input_buffer:
    db(bytes.repeat(8, 0));
extra_buffer:
    db(0);
format_section_end(image0, ".data");

format_pe_import_section(image0, ".idata", imports);

const image: map = format_entry(image0, start)
format_finish(image);

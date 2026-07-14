// Windows x64 stream 模式错误运行测试。
// 对读模式状态调用写字节接口，必须返回 stream 自定义错误且不得执行 WriteFile。

import("format/format.inc");
import("io/windows.inc");
x86.use64();

const imports0: map = pe_import_new()
const imports1: map = io_windows64_file_imports(imports0)
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
    lea rdi, [rel stream_state]
    mov al, 0x41
    io_stream_write_byte();
    cmp rax, -1
    jne failed
    cmp rdx, io_stream_error_wrong_mode
    jne failed
    test_exit(0);
failed:
    test_exit(1);
format_section_end(image0, ".text");

format_section_begin(image0, ".data");
stream_state:
    dq(-1);
    dq(0);
    dq(1);
    dq(0);
    dq(0);
    dq(io_stream_mode_read);
    dq(0);
    dq(0);
format_section_end(image0, ".data");

format_pe_import_section(image0, ".idata", imports);

const image: map = format_entry(image0, start)
format_finish(image);

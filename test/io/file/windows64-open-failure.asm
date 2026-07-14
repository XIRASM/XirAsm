// Windows x64 失败路径测试。
// CreateFileW 打开确定不存在的文件必须返回 rax=-1、
// rdx=GetLastError() 的正数错误码。

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
        format_section(".rdata", format_data | format_readable),
        format_section(".idata", format_imports | format_readable | format_writeable)
    )
)
format_begin(image0);

format_section_begin(image0, ".text");
start:
    io_file_open_read_label("missing_path");
    cmp rax, -1
    jne failed
    test rdx, rdx
    jz failed
    test_exit(0);
failed:
    test_exit(1);
format_section_end(image0, ".text");

format_section_begin(image0, ".rdata");
missing_path:
    dw(0x0078, 0x0069, 0x006f, 0x002d, 0x0077, 0x0036, 0x0034, 0x002d, 0x006d, 0x0069, 0x0073, 0x0073, 0x0069, 0x006e, 0x0067, 0x002e, 0x0074, 0x006d, 0x0070, 0);
format_section_end(image0, ".rdata");

format_pe_import_section(image0, ".idata", imports);

const image: map = format_entry(image0, start)
format_finish(image);

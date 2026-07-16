// Windows x64 整文件读写测试。
// 覆盖 caller-owned 缓冲区的 store/load、容量不足和零字节 store/load。

import("format/format.inc");
import("io/windows.inc");
x86.use64();

const payload: string = "WHOLE-FILE-IO"
const payload_length: u64 = len(payload)

let imports: map = pe_import_new()
imports = io_windows64_file_imports(imports)
imports = io_windows64_path_imports(imports)
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
format_section_end(image, ".text");

format_section_begin(image, ".rdata");
file_path:
    dw(0x0078, 0x0069, 0x006f, 0x002d, 0x0077, 0x0068, 0x006f, 0x006c, 0x0065, 0x002d, 0x0077, 0x0036, 0x0034, 0x002e, 0x0074, 0x006d, 0x0070, 0);
empty_path:
    dw(0x0078, 0x0069, 0x006f, 0x002d, 0x0077, 0x0068, 0x006f, 0x006c, 0x0065, 0x002d, 0x0065, 0x006d, 0x0070, 0x0074, 0x0079, 0x002d, 0x0077, 0x0036, 0x0034, 0x002e, 0x0074, 0x006d, 0x0070, 0);
payload_data:
    db(payload);
format_section_end(image, ".rdata");

format_section_begin(image, ".data");
load_buffer:
    dq(0, 0);
small_buffer:
    dq(0);
format_section_end(image, ".data");

format_pe_import_section(image, ".idata", imports);

format_entry_mut(image, start)
format_finish(image);

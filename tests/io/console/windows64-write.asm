import("format/format.inc");
import("io/windows.inc");
x86.use64();

const message_text: string = "XIRASM Windows console"
const message_length: u64 = len(message_text) + 1

let imports: map = pe_import_new()
imports = io_windows64_imports(imports)
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
        format_section(".idata", format_imports | format_readable | format_writeable)
    )
)
format_begin(image);

format_section_begin(image, ".text");
start:
    io_write_stdout_label("message", message_length);
    cmp rax, message_length
    jne failed
    test rdx, rdx
    jne failed

    io_write_stderr_label("message", message_length);
    cmp rax, message_length
    jne failed
    test rdx, rdx
    jne failed

    test_exit(0);
failed:
    test_exit(1);
format_section_end(image, ".text");

format_section_begin(image, ".rdata");
message:
    db(message_text, 10);
format_section_end(image, ".rdata");

format_pe_import_section(image, ".idata", imports);

format_entry_mut(image, start)
format_finish(image);

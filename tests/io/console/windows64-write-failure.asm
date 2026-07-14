import("format/format.inc");
import("io/windows.inc");
x86.use64();

const message_text: string = "failure probe"
const message_length: u64 = len(message_text)

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
        format_section(".rdata", format_data | format_readable),
        format_section(".idata", format_imports | format_readable | format_writeable)
    )
)
format_begin(image0);

format_section_begin(image0, ".text");
start:
    mov rcx, -1
    lea rsi, [rel message]
    mov rdx, message_length
    io_windows64_write_handle();
    cmp rax, -1
    jne failed
    test rdx, rdx
    jz failed
    test_exit(0);
failed:
    test_exit(1);
format_section_end(image0, ".text");

format_section_begin(image0, ".rdata");
message:
    db(message_text);
format_section_end(image0, ".rdata");

format_pe_import_section(image0, ".idata", imports);

const image: map = format_entry(image0, start)
format_finish(image);

import("../../../include/format/pe64.inc");
import("../../../include/format/pe_import.inc");

struct NaturalFrame {
    tag: u8,
    value: u32,
    tail: u16,
}

packed struct PackedFrame {
    tag: u8,
    value: u32,
    tail: u16,
}

packed struct Point {
    x: u16,
    y: u32,
}

packed struct NestedFrame {
    tag: u8,
    point: Point,
    tail: u8,
}

assert(sizeof(NaturalFrame) == 12);
assert(offset_of(NaturalFrame, value) == 4);
assert(offset_of(NaturalFrame, tail) == 8);
assert(sizeof(PackedFrame) == 7);
assert(offset_of(PackedFrame, value) == 1);
assert(offset_of(PackedFrame, tail) == 5);
assert(sizeof(NestedFrame) == 8);
assert(offset_of(NestedFrame, point.y) == 3);

const imports0: map = pe_import_new()
const imports: map = pe_import_use64(imports0, "KERNEL32.DLL", "ExitProcess")

const text_rva: u64 = pe_section_rva(0, pe_default_section_align)
const text_raw: u64 = pe_section_raw_ptr(0, pe_default_file_align)
const idata_rva: u64 = pe_section_rva(1, pe_default_section_align)
const idata_raw: u64 = pe_section_raw_ptr(1, pe_default_file_align)

pe64_exe(2);

pe64_section(".text", 0);
text_start:
start:
    sub rsp, sizeof(NaturalFrame)
    mov dword [rsp + offset_of(NaturalFrame, value)], 0x44332211
    mov word [rsp + offset_of(NaturalFrame, tail)], 0x6655
    mov eax, [rsp + offset_of(NaturalFrame, value)]
    movzx edx, word [rsp + offset_of(NaturalFrame, tail)]
    add rsp, sizeof(NaturalFrame)
    cmp eax, 0x44332211
    jne failed
    cmp edx, 0x6655
    jne failed

    sub rsp, sizeof(PackedFrame)
    mov dword [rsp + offset_of(PackedFrame, value)], 0x88776655
    mov word [rsp + offset_of(PackedFrame, tail)], 0xaa99
    mov eax, [rsp + offset_of(PackedFrame, value)]
    movzx edx, word [rsp + offset_of(PackedFrame, tail)]
    add rsp, sizeof(PackedFrame)
    cmp eax, 0x88776655
    jne failed
    cmp edx, 0xaa99
    jne failed

    sub rsp, sizeof(NestedFrame)
    mov dword [rsp + offset_of(NestedFrame, point.y)], 0xddccbbaa
    mov eax, [rsp + offset_of(NestedFrame, point.y)]
    add rsp, sizeof(NestedFrame)
    cmp eax, 0xddccbbaa
    jne failed

    xor ecx, ecx
    jmp exit_process

failed:
    mov ecx, 1

exit_process:
    sub rsp, 40
call_exitprocess:
db(0xff, 0x15);
dd(0);
text_end:
pe64_end_section(0);

pe64_section(".idata", 1);
idata_start:
pe_import_emit64(imports, idata_rva, idata_start);
idata_end:
pe64_end_section(1);

pe64_finish_text(0, start, text_start, text_end, pe_text_chars);
pe64_finish_import_section(1, idata_start, idata_end);
pe_finalize_u32(call_exitprocess + 2, ExitProcess - (call_exitprocess + 6));

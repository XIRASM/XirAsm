import("format/format.inc");

// AArch64 ELF64 relocatable object through the format.inc facade. The A64
// words below are placeholders whose fixup fields the relocations patch; the
// AArch64 relocation type numbers come from elf_const.inc.

let object: map = format_elfobj64_aarch64(
    list.of(
        format_section(".text", format_code | format_readable | format_executable),
        format_section(".data", format_data | format_readable | format_writeable)
    )
)
format_begin(object);

format_section_begin(object, ".text");
text_start:
_start:
call_site:
    emit.u32(0x94000000);
page_site:
    emit.u32(0x90000000);
lo12_site:
    emit.u32(0x91000000);
    emit.u32(0xd65f03c0);
format_section_end(object, ".text");

format_section_begin(object, ".data");
data_start:
answer:
    emit.u64(42);
ptr_slot:
    emit.u64(0);
format_section_end(object, ".data");

const symbols: list = list.of(
    format_elfobj_public("_start", ".text", text_start, _start, 16, elfobj_stt_func),
    format_elfobj_public("answer", ".data", data_start, answer, 8, elfobj_stt_object),
    format_elfobj_extern("printf", elfobj_stt_func)
)
const relocs: list = list.of(
    format_elfobj_reloc(".text", text_start, call_site, "printf", elf_r_aarch64_call26, 0),
    format_elfobj_reloc(".text", text_start, page_site, "answer", elf_r_aarch64_adr_prel_pg_hi21, 0),
    format_elfobj_reloc(".text", text_start, lo12_site, "answer", elf_r_aarch64_add_abs_lo12_nc, 0),
    format_elfobj_reloc(".data", data_start, ptr_slot, "printf", elf_r_aarch64_abs64, 0)
)
format_elfobj_tables_mut(object, symbols, relocs)
format_finish(object);

defer {
    assert(load.u16(18) == elf_machine_aarch64);
    // nlist index = 1 + 2 sections + user index: printf is 5, answer is 4.
    assert(load.u32(96) == 0);
    assert(load.u64(104) == 5 * 0x100000000 + elf_r_aarch64_call26);
    assert(load.u32(120) == 4);
    assert(load.u64(128) == 4 * 0x100000000 + elf_r_aarch64_adr_prel_pg_hi21);
    assert(load.u64(176) == 5 * 0x100000000 + elf_r_aarch64_abs64);
}

// AArch64 COFF object through the format.inc user layer. The machine field and
// the relocation types come from the plan, so an AArch64 object is described
// the same way as the x86-64 one. The A64 words below are placeholders whose
// fixup fields the relocations patch.
import("format/format.inc");

let object: map = format_coff64_arm64(
    list.of(
        format_section(".text", format_code | format_readable | format_executable),
        format_section(".data", format_data | format_readable | format_writeable)
    )
)
format_begin(object);

format_section_begin(object, ".text");
text_start:
caller:
    emit.u32(0x94000000);
page_site:
    emit.u32(0x90000000);
lo12_site:
    emit.u32(0xf9400000);
    emit.u32(0xd65f03c0);
format_section_end(object, ".text");

format_section_begin(object, ".data");
data_start:
answer:
    dq(42);
ptr_slot:
    dq(0);
format_section_end(object, ".data");

const symbols: list = list.of(
    format_coff_public("caller", ".text", text_start, caller, coff_sym_type_function),
    format_coff_public("answer", ".data", data_start, answer, coff_sym_type_null),
    format_coff_extern("ext_fn", coff_sym_type_function),
    format_coff_extern("ext_data", coff_sym_type_null)
)
const relocs: list = list.of(
    format_coff_reloc(".text", text_start, caller, "ext_fn", coff_rel_arm64_branch26),
    format_coff_reloc(".text", text_start, page_site, "ext_data", coff_rel_arm64_pagebase_rel21),
    format_coff_reloc(".text", text_start, lo12_site, "ext_data", coff_rel_arm64_pageoffset_12l),
    format_coff_reloc(".data", data_start, ptr_slot, "ext_data", coff_rel_arm64_addr64)
)
format_coff_tables_mut(object, symbols, relocs)
format_finish(object);

assert(file_cursor_real() == 248, "AArch64 COFF object size drifted");

defer {
    assert(load.u16(region_base()) == coff_machine_arm64);
    assert(load.u16(region_base() + 2) == 2);
    assert(load.u32(region_base() + 12) == 4);
    assert(load.u16(region_base() + coff_section_row_foa(0) + coff_sec_reloc_count_foa) == 3);
    assert(load.u16(region_base() + coff_section_row_foa(1) + coff_sec_reloc_count_foa) == 1);
    assert(load.u32(region_base() + coff_section_row_foa(0) + coff_sec_raw_size_foa) == 16);
}

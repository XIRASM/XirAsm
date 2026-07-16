// api-matrix-fixture: pe_finalize_reloc_dir64(
// api-matrix-fixture: pe64_finish_reloc_section(
// api-matrix-fixture: pe_reloc_new(
// api-matrix-fixture: pe_reloc_add_highlow(
// api-matrix-fixture: pe_reloc_add_dir64(
// api-matrix-fixture: pe_reloc_add_dir64_at(
// api-matrix-fixture: pe_reloc_add(
// api-matrix-fixture: pe_reloc_rva(
// api-matrix-fixture: pe_reloc_block_size(
// api-matrix-fixture: pe_reloc_emit_block(

import("../../include/format/pe64.inc");
import("../../include/format/pe_reloc.inc");

const text_rva: u64 = pe_section_rva(0, pe_default_section_align)
const reloc_rva: u64 = pe_section_rva(1, pe_default_section_align)

pe64_dll(2);

pe64_section(".text", 0);
text_start:
dll_main:
    mov eax, 1
    ret
abs_ptr:
    dq(dll_main);
text_end:
pe64_end_section(0);

const pointer_rva: u64 = pe_reloc_rva(text_rva, abs_ptr, text_start)
let relocs: list = pe_reloc_new()
relocs = pe_reloc_add_dir64_at(relocs, text_rva, abs_ptr, text_start)

pe64_section(".reloc", 1);
reloc_start:
pe_reloc_emit_block(relocs, text_rva);
reloc_end:
pe64_end_section(1);

pe64_finish_text(0, dll_main, text_start, text_end, pe_text_chars);
pe64_finish_reloc_section(1, reloc_start, reloc_end);

defer {

    assert(load.u32(region_base() + pe_dir_rva_foa(pe_dir_basereloc)) == reloc_rva);
    assert(load.u32(region_base() + pe_dir_size_foa(pe_dir_basereloc)) == pe_reloc_block_size(1));
    assert(load.u32(pe_reloc_block) == text_rva);
    assert(load.u32(pe_reloc_block + 4) == pe_reloc_block_size(1));
    assert(load.u16(pe_reloc_block + 8) == pe_reloc_dir64 * 0x1000 + (pointer_rva - text_rva));
    assert(load.u16(pe_reloc_block + 10) == pe_reloc_absolute);
}

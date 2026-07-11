import("../../include/format/pe32.inc");
import("../../include/format/pe_reloc.inc");

x86.use32();

const text_rva: u64 = pe_section_rva(0, pe_default_section_align)

pe32_dll(2);

pe32_section(".text", 0);
text_start:
dll_main:
    mov eax, 1
    ret
abs_ptr0:
    dd(0);
abs_ptr1:
    dd(0);
    rb(pe_reloc_page_size - (abs_ptr1 - text_start) - 4);
abs_ptr2:
    dd(0);
text_end:
pe32_end_section(0);

const pointer0_rva: u64 = pe_reloc_rva(text_rva, abs_ptr0, text_start)
const pointer1_rva: u64 = pe_reloc_rva(text_rva, abs_ptr1, text_start)
const pointer2_rva: u64 = pe_reloc_rva(text_rva, abs_ptr2, text_start)
const relocs0: list = pe_reloc_new()
const relocs1: list = pe_reloc_add_highlow_at(relocs0, text_rva, abs_ptr0, text_start)
const relocs2: list = pe_reloc_add_highlow_at(relocs1, text_rva, abs_ptr1, text_start)
const relocs3: list = pe_reloc_add_highlow_at(relocs2, text_rva, abs_ptr2, text_start)

pe32_section(".reloc", 1);
reloc_start:
const reloc_rva: u64 = reloc_start - pe_default_image_base32
assert(pe_reloc_page_entry_count_sorted_from(relocs3, 0, pe_reloc_page_rva(pointer0_rva), 0) == 2);
assert(pe_reloc_page_entry_count_sorted_from(relocs3, 2, pe_reloc_page_rva(pointer2_rva), 0) == 1);
pe_reloc_assert_sorted(relocs3);
pe_reloc_emit_grouped_sorted(relocs3);
reloc_end:
pe32_end_section(1);

pe32_finish_text(0, dll_main, text_start, text_end, pe_text_chars);
pe32_finish_reloc_section(1, reloc_start, reloc_end);

defer {

    store.u32(abs_ptr0, dll_main);
    store.u32(abs_ptr1, abs_ptr0);
    store.u32(abs_ptr2, abs_ptr1);
    assert(load.u32(abs_ptr0) == dll_main);
    assert(load.u32(abs_ptr1) == abs_ptr0);
    assert(load.u32(abs_ptr2) == abs_ptr1);
    assert(load.u16(region_base() + pe_opt_dll_chars_foa) == pe_dll_dynamic_base | pe_dll_nx_compat);
    assert(text_rva + (abs_ptr0 - text_start) == pointer0_rva);
    assert(text_rva + (abs_ptr1 - text_start) == pointer1_rva);
    assert(text_rva + (abs_ptr2 - text_start) == pointer2_rva);
    assert(load.u32(region_base() + pe_dir32_rva_foa(pe_dir_basereloc)) == reloc_rva);
    assert(load.u32(region_base() + pe_dir32_size_foa(pe_dir_basereloc)) == pe_reloc_block_size(2) + pe_reloc_block_size(1));
    assert(load.u32(pe_reloc_grouped_start) == pe_reloc_page_rva(pointer0_rva));
    assert(load.u32(pe_reloc_grouped_start + 4) == pe_reloc_block_size(2));
    assert(load.u16(pe_reloc_grouped_start + 8) == pe_reloc_type_offset(pointer0_rva, pe_reloc_highlow));
    assert(load.u16(pe_reloc_grouped_start + 10) == pe_reloc_type_offset(pointer1_rva, pe_reloc_highlow));
    assert(load.u32(pe_reloc_grouped_start + pe_reloc_block_size(2)) == pe_reloc_page_rva(pointer2_rva));
    assert(load.u32(pe_reloc_grouped_start + pe_reloc_block_size(2) + 4) == pe_reloc_block_size(1));
    assert(load.u16(pe_reloc_grouped_start + pe_reloc_block_size(2) + 8) == pe_reloc_type_offset(pointer2_rva, pe_reloc_highlow));
    assert(load.u16(pe_reloc_grouped_start + pe_reloc_block_size(2) + 10) == pe_reloc_absolute);
    assert(pe_reloc_grouped_end - pe_reloc_grouped_start == pe_reloc_block_size(2) + pe_reloc_block_size(1));
}

// api-matrix-fixture: elfobj_begin64_deferred(
// api-matrix-fixture: elfobj_patch_header64(
// api-matrix-fixture: elfobj_begin32_deferred(
// api-matrix-fixture: elfobj_patch_header32(
// api-matrix-fixture: late_layout {

import("../../include/format/elfobj.inc");

const section_count: u16 = 5
const shstrndx: u16 = 4
const symbol_count: u64 = 3

const text_index: u64 = 1
const rela_text_index: u64 = 2
const symtab_index: u64 = 3

const sh_name_text: u64 = 1
const sh_name_rela_text: u64 = 7
const sh_name_symtab: u64 = 18
const sh_name_shstrtab: u64 = 26
const str_name_start: u64 = 1

const text_foa: u64 = elfobj_align_up(elfobj_header64_size, 16)
const text_raw_size: u64 = 8
const rela_text_foa: u64 = 72
const rela_text_size: u64 = elfobj_rela64_size
const symtab_foa: u64 = 96
const symtab_size: u64 = symbol_count * elfobj_sym64_size
const shstrtab_foa: u64 = 168
const shstrtab_size: u64 = 36
const section_table_foa: u64 = 208

elfobj_begin64_deferred();

elfobj_begin_section(".text", text_foa);
text_start:
_start:
    db(0xe8);
rel_call_site:
    dd(0);
    ret
text_end:
elfobj_end_section(text_raw_size);
reserve(16);

virtual.begin(0);
rela_scratch:
elfobj_rela64_x86_64_pc32_at(text_start, rel_call_site, 2, 0xfffffffffffffffc);
rela_scratch_end:
virtual.end();

virtual.begin(0);
symtab_scratch:
elfobj_sym64(0, 0, elf_shn_undef, 0, 0);
elfobj_sym64(0, elfobj_st_info(elfobj_stb_local, elfobj_stt_section), text_index, 0, 0);
elfobj_sym64(str_name_start, elfobj_st_info(elfobj_stb_global, elfobj_stt_func), text_index, _start - text_start, text_end - _start);
virtual.end();

virtual.begin(0);
shstrtab_scratch:
db(0, ".text", 0, ".rela.text", 0, ".symtab", 0, ".shstrtab", 0);
virtual.end();

virtual.begin(0);
shdr_scratch:
elfobj_shdr64(0, elf_sht_null, 0, 0, 0, 0, 0, 0, 0);
elfobj_shdr64(sh_name_text, elf_sht_progbits, elf_shf_alloc | elf_shf_execinstr, text_foa, text_raw_size, 0, 0, 16, 0);
elfobj_shdr64(sh_name_rela_text, elf_sht_rela, 0, 0, rela_text_size, symtab_index, text_index, 8, elfobj_rela64_size);
elfobj_shdr64(sh_name_symtab, elf_sht_symtab, 0, 0, symtab_size, 0, 2, 8, elfobj_sym64_size);
elfobj_shdr64(sh_name_shstrtab, elf_sht_strtab, 0, 0, shstrtab_size, 0, 0, 1, 0);
virtual.end();

elfobj_patch_header64(section_table_foa, section_count, shstrndx);

late_layout {
    region.begin(".rela.text", 0, rela_text_foa);
    store.u64(shdr_scratch + elfobj64_shdr_foa(0, rela_text_index) + elfobj64_sh_offset_foa, rela_text_foa);
    emit.bytes(load.bytes(rela_scratch, rela_text_size));

    align(8);
    region.begin(".symtab", 0, symtab_foa);
    store.u64(shdr_scratch + elfobj64_shdr_foa(0, symtab_index) + elfobj64_sh_offset_foa, symtab_foa);
    emit.bytes(load.bytes(symtab_scratch, symtab_size));

    region.begin(".shstrtab", 0, shstrtab_foa);
    store.u64(shdr_scratch + elfobj64_shdr_foa(0, shstrndx) + elfobj64_sh_offset_foa, shstrtab_foa);
    emit.bytes(load.bytes(shstrtab_scratch, shstrtab_size));

    align(8);
    region.begin(".shdr", 0, section_table_foa);
    emit.bytes(load.bytes(shdr_scratch, section_count * elfobj_shdr64_size));
}

defer {
    assert(elfobj64_rela_count(rela_scratch, rela_scratch_end) == rela_text_size / elfobj_rela64_size);
}

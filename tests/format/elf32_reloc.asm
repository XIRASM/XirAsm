// api-matrix-fixture: elfobj_reloc_offset(
// api-matrix-fixture: elfobj_r_info32(
// api-matrix-fixture: elfobj32_shdr_foa(
// api-matrix-fixture: elfobj32_rel_foa(
// api-matrix-fixture: elfobj32_rel_count(
// api-matrix-fixture: elfobj_rel32(
// api-matrix-fixture: elfobj_rel32_at(
// api-matrix-fixture: elfobj_rel32_386_32_at(
// api-matrix-fixture: elfobj_rel32_386_pc32_at(
import("../../include/format/elfobj.inc");

x86.use32();

const section_count: u16 = 9
const shstrndx: u16 = 7
const symbol_count: u64 = 7

const text_index: u64 = 1
const data_index: u64 = 2
const bss_index: u64 = 3
const rel_text_index: u64 = 4
const symtab_index: u64 = 5
const strtab_index: u64 = 6
const first_global_symbol_index: u64 = 4
const helper_symbol_index: u64 = 6

const sh_name_text: u64 = 1
const sh_name_data: u64 = 7
const sh_name_bss: u64 = 13
const sh_name_rel_text: u64 = 18
const sh_name_symtab: u64 = 28
const sh_name_strtab: u64 = 36
const sh_name_shstrtab: u64 = 44
const sh_name_gnu_stack: u64 = 54

const str_name_start: u64 = 1
const str_name_scratch: u64 = 8
const str_name_helper: u64 = 16
const strtab_size: u64 = 23
const shstrtab_size: u64 = 70

const text_foa: u64 = elfobj_align_up(elfobj_header32_size, 16)
const text_size: u64 = 36
const data_foa: u64 = elfobj_align_up(text_foa + text_size, 4)
const data_size: u64 = 4
const bss_foa: u64 = data_foa + data_size
const bss_size: u64 = 64
const rel_text_foa: u64 = elfobj_align_up(bss_foa, 4)
const rel_text_size: u64 = 4 * elfobj_rel32_size
const symtab_foa: u64 = elfobj_align_up(rel_text_foa + rel_text_size, 4)
const symtab_size: u64 = symbol_count * elfobj_sym32_size
const strtab_foa: u64 = symtab_foa + symtab_size
const shstrtab_foa: u64 = strtab_foa + strtab_size
const section_table_foa: u64 = elfobj_align_up(shstrtab_foa + shstrtab_size, 4)

elfobj_begin32(section_count, section_table_foa, shstrndx);

elfobj_begin_section(".text", text_foa);
text_start:
_start:
    db(0xff, 0x35);
rel_data:
    dd(0);
    db(0xe8);
rel_helper:
    dd(0xfffffffc);
    db(0x83, 0xc4, 4);
    db(0xa3);
rel_scratch_store:
    dd(0);
    db(0xa1);
rel_scratch_load:
    dd(0);
    db(0x83, 0xe8, 42);
    db(0x89, 0xc3);
    mov eax, 1
    int 0x80
text_end:
elfobj_end_section(text_size);

elfobj_begin_section(".data", data_foa);
data_start:
    dd(41);
data_end:
elfobj_end_section(data_size);

region.begin(".bss", 0, bss_foa);
bss_start:
scratch:
    reserve(bss_size);
bss_end:
region.file_align(1);

region.begin(".rel.text", rel_text_foa, rel_text_foa);
rel_start:
elfobj_rel32_386_32_at(text_start, rel_data, data_index);
elfobj_rel32_386_pc32_at(text_start, rel_helper, helper_symbol_index);
elfobj_rel32_386_32_at(text_start, rel_scratch_store, bss_index);
elfobj_rel32_386_32_at(text_start, rel_scratch_load, bss_index);
rel_end:

region.begin(".symtab", symtab_foa, symtab_foa);
elfobj_sym32(0, 0, elf_shn_undef, 0, 0);
elfobj_sym32(0, elfobj_st_info(elfobj_stb_local, elfobj_stt_section), text_index, 0, 0);
elfobj_sym32(0, elfobj_st_info(elfobj_stb_local, elfobj_stt_section), data_index, 0, 0);
elfobj_sym32(0, elfobj_st_info(elfobj_stb_local, elfobj_stt_section), bss_index, 0, 0);
elfobj_sym32(str_name_start, elfobj_st_info(elfobj_stb_global, elfobj_stt_func), text_index, 0, text_size);
elfobj_sym32(str_name_scratch, elfobj_st_info(elfobj_stb_global, elfobj_stt_object), bss_index, 0, bss_size);
elfobj_sym32(str_name_helper, elfobj_st_info(elfobj_stb_global, elfobj_stt_func), elf_shn_undef, 0, 0);

region.begin(".strtab", strtab_foa, strtab_foa);
db(0, "_start", 0, "scratch", 0, "helper", 0);

region.begin(".shstrtab", shstrtab_foa, shstrtab_foa);
db(
    0,
    ".text", 0,
    ".data", 0,
    ".bss", 0,
    ".rel.text", 0,
    ".symtab", 0,
    ".strtab", 0,
    ".shstrtab", 0,
    ".note.GNU-stack", 0
);

region.begin(".shdr", section_table_foa, section_table_foa);
elfobj_shdr32(0, elf_sht_null, 0, 0, 0, 0, 0, 0, 0);
elfobj_shdr32(sh_name_text, elf_sht_progbits, elf_shf_alloc | elf_shf_execinstr, text_foa, text_size, 0, 0, 16, 0);
elfobj_shdr32(sh_name_data, elf_sht_progbits, elf_shf_alloc | elf_shf_write, data_foa, data_size, 0, 0, 4, 0);
elfobj_shdr32(sh_name_bss, elf_sht_nobits, elf_shf_alloc | elf_shf_write, bss_foa, bss_size, 0, 0, 4, 0);
elfobj_shdr32(sh_name_rel_text, elf_sht_rel, 0, rel_text_foa, rel_text_size, symtab_index, text_index, 4, elfobj_rel32_size);
elfobj_shdr32(
    sh_name_symtab,
    elf_sht_symtab,
    0,
    symtab_foa,
    symtab_size,
    strtab_index,
    first_global_symbol_index,
    4,
    elfobj_sym32_size
);
elfobj_shdr32(sh_name_strtab, elf_sht_strtab, 0, strtab_foa, strtab_size, 0, 0, 1, 0);
elfobj_shdr32(sh_name_shstrtab, elf_sht_strtab, 0, shstrtab_foa, shstrtab_size, 0, 0, 1, 0);
elfobj_shdr32(sh_name_gnu_stack, elf_sht_progbits, 0, 0, 0, 0, 0, 1, 0);

defer {
    assert(load.u16(region_base() + 16) == elf_type_rel);
    assert(load.u16(region_base() + 18) == elf_machine_386);
    assert(load.u32(region_base() + elfobj32_shoff_foa) == section_table_foa);
    assert(load.u16(region_base() + elfobj32_shnum_foa) == section_count);
    assert(region_file_size(bss_start) == 0);
    assert(bss_end - bss_start == bss_size);
    assert(elfobj_r_info32(6, 2) == 0x602);
    assert(elfobj32_shdr_foa(section_table_foa, 1) == section_table_foa + elfobj_shdr32_size);
    assert(elfobj32_rel_foa(rel_text_foa, 1) == rel_text_foa + elfobj_rel32_size);
    assert(elfobj32_rel_count(rel_start, rel_end) == 4);
}

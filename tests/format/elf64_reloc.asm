// api-matrix-fixture: elfobj64_rela_count(
// api-matrix-fixture: elfobj_r_info64(
// api-matrix-fixture: elfobj64_rela_foa(
// api-matrix-fixture: elfobj_rela64(
// api-matrix-fixture: elfobj_rela64_at(
// api-matrix-fixture: elfobj_rela64_x86_64_64_at(
// api-matrix-fixture: elfobj_rela64_x86_64_pc32_at(
// api-matrix-fixture: elfobj_rela64_x86_64_plt32_at(
// api-matrix-fixture: elfobj_rela64_x86_64_gotpcrel_at(
// api-matrix-fixture: elfobj_rela64_x86_64_32_at(
// api-matrix-fixture: elfobj_rela64_x86_64_32s_at(
import("../../include/format/elfobj.inc");

const section_count: u16 = 9
const shstrndx: u16 = 7
const symbol_count: u64 = 7

const text_index: u64 = 1
const data_index: u64 = 2
const bss_index: u64 = 3
const rela_text_index: u64 = 4
const symtab_index: u64 = 5
const strtab_index: u64 = 6
const first_global_symbol_index: u64 = 4
const helper_symbol_index: u64 = 6

const sh_name_text: u64 = 1
const sh_name_data: u64 = 7
const sh_name_bss: u64 = 13
const sh_name_rela_text: u64 = 18
const sh_name_symtab: u64 = 29
const sh_name_strtab: u64 = 37
const sh_name_shstrtab: u64 = 45
const sh_name_gnu_stack: u64 = 55

const str_name_start: u64 = 1
const str_name_scratch: u64 = 8
const str_name_helper: u64 = 16
const strtab_size: u64 = 23
const shstrtab_size: u64 = 71

const text_foa: u64 = elfobj_align_up(elfobj_header64_size, 16)
const text_size: u64 = 35
const data_foa: u64 = elfobj_align_up(text_foa + text_size, 4)
const data_size: u64 = 4
const bss_foa: u64 = data_foa + data_size
const bss_size: u64 = 64
const rela_text_foa: u64 = elfobj_align_up(bss_foa, 8)
const rela_text_size: u64 = 4 * elfobj_rela64_size
const symtab_foa: u64 = elfobj_align_up(rela_text_foa + rela_text_size, 8)
const symtab_size: u64 = symbol_count * elfobj_sym64_size
const strtab_foa: u64 = symtab_foa + symtab_size
const shstrtab_foa: u64 = strtab_foa + strtab_size
const section_table_foa: u64 = elfobj_align_up(shstrtab_foa + shstrtab_size, 8)

elfobj_begin64(section_count, section_table_foa, shstrndx);

elfobj_begin_section(".text", text_foa);
text_start:
_start:
    db(0x8b, 0x3d);
rel_data:
    dd(0);
    db(0xe8);
rel_helper:
    dd(0);
    db(0x89, 0x05);
rel_scratch_store:
    dd(0);
    db(0x8b, 0x05);
rel_scratch_load:
    dd(0);
    db(0x83, 0xe8, 42);
    db(0x89, 0xc7);
    mov eax, 60
    syscall
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

region.begin(".rela.text", rela_text_foa, rela_text_foa);
rela_start:
elfobj_rela64_x86_64_pc32_at(text_start, rel_data, data_index, 0xfffffffffffffffc);
elfobj_rela64_x86_64_plt32_at(
    text_start,
    rel_helper,
    helper_symbol_index,
    0xfffffffffffffffc
);
elfobj_rela64_x86_64_pc32_at(text_start, rel_scratch_store, bss_index, 0xfffffffffffffffc);
elfobj_rela64_x86_64_pc32_at(text_start, rel_scratch_load, bss_index, 0xfffffffffffffffc);
rela_end:

region.begin(".symtab", symtab_foa, symtab_foa);
elfobj_sym64(0, 0, elf_shn_undef, 0, 0);
elfobj_sym64(0, elfobj_st_info(elfobj_stb_local, elfobj_stt_section), text_index, 0, 0);
elfobj_sym64(0, elfobj_st_info(elfobj_stb_local, elfobj_stt_section), data_index, 0, 0);
elfobj_sym64(0, elfobj_st_info(elfobj_stb_local, elfobj_stt_section), bss_index, 0, 0);
elfobj_sym64(str_name_start, elfobj_st_info(elfobj_stb_global, elfobj_stt_func), text_index, 0, text_size);
elfobj_sym64(str_name_scratch, elfobj_st_info(elfobj_stb_global, elfobj_stt_object), bss_index, 0, bss_size);
elfobj_sym64(str_name_helper, elfobj_st_info(elfobj_stb_global, elfobj_stt_func), elf_shn_undef, 0, 0);

region.begin(".strtab", strtab_foa, strtab_foa);
db(0, "_start", 0, "scratch", 0, "helper", 0);

region.begin(".shstrtab", shstrtab_foa, shstrtab_foa);
db(
    0,
    ".text", 0,
    ".data", 0,
    ".bss", 0,
    ".rela.text", 0,
    ".symtab", 0,
    ".strtab", 0,
    ".shstrtab", 0,
    ".note.GNU-stack", 0
);

region.begin(".shdr", section_table_foa, section_table_foa);
elfobj_shdr64(0, elf_sht_null, 0, 0, 0, 0, 0, 0, 0);
elfobj_shdr64(sh_name_text, elf_sht_progbits, elf_shf_alloc | elf_shf_execinstr, text_foa, text_size, 0, 0, 16, 0);
elfobj_shdr64(sh_name_data, elf_sht_progbits, elf_shf_alloc | elf_shf_write, data_foa, data_size, 0, 0, 4, 0);
elfobj_shdr64(sh_name_bss, elf_sht_nobits, elf_shf_alloc | elf_shf_write, bss_foa, bss_size, 0, 0, 4, 0);
elfobj_shdr64(sh_name_rela_text, elf_sht_rela, 0, rela_text_foa, rela_text_size, symtab_index, text_index, 8, elfobj_rela64_size);
elfobj_shdr64(
    sh_name_symtab,
    elf_sht_symtab,
    0,
    symtab_foa,
    symtab_size,
    strtab_index,
    first_global_symbol_index,
    8,
    elfobj_sym64_size
);
elfobj_shdr64(sh_name_strtab, elf_sht_strtab, 0, strtab_foa, strtab_size, 0, 0, 1, 0);
elfobj_shdr64(sh_name_shstrtab, elf_sht_strtab, 0, shstrtab_foa, shstrtab_size, 0, 0, 1, 0);
elfobj_shdr64(sh_name_gnu_stack, elf_sht_progbits, 0, 0, 0, 0, 0, 1, 0);

defer {
    assert(load.u16(region_base() + 16) == elf_type_rel);
    assert(load.u16(region_base() + 18) == elf_machine_x86_64);
    assert(load.u64(region_base() + elfobj64_shoff_foa) == section_table_foa);
    assert(load.u16(region_base() + elfobj64_shnum_foa) == section_count);
    assert(region_file_size(bss_start) == 0);
    assert(bss_end - bss_start == bss_size);
    assert(elfobj_r_info64(6, 4) == 0x600000004);
    assert(elfobj64_rela_foa(rela_text_foa, 1) == rela_text_foa + elfobj_rela64_size);
    assert(elfobj64_rela_count(rela_start, rela_end) == 4);
}

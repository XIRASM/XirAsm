// api-matrix-fixture: elfso_finalize_phdr64(
// api-matrix-fixture: elf_export_new(
// api-matrix-fixture: elf_export_use64(
// api-matrix-fixture: elf_export_use64_many(
// api-matrix-fixture: elf_export_use64_pairs(
// api-matrix-fixture: elf_export_emit_dynsym64(
// api-matrix-fixture: elf_export_emit_dynstr64(
// api-matrix-fixture: elf_export_emit_dynamic64(
// api-matrix-fixture: elf_export_hash(
// api-matrix-fixture: elf_export_hash_size(
// api-matrix-fixture: elf_export_dynstr_size(
// api-matrix-fixture: elf_export_names_size(
// api-matrix-fixture: elfso_dyn64(
// api-matrix-fixture: elfso_hash_one(

import("../../include/format/elf_export.inc");

const ph_count: u16 = 3
const section_count: u16 = 7
const shstrndx: u16 = 6

const text_index: u64 = 1
const dynsym_index: u64 = 2
const dynstr_index: u64 = 3
const hash_index: u64 = 4
const dynamic_index: u64 = 5

const sh_name_text: u64 = 1
const sh_name_dynsym: u64 = 7
const sh_name_dynstr: u64 = 15
const sh_name_hash: u64 = 23
const sh_name_dynamic: u64 = 29
const sh_name_shstrtab: u64 = 38

const text_foa: u64 = elfso_align_up(elfso_header64_size + ph_count * elfso_phdr64_size, 16)
const export_size: u64 = 4
const text_size: u64 = export_size * 2
let exports: list = elf_export_new()
exports = elf_export_use64_many(exports, list.of("x_add7", "x_sub3"), text_index, export_size)

const soname: string = "libxirasm_so.so"
const dynstr_first_export: u64 = 1
const dynstr_soname: u64 = dynstr_first_export + elf_export_names_size(exports)
const dynstr_size: u64 = elf_export_dynstr_size(exports, soname)
const shstrtab_size: u64 = 48

const dynsym_foa: u64 = elfso_align_up(text_foa + text_size, 8)
const metadata_foa: u64 = dynsym_foa
const metadata_vaddr: u64 = elfso_align_up(text_foa + text_size, elf_default_page_align) + metadata_foa % elf_default_page_align
const dynsym_size: u64 = (len(exports) + 1) * elfso_sym64_size
const dynstr_foa: u64 = dynsym_foa + dynsym_size
const hash_foa: u64 = elfso_align_up(dynstr_foa + dynstr_size, 4)
const hash_size: u64 = elf_export_hash_size(exports)
const dynamic_foa: u64 = elfso_align_up(hash_foa + hash_size, 8)
const dynamic_size: u64 = 7 * elfso_dyn64_size
const shstrtab_foa: u64 = dynamic_foa + dynamic_size
const section_table_foa: u64 = elfso_align_up(shstrtab_foa + shstrtab_size, 8)
const file_size: u64 = section_table_foa + section_count * elfso_shdr64_size
const dynsym_vaddr: u64 = metadata_vaddr + dynsym_foa - metadata_foa
const dynstr_vaddr: u64 = metadata_vaddr + dynstr_foa - metadata_foa
const hash_vaddr: u64 = metadata_vaddr + hash_foa - metadata_foa
const dynamic_vaddr: u64 = metadata_vaddr + dynamic_foa - metadata_foa
const metadata_size: u64 = dynamic_foa + dynamic_size - metadata_foa

virtual.begin(0);
elfso_phdr64(elf_pt_null, 0, 0, 0, 0, 0, 0);
virtual.end();

elfso_begin64(ph_count, section_table_foa, section_count, shstrndx);

elfso_begin_region(".text", text_foa);
text_start:
x_add7:
    db(0x8d, 0x47, 0x07, 0xc3);
x_sub3:
    db(0x8d, 0x47, 0xfd, 0xc3);
text_end:
elfso_end_region(text_size);

region.begin(".metadata", metadata_vaddr, metadata_foa);
assert(file_cursor_real() == dynsym_foa);
elf_export_emit_dynsym64(exports, dynstr_first_export);

assert(file_cursor_real() == dynstr_foa);
elf_export_emit_dynstr64(exports, soname);

align(4);
assert(file_cursor_real() == hash_foa);
elf_export_hash(exports);

align(8);
assert(file_cursor_real() == dynamic_foa);
elf_export_emit_dynamic64(dynstr_vaddr, dynstr_size, dynsym_vaddr, hash_vaddr, dynstr_soname);

assert(file_cursor_real() == shstrtab_foa);
db(0, ".text", 0, ".dynsym", 0, ".dynstr", 0, ".hash", 0, ".dynamic", 0, ".shstrtab", 0);

align(8);
assert(file_cursor_real() == section_table_foa);
elfso_shdr64(0, elf_sht_null, 0, 0, 0, 0, 0, 0, 0, 0);
elfso_shdr64(sh_name_text, elf_sht_progbits, elf_shf_alloc | elf_shf_execinstr, text_foa, text_foa, text_end - text_start, 0, 0, 16, 0);
elfso_shdr64(sh_name_dynsym, elf_sht_dynsym, elf_shf_alloc, dynsym_vaddr, dynsym_foa, dynsym_size, dynstr_index, 1, 8, elfso_sym64_size);
elfso_shdr64(sh_name_dynstr, elf_sht_strtab, elf_shf_alloc, dynstr_vaddr, dynstr_foa, dynstr_size, 0, 0, 1, 0);
elfso_shdr64(sh_name_hash, elf_sht_hash, elf_shf_alloc, hash_vaddr, hash_foa, hash_size, dynsym_index, 0, 4, 4);
elfso_shdr64(sh_name_dynamic, elf_sht_dynamic, elf_shf_alloc | elf_shf_write, dynamic_vaddr, dynamic_foa, dynamic_size, dynstr_index, 0, 8, elfso_dyn64_size);
elfso_shdr64(sh_name_shstrtab, elf_sht_strtab, 0, 0, shstrtab_foa, shstrtab_size, 0, 0, 1, 0);
region.file_align(1);

elfso_finalize_load64(0, 0, 0, text_foa + text_size, text_foa + text_size, elf_pf_r | elf_pf_x);
elfso_finalize_load64(1, metadata_foa, metadata_vaddr, metadata_size, metadata_size, elf_pf_r | elf_pf_w);
elfso_finalize_phdr64(2, elf_pt_dynamic, elf_pf_r | elf_pf_w, dynamic_foa, dynamic_vaddr, dynamic_size, dynamic_size, 8);

defer {

    assert(load.u16(region_base() + 16) == elf_type_dyn);
    assert(load.u16(region_base() + 18) == elf_machine_x86_64);
    assert(load.u64(region_base() + elfso64_shoff_foa) == section_table_foa);
    assert(load.u16(region_base() + elfso64_shnum_foa) == section_count);
    assert(load.u32(region_base() + elfso64_phdr_foa(2) + elfso64_phdr_type_foa) == elf_pt_dynamic);
    assert(elfso64_shdr_foa(section_table_foa, dynamic_index) == section_table_foa + dynamic_index * elfso_shdr64_size);
    assert(load.u64(elfso64_dyn_foa(dynamic_vaddr, 0)) == elf_dt_hash);
    assert(load.u64(elfso64_dyn_foa(dynamic_vaddr, 0) + 8) == hash_vaddr);
    assert(load.u32(region_base() + text_foa) == 0xc307478d);
}

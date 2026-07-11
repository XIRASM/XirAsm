// api-matrix-fixture: elfso_finalize_load64(
// api-matrix-fixture: elfso_finalize_dynamic64(
// api-matrix-fixture: elfso_import_new(
// api-matrix-fixture: elfso_import_use64(
// api-matrix-fixture: elfso_import_use64_as(
// api-matrix-fixture: elfso_import_use64_plt(
// api-matrix-fixture: elfso_import_use64_plt_as(
// api-matrix-fixture: elfso_import_r_info64(
// api-matrix-fixture: elfso_import_rela64(
// api-matrix-fixture: elfso_import_rel32(
// api-matrix-fixture: elfso_import_plt_size(
// api-matrix-fixture: elfso_import_gotplt_size(
// api-matrix-fixture: elfso_import_rela_plt_size(
// api-matrix-fixture: elfso_import_dynamic_plt_size(
// api-matrix-fixture: elfso_import_emit_slots64(
// api-matrix-fixture: elfso_import_emit_plt64(
// api-matrix-fixture: elfso_import_emit_gotplt64(
// api-matrix-fixture: elfso_import_emit_dynstr64(
// api-matrix-fixture: elfso_import_emit_dynsym64(
// api-matrix-fixture: elfso_import_emit_rela64(
// api-matrix-fixture: elfso_import_emit_rela_plt64(
// api-matrix-fixture: elfso_import_emit_dynamic64(
// api-matrix-fixture: elfso_import_emit_dynamic64_plt(
// api-matrix-fixture: elfso_import_hash(
// api-matrix-fixture: elfso_import_hash_size(
// api-matrix-fixture: elfso_import_dynstr_size(
// api-matrix-fixture: elfso_import_names_size(
// api-matrix-fixture: elfso_import_libraries(

import("../../include/format/elfso_import.inc");

const imports0: list = elfso_import_new()
const imports_unused: list = elfso_import_use64(imports0, "libc.so.6", "exit")
const imports1: list = elfso_import_use64_plt_as(imports0, "libc.so.6", "puts", "puts_gotplt", "puts_plt")

const soname: string = "libxirasm_import.so"

const ph_count: u16 = 4
const section_count: u16 = 10
const shstrndx: u16 = 9

const text_index: u64 = 1
const plt_index: u64 = 2
const gotplt_index: u64 = 3
const dynsym_index: u64 = 4
const dynstr_index: u64 = 5
const hash_index: u64 = 6
const rela_plt_index: u64 = 7
const dynamic_index: u64 = 8

const sh_name_text: u64 = 1
const sh_name_plt: u64 = 7
const sh_name_gotplt: u64 = 12
const sh_name_dynsym: u64 = 21
const sh_name_dynstr: u64 = 29
const sh_name_hash: u64 = 37
const sh_name_rela_plt: u64 = 43
const sh_name_dynamic: u64 = 53
const sh_name_shstrtab: u64 = 62

const import_count: u64 = len(imports1)
const first_import_symbol: u64 = 1
const exported_call_puts_symbol: u64 = first_import_symbol + import_count
const exported_call_puts_name: string = "exported_call_puts"

const text_foa: u64 = elfso_align_up(elfso_header64_size + ph_count * elfso_phdr64_size, 16)
const text_size: u64 = 32
const plt_foa: u64 = elfso_align_up(text_foa + text_size, 16)
const plt_size: u64 = elfso_import_plt_size(imports1)
const gotplt_foa: u64 = elfso_align_up(plt_foa + plt_size, 8)
const gotplt_size: u64 = elfso_import_gotplt_size(imports1)
const dynsym_foa: u64 = elfso_align_up(gotplt_foa + gotplt_size, 8)
const dynsym_size: u64 = (1 + import_count + 1) * elfso_sym64_size
const dynstr_foa: u64 = dynsym_foa + dynsym_size
const dynstr_size: u64 = elfso_import_dynstr_size(imports1, soname) + len(exported_call_puts_name) + 1
const hash_foa: u64 = elfso_align_up(dynstr_foa + dynstr_size, 4)
const hash_size: u64 = 24
const rela_plt_foa: u64 = elfso_align_up(hash_foa + hash_size, 8)
const rela_plt_size: u64 = elfso_import_rela_plt_size(imports1)
const dynamic_foa: u64 = elfso_align_up(rela_plt_foa + rela_plt_size, 8)
const dynamic_size: u64 = elfso_import_dynamic_plt_size(imports1)
const shstrtab_foa: u64 = dynamic_foa + dynamic_size
const shstrtab_size: u64 = 72
const section_table_foa: u64 = elfso_align_up(shstrtab_foa + shstrtab_size, 8)
const file_size: u64 = section_table_foa + section_count * elfso_shdr64_size
const plt_vaddr: u64 = elfso_align_up(text_foa + text_size, elf_default_page_align) + plt_foa % elf_default_page_align
const metadata_foa: u64 = gotplt_foa
const metadata_vaddr: u64 = elfso_align_up(plt_vaddr + plt_size, elf_default_page_align) + metadata_foa % elf_default_page_align
const gotplt_vaddr: u64 = metadata_vaddr
const dynsym_vaddr: u64 = metadata_vaddr + dynsym_foa - metadata_foa
const dynstr_vaddr: u64 = metadata_vaddr + dynstr_foa - metadata_foa
const hash_vaddr: u64 = metadata_vaddr + hash_foa - metadata_foa
const rela_plt_vaddr: u64 = metadata_vaddr + rela_plt_foa - metadata_foa
const dynamic_vaddr: u64 = metadata_vaddr + dynamic_foa - metadata_foa
const metadata_size: u64 = dynamic_foa + dynamic_size - metadata_foa

const dynstr_name_start: u64 = 1
const dynstr_exported_call_puts: u64 = dynstr_name_start + elfso_import_names_size(imports1)
const dynstr_soname: u64 = dynstr_exported_call_puts + len(exported_call_puts_name) + 1
const dynstr_needed_start: u64 = dynstr_soname + len(soname) + 1

virtual.begin(0);
elfso_phdr64(elf_pt_null, 0, 0, 0, 0, 0, 0);
virtual.end();

elfso_begin64(ph_count, section_table_foa, section_count, shstrndx);

elfso_begin_region(".text", text_foa);
exported_call_puts:
    lea rdi, [rel message_text]
    call puts_plt
    ret
message_text:
    db("xirasm import slot", 0);
elfso_end_region(text_size);

region.begin(".plt", plt_vaddr, plt_foa);
elfso_import_emit_plt64(imports1, plt_vaddr, gotplt_vaddr);
region.file_align(1);

region.begin(".metadata", metadata_vaddr, metadata_foa);
elfso_import_emit_gotplt64(imports1, dynamic_vaddr, plt_vaddr);

align(8);
assert(file_cursor_real() == dynsym_foa);
elfso_import_emit_dynsym64(imports1, dynstr_name_start);
elfso_sym64(dynstr_exported_call_puts, elfso_st_info(elf_stb_global, elf_stt_func), text_index, exported_call_puts, text_size);

assert(file_cursor_real() == dynstr_foa);
db(0, "puts", 0, exported_call_puts_name, 0, soname, 0, "libc.so.6", 0);

align(4);
assert(file_cursor_real() == hash_foa);
dd(1);
dd(exported_call_puts_symbol + 1);
dd(first_import_symbol);
dd(0);
dd(exported_call_puts_symbol);
dd(0);

align(8);
assert(file_cursor_real() == rela_plt_foa);
elfso_import_emit_rela_plt64(imports1, first_import_symbol);

assert(file_cursor_real() == dynamic_foa);
elfso_import_emit_dynamic64_plt(imports1, dynstr_vaddr, dynstr_size, dynsym_vaddr, hash_vaddr, gotplt_vaddr, rela_plt_vaddr, rela_plt_size, dynstr_needed_start);

assert(file_cursor_real() == shstrtab_foa);
db(0, ".text", 0, ".plt", 0, ".got.plt", 0, ".dynsym", 0, ".dynstr", 0, ".hash", 0, ".rela.plt", 0, ".dynamic", 0, ".shstrtab", 0);

align(8);
assert(file_cursor_real() == section_table_foa);
elfso_shdr64(0, elf_sht_null, 0, 0, 0, 0, 0, 0, 0, 0);
elfso_shdr64(sh_name_text, elf_sht_progbits, elf_shf_alloc | elf_shf_execinstr, text_foa, text_foa, text_size, 0, 0, 16, 0);
elfso_shdr64(sh_name_plt, elf_sht_progbits, elf_shf_alloc | elf_shf_execinstr, plt_vaddr, plt_foa, plt_size, 0, 0, 16, elfso_import_plt_entry_size);
elfso_shdr64(sh_name_gotplt, elf_sht_progbits, elf_shf_alloc | elf_shf_write, gotplt_vaddr, gotplt_foa, gotplt_size, 0, 0, 8, elfso_import_gotplt_entry_size);
elfso_shdr64(sh_name_dynsym, elf_sht_dynsym, elf_shf_alloc, dynsym_vaddr, dynsym_foa, dynsym_size, dynstr_index, first_import_symbol, 8, elfso_sym64_size);
elfso_shdr64(sh_name_dynstr, elf_sht_strtab, elf_shf_alloc, dynstr_vaddr, dynstr_foa, dynstr_size, 0, 0, 1, 0);
elfso_shdr64(sh_name_hash, elf_sht_hash, elf_shf_alloc, hash_vaddr, hash_foa, hash_size, dynsym_index, 0, 4, 4);
elfso_shdr64(sh_name_rela_plt, elf_sht_rela, elf_shf_alloc, rela_plt_vaddr, rela_plt_foa, rela_plt_size, dynsym_index, 0, 8, elfso_import_rela64_size);
elfso_shdr64(sh_name_dynamic, elf_sht_dynamic, elf_shf_alloc | elf_shf_write, dynamic_vaddr, dynamic_foa, dynamic_size, dynstr_index, 0, 8, elfso_dyn64_size);
elfso_shdr64(sh_name_shstrtab, elf_sht_strtab, 0, 0, shstrtab_foa, shstrtab_size, 0, 0, 1, 0);
region.file_align(1);

elfso_finalize_load64(0, 0, 0, text_foa + text_size, text_foa + text_size, elf_pf_r | elf_pf_x);
elfso_finalize_load64(1, plt_foa, plt_vaddr, plt_size, plt_size, elf_pf_r | elf_pf_x);
elfso_finalize_load64(2, metadata_foa, metadata_vaddr, metadata_size, metadata_size, elf_pf_r | elf_pf_w);
elfso_finalize_phdr64(3, elf_pt_dynamic, elf_pf_r | elf_pf_w, dynamic_foa, dynamic_vaddr, dynamic_size, dynamic_size, 8);

defer {

    assert(load.u16(region_base() + 16) == elf_type_dyn);
    assert(load.u64(region_base() + elfso64_shoff_foa) == section_table_foa);
    assert(load.u64(elfso64_dyn_foa(dynamic_vaddr, 0)) == elf_dt_hash);
    assert(load.u64(elfso64_dyn_foa(dynamic_vaddr, 5)) == elf_dt_pltgot);
    assert(load.u64(elfso64_dyn_foa(dynamic_vaddr, 8)) == elf_dt_jmprel);
    assert(load.u64(elfso64_dyn_foa(dynamic_vaddr, 9)) == elf_dt_needed);
    assert(load.u32(text_foa + 3) == 6);
    assert(load.u32(text_foa + 8) == plt_vaddr + elfso_import_plt0_size - (text_foa + 12));
}

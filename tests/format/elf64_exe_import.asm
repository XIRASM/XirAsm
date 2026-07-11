// api-matrix-fixture: elfexe_finalize_entry64(
// api-matrix-fixture: elfexe_finalize_phdr64(
// api-matrix-fixture: elfexe_import_new(
// api-matrix-fixture: elfexe_import_use64(
// api-matrix-fixture: elfexe_import_use64_as(
// api-matrix-fixture: elfexe_import_r_info64(
// api-matrix-fixture: elfexe_import_rela64(
// api-matrix-fixture: elfexe_import_dyn64(
// api-matrix-fixture: elfexe_import_sym64(
// api-matrix-fixture: elfexe_import_st_info(
// api-matrix-fixture: elfexe_import_emit_slots64(
// api-matrix-fixture: elfexe_import_emit_dynstr64(
// api-matrix-fixture: elfexe_import_emit_dynsym64(
// api-matrix-fixture: elfexe_import_emit_rela64(
// api-matrix-fixture: elfexe_import_emit_dynamic64(
// api-matrix-fixture: elfexe_import_hash(
// api-matrix-fixture: elfexe_import_hash_size(
// api-matrix-fixture: elfexe_import_dynstr_size(
// api-matrix-fixture: elfexe_import_names_size(
// api-matrix-fixture: elfexe_import_libraries(

import("../../include/format/elfexe_import.inc");

const imports0: list = elfexe_import_new()
const imports_unused: list = elfexe_import_use64(imports0, "libc.so.6", "exit")
const imports1: list = elfexe_import_use64_as(imports0, "libc.so.6", "getpid", "getpid_slot")

const ph_count: u16 = 4
const first_import_symbol: u64 = 1
const import_count: u64 = len(imports1)

const text_foa: u64 = 0x1000
const text_vaddr: u64 = elf_segment_vaddr(elf_default_base64, text_foa)
const data_foa: u64 = 0x2000
const data_vaddr: u64 = elf_segment_vaddr(elf_default_base64, data_foa)
const interp_foa: u64 = data_foa + 0x100
const interp_vaddr: u64 = elf_segment_vaddr(elf_default_base64, interp_foa)
const dynsym_foa: u64 = data_foa + 0x140
const dynsym_vaddr: u64 = elf_segment_vaddr(elf_default_base64, dynsym_foa)
const dynsym_size: u64 = (1 + import_count) * elfexe_import_sym64_size
const dynstr_foa: u64 = dynsym_foa + dynsym_size
const dynstr_vaddr: u64 = elf_segment_vaddr(elf_default_base64, dynstr_foa)
const dynstr_size: u64 = elfexe_import_dynstr_size(imports1)
const hash_foa: u64 = elfexe_align_up(dynstr_foa + dynstr_size, 4)
const hash_vaddr: u64 = elf_segment_vaddr(elf_default_base64, hash_foa)
const hash_size: u64 = elfexe_import_hash_size(imports1)
const rela_foa: u64 = elfexe_align_up(hash_foa + hash_size, 8)
const rela_vaddr: u64 = elf_segment_vaddr(elf_default_base64, rela_foa)
const rela_size: u64 = import_count * elfexe_import_rela64_size
const dynamic_foa: u64 = elfexe_align_up(rela_foa + rela_size, 8)
const dynamic_vaddr: u64 = elf_segment_vaddr(elf_default_base64, dynamic_foa)
const dynamic_size: u64 = (8 + len(elfexe_import_libraries(imports1)) + 1) * elfexe_import_dyn64_size
const ro_end_foa: u64 = dynamic_foa + dynamic_size
const data_size: u64 = elfexe_align_up(ro_end_foa - data_foa, 0x100)

const dynstr_name_start: u64 = 1
const dynstr_needed_start: u64 = dynstr_name_start + elfexe_import_names_size(imports1)

elfexe_begin64(ph_count);

elfexe_begin_segment64(".text", text_foa);
text_start:
start:
    call [rel getpid_slot]
    xor edi, edi
    mov eax, 60
    syscall
text_end:
elfexe_end_segment(0x100);

elfexe_begin_segment64(".data", data_foa);
data_start:
elfexe_import_emit_slots64(imports1);

pad_to(interp_foa - data_foa, 0);
interp_start:
db(elfexe_import_default_interp64, 0);
interp_end:

pad_to(dynsym_foa - data_foa, 0);
dynsym_start:
elfexe_import_emit_dynsym64(imports1, dynstr_name_start);

pad_to(dynstr_foa - data_foa, 0);
dynstr_start:
elfexe_import_emit_dynstr64(imports1);

pad_to(hash_foa - data_foa, 0);
hash_start:
elfexe_import_hash(imports1);

pad_to(rela_foa - data_foa, 0);
rela_start:
elfexe_import_emit_rela64(imports1, first_import_symbol);

pad_to(dynamic_foa - data_foa, 0);
dynamic_start:
elfexe_import_emit_dynamic64(imports1, dynstr_vaddr, dynstr_size, dynsym_vaddr, hash_vaddr, rela_vaddr, rela_size, dynstr_needed_start);

data_end:
elfexe_end_segment(data_size);

elfexe_finalize_entry64(start, text_start, text_vaddr);
elfexe_finalize_phdr64(0, elf_pt_load, elf_pf_r | elf_pf_x, 0, elf_default_base64, text_foa + (text_end - text_start), text_foa + (text_end - text_start), elf_default_page_align);
elfexe_finalize_phdr64(1, elf_pt_load, elf_pf_r | elf_pf_w, data_foa, data_vaddr, data_size, data_size, elf_default_page_align);
elfexe_finalize_phdr64(2, elf_pt_interp, elf_pf_r, interp_foa, interp_vaddr, interp_end - interp_start, interp_end - interp_start, 1);
elfexe_finalize_phdr64(3, elf_pt_dynamic, elf_pf_r | elf_pf_w, dynamic_foa, dynamic_vaddr, dynamic_size, dynamic_size, 8);

defer {

    assert(load.u16(region_base() + 16) == elf_type_exec);
    assert(load.u16(region_base() + elf64_phnum_foa) == ph_count);
    assert(load.u64(region_base() + elf64_entry_foa) == text_vaddr + (start - text_start));
    assert(load.u32(region_base() + elf64_phdr_foa(2) + elf64_phdr_type_foa) == elf_pt_interp);
    assert(load.u32(region_base() + elf64_phdr_foa(3) + elf64_phdr_type_foa) == elf_pt_dynamic);
    assert(load.u64(dynamic_start) == elf_dt_hash);
    assert(load.u64(dynamic_start + 5 * elfexe_import_dyn64_size) == elf_dt_rela);
    assert(load.u64(dynamic_start + 8 * elfexe_import_dyn64_size) == elf_dt_needed);
    assert(load.u64(rela_start) == getpid_slot);
    assert(load.u64(rela_start + 8) == elfexe_import_r_info64(first_import_symbol, elf_r_x86_64_64));
    assert(load.u32(dynsym_start + elfexe_import_sym64_size) == dynstr_name_start);
    assert(load.u32(start + 2) == getpid_slot - (start + 6));
}

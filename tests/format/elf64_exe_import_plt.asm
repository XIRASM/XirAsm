// api-matrix-fixture: elfexe_import_use64_plt(
// api-matrix-fixture: elfexe_import_use64_plt_as(
// api-matrix-fixture: elfexe_import_use64_plt_many(
// api-matrix-fixture: elfexe_import_use64_plt_pairs(
// api-matrix-fixture: elfexe_import_rel32(
// api-matrix-fixture: elfexe_import_plt_size(
// api-matrix-fixture: elfexe_import_gotplt_size(
// api-matrix-fixture: elfexe_import_rela_plt_size(
// api-matrix-fixture: elfexe_import_dynamic_plt_size(
// api-matrix-fixture: elfexe_import_emit_plt64(
// api-matrix-fixture: elfexe_import_emit_gotplt64(
// api-matrix-fixture: elfexe_import_emit_rela_plt64(
// api-matrix-fixture: elfexe_import_emit_dynamic64_plt(

import("../../include/format/elfexe_import.inc");

const base_imports: list = elfexe_import_new()
const imports_unused: list = elfexe_import_use64_plt(base_imports, "libc.so.6", "exit")
const imports: list = elfexe_import_use64_plt_pairs(base_imports, "libc.so.6", list.of("getpid", "getpid"))

const ph_count: u16 = 4
const first_import_symbol: u64 = 1
const import_count: u64 = len(imports)

const text_foa: u64 = 0x1000
const text_vaddr: u64 = elf_segment_vaddr(elf_default_base64, text_foa)
const plt_foa: u64 = 0x1100
const plt_vaddr: u64 = elf_segment_vaddr(elf_default_base64, plt_foa)
const data_foa: u64 = 0x2000
const data_vaddr: u64 = elf_segment_vaddr(elf_default_base64, data_foa)
const gotplt_foa: u64 = data_foa
const gotplt_vaddr: u64 = elf_segment_vaddr(elf_default_base64, gotplt_foa)
const interp_foa: u64 = data_foa + 0x100
const interp_vaddr: u64 = elf_segment_vaddr(elf_default_base64, interp_foa)
const dynsym_foa: u64 = data_foa + 0x140
const dynsym_vaddr: u64 = elf_segment_vaddr(elf_default_base64, dynsym_foa)
const dynsym_size: u64 = (1 + import_count) * elfexe_import_sym64_size
const dynstr_foa: u64 = dynsym_foa + dynsym_size
const dynstr_vaddr: u64 = elf_segment_vaddr(elf_default_base64, dynstr_foa)
const dynstr_size: u64 = elfexe_import_dynstr_size(imports)
const hash_foa: u64 = elfexe_align_up(dynstr_foa + dynstr_size, 4)
const hash_vaddr: u64 = elf_segment_vaddr(elf_default_base64, hash_foa)
const hash_size: u64 = elfexe_import_hash_size(imports)
const rela_plt_foa: u64 = elfexe_align_up(hash_foa + hash_size, 8)
const rela_plt_vaddr: u64 = elf_segment_vaddr(elf_default_base64, rela_plt_foa)
const rela_plt_size: u64 = elfexe_import_rela_plt_size(imports)
const dynamic_foa: u64 = elfexe_align_up(rela_plt_foa + rela_plt_size, 8)
const dynamic_vaddr: u64 = elf_segment_vaddr(elf_default_base64, dynamic_foa)
const dynamic_size: u64 = elfexe_import_dynamic_plt_size(imports)
const ro_end_foa: u64 = dynamic_foa + dynamic_size
const data_size: u64 = elfexe_align_up(ro_end_foa - data_foa, 0x100)
const gotplt_size: u64 = elfexe_import_gotplt_size(imports)
const plt_size: u64 = elfexe_import_plt_size(imports)

const dynstr_name_start: u64 = 1
const dynstr_needed_start: u64 = dynstr_name_start + elfexe_import_names_size(imports)

elfexe_begin64(ph_count);

elfexe_begin_segment64(".text", text_foa);
text_start:
start:
    call getpid_plt
    xor edi, edi
    mov eax, 60
    syscall
text_end:
elfexe_end_segment(0x100);

elfexe_begin_segment64(".plt", plt_foa);
plt_start:
elfexe_import_emit_plt64(imports, plt_vaddr, gotplt_vaddr);
plt_end:
elfexe_end_segment(0x100);

elfexe_begin_segment64(".data", data_foa);
data_start:
elfexe_import_emit_gotplt64(imports, dynamic_vaddr, plt_vaddr);

pad_to(interp_foa - data_foa, 0);
interp_start:
db(elfexe_import_default_interp64, 0);
interp_end:

pad_to(dynsym_foa - data_foa, 0);
dynsym_start:
elfexe_import_emit_dynsym64(imports, dynstr_name_start);

pad_to(dynstr_foa - data_foa, 0);
dynstr_start:
elfexe_import_emit_dynstr64(imports);

pad_to(hash_foa - data_foa, 0);
hash_start:
elfexe_import_hash(imports);

pad_to(rela_plt_foa - data_foa, 0);
rela_plt_start:
elfexe_import_emit_rela_plt64(imports, first_import_symbol);

pad_to(dynamic_foa - data_foa, 0);
dynamic_start:
elfexe_import_emit_dynamic64_plt(imports, dynstr_vaddr, dynstr_size, dynsym_vaddr, hash_vaddr, gotplt_vaddr, rela_plt_vaddr, rela_plt_size, dynstr_needed_start);

data_end:
elfexe_end_segment(data_size);

elfexe_finalize_entry64(start, text_start, text_vaddr);
elfexe_finalize_phdr64(0, elf_pt_load, elf_pf_r | elf_pf_x, 0, elf_default_base64, plt_foa + (plt_end - plt_start), plt_foa + (plt_end - plt_start), elf_default_page_align);
elfexe_finalize_phdr64(1, elf_pt_load, elf_pf_r | elf_pf_w, data_foa, data_vaddr, data_size, data_size, elf_default_page_align);
elfexe_finalize_phdr64(2, elf_pt_interp, elf_pf_r, interp_foa, interp_vaddr, interp_end - interp_start, interp_end - interp_start, 1);
elfexe_finalize_phdr64(3, elf_pt_dynamic, elf_pf_r | elf_pf_w, dynamic_foa, dynamic_vaddr, dynamic_size, dynamic_size, 8);

defer {

    assert(plt_size == elfexe_import_plt_size(imports));
    assert(gotplt_size == elfexe_import_gotplt_size(imports));
    assert(rela_plt_size == elfexe_import_rela_plt_size(imports));
    assert(dynamic_size == elfexe_import_dynamic_plt_size(imports));
    assert(elfexe_import_rel32(getpid_plt, start + 5) == getpid_plt - (start + 5));
    assert(load.u16(region_base() + 16) == elf_type_exec);
    assert(load.u16(region_base() + elf64_phnum_foa) == ph_count);
    assert(load.u64(region_base() + elf64_entry_foa) == text_vaddr + (start - text_start));
    assert(load.u32(region_base() + elf64_phdr_foa(2) + elf64_phdr_type_foa) == elf_pt_interp);
    assert(load.u32(region_base() + elf64_phdr_foa(3) + elf64_phdr_type_foa) == elf_pt_dynamic);
    assert(load.u64(dynamic_start) == elf_dt_hash);
    assert(load.u64(dynamic_start + 5 * elfexe_import_dyn64_size) == elf_dt_pltgot);
    assert(load.u64(dynamic_start + 8 * elfexe_import_dyn64_size) == elf_dt_jmprel);
    assert(load.u64(dynamic_start + 9 * elfexe_import_dyn64_size) == elf_dt_needed);
    assert(load.u64(rela_plt_start) == getpid_gotplt);
    assert(load.u64(rela_plt_start + 8) == elfexe_import_r_info64(first_import_symbol, elf_r_x86_64_jump_slot));
    assert(load.u64(getpid_gotplt) == getpid_plt + 6);
    assert(load.u32(start + 1) == getpid_plt - (start + 5));
}

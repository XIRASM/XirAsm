// Width-specific AMD64 COFF object compatibility include.
//
// This include remains as a source-level compatibility layer over coff.inc.

import("coff.inc");

const coff_r: u32 = coff_scn_mem_read
const coff_w: u32 = coff_scn_mem_write
const coff_x: u32 = coff_scn_mem_execute
const coff_rx: u32 = coff_scn_cnt_code | coff_r | coff_x | coff_scn_align_16bytes
const coff_rw: u32 = coff_scn_cnt_init_data | coff_r | coff_w | coff_scn_align_4bytes
const coff_ro: u32 = coff_scn_cnt_init_data | coff_r | coff_scn_align_4bytes

fn coff64_obj_raw(section_count: u16, symbol_table_foa: u64, symbol_count: u64) {
    coff_begin64(section_count, symbol_table_foa, symbol_count);
}

fn coff64_obj(section_count: u16, symbol_count: u64) {
    coff_begin64(section_count, 0, symbol_count);
}

fn coff64_section_raw(name: string, raw_ptr: u64) {
    coff_begin_section(name, raw_ptr);
}

fn coff64_section(name: string) {
    coff_begin_section_auto(name);
}

fn coff64_end_section_raw(raw_size: u64) {
    coff_end_section(raw_size);
}

fn coff64_end_section() {
    coff_align_section_file();
}

fn coff64_symbols() {
    coff_begin_symbols(".symtab");
}

fn coff64_finish_section_raw(row: u64, name0: u64, raw_size: u64, raw_ptr: u64, chars: u64) {
    coff_finalize_section(row, name0, raw_size, raw_ptr, chars);
}

fn coff64_finish_section(row: u64, name0: u64, start: u64, chars: u64) {
    coff_finalize_section_auto(row, name0, start, chars);
}

fn coff64_finish_section_reloc(row: u64, name0: u64, start: u64, reloc_ptr: u64, reloc_count: u64, chars: u64) {
    coff_finalize_section_reloc_auto(row, name0, start, reloc_ptr, reloc_count, chars);
}

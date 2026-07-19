// Width-specific ELF32 format compatibility include.
//
// This file provides short executable entry points. It delegates raw record
// emission and final backfill to elfexe.inc.

import("elfexe.inc");

const elf32_r: u32 = elf_pf_r
const elf32_w: u32 = elf_pf_w
const elf32_x: u32 = elf_pf_x
const elf32_rx: u32 = elf_pf_r | elf_pf_x
const elf32_rw: u32 = elf_pf_r | elf_pf_w
const elf32_rwx: u32 = elf_pf_r | elf_pf_w | elf_pf_x

fn elf32_exe(segment_count: u16) {
    elfexe_begin32(segment_count);
}

fn elf32_first_foa(segment_count: u64) -> u64 {
    return elf32_first_segment_foa(segment_count);
}

fn elf32_vaddr(file_offset: u64) -> u64 {
    return elf_segment_vaddr(elf_default_base32, file_offset);
}

fn elf32_segment_raw(name: string, file_offset: u64) {
    elfexe_begin_segment32(name, file_offset);
}

fn elf32_segment(name: string) {
    elfexe_begin_segment32_auto(name);
}

fn elf32_end_segment_raw(raw_size: u64) {
    elfexe_end_segment(raw_size);
}

fn elf32_end_segment() {
    elfexe_align_segment_file();
}

fn elf32_finish_load_raw(row: u64, entry_label: u64, file_offset: u64, start: u64, end: u64, flags: u64) {
    const vaddr: u64 = elf32_vaddr(file_offset)
    elfexe_finalize_entry32(entry_label, start, vaddr);
    elfexe_finalize_load32(row, file_offset, vaddr, start, end, flags);
}

fn elf32_finish_load(row: u64, entry_label: u64, start: u64, flags: u64) {
    elfexe_finalize_load32_auto(row, entry_label, start, flags);
}

fn elf32_finish_note(row: u64, start: u64, flags: u64) {
    elfexe_finalize_region32(row, elf_pt_note, start, flags);
}

fn elf32_finish_gnu_stack(row: u64, file_offset: u64, flags: u64) {
    elfexe_finalize_phdr32(row, elf_pt_gnu_stack, flags, file_offset, elf32_vaddr(file_offset), 0, 0, 1);
}

fn elf32_finish_gnu_eh_frame(row: u64, start: u64, flags: u64) {
    elfexe_finalize_region32(row, elf_pt_gnu_eh_frame, start, flags);
}

fn elf32_finish_gnu_relro(row: u64, start: u64, flags: u64) {
    elfexe_finalize_region32(row, elf_pt_gnu_relro, start, flags);
}

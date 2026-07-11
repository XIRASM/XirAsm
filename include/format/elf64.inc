// User-facing ELF64 format facade.
//
// This file provides short executable entry points. It delegates raw record
// emission and final backfill to elfexe.inc.

import("elfexe.inc");

const elf_r: u32 = elf_pf_r
const elf_w: u32 = elf_pf_w
const elf_x: u32 = elf_pf_x
const elf_rx: u32 = elf_pf_r | elf_pf_x
const elf_rw: u32 = elf_pf_r | elf_pf_w
const elf_rwx: u32 = elf_pf_r | elf_pf_w | elf_pf_x

fn elf64_exe(segment_count: u16) {
    elfexe_begin64(segment_count);
}

fn elf64_pie(segment_count: u16) {
    elfexe_begin64_at(segment_count, elf_type_dyn, 0);
}

fn elf64_first_foa(segment_count: u64) -> u64 {
    return elf64_first_segment_foa(segment_count);
}

fn elf64_pie_first_foa(segment_count: u64) -> u64 {
    return elf64_first_segment_foa(segment_count);
}

fn elf64_vaddr(file_offset: u64) -> u64 {
    return elf_segment_vaddr(elf_default_base64, file_offset);
}

fn elf64_pie_vaddr(file_offset: u64) -> u64 {
    return elf_segment_vaddr(0, file_offset);
}

fn elf64_segment_raw(name: string, file_offset: u64) {
    elfexe_begin_segment64(name, file_offset);
}

fn elf64_pie_segment_raw(name: string, file_offset: u64) {
    elfexe_begin_segment64_at(name, file_offset, 0);
}

fn elf64_segment(name: string) {
    elfexe_begin_segment64_auto(name);
}

fn elf64_pie_segment(name: string) {
    elfexe_begin_segment64_auto_at(name, 0);
}

fn elf64_end_segment_raw(raw_size: u64) {
    elfexe_end_segment(raw_size);
}

fn elf64_pie_end_segment_raw(raw_size: u64) {
    elfexe_end_segment(raw_size);
}

fn elf64_end_segment() {
    elfexe_align_segment_file();
}

fn elf64_pie_end_segment() {
    elfexe_align_segment_file();
}

fn elf64_finish_load_raw(row: u64, entry_label: u64, file_offset: u64, start: u64, end: u64, flags: u64) {
    const vaddr: u64 = elf64_vaddr(file_offset)
    elfexe_finalize_entry64(entry_label, start, vaddr);
    elfexe_finalize_load64(row, file_offset, vaddr, start, end, flags);
}

fn elf64_pie_finish_load_raw(row: u64, entry_label: u64, file_offset: u64, start: u64, end: u64, flags: u64) {
    const vaddr: u64 = elf64_pie_vaddr(file_offset)
    elfexe_finalize_entry64(entry_label, start, vaddr);
    elfexe_finalize_load64(row, file_offset, vaddr, start, end, flags);
}

fn elf64_finish_load(row: u64, entry_label: u64, start: u64, flags: u64) {
    elfexe_finalize_load64_auto(row, entry_label, start, flags);
}

fn elf64_pie_finish_load(row: u64, entry_label: u64, start: u64, flags: u64) {
    elfexe_finalize_load64_auto_at(row, entry_label, start, flags, 0);
}

fn elf64_finish_note(row: u64, start: u64, flags: u64) {
    elfexe_finalize_region64(row, elf_pt_note, start, flags);
}

fn elf64_pie_finish_note(row: u64, start: u64, flags: u64) {
    elfexe_finalize_region64_at(row, elf_pt_note, start, flags, 0);
}

fn elf64_finish_gnu_stack(row: u64, file_offset: u64, flags: u64) {
    elfexe_finalize_phdr64(row, elf_pt_gnu_stack, flags, file_offset, elf64_vaddr(file_offset), 0, 0, 1);
}

fn elf64_pie_finish_gnu_stack(row: u64, file_offset: u64, flags: u64) {
    elfexe_finalize_phdr64(row, elf_pt_gnu_stack, flags, file_offset, elf64_pie_vaddr(file_offset), 0, 0, 1);
}

fn elf64_finish_gnu_eh_frame(row: u64, start: u64, flags: u64) {
    elfexe_finalize_region64(row, elf_pt_gnu_eh_frame, start, flags);
}

fn elf64_pie_finish_gnu_eh_frame(row: u64, start: u64, flags: u64) {
    elfexe_finalize_region64_at(row, elf_pt_gnu_eh_frame, start, flags, 0);
}

fn elf64_finish_gnu_relro(row: u64, start: u64, flags: u64) {
    elfexe_finalize_region64(row, elf_pt_gnu_relro, start, flags);
}

fn elf64_pie_finish_gnu_relro(row: u64, start: u64, flags: u64) {
    elfexe_finalize_region64_at(row, elf_pt_gnu_relro, start, flags, 0);
}

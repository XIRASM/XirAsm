// ELF executable helpers for XIRASM.
//
// Design boundary:
// - This file provides explicit ELF32/ELF64 executable header helpers.
// - It provides explicit field layout and constants without hidden
//   section/symbol/relocation state.
// - Users choose file offsets, virtual addresses, and sizes explicitly.
// - `elfexe_finalize_*` helpers own the deferred PHDR/entry backfill, matching
//   XIRASM's logical-region model.

import("elf_const.inc");

const elf_ident_size: u64 = 16
const elf_header64_size: u64 = 64
const elf_header32_size: u64 = 52
const elf_phdr64_size: u64 = 56
const elf_phdr32_size: u64 = 32
const elf_shdr64_size: u64 = 64
const elf_shdr32_size: u64 = 40

const elf64_entry_foa: u64 = 24
const elf64_phoff_foa: u64 = 32
const elf64_shoff_foa: u64 = 40
const elf64_ehsize_foa: u64 = 52
const elf64_phentsize_foa: u64 = 54
const elf64_phnum_foa: u64 = 56
const elf64_shentsize_foa: u64 = 58
const elf64_shnum_foa: u64 = 60
const elf64_shstrndx_foa: u64 = 62

const elf32_entry_foa: u64 = 24
const elf32_phoff_foa: u64 = 28
const elf32_shoff_foa: u64 = 32
const elf32_ehsize_foa: u64 = 40
const elf32_phentsize_foa: u64 = 42
const elf32_phnum_foa: u64 = 44
const elf32_shentsize_foa: u64 = 46
const elf32_shnum_foa: u64 = 48
const elf32_shstrndx_foa: u64 = 50

const elf64_phdr_type_foa: u64 = 0
const elf64_phdr_flags_foa: u64 = 4
const elf64_phdr_offset_foa: u64 = 8
const elf64_phdr_vaddr_foa: u64 = 16
const elf64_phdr_paddr_foa: u64 = 24
const elf64_phdr_filesz_foa: u64 = 32
const elf64_phdr_memsz_foa: u64 = 40
const elf64_phdr_align_foa: u64 = 48

const elf32_phdr_type_foa: u64 = 0
const elf32_phdr_offset_foa: u64 = 4
const elf32_phdr_vaddr_foa: u64 = 8
const elf32_phdr_paddr_foa: u64 = 12
const elf32_phdr_filesz_foa: u64 = 16
const elf32_phdr_memsz_foa: u64 = 20
const elf32_phdr_flags_foa: u64 = 24
const elf32_phdr_align_foa: u64 = 28

const elf_name_text: u64 = 0x000000747865742e
const elf_name_data: u64 = 0x000000617461642e
const elf_name_rodata: u64 = 0x617461646f722e

fn elfexe_align_up(value: u64, align: u64) -> u64 {
    return ((value + align - 1) / align) * align;
}

fn elf64_phdr_foa(index: u64) -> u64 {
    return elf_header64_size + index * elf_phdr64_size;
}

fn elf32_phdr_foa(index: u64) -> u64 {
    return elf_header32_size + index * elf_phdr32_size;
}

fn elf64_first_segment_foa(ph_count: u64) -> u64 {
    return elfexe_align_up(elf_header64_size + ph_count * elf_phdr64_size, 16);
}

fn elf32_first_segment_foa(ph_count: u64) -> u64 {
    return elfexe_align_up(elf_header32_size + ph_count * elf_phdr32_size, 16);
}

fn elf_segment_vaddr(base: u64, file_offset: u64) -> u64 {
    return base + file_offset;
}

fn elfexe_finalize_entry64(entry_label: u64, segment_start: u64, segment_vaddr: u64) {
    defer {
        store.u64(region_base() + elf64_entry_foa, segment_vaddr + (entry_label - segment_start));
    }
}

fn elfexe_finalize_entry32(entry_label: u64, segment_start: u64, segment_vaddr: u64) {
    defer {
        store.u32(region_base() + elf32_entry_foa, segment_vaddr + (entry_label - segment_start));
    }
}

fn elfexe_finalize_phdr64(row: u64, segment_type: u64, flags: u64, offset: u64, vaddr: u64, filesz: u64, memsz: u64, alignment: u64) {
    defer {
        store.u32(region_base() + elf64_phdr_foa(row) + elf64_phdr_type_foa, segment_type);
        store.u32(region_base() + elf64_phdr_foa(row) + elf64_phdr_flags_foa, flags);
        store.u64(region_base() + elf64_phdr_foa(row) + elf64_phdr_offset_foa, offset);
        store.u64(region_base() + elf64_phdr_foa(row) + elf64_phdr_vaddr_foa, vaddr);
        store.u64(region_base() + elf64_phdr_foa(row) + elf64_phdr_paddr_foa, vaddr);
        store.u64(region_base() + elf64_phdr_foa(row) + elf64_phdr_filesz_foa, filesz);
        store.u64(region_base() + elf64_phdr_foa(row) + elf64_phdr_memsz_foa, memsz);
        store.u64(region_base() + elf64_phdr_foa(row) + elf64_phdr_align_foa, alignment);
    }
}

fn elfexe_finalize_phdr32(row: u64, segment_type: u64, flags: u64, offset: u64, vaddr: u64, filesz: u64, memsz: u64, alignment: u64) {
    defer {
        store.u32(region_base() + elf32_phdr_foa(row) + elf32_phdr_type_foa, segment_type);
        store.u32(region_base() + elf32_phdr_foa(row) + elf32_phdr_offset_foa, offset);
        store.u32(region_base() + elf32_phdr_foa(row) + elf32_phdr_vaddr_foa, vaddr);
        store.u32(region_base() + elf32_phdr_foa(row) + elf32_phdr_paddr_foa, vaddr);
        store.u32(region_base() + elf32_phdr_foa(row) + elf32_phdr_filesz_foa, filesz);
        store.u32(region_base() + elf32_phdr_foa(row) + elf32_phdr_memsz_foa, memsz);
        store.u32(region_base() + elf32_phdr_foa(row) + elf32_phdr_flags_foa, flags);
        store.u32(region_base() + elf32_phdr_foa(row) + elf32_phdr_align_foa, alignment);
    }
}

fn elfexe_finalize_region64_at(row: u64, segment_type: u64, start: u64, flags: u64, image_base: u64) {
    defer {
        const offset: u64 = region_file_offset(start)
        const filesz: u64 = region_file_size(start)
        const memsz: u64 = region_logical_size(start)
        assert(filesz == memsz, "ELF non-LOAD segment must be fully file-backed");
        store.u32(region_base() + elf64_phdr_foa(row) + elf64_phdr_type_foa, segment_type);
        store.u32(region_base() + elf64_phdr_foa(row) + elf64_phdr_flags_foa, flags);
        store.u64(region_base() + elf64_phdr_foa(row) + elf64_phdr_offset_foa, offset);
        store.u64(region_base() + elf64_phdr_foa(row) + elf64_phdr_vaddr_foa, elf_segment_vaddr(image_base, offset));
        store.u64(region_base() + elf64_phdr_foa(row) + elf64_phdr_paddr_foa, elf_segment_vaddr(image_base, offset));
        store.u64(region_base() + elf64_phdr_foa(row) + elf64_phdr_filesz_foa, filesz);
        store.u64(region_base() + elf64_phdr_foa(row) + elf64_phdr_memsz_foa, memsz);
        store.u64(region_base() + elf64_phdr_foa(row) + elf64_phdr_align_foa, 1);
    }
}

fn elfexe_finalize_region64(row: u64, segment_type: u64, start: u64, flags: u64) {
    elfexe_finalize_region64_at(row, segment_type, start, flags, elf_default_base64);
}

fn elfexe_finalize_region32(row: u64, segment_type: u64, start: u64, flags: u64) {
    defer {
        const offset: u64 = region_file_offset(start)
        const filesz: u64 = region_file_size(start)
        const memsz: u64 = region_logical_size(start)
        assert(filesz == memsz, "ELF non-LOAD segment must be fully file-backed");
        store.u32(region_base() + elf32_phdr_foa(row) + elf32_phdr_type_foa, segment_type);
        store.u32(region_base() + elf32_phdr_foa(row) + elf32_phdr_offset_foa, offset);
        store.u32(region_base() + elf32_phdr_foa(row) + elf32_phdr_vaddr_foa, elf_segment_vaddr(elf_default_base32, offset));
        store.u32(region_base() + elf32_phdr_foa(row) + elf32_phdr_paddr_foa, elf_segment_vaddr(elf_default_base32, offset));
        store.u32(region_base() + elf32_phdr_foa(row) + elf32_phdr_filesz_foa, filesz);
        store.u32(region_base() + elf32_phdr_foa(row) + elf32_phdr_memsz_foa, memsz);
        store.u32(region_base() + elf32_phdr_foa(row) + elf32_phdr_flags_foa, flags);
        store.u32(region_base() + elf32_phdr_foa(row) + elf32_phdr_align_foa, 1);
    }
}

fn elfexe_finalize_load64(row: u64, offset: u64, vaddr: u64, start: u64, end: u64, flags: u64) {
    defer {
        store.u32(region_base() + elf64_phdr_foa(row) + elf64_phdr_type_foa, elf_pt_load);
        store.u32(region_base() + elf64_phdr_foa(row) + elf64_phdr_flags_foa, flags);
        store.u64(region_base() + elf64_phdr_foa(row) + elf64_phdr_offset_foa, offset);
        store.u64(region_base() + elf64_phdr_foa(row) + elf64_phdr_vaddr_foa, vaddr);
        store.u64(region_base() + elf64_phdr_foa(row) + elf64_phdr_paddr_foa, vaddr);
        store.u64(region_base() + elf64_phdr_foa(row) + elf64_phdr_filesz_foa, end - start);
        store.u64(region_base() + elf64_phdr_foa(row) + elf64_phdr_memsz_foa, end - start);
        store.u64(region_base() + elf64_phdr_foa(row) + elf64_phdr_align_foa, elf_default_page_align);
    }
}

fn elfexe_finalize_load64_auto_at(row: u64, entry_label: u64, start: u64, flags: u64, image_base: u64) {
    defer {
        let filesz = region_file_size(start)
        let memsz = region_logical_size(start)
        if memsz < filesz {
            memsz = filesz
        }
        store.u64(region_base() + elf64_entry_foa, image_base + region_file_offset(start) + (entry_label - start));
        store.u32(region_base() + elf64_phdr_foa(row) + elf64_phdr_type_foa, elf_pt_load);
        store.u32(region_base() + elf64_phdr_foa(row) + elf64_phdr_flags_foa, flags);
        store.u64(region_base() + elf64_phdr_foa(row) + elf64_phdr_offset_foa, region_file_offset(start));
        store.u64(region_base() + elf64_phdr_foa(row) + elf64_phdr_vaddr_foa, image_base + region_file_offset(start));
        store.u64(region_base() + elf64_phdr_foa(row) + elf64_phdr_paddr_foa, image_base + region_file_offset(start));
        store.u64(region_base() + elf64_phdr_foa(row) + elf64_phdr_filesz_foa, filesz);
        store.u64(region_base() + elf64_phdr_foa(row) + elf64_phdr_memsz_foa, memsz);
        store.u64(region_base() + elf64_phdr_foa(row) + elf64_phdr_align_foa, elf_default_page_align);
    }
}

fn elfexe_finalize_load64_auto(row: u64, entry_label: u64, start: u64, flags: u64) {
    elfexe_finalize_load64_auto_at(row, entry_label, start, flags, elf_default_base64);
}

fn elfexe_finalize_load32(row: u64, offset: u64, vaddr: u64, start: u64, end: u64, flags: u64) {
    defer {
        store.u32(region_base() + elf32_phdr_foa(row) + elf32_phdr_type_foa, elf_pt_load);
        store.u32(region_base() + elf32_phdr_foa(row) + elf32_phdr_offset_foa, offset);
        store.u32(region_base() + elf32_phdr_foa(row) + elf32_phdr_vaddr_foa, vaddr);
        store.u32(region_base() + elf32_phdr_foa(row) + elf32_phdr_paddr_foa, vaddr);
        store.u32(region_base() + elf32_phdr_foa(row) + elf32_phdr_filesz_foa, end - start);
        store.u32(region_base() + elf32_phdr_foa(row) + elf32_phdr_memsz_foa, end - start);
        store.u32(region_base() + elf32_phdr_foa(row) + elf32_phdr_flags_foa, flags);
        store.u32(region_base() + elf32_phdr_foa(row) + elf32_phdr_align_foa, elf_default_page_align);
    }
}

fn elfexe_finalize_load32_auto(row: u64, entry_label: u64, start: u64, flags: u64) {
    defer {
        let filesz = region_file_size(start)
        let memsz = region_logical_size(start)
        if memsz < filesz {
            memsz = filesz
        }
        store.u32(region_base() + elf32_entry_foa, elf_default_base32 + region_file_offset(start) + (entry_label - start));
        store.u32(region_base() + elf32_phdr_foa(row) + elf32_phdr_type_foa, elf_pt_load);
        store.u32(region_base() + elf32_phdr_foa(row) + elf32_phdr_offset_foa, region_file_offset(start));
        store.u32(region_base() + elf32_phdr_foa(row) + elf32_phdr_vaddr_foa, elf_default_base32 + region_file_offset(start));
        store.u32(region_base() + elf32_phdr_foa(row) + elf32_phdr_paddr_foa, elf_default_base32 + region_file_offset(start));
        store.u32(region_base() + elf32_phdr_foa(row) + elf32_phdr_filesz_foa, filesz);
        store.u32(region_base() + elf32_phdr_foa(row) + elf32_phdr_memsz_foa, memsz);
        store.u32(region_base() + elf32_phdr_foa(row) + elf32_phdr_flags_foa, flags);
        store.u32(region_base() + elf32_phdr_foa(row) + elf32_phdr_align_foa, elf_default_page_align);
    }
}

packed struct ElfIdent {
    magic: u32 = elf_magic,
    class: u8,
    data: u8 = elf_data_lsb,
    version: u8 = 1,
    osabi: u8 = elf_osabi_none,
    abi_version: u8 = 0,
    pad0: u32 = 0,
    pad1: u16 = 0,
    pad2: u8 = 0,
}

packed struct ElfHeader64 {
    ident: ElfIdent,
    file_type: u16 = elf_type_exec,
    machine: u16 = elf_machine_x86_64,
    version: u32 = elf_version_current,
    entry: u64 = 0,
    phoff: u64 = elf_header64_size,
    shoff: u64 = 0,
    flags: u32 = 0,
    ehsize: u16 = elf_header64_size,
    phentsize: u16 = elf_phdr64_size,
    phnum: u16,
    shentsize: u16 = elf_shdr64_size,
    shnum: u16 = 0,
    shstrndx: u16 = 0,
}

packed struct ElfHeader32 {
    ident: ElfIdent,
    file_type: u16 = elf_type_exec,
    machine: u16 = elf_machine_386,
    version: u32 = elf_version_current,
    entry: u32 = 0,
    phoff: u32 = elf_header32_size,
    shoff: u32 = 0,
    flags: u32 = 0,
    ehsize: u16 = elf_header32_size,
    phentsize: u16 = elf_phdr32_size,
    phnum: u16,
    shentsize: u16 = elf_shdr32_size,
    shnum: u16 = 0,
    shstrndx: u16 = 0,
}

packed struct ElfProgramHeader64 {
    segment_type: u32 = elf_pt_load,
    flags: u32 = elf_pf_r | elf_pf_x,
    offset: u64 = 0,
    vaddr: u64 = 0,
    paddr: u64 = 0,
    filesz: u64 = 0,
    memsz: u64 = 0,
    alignment: u64 = elf_default_page_align,
}

packed struct ElfProgramHeader32 {
    segment_type: u32 = elf_pt_load,
    offset: u32 = 0,
    vaddr: u32 = 0,
    paddr: u32 = 0,
    filesz: u32 = 0,
    memsz: u32 = 0,
    flags: u32 = elf_pf_r | elf_pf_x,
    alignment: u32 = elf_default_page_align,
}

packed struct ElfSectionHeader64 {
    name: u32 = 0,
    section_type: u32 = elf_sht_null,
    flags: u64 = 0,
    addr: u64 = 0,
    offset: u64 = 0,
    size: u64 = 0,
    link: u32 = 0,
    info: u32 = 0,
    addralign: u64 = 0,
    entsize: u64 = 0,
}

packed struct ElfSectionHeader32 {
    name: u32 = 0,
    section_type: u32 = elf_sht_null,
    flags: u32 = 0,
    addr: u32 = 0,
    offset: u32 = 0,
    size: u32 = 0,
    link: u32 = 0,
    info: u32 = 0,
    addralign: u32 = 0,
    entsize: u32 = 0,
}

fn elfexe_begin64_at(ph_count: u16, file_type: u16, image_base: u64) {
    assert(ph_count > 0, "elfexe_begin64 requires at least one program header");
    origin(image_base);
    emit.struct(ElfHeader64 { ident: ElfIdent { class: elf_class_64 }, file_type: file_type, phnum: ph_count });
    for i in range(0, ph_count) {
        emit.struct(ElfProgramHeader64 {});
    }
}

fn elfexe_begin64(ph_count: u16) {
    elfexe_begin64_at(ph_count, elf_type_exec, elf_default_base64);
}

fn elfexe_begin32(ph_count: u16) {
    assert(ph_count > 0, "elfexe_begin32 requires at least one program header");
    origin(elf_default_base32);
    emit.struct(ElfHeader32 { ident: ElfIdent { class: elf_class_32 }, phnum: ph_count });
    for i in range(0, ph_count) {
        emit.struct(ElfProgramHeader32 {});
    }
}

fn elfexe_begin_segment64_at(name: string, file_offset: u64, image_base: u64) {
    region.begin(name, elf_segment_vaddr(image_base, file_offset), file_offset);
}

fn elfexe_begin_segment64(name: string, file_offset: u64) {
    elfexe_begin_segment64_at(name, file_offset, elf_default_base64);
}

fn elfexe_begin_segment64_auto_at(name: string, image_base: u64) {
    align(16);
    const offset: u64 = file_offset()
    region.begin(name, elf_segment_vaddr(image_base, offset), offset);
}

fn elfexe_begin_segment64_auto(name: string) {
    elfexe_begin_segment64_auto_at(name, elf_default_base64);
}

fn elfexe_begin_segment32(name: string, file_offset: u64) {
    region.begin(name, elf_segment_vaddr(elf_default_base32, file_offset), file_offset);
}

fn elfexe_begin_segment32_auto(name: string) {
    align(16);
    const offset: u64 = file_offset()
    region.begin(name, elf_segment_vaddr(elf_default_base32, offset), offset);
}

fn elfexe_end_segment(raw_size: u64) {
    pad_to(raw_size, 0);
}

fn elfexe_align_segment_file() {
    region.file_align(16);
}

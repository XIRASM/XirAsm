// ELF64 shared object core helpers for XIRASM.
//
// This file owns the low-level ET_DYN records shared by export/import DSLs:
// ELF header, program/section headers, dynamic symbols, dynamic entries, and
// small offset helpers. Export and import table builders live in separate
// include files so users can opt into only the layer they need. Common program
// header backfill belongs in `elfso_finalize_*` helpers.

import("elf_const.inc");

const elfso_header64_size: u64 = 64
const elfso_phdr64_size: u64 = 56
const elfso_shdr64_size: u64 = 64
const elfso_sym64_size: u64 = 24
const elfso_dyn64_size: u64 = 16

const elfso64_entry_foa: u64 = 24
const elfso64_phoff_foa: u64 = 32
const elfso64_shoff_foa: u64 = 40
const elfso64_phnum_foa: u64 = 56
const elfso64_shentsize_foa: u64 = 58
const elfso64_shnum_foa: u64 = 60
const elfso64_shstrndx_foa: u64 = 62

const elfso64_phdr_type_foa: u64 = 0
const elfso64_phdr_flags_foa: u64 = 4
const elfso64_phdr_offset_foa: u64 = 8
const elfso64_phdr_vaddr_foa: u64 = 16
const elfso64_phdr_paddr_foa: u64 = 24
const elfso64_phdr_filesz_foa: u64 = 32
const elfso64_phdr_memsz_foa: u64 = 40
const elfso64_phdr_align_foa: u64 = 48

const elfso_sh_type_foa: u64 = 4
const elfso64_sh_addr_foa: u64 = 16
const elfso64_sh_offset_foa: u64 = 24
const elfso64_sh_size_foa: u64 = 32
const elfso64_sh_link_foa: u64 = 40
const elfso64_sh_info_foa: u64 = 44
const elfso64_sh_entsize_foa: u64 = 56

fn elfso_align_up(value: u64, align: u64) -> u64 {
    assert(align > 0, "elfso_align_up requires non-zero alignment");
    return ((value + align - 1) / align) * align;
}

fn elfso64_phdr_foa(index: u64) -> u64 {
    return elfso_header64_size + index * elfso_phdr64_size;
}

fn elfso64_shdr_foa(section_table_foa: u64, index: u64) -> u64 {
    return section_table_foa + index * elfso_shdr64_size;
}

fn elfso64_dyn_foa(dynamic_foa: u64, index: u64) -> u64 {
    return dynamic_foa + index * elfso_dyn64_size;
}

fn elfso_finalize_phdr64(row: u64, segment_type: u64, flags: u64, offset: u64, vaddr: u64, filesz: u64, memsz: u64, alignment: u64) {
    defer {
        store.u32(region_base() + elfso64_phdr_foa(row) + elfso64_phdr_type_foa, segment_type);
        store.u32(region_base() + elfso64_phdr_foa(row) + elfso64_phdr_flags_foa, flags);
        store.u64(region_base() + elfso64_phdr_foa(row) + elfso64_phdr_offset_foa, offset);
        store.u64(region_base() + elfso64_phdr_foa(row) + elfso64_phdr_vaddr_foa, vaddr);
        store.u64(region_base() + elfso64_phdr_foa(row) + elfso64_phdr_paddr_foa, vaddr);
        store.u64(region_base() + elfso64_phdr_foa(row) + elfso64_phdr_filesz_foa, filesz);
        store.u64(region_base() + elfso64_phdr_foa(row) + elfso64_phdr_memsz_foa, memsz);
        store.u64(region_base() + elfso64_phdr_foa(row) + elfso64_phdr_align_foa, alignment);
    }
}

fn elfso_finalize_load64(row: u64, offset: u64, vaddr: u64, filesz: u64, memsz: u64, flags: u64) {
    defer {
        store.u32(region_base() + elfso64_phdr_foa(row) + elfso64_phdr_type_foa, elf_pt_load);
        store.u32(region_base() + elfso64_phdr_foa(row) + elfso64_phdr_flags_foa, flags);
        store.u64(region_base() + elfso64_phdr_foa(row) + elfso64_phdr_offset_foa, offset);
        store.u64(region_base() + elfso64_phdr_foa(row) + elfso64_phdr_vaddr_foa, vaddr);
        store.u64(region_base() + elfso64_phdr_foa(row) + elfso64_phdr_paddr_foa, vaddr);
        store.u64(region_base() + elfso64_phdr_foa(row) + elfso64_phdr_filesz_foa, filesz);
        store.u64(region_base() + elfso64_phdr_foa(row) + elfso64_phdr_memsz_foa, memsz);
        store.u64(region_base() + elfso64_phdr_foa(row) + elfso64_phdr_align_foa, elf_default_page_align);
    }
}

fn elfso_finalize_dynamic64(row: u64, dynamic_foa: u64, dynamic_size: u64) {
    defer {
        store.u32(region_base() + elfso64_phdr_foa(row) + elfso64_phdr_type_foa, elf_pt_dynamic);
        store.u32(region_base() + elfso64_phdr_foa(row) + elfso64_phdr_flags_foa, elf_pf_r | elf_pf_w);
        store.u64(region_base() + elfso64_phdr_foa(row) + elfso64_phdr_offset_foa, dynamic_foa);
        store.u64(region_base() + elfso64_phdr_foa(row) + elfso64_phdr_vaddr_foa, dynamic_foa);
        store.u64(region_base() + elfso64_phdr_foa(row) + elfso64_phdr_paddr_foa, dynamic_foa);
        store.u64(region_base() + elfso64_phdr_foa(row) + elfso64_phdr_filesz_foa, dynamic_size);
        store.u64(region_base() + elfso64_phdr_foa(row) + elfso64_phdr_memsz_foa, dynamic_size);
        store.u64(region_base() + elfso64_phdr_foa(row) + elfso64_phdr_align_foa, 8);
    }
}

fn elfso_st_info(bind: u8, symbol_type: u8) -> u8 {
    assert(bind < 16, "ELF symbol binding must fit in four bits");
    assert(symbol_type < 16, "ELF symbol type must fit in four bits");
    return bind * 16 + symbol_type;
}

packed struct ElfSoHeader64 {
    magic: u32 = elf_magic,
    class: u8 = elf_class_64,
    data: u8 = elf_data_lsb,
    ident_version: u8 = 1,
    osabi: u8 = elf_osabi_none,
    abi_version: u8 = 0,
    pad0: u32 = 0,
    pad1: u16 = 0,
    pad2: u8 = 0,
    file_type: u16 = elf_type_dyn,
    machine: u16 = elf_machine_x86_64,
    version: u32 = elf_version_current,
    entry: u64 = 0,
    phoff: u64 = elfso_header64_size,
    shoff: u64,
    flags: u32 = 0,
    ehsize: u16 = elfso_header64_size,
    phentsize: u16 = elfso_phdr64_size,
    phnum: u16,
    shentsize: u16 = elfso_shdr64_size,
    shnum: u16,
    shstrndx: u16,
}

packed struct ElfSoProgramHeader64 {
    segment_type: u32 = elf_pt_null,
    flags: u32 = 0,
    offset: u64 = 0,
    vaddr: u64 = 0,
    paddr: u64 = 0,
    filesz: u64 = 0,
    memsz: u64 = 0,
    alignment: u64 = 0,
}

packed struct ElfSoSectionHeader64 {
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

packed struct ElfSoSymbol64 {
    name: u32 = 0,
    info: u8 = 0,
    other: u8 = 0,
    shndx: u16 = elf_shn_undef,
    value: u64 = 0,
    size: u64 = 0,
}

packed struct ElfSoDynamic64 {
    tag: u64,
    value: u64,
}

fn elfso_begin64(ph_count: u16, section_table_foa: u64, section_count: u16, shstrndx: u16) {
    assert(ph_count > 1, "elfso_begin64 requires PT_LOAD and PT_DYNAMIC");
    assert(section_count > 0, "elfso_begin64 requires section headers");
    origin(0);
    emit.struct(ElfSoHeader64 { phnum: ph_count, shoff: section_table_foa, shnum: section_count, shstrndx: shstrndx });
    for i in range(0, ph_count) {
        emit.struct(ElfSoProgramHeader64 {});
    }
}

fn elfso_begin_region(name: string, file_offset: u64) {
    region.begin(name, file_offset, file_offset);
}

fn elfso_end_region(raw_size: u64) {
    pad_to(raw_size, 0);
}

fn elfso_phdr64(segment_type: u32, flags: u32, offset: u64, vaddr: u64, filesz: u64, memsz: u64, alignment: u64) {
    emit.struct(ElfSoProgramHeader64 { segment_type: segment_type, flags: flags, offset: offset, vaddr: vaddr, paddr: vaddr, filesz: filesz, memsz: memsz, alignment: alignment });
}

fn elfso_shdr64(name: u64, section_type: u32, flags: u64, addr: u64, offset: u64, size: u64, link: u64, info: u64, addralign: u64, entsize: u64) {
    emit.struct(ElfSoSectionHeader64 { name: name, section_type: section_type, flags: flags, addr: addr, offset: offset, size: size, link: link, info: info, addralign: addralign, entsize: entsize });
}

fn elfso_sym64(name: u64, info: u8, shndx: u16, value: u64, size: u64) {
    emit.struct(ElfSoSymbol64 { name: name, info: info, shndx: shndx, value: value, size: size });
}

fn elfso_dyn64(tag: u64, value: u64) {
    emit.struct(ElfSoDynamic64 { tag: tag, value: value });
}

fn elfso_hash_one(symbol_index: u64) {
    assert(symbol_index < 0xffffffff, "elfso_hash_one symbol index must fit u32 with null symbol");
    dd(1);
    dd(symbol_index + 1);
    dd(symbol_index);
    dd(0);
    dd(0);
}

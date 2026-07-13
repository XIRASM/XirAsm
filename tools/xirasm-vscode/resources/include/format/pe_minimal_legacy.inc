// Minimal PE helpers kept as the original smoke-test reference.
//
// This file intentionally stays small. The maintained PE DSL lives in
// `include/format/pe.inc` and uses explicit finalizer backfill.

const pe_magic_mz: u16 = 0x5a4d
const pe_sig: u32 = 0x00004550
const pe_machine_x64: u16 = 0x8664
const pe_chars_exe: u16 = 0x0022
const pe_opt64_magic: u16 = 0x020b
const pe_subsystem_console: u16 = 3

const pe_file_align: u64 = 0x200
const pe_section_align: u64 = 0x1000
const pe_image_base: u64 = 0x140000000

fn align_up(value: u64, align: u64) -> u64 {
    return ((value + align - 1) / align) * align;
}

packed struct PeDosStub {
    mz: u16 = pe_magic_mz,
    cblp: u16 = 0x0090,
    cp: u16 = 0x0003,
    crlc: u16 = 0,
    cparhdr: u16 = 0x0004,
    minalloc: u16 = 0,
    maxalloc: u16 = 0xffff,
    ss: u16 = 0,
    sp: u16 = 0x00b8,
    csum: u16 = 0,
    ip: u16 = 0,
    cs: u16 = 0,
    lfarlc: u16 = 0x0040,
    ovno: u16 = 0,
    res0: u64 = 0,
    oemid: u16 = 0,
    oeminfo: u16 = 0,
    res1_a: u64 = 0,
    res1_b: u64 = 0,
    lfanew: u32 = 0,
}

packed struct PeFileHeader64 {
    machine: u16 = pe_machine_x64,
    sections: u16,
    timestamp: u32 = 0,
    symbols: u32 = 0,
    symbol_count: u32 = 0,
    optional_size: u16 = 0xf0,
    characteristics: u16 = pe_chars_exe,
}

packed struct PeOpt64A {
    magic: u16 = pe_opt64_magic,
    linker_major: u8 = 0,
    linker_minor: u8 = 0,
    code_size: u32,
    init_data_size: u32 = 0,
    uninit_data_size: u32 = 0,
    entry_rva: u32,
    code_base: u32,
    image_base: u64 = pe_image_base,
    section_align: u32 = pe_section_align,
    file_align: u32 = pe_file_align,
}

packed struct PeOpt64B {
    os_major: u16 = 6,
    os_minor: u16 = 0,
    image_major: u16 = 0,
    image_minor: u16 = 0,
    subsystem_major: u16 = 6,
    subsystem_minor: u16 = 0,
    win32_version: u32 = 0,
    image_size: u32,
    headers_size: u32,
    checksum: u32 = 0,
    subsystem: u16 = pe_subsystem_console,
    dll_chars: u16 = 0,
    stack_reserve: u64 = 0x100000,
    stack_commit: u64 = 0x1000,
    heap_reserve: u64 = 0x100000,
    heap_commit: u64 = 0x1000,
    loader_flags: u32 = 0,
    data_dirs: u32 = 16,
}

packed struct PeDataDir {
    rva: u32 = 0,
    size: u32 = 0,
}

packed struct PeSectionHeader {
    name0: u64,
    virtual_size: u32,
    virtual_address: u32,
    raw_size: u32,
    raw_ptr: u32,
    reloc_ptr: u32 = 0,
    line_ptr: u32 = 0,
    reloc_count: u16 = 0,
    line_count: u16 = 0,
    characteristics: u32,
}

fn pe_begin64() {
    origin(pe_image_base);
    emit.struct(PeDosStub {});
    emit.bytes(b"This program cannot be run in DOS mode.");
    emit.u16(0x0a0d);
    emit.u8(0x24);
    pad_to(0x80, 0);
    pe_header:
    emit.u32(pe_sig);
}

fn pe_headers64() {
    pe_file:
    emit.struct(PeFileHeader64 { sections: 1 });

    pe_opt_a:
    emit.struct(PeOpt64A { code_size: 0, entry_rva: 0, code_base: 0 });
    pe_opt_b:
    emit.struct(PeOpt64B { image_size: 0, headers_size: pe_file_align });

    for i in range(0, 16) {
        emit.struct(PeDataDir {});
    }

    pe_text_sec:
    emit.struct(PeSectionHeader { name0: 0x000000747865742e, virtual_size: 0, virtual_address: 0, raw_size: 0, raw_ptr: pe_file_align, characteristics: 0x60000020 });

    pad_to(pe_file_align, 0);
}

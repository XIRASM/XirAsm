// PE executable helpers for XIRASM.
//
// Design boundary:
// - XIRASM logical regions are not PE object sections. PE sections are described
//   by header fields plus explicit raw placement.
// - `origin(image_base)` changes label addresses only. Raw placement is handled
//   by region file offsets and explicit padding.
// - Section raw data is explicitly padded to FileAlignment so Windows loader
//   never sees a header that promises bytes past EOF.
// - Layout-dependent fields are registered through `pe_finalize_*` helpers.
//   The helpers own the deferred stores so user recipes do not have to handwrite
//   header patch blocks.

import("pe_const.inc");

const pe_headers_foa: u64 = 0
const pe_nt_headers_foa: u64 = 0x80
const pe_file_header_foa: u64 = pe_nt_headers_foa + 4
const pe_optional_header_foa: u64 = pe_file_header_foa + 20
const pe_optional32_size: u64 = 0xe0
const pe_optional64_size: u64 = 0xf0
const pe_section_table_foa: u64 = pe_optional_header_foa + pe_optional64_size
const pe_section32_table_foa: u64 = pe_optional_header_foa + pe_optional32_size

const pe_opt_size_of_code_foa: u64 = pe_optional_header_foa + 4
const pe_opt_size_of_init_data_foa: u64 = pe_optional_header_foa + 8
const pe_opt_size_of_uninit_data_foa: u64 = pe_optional_header_foa + 12
const pe_opt_entry_rva_foa: u64 = pe_optional_header_foa + 16
const pe_opt_base_of_code_foa: u64 = pe_optional_header_foa + 20
const pe_opt32_base_of_data_foa: u64 = pe_optional_header_foa + 24
const pe_opt_size_of_image_foa: u64 = pe_optional_header_foa + 56
const pe_opt_size_of_headers_foa: u64 = pe_optional_header_foa + 60
const pe_opt_checksum_foa: u64 = pe_optional_header_foa + 64
const pe_opt_dll_chars_foa: u64 = pe_optional_header_foa + 70
const pe_dir_table_foa: u64 = pe_optional_header_foa + 112
const pe_dir32_table_foa: u64 = pe_optional_header_foa + 96

const pe_sec_name_foa: u64 = 0
const pe_sec_virtual_size_foa: u64 = 8
const pe_sec_rva_foa: u64 = 12
const pe_sec_raw_size_foa: u64 = 16
const pe_sec_raw_ptr_foa: u64 = 20
const pe_sec_chars_foa: u64 = 36

const pe_name_text: u64 = 0x000000747865742e
const pe_name_data: u64 = 0x000000617461642e
const pe_name_rdata: u64 = 0x0061746164722e
const pe_name_idata: u64 = 0x000061746164692e
const pe_name_edata: u64 = 0x000061746164652e
const pe_name_reloc: u64 = 0x0000636f6c65722e
const pe_name_rsrc: u64 = 0x000000637273722e
const pe_name_bss: u64 = 0x0000007373622e

fn align_up(value: u64, align: u64) -> u64 {
    return ((value + align - 1) / align) * align;
}

fn pe_row_foa(row: u64) -> u64 {
    return pe_section_table_foa + row * pe_section_header_size;
}

fn pe_row32_foa(row: u64) -> u64 {
    return pe_section32_table_foa + row * pe_section_header_size;
}

fn pe_dir_rva_foa(slot: u64) -> u64 {
    return pe_dir_table_foa + slot * 8;
}

fn pe_dir_size_foa(slot: u64) -> u64 {
    return pe_dir_rva_foa(slot) + 4;
}

fn pe_dir32_rva_foa(slot: u64) -> u64 {
    return pe_dir32_table_foa + slot * 8;
}

fn pe_dir32_size_foa(slot: u64) -> u64 {
    return pe_dir32_rva_foa(slot) + 4;
}

fn pe_rva(label: u64, image_base: u64) -> u64 {
    return label - image_base;
}

fn pe_section_rva(row: u64, section_align: u64) -> u64 {
    return section_align + row * section_align;
}

fn pe_section_raw_ptr(row: u64, file_align: u64) -> u64 {
    return file_align + row * file_align;
}

fn pe_code_size(raw_size: u64, chars: u64) -> u64 {
    if (chars & pe_scn_cnt_code) != 0 {
        return raw_size;
    }
    return 0;
}

fn pe_init_data_size(raw_size: u64, chars: u64) -> u64 {
    if (chars & pe_scn_cnt_init_data) != 0 {
        return raw_size;
    }
    return 0;
}

fn pe_uninit_data_size(virtual_size: u64, chars: u64) -> u64 {
    if (chars & pe_scn_cnt_uninit_data) != 0 {
        return virtual_size;
    }
    return 0;
}

fn pe_finalize_u32(addr: u64, value: u64) {
    defer {
        store.u32(addr, value);
    }
}

fn pe_finalize_section64(row: u64, name0: u64, rva: u64, raw_ptr: u64, start: u64, end: u64, chars: u64) {
    assert(row < pe_max_image_sections, "PE section row out of range");
    defer {
        store.u64(region_base() + pe_row_foa(row) + pe_sec_name_foa, name0);
        store.u32(region_base() + pe_row_foa(row) + pe_sec_virtual_size_foa, end - start);
        store.u32(region_base() + pe_row_foa(row) + pe_sec_rva_foa, rva);
        store.u32(region_base() + pe_row_foa(row) + pe_sec_raw_size_foa, align_up(end - start, pe_default_file_align));
        store.u32(region_base() + pe_row_foa(row) + pe_sec_raw_ptr_foa, raw_ptr);
        store.u32(region_base() + pe_row_foa(row) + pe_sec_chars_foa, chars);
    }
}

fn pe_finalize_section64_auto(row: u64, name0: u64, start: u64, chars: u64) {
    assert(row < pe_max_image_sections, "PE section row out of range");
    defer {
        let file_size = region_file_size(start)
        let raw_ptr = 0
        if file_size > 0 {
            raw_ptr = region_file_offset(start)
        }
        store.u64(region_base() + pe_row_foa(row) + pe_sec_name_foa, name0);
        store.u32(region_base() + pe_row_foa(row) + pe_sec_virtual_size_foa, region_logical_size(start));
        store.u32(region_base() + pe_row_foa(row) + pe_sec_rva_foa, start - pe_default_image_base64);
        store.u32(region_base() + pe_row_foa(row) + pe_sec_raw_size_foa, file_size);
        store.u32(region_base() + pe_row_foa(row) + pe_sec_raw_ptr_foa, raw_ptr);
        store.u32(region_base() + pe_row_foa(row) + pe_sec_chars_foa, chars);
    }
}

fn pe_finalize_section32(row: u64, name0: u64, rva: u64, raw_ptr: u64, start: u64, end: u64, chars: u64) {
    assert(row < pe_max_image_sections, "PE section row out of range");
    defer {
        store.u64(region_base() + pe_row32_foa(row) + pe_sec_name_foa, name0);
        store.u32(region_base() + pe_row32_foa(row) + pe_sec_virtual_size_foa, end - start);
        store.u32(region_base() + pe_row32_foa(row) + pe_sec_rva_foa, rva);
        store.u32(region_base() + pe_row32_foa(row) + pe_sec_raw_size_foa, align_up(end - start, pe_default_file_align));
        store.u32(region_base() + pe_row32_foa(row) + pe_sec_raw_ptr_foa, raw_ptr);
        store.u32(region_base() + pe_row32_foa(row) + pe_sec_chars_foa, chars);
    }
}

fn pe_finalize_section32_auto(row: u64, name0: u64, start: u64, chars: u64) {
    assert(row < pe_max_image_sections, "PE section row out of range");
    defer {
        let file_size = region_file_size(start)
        let raw_ptr = 0
        if file_size > 0 {
            raw_ptr = region_file_offset(start)
        }
        store.u64(region_base() + pe_row32_foa(row) + pe_sec_name_foa, name0);
        store.u32(region_base() + pe_row32_foa(row) + pe_sec_virtual_size_foa, region_logical_size(start));
        store.u32(region_base() + pe_row32_foa(row) + pe_sec_rva_foa, start - pe_default_image_base32);
        store.u32(region_base() + pe_row32_foa(row) + pe_sec_raw_size_foa, file_size);
        store.u32(region_base() + pe_row32_foa(row) + pe_sec_raw_ptr_foa, raw_ptr);
        store.u32(region_base() + pe_row32_foa(row) + pe_sec_chars_foa, chars);
    }
}

fn pe_finalize_entry(entry_label: u64, section_start: u64, section_rva: u64) {
    defer {
        store.u32(region_base() + pe_opt_entry_rva_foa, section_rva + (entry_label - section_start));
    }
}

fn pe_finalize_image_size(last_section_rva: u64, last_section_start: u64, last_section_end: u64) {
    assert(last_section_end >= last_section_start, "PE image-size section end is before section start");
    defer {
        store.u32(region_base() + pe_opt_size_of_image_foa, align_up(last_section_rva + (last_section_end - last_section_start), pe_default_section_align));
    }
}

fn pe_finalize_code_size(code_start: u64, code_end: u64) {
    assert(code_end >= code_start, "PE code-size section end is before section start");
    defer {
        store.u32(region_base() + pe_opt_size_of_code_foa, region_file_size(code_start));
    }
}

fn pe_finalize_init_data_size(data_start: u64, data_end: u64) {
    assert(data_end >= data_start, "PE initialized-data section end is before section start");
    defer {
        store.u32(region_base() + pe_opt_size_of_init_data_foa, region_file_size(data_start));
    }
}

fn pe_finalize_base_of_code(text_rva: u64) {
    defer {
        store.u32(region_base() + pe_opt_base_of_code_foa, text_rva);
    }
}

fn pe_finalize_base_of_data32(data_rva: u64) {
    defer {
        store.u32(region_base() + pe_opt32_base_of_data_foa, data_rva);
    }
}

fn pe_finalize_data_dir64(slot: u64, rva: u64, size: u64) {
    defer {
        store.u32(region_base() + pe_dir_rva_foa(slot), rva);
        store.u32(region_base() + pe_dir_size_foa(slot), size);
    }
}

fn pe_finalize_data_dir32(slot: u64, rva: u64, size: u64) {
    defer {
        store.u32(region_base() + pe_dir32_rva_foa(slot), rva);
        store.u32(region_base() + pe_dir32_size_foa(slot), size);
    }
}

fn pe_finalize_import_dir64(idata_rva: u64, idata_start: u64, directory_start: u64, directory_end: u64) {
    defer {
        store.u32(region_base() + pe_dir_rva_foa(pe_dir_import), idata_rva + (directory_start - idata_start));
        store.u32(region_base() + pe_dir_size_foa(pe_dir_import), directory_end - directory_start);
    }
}

fn pe_finalize_import_dir32(idata_rva: u64, idata_start: u64, directory_start: u64, directory_end: u64) {
    defer {
        store.u32(region_base() + pe_dir32_rva_foa(pe_dir_import), idata_rva + (directory_start - idata_start));
        store.u32(region_base() + pe_dir32_size_foa(pe_dir_import), directory_end - directory_start);
    }
}

fn pe_finalize_export_dir64(edata_rva: u64, edata_start: u64, directory_start: u64, directory_end: u64) {
    defer {
        store.u32(region_base() + pe_dir_rva_foa(pe_dir_export), edata_rva + (directory_start - edata_start));
        store.u32(region_base() + pe_dir_size_foa(pe_dir_export), directory_end - directory_start);
    }
}

fn pe_finalize_export_dir32(edata_rva: u64, edata_start: u64, directory_start: u64, directory_end: u64) {
    defer {
        store.u32(region_base() + pe_dir32_rva_foa(pe_dir_export), edata_rva + (directory_start - edata_start));
        store.u32(region_base() + pe_dir32_size_foa(pe_dir_export), directory_end - directory_start);
    }
}

fn pe_finalize_reloc_dir64(reloc_rva: u64, reloc_start: u64, directory_start: u64, directory_end: u64) {
    defer {
        store.u32(region_base() + pe_dir_rva_foa(pe_dir_basereloc), reloc_rva + (directory_start - reloc_start));
        store.u32(region_base() + pe_dir_size_foa(pe_dir_basereloc), directory_end - directory_start);
    }
}

fn pe_finalize_reloc_dir32(reloc_rva: u64, reloc_start: u64, directory_start: u64, directory_end: u64) {
    defer {
        store.u32(region_base() + pe_dir32_rva_foa(pe_dir_basereloc), reloc_rva + (directory_start - reloc_start));
        store.u32(region_base() + pe_dir32_size_foa(pe_dir_basereloc), directory_end - directory_start);
    }
}

fn pe_finalize_resource_dir64(rsrc_rva: u64, rsrc_start: u64, directory_start: u64, directory_end: u64) {
    defer {
        store.u32(region_base() + pe_dir_rva_foa(pe_dir_resource), rsrc_rva + (directory_start - rsrc_start));
        store.u32(region_base() + pe_dir_size_foa(pe_dir_resource), directory_end - directory_start);
    }
}

fn pe_finalize_resource_dir32(rsrc_rva: u64, rsrc_start: u64, directory_start: u64, directory_end: u64) {
    defer {
        store.u32(region_base() + pe_dir32_rva_foa(pe_dir_resource), rsrc_rva + (directory_start - rsrc_start));
        store.u32(region_base() + pe_dir32_size_foa(pe_dir_resource), directory_end - directory_start);
    }
}

fn pe_checksum_begin() {
    defer {
        let checksum_addr = region_base() + pe_opt_checksum_foa
        store.u32(checksum_addr, 0);

        let checksum = 0
        let start = region_base()
        let size = region_file_size(start)
        let offset = 0
        while offset + 2 <= size {
            checksum = checksum + load.u16(start + offset)
            offset = offset + 2
        }
        if offset < size {
            checksum = checksum + load.u8(start + offset)
        }
        while (checksum >> 16) != 0 {
            checksum = (checksum & 0xffff) + (checksum >> 16)
        }

        store.u32(checksum_addr, checksum);
    }
}

fn pe_checksum_add_region(start: u64) {
    defer {
        let checksum_addr = region_base() + pe_opt_checksum_foa
        let checksum = load.u32(checksum_addr)
        let size = region_file_size(start)
        let offset = 0
        while offset + 2 <= size {
            checksum = checksum + load.u16(start + offset)
            offset = offset + 2
        }
        if offset < size {
            checksum = checksum + load.u8(start + offset)
        }
        while (checksum >> 16) != 0 {
            checksum = (checksum & 0xffff) + (checksum >> 16)
        }

        store.u32(checksum_addr, checksum);
    }
}

fn pe_checksum_finish(last_region_start: u64) {
    defer {
        let checksum_addr = region_base() + pe_opt_checksum_foa
        let checksum = load.u32(checksum_addr)
        let final_file_size = region_file_offset(last_region_start) + region_file_size(last_region_start)
        store.u32(checksum_addr, checksum + final_file_size);
    }
}

packed struct PeDosHeader {
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
    res1_c: u32 = 0,
    lfanew: u32 = pe_nt_headers_foa,
}

packed struct PeFileHeader64 {
    machine: u16 = pe_machine_amd64,
    sections: u16,
    timestamp: u32 = 0,
    symbols: u32 = 0,
    symbol_count: u32 = 0,
    optional_size: u16 = pe_optional64_size,
    characteristics: u16,
}

packed struct PeFileHeader32 {
    machine: u16 = pe_machine_i386,
    sections: u16,
    timestamp: u32 = 0,
    symbols: u32 = 0,
    symbol_count: u32 = 0,
    optional_size: u16 = pe_optional32_size,
    characteristics: u16,
}

packed struct PeOptionalHeader32A {
    magic: u16 = pe_opt32_magic,
    linker_major: u8 = 0,
    linker_minor: u8 = 0,
    code_size: u32 = 0,
    init_data_size: u32 = 0,
    uninit_data_size: u32 = 0,
    entry_rva: u32 = 0,
    code_base: u32 = pe_default_section_align,
    data_base: u32 = 0,
    image_base: u32 = pe_default_image_base32,
    section_align: u32 = pe_default_section_align,
    file_align: u32 = pe_default_file_align,
}

packed struct PeOptionalHeader32B {
    os_major: u16 = 6,
    os_minor: u16 = 0,
    image_major: u16 = 0,
    image_minor: u16 = 0,
    subsystem_major: u16 = 6,
    subsystem_minor: u16 = 0,
    win32_version: u32 = 0,
    image_size: u32 = 0,
    headers_size: u32 = pe_default_file_align,
    checksum: u32 = 0,
    subsystem: u16 = pe_subsystem_console,
    dll_chars: u16 = pe_dll_nx_compat,
    stack_reserve: u32 = 0x100000,
    stack_commit: u32 = 0x1000,
    heap_reserve: u32 = 0x100000,
    heap_commit: u32 = 0x1000,
    loader_flags: u32 = 0,
    data_dirs: u32 = pe_data_dir_count,
}

packed struct PeOptionalHeader64A {
    magic: u16 = pe_opt64_magic,
    linker_major: u8 = 0,
    linker_minor: u8 = 0,
    code_size: u32 = 0,
    init_data_size: u32 = 0,
    uninit_data_size: u32 = 0,
    entry_rva: u32 = 0,
    code_base: u32 = pe_default_section_align,
    image_base: u64 = pe_default_image_base64,
    section_align: u32 = pe_default_section_align,
    file_align: u32 = pe_default_file_align,
}

packed struct PeOptionalHeader64B {
    os_major: u16 = 6,
    os_minor: u16 = 0,
    image_major: u16 = 0,
    image_minor: u16 = 0,
    subsystem_major: u16 = 6,
    subsystem_minor: u16 = 0,
    win32_version: u32 = 0,
    image_size: u32 = 0,
    headers_size: u32 = pe_default_file_align,
    checksum: u32 = 0,
    subsystem: u16 = pe_subsystem_console,
    dll_chars: u16 = pe_dll_nx_compat,
    stack_reserve: u64 = 0x100000,
    stack_commit: u64 = 0x1000,
    heap_reserve: u64 = 0x100000,
    heap_commit: u64 = 0x1000,
    loader_flags: u32 = 0,
    data_dirs: u32 = pe_data_dir_count,
}

packed struct PeDataDir {
    rva: u32 = 0,
    size: u32 = 0,
}

packed struct PeSectionHeader {
    name0: u64 = 0,
    virtual_size: u32 = 0,
    virtual_address: u32 = 0,
    raw_size: u32 = 0,
    raw_ptr: u32 = 0,
    reloc_ptr: u32 = 0,
    line_ptr: u32 = 0,
    reloc_count: u16 = 0,
    line_count: u16 = 0,
    characteristics: u32 = 0,
}

fn pe_begin(image_base: u64) {
    origin(image_base);
    pe_dos:
    emit.struct(PeDosHeader {});
    emit.bytes(b"This program cannot be run in DOS mode.");
    emit.u16(0x0a0d);
    emit.u8(0x24);
    pad_to(pe_nt_headers_foa, 0);
    pe_nt:
    emit.u32(pe_signature);
}

fn pe_begin32() {
    pe_begin(pe_default_image_base32);
}

fn pe_begin_dll32() {
    pe_begin32();
}

fn pe_begin64() {
    pe_begin(pe_default_image_base64);
}

fn pe_begin_dll64() {
    pe_begin64();
}

fn pe_headers32_with_characteristics(section_count: u16, characteristics: u16) {
    assert(section_count > 0, "pe_headers32 requires at least one section");
    assert(section_count <= pe_max_image_sections, "pe_headers32 section count is too large");
    const headers_size: u64 = align_up(
        pe_section32_table_foa + section_count * pe_section_header_size,
        pe_default_file_align
    )

    pe_file:
    emit.struct(PeFileHeader32 { sections: section_count, characteristics: characteristics });

    pe_opt_a:
    emit.struct(PeOptionalHeader32A {});
    pe_opt_b:
    emit.struct(PeOptionalHeader32B { headers_size: headers_size });

    pe_dirs:
    for i in range(0, pe_data_dir_count) {
        emit.struct(PeDataDir {});
    }

    pe_sections:
    for i in range(0, section_count) {
        emit.struct(PeSectionHeader {});
    }

    pad_to(headers_size, 0);
}

fn pe_headers32(section_count: u16) {
    pe_headers32_with_characteristics(section_count, pe_file_executable_image | pe_file_32bit_machine);
}

fn pe_headers_dll32(section_count: u16) {
    pe_headers32_with_characteristics(section_count, pe_file_executable_image | pe_file_32bit_machine | pe_file_dll);
}

fn pe_headers64_with_characteristics(section_count: u16, characteristics: u16) {
    assert(section_count > 0, "pe_headers64 requires at least one section");
    assert(section_count <= pe_max_image_sections, "pe_headers64 section count is too large");
    const headers_size: u64 = align_up(
        pe_section_table_foa + section_count * pe_section_header_size,
        pe_default_file_align
    )

    pe_file:
    emit.struct(PeFileHeader64 { sections: section_count, characteristics: characteristics });

    pe_opt_a:
    emit.struct(PeOptionalHeader64A {});
    pe_opt_b:
    emit.struct(PeOptionalHeader64B { headers_size: headers_size });

    pe_dirs:
    for i in range(0, pe_data_dir_count) {
        emit.struct(PeDataDir {});
    }

    pe_sections:
    for i in range(0, section_count) {
        emit.struct(PeSectionHeader {});
    }

    pad_to(headers_size, 0);
}

fn pe_headers64(section_count: u16) {
    pe_headers64_with_characteristics(section_count, pe_file_executable_image | pe_file_large_address_aware);
}

fn pe_headers_dll64(section_count: u16) {
    pe_headers64_with_characteristics(section_count, pe_file_executable_image | pe_file_large_address_aware | pe_file_dll);
}

fn pe_begin_section32(name: string, row: u64, rva: u64) {
    assert(row < pe_max_image_sections, "PE section row out of range");
    region.begin(name, pe_default_image_base32 + rva, pe_section_raw_ptr(row, pe_default_file_align));
}

fn pe_begin_section32_at(name: string, row: u64, rva: u64, raw_ptr: u64) {
    assert(row < pe_max_image_sections, "PE section row out of range");
    region.begin(name, pe_default_image_base32 + rva, raw_ptr);
}

fn pe_begin_section(name: string, row: u64, rva: u64) {
    assert(row < pe_max_image_sections, "PE section row out of range");
    region.begin(name, pe_default_image_base64 + rva, pe_section_raw_ptr(row, pe_default_file_align));
}

fn pe_begin_section_at(name: string, row: u64, rva: u64, raw_ptr: u64) {
    assert(row < pe_max_image_sections, "PE section row out of range");
    region.begin(name, pe_default_image_base64 + rva, raw_ptr);
}

fn pe_end_section(row: u64, raw_size: u64) {
    assert(row < pe_max_image_sections, "PE section row out of range");
    pad_to(raw_size, 0);
}

fn pe_align_section_file(row: u64) {
    assert(row < pe_max_image_sections, "PE section row out of range");
    region.file_align(pe_default_file_align);
}

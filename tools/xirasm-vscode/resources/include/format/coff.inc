// COFF object helpers for XIRASM.
//
// This is the stable object-container subset: file header, section headers,
// raw logical regions, explicit relocation records, short-name symbol entries,
// and the string table header. Users pass section-relative offsets and symbol
// indexes explicitly; there is no hidden relocatable element state machine.

import("pe_const.inc");

const coff_file_header_size: u64 = 20
const coff_section_header_size: u64 = 40
const coff_symbol_size: u64 = 18
const coff_reloc_size: u64 = 10
const coff_string_table_min_size: u64 = 4

const coff_machine_i386: u16 = pe_machine_i386
const coff_machine_amd64: u16 = pe_machine_amd64

const coff_file_32bit_machine: u16 = pe_file_32bit_machine
const coff_file_line_nums_stripped: u16 = 0x0004

const coff_scn_cnt_code: u32 = pe_scn_cnt_code
const coff_scn_cnt_init_data: u32 = pe_scn_cnt_init_data
const coff_scn_cnt_uninit_data: u32 = pe_scn_cnt_uninit_data
const coff_scn_mem_execute: u32 = pe_scn_mem_execute
const coff_scn_mem_read: u32 = pe_scn_mem_read
const coff_scn_mem_write: u32 = pe_scn_mem_write

const coff_scn_align_1bytes: u32 = 0x00100000
const coff_scn_align_2bytes: u32 = 0x00200000
const coff_scn_align_4bytes: u32 = 0x00300000
const coff_scn_align_8bytes: u32 = 0x00400000
const coff_scn_align_16bytes: u32 = 0x00500000

const coff_text_chars: u32 = coff_scn_cnt_code | coff_scn_mem_execute | coff_scn_mem_read | coff_scn_align_16bytes
const coff_rdata_chars: u32 = coff_scn_cnt_init_data | coff_scn_mem_read | coff_scn_align_4bytes
const coff_data_chars: u32 = coff_scn_cnt_init_data | coff_scn_mem_read | coff_scn_mem_write | coff_scn_align_4bytes
const coff_bss_chars: u32 = coff_scn_cnt_uninit_data | coff_scn_mem_read | coff_scn_mem_write | coff_scn_align_4bytes

const coff_sym_type_null: u16 = 0
const coff_sym_type_function: u16 = 0x20
const coff_sym_undefined: u16 = 0
const coff_sym_absolute: u16 = 0xffff
const coff_sym_class_external: u8 = 2
const coff_sym_class_static: u8 = 3
const coff_sym_class_weak_external: u8 = 105

const coff_weak_search_no_library: u32 = 1
const coff_weak_search_library: u32 = 2
const coff_weak_search_alias: u32 = 3

const coff_rel_amd64_addr64: u16 = 0x0001
const coff_rel_amd64_addr32: u16 = 0x0002
const coff_rel_amd64_addr32nb: u16 = 0x0003
const coff_rel_amd64_rel32: u16 = 0x0004
const coff_rel_i386_dir32: u16 = 0x0006
const coff_rel_i386_dir32nb: u16 = 0x0007
const coff_rel_i386_rel32: u16 = 0x0014

const coff_sec_name_foa: u64 = 0
const coff_sec_raw_size_foa: u64 = 16
const coff_sec_raw_ptr_foa: u64 = 20
const coff_sec_reloc_ptr_foa: u64 = 24
const coff_sec_reloc_count_foa: u64 = 32
const coff_sec_chars_foa: u64 = 36

const coff_name_text: u64 = 0x000000747865742e
const coff_name_data: u64 = 0x000000617461642e
const coff_name_rdata: u64 = 0x0061746164722e
const coff_name_bss: u64 = 0x0000007373622e
const coff_name_main: u64 = 0x000000006e69616d
const coff_name__main: u64 = 0x0000006e69616d5f
const coff_name_puts: u64 = 0x0000000073747570
const coff_name__puts: u64 = 0x000000737475705f

fn coff_align_up(value: u64, align: u64) -> u64 {
    return ((value + align - 1) / align) * align;
}

fn coff_section_row_foa(row: u64) -> u64 {
    return coff_file_header_size + row * coff_section_header_size;
}

fn coff_first_raw_foa(section_count: u64) -> u64 {
    return coff_align_up(coff_file_header_size + section_count * coff_section_header_size, 4);
}

fn coff_next_foa(file_offset: u64, size: u64, file_align: u64) -> u64 {
    return coff_align_up(file_offset + size, file_align);
}

fn coff_symbol_foa(symbol_table_foa: u64, index: u64) -> u64 {
    return symbol_table_foa + index * coff_symbol_size;
}

fn coff_reloc_foa(reloc_table_foa: u64, index: u64) -> u64 {
    return reloc_table_foa + index * coff_reloc_size;
}

fn coff_reloc_table_end_foa(reloc_table_foa: u64, reloc_count: u64) -> u64 {
    return reloc_table_foa + reloc_count * coff_reloc_size;
}

fn coff_reloc_count(start: u64, end: u64) -> u64 {
    assert(end >= start, "COFF relocation table end is before start");
    assert((end - start) % coff_reloc_size == 0, "COFF relocation table size is not record-aligned");
    return (end - start) / coff_reloc_size;
}

fn coff_reloc_offset(section_start: u64, label_address: u64) -> u64 {
    assert(label_address >= section_start, "COFF relocation location is before its section start");
    return label_address - section_start;
}

fn coff_string_table_foa(symbol_table_foa: u64, symbol_count: u64) -> u64 {
    return symbol_table_foa + symbol_count * coff_symbol_size;
}

fn coff_finalize_section(row: u64, name0: u64, raw_size: u64, raw_ptr: u64, chars: u64) {
    defer {
        store.u64(region_base() + coff_section_row_foa(row) + coff_sec_name_foa, name0);
        store.u32(region_base() + coff_section_row_foa(row) + coff_sec_raw_size_foa, raw_size);
        store.u32(region_base() + coff_section_row_foa(row) + coff_sec_raw_ptr_foa, raw_ptr);
        store.u32(region_base() + coff_section_row_foa(row) + coff_sec_chars_foa, chars);
    }
}

fn coff_finalize_section_auto(row: u64, name0: u64, start: u64, chars: u64) {
    defer {
        store.u64(region_base() + coff_section_row_foa(row) + coff_sec_name_foa, name0);
        store.u32(region_base() + coff_section_row_foa(row) + coff_sec_raw_size_foa, region_file_size(start));
        store.u32(region_base() + coff_section_row_foa(row) + coff_sec_raw_ptr_foa, region_file_offset(start));
        store.u32(region_base() + coff_section_row_foa(row) + coff_sec_chars_foa, chars);
    }
}

fn coff_finalize_section_reloc(row: u64, name0: u64, raw_size: u64, raw_ptr: u64, reloc_ptr: u64, reloc_count: u64, chars: u64) {
    defer {
        store.u64(region_base() + coff_section_row_foa(row) + coff_sec_name_foa, name0);
        store.u32(region_base() + coff_section_row_foa(row) + coff_sec_raw_size_foa, raw_size);
        store.u32(region_base() + coff_section_row_foa(row) + coff_sec_raw_ptr_foa, raw_ptr);
        store.u32(region_base() + coff_section_row_foa(row) + coff_sec_reloc_ptr_foa, reloc_ptr);
        store.u16(region_base() + coff_section_row_foa(row) + coff_sec_reloc_count_foa, reloc_count);
        store.u32(region_base() + coff_section_row_foa(row) + coff_sec_chars_foa, chars);
    }
}

fn coff_finalize_section_reloc_auto(row: u64, name0: u64, start: u64, reloc_ptr: u64, reloc_count: u64, chars: u64) {
    defer {
        store.u64(region_base() + coff_section_row_foa(row) + coff_sec_name_foa, name0);
        store.u32(region_base() + coff_section_row_foa(row) + coff_sec_raw_size_foa, region_file_size(start));
        store.u32(region_base() + coff_section_row_foa(row) + coff_sec_raw_ptr_foa, region_file_offset(start));
        store.u32(region_base() + coff_section_row_foa(row) + coff_sec_reloc_ptr_foa, reloc_ptr);
        store.u16(region_base() + coff_section_row_foa(row) + coff_sec_reloc_count_foa, reloc_count);
        store.u32(region_base() + coff_section_row_foa(row) + coff_sec_chars_foa, chars);
    }
}

fn coff_finalize_symbol_table(symbol_table_start: u64) {
    defer {
        store.u32(region_base() + 8, region_file_offset(symbol_table_start));
    }
}

packed struct CoffFileHeader {
    machine: u16,
    sections: u16,
    timestamp: u32 = 0,
    symbol_ptr: u32,
    symbol_count: u32,
    optional_size: u16 = 0,
    characteristics: u16,
}

packed struct CoffSectionHeader {
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

packed struct CoffSymbol {
    name0: u64 = 0,
    value: u32 = 0,
    section_number: u16 = 0,
    sym_type: u16 = coff_sym_type_null,
    storage_class: u8 = coff_sym_class_static,
    aux_count: u8 = 0,
}

packed struct CoffWeakExternalAux {
    tag_index: u32,
    characteristics: u32,
    reserved0: u64 = 0,
    reserved1: u16 = 0,
}

packed struct CoffRelocation {
    virtual_address: u32,
    symbol_index: u32,
    reloc_type: u16,
}

fn coff_begin(machine: u16, section_count: u16, symbol_table_foa: u64, symbol_count: u64, characteristics: u16) {
    assert(section_count > 0, "coff_begin requires at least one section");
    assert(symbol_count > 0, "coff_begin requires at least one symbol");

    coff_file:
    emit.struct(CoffFileHeader { machine: machine, sections: section_count, symbol_ptr: symbol_table_foa, symbol_count: symbol_count, characteristics: characteristics });

    coff_sections:
    for i in range(0, section_count) {
        emit.struct(CoffSectionHeader {});
    }
}

fn coff_begin32(section_count: u16, symbol_table_foa: u64, symbol_count: u64) {
    coff_begin(coff_machine_i386, section_count, symbol_table_foa, symbol_count, coff_file_32bit_machine | coff_file_line_nums_stripped);
}

fn coff_begin64(section_count: u16, symbol_table_foa: u64, symbol_count: u64) {
    coff_begin(coff_machine_amd64, section_count, symbol_table_foa, symbol_count, coff_file_line_nums_stripped);
}

fn coff_begin_section(name: string, raw_ptr: u64) {
    region.begin(name, 0, raw_ptr);
}

fn coff_begin_section_auto(name: string) {
    region.begin(name, file_offset(), file_offset());
}

fn coff_end_section(raw_size: u64) {
    pad_to(raw_size, 0);
}

fn coff_align_section_file() {
    region.file_align(4);
}

fn coff_begin_symbols(name: string) {
    region.begin(name, file_offset(), file_offset());
    coff_finalize_symbol_table(here());
}

fn coff_symbol(name0: u64, value: u64, section_number: u16, storage_class: u8, sym_type: u16) {
    emit.struct(CoffSymbol { name0: name0, value: value, section_number: section_number, sym_type: sym_type, storage_class: storage_class });
}

fn coff_public(name0: u64, value: u64, section_number: u16, sym_type: u16) {
    coff_symbol(name0, value, section_number, coff_sym_class_external, sym_type);
}

fn coff_static(name0: u64, value: u64, section_number: u16, sym_type: u16) {
    coff_symbol(name0, value, section_number, coff_sym_class_static, sym_type);
}

fn coff_extrn(name0: u64, sym_type: u16) {
    coff_symbol(name0, 0, coff_sym_undefined, coff_sym_class_external, sym_type);
}

fn coff_weak_external_alias(name0: u64, fallback_symbol_index: u64, sym_type: u16) {
    emit.struct(CoffSymbol {
        name0: name0,
        section_number: coff_sym_undefined,
        sym_type: sym_type,
        storage_class: coff_sym_class_weak_external,
        aux_count: 1,
    });
    emit.struct(CoffWeakExternalAux {
        tag_index: fallback_symbol_index,
        characteristics: coff_weak_search_alias,
    });
}

fn coff_reloc(virtual_address: u64, symbol_index: u64, reloc_type: u16) {
    emit.struct(CoffRelocation { virtual_address: virtual_address, symbol_index: symbol_index, reloc_type: reloc_type });
}

fn coff_reloc_at(section_start: u64, label_address: u64, symbol_index: u64, reloc_type: u16) {
    coff_reloc(coff_reloc_offset(section_start, label_address), symbol_index, reloc_type);
}

fn coff_reloc_amd64_addr64_at(section_start: u64, label_address: u64, symbol_index: u64) {
    coff_reloc_at(section_start, label_address, symbol_index, coff_rel_amd64_addr64);
}

fn coff_reloc_amd64_addr32_at(section_start: u64, label_address: u64, symbol_index: u64) {
    coff_reloc_at(section_start, label_address, symbol_index, coff_rel_amd64_addr32);
}

fn coff_reloc_amd64_addr32nb_at(section_start: u64, label_address: u64, symbol_index: u64) {
    coff_reloc_at(section_start, label_address, symbol_index, coff_rel_amd64_addr32nb);
}

fn coff_reloc_amd64_rel32_at(section_start: u64, label_address: u64, symbol_index: u64) {
    coff_reloc_at(section_start, label_address, symbol_index, coff_rel_amd64_rel32);
}

fn coff_reloc_i386_dir32_at(section_start: u64, label_address: u64, symbol_index: u64) {
    coff_reloc_at(section_start, label_address, symbol_index, coff_rel_i386_dir32);
}

fn coff_reloc_i386_dir32nb_at(section_start: u64, label_address: u64, symbol_index: u64) {
    coff_reloc_at(section_start, label_address, symbol_index, coff_rel_i386_dir32nb);
}

fn coff_reloc_i386_rel32_at(section_start: u64, label_address: u64, symbol_index: u64) {
    coff_reloc_at(section_start, label_address, symbol_index, coff_rel_i386_rel32);
}

fn coff_end_symbols(symbol_count: u64) {
    emit.u32(coff_string_table_min_size);
    assert(symbol_count > 0, "COFF symbol table must not be empty");
}

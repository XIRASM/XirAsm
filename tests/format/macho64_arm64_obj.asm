import("../../include/format/macho_obj.inc");

const section_count: u64 = 1
const command_count: u64 = 2
const command_size: u64 = macho_segment_command64_size_for(section_count) + macho_symtab_command_size

const text_foa: u64 = macho_header64_size + command_size
const text_size: u64 = 16
const relocation_foa: u64 = text_foa + text_size
const relocation_count: u64 = 3
const symbol_foa: u64 = relocation_foa + relocation_count * macho_relocation_size
const symbol_count: u64 = 3
const string_foa: u64 = symbol_foa + symbol_count * macho_nlist64_size

const start_string_index: u64 = 1
const callee_string_index: u64 = 8
const data_string_index: u64 = 16
const string_size: u64 = 22

region.begin(".macho.header", 0, 0);
macho_file:
macho_obj_header64_arm64(command_count, command_size);
macho_segment64("", 0, text_size, text_foa, text_size, macho_vm_prot_read | macho_vm_prot_write | macho_vm_prot_execute, macho_vm_prot_read | macho_vm_prot_write | macho_vm_prot_execute, section_count, 0);
macho_section64("__text", "__TEXT", 0, text_size, text_foa, 2, relocation_foa, relocation_count, macho_s_regular | macho_s_attr_pure_instructions | macho_s_attr_some_instructions, 0, 0, 0);
macho_symtab_command(symbol_foa, symbol_count, string_foa, string_size);

defer {
    assert(load.u32(macho_file) == macho_magic_64);
    assert(load.u32(macho_file + 4) == macho_cpu_type_arm64);
    assert(load.u32(macho_file + 12) == macho_mh_object);
    assert(load.u32(macho_file + 16) == command_count);
    assert(load.u32(macho_file + 20) == command_size);
    assert(region_file_offset(macho_file) == 0);
    assert(region_file_size(macho_file) == text_foa);
}

region.begin("__text", 0, text_foa);
text_start:
start:
    emit.u32(0x94000000);
    emit.u32(0x90000000);
    emit.u32(0x91000000);
    emit.u32(0xd65f03c0);
text_end:
defer {
    assert(load.u32(text_start) == 0x94000000);
    assert(load.u32(text_start + 4) == 0x90000000);
    assert(load.u32(text_start + 8) == 0x91000000);
    assert(load.u32(text_start + 12) == 0xd65f03c0);
    assert(region_file_offset(text_start) == text_foa);
    assert(region_file_size(text_start) == text_size);
}

region.begin(".reloc", 0, relocation_foa);
relocation_start:
macho_arm64_reloc_pageoff12_external(8, 2);
macho_arm64_reloc_page21_external(4, 2);
macho_arm64_reloc_branch26_external(0, 1);
defer {
    assert(load.u32(relocation_start) == 8);
    assert(load.u32(relocation_start + 4) == 0x4c000002);
    assert(load.u32(relocation_start + 8) == 4);
    assert(load.u32(relocation_start + 12) == 0x3d000002);
    assert(load.u32(relocation_start + 16) == 0);
    assert(load.u32(relocation_start + 20) == 0x2d000001);
    assert(region_file_offset(relocation_start) == relocation_foa);
}

region.begin(".symtab", 0, symbol_foa);
symbol_start:
macho_nlist64(start_string_index, macho_n_sect | macho_n_ext, 1, 0, 0);
macho_nlist64(callee_string_index, macho_n_undef | macho_n_ext, 0, 0, 0);
macho_nlist64(data_string_index, macho_n_undef | macho_n_ext, 0, 0, 0);

region.begin(".strtab", 0, string_foa);
string_start:
db(0, "_start", 0, "_callee", 0, "_data", 0);
defer {
    assert(region_file_offset(symbol_start) == symbol_foa);
    assert(region_file_size(symbol_start) == symbol_count * macho_nlist64_size);
    assert(region_file_offset(string_start) == string_foa);
    assert(region_file_size(string_start) == string_size);
}

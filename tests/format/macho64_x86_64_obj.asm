import("../../include/format/macho_obj.inc");

const section_count: u64 = 1
const command_count: u64 = 2
const command_size: u64 = macho_segment_command64_size_for(section_count) + macho_symtab_command_size
const text_foa: u64 = macho_header64_size + command_size
const text_size: u64 = 6
const relocation_foa: u64 = text_foa + text_size
const symbol_count: u64 = 2
const symbol_foa: u64 = relocation_foa + macho_relocation_size
const string_foa: u64 = symbol_foa + symbol_count * macho_nlist64_size
const string_size: u64 = 16

region.begin(".macho.header", 0, 0);
macho_file:
macho_obj_header64_x86_64(command_count, command_size);
macho_segment64("", 0, text_size, text_foa, text_size, macho_vm_prot_read | macho_vm_prot_write | macho_vm_prot_execute, macho_vm_prot_read | macho_vm_prot_write | macho_vm_prot_execute, section_count, 0);
macho_section64("__text", "__TEXT", 0, text_size, text_foa, 2, relocation_foa, 1, macho_s_regular | macho_s_attr_pure_instructions | macho_s_attr_some_instructions, 0, 0, 0);
macho_symtab_command(symbol_foa, symbol_count, string_foa, string_size);

region.begin("__text", 0, text_foa);
text_start:
emit.u8(0xe8);
emit.u8(0);
emit.u8(0);
emit.u8(0);
emit.u8(0);
emit.u8(0xc3);

region.begin(".reloc", 0, relocation_foa);
relocation_start:
macho_x86_64_reloc_branch_external(1, 1);

region.begin(".symtab", 0, symbol_foa);
symbol_start:
macho_nlist64(1, macho_n_sect | macho_n_ext, 1, 0, 0);
macho_nlist64(8, macho_n_undef | macho_n_ext, 0, 0, 0);

region.begin(".strtab", 0, string_foa);
string_start:
db(0, "_start", 0, "_callee", 0);

defer {
    assert(load.u32(macho_file + 4) == macho_cpu_type_x86_64);
    assert(load.u32(macho_file + 8) == macho_cpu_subtype_x86_64_all);
    assert(load.u32(text_start) == 0x000000e8);
    assert(load.u32(relocation_start + 4) == 0x2d000001);
    assert(region_file_size(text_start) == text_size);
    assert(region_file_size(symbol_start) == symbol_count * macho_nlist64_size);
    assert(region_file_size(string_start) == string_size);
}

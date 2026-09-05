import("../../include/format/macho_obj.inc");

const command_size: u64 = macho_segment_command64_size_for(1) + macho_symtab_command_size
const text_foa: u64 = macho_header64_size + command_size
const text_size: u64 = 1
const symbol_foa: u64 = text_foa + text_size
const string_foa: u64 = symbol_foa + macho_nlist64_size
const string_size: u64 = 9

region.begin("file", 0, 0);
macho_file:
macho_obj_header64_x86_64(2, command_size);
macho_segment64("", 0, text_size, text_foa, text_size, macho_vm_prot_read | macho_vm_prot_execute, macho_vm_prot_read | macho_vm_prot_execute, 1, 0);
macho_section64("__text", "__TEXT", 0, text_size, text_foa, 0, 0, 0, macho_s_regular | macho_s_attr_pure_instructions | macho_s_attr_some_instructions, 0, 0, 0);
macho_symtab_command(symbol_foa, 1, string_foa, string_size);
region.begin("text", 0, text_foa);
callee:
emit.u8(0xc3);
region.begin("sym", 0, symbol_foa);
macho_nlist64(1, macho_n_sect | macho_n_ext, 1, 0, 0);
region.begin("str", 0, string_foa);
db(0, "_callee", 0);

import("../../include/format/macho_obj.inc");

const command_size: u64 = macho_segment_command64_size_for(1) + macho_symtab_command_size
const data_foa: u64 = macho_header64_size + command_size
const data_size: u64 = 8
const symbol_foa: u64 = data_foa + data_size
const string_foa: u64 = symbol_foa + macho_nlist64_size
const string_size: u64 = 7

region.begin("file", 0, 0);
macho_file:
macho_obj_header64_x86_64(2, command_size);
macho_segment64("", 0, data_size, data_foa, data_size, macho_vm_prot_read | macho_vm_prot_write, macho_vm_prot_read | macho_vm_prot_write, 1, 0);
macho_section64("__data", "__DATA", 0, data_size, data_foa, 3, 0, 0, macho_s_regular, 0, 0, 0);
macho_symtab_command(symbol_foa, 1, string_foa, string_size);
region.begin("data", 0, data_foa);
value:
emit.u64(0x1122334455667788);
region.begin("sym", 0, symbol_foa);
macho_nlist64(1, macho_n_sect | macho_n_ext, 1, 0, 0);
region.begin("str", 0, string_foa);
db(0, "_data", 0);

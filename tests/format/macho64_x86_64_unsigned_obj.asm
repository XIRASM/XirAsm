import("../../include/format/macho_obj.inc");

const section_count: u64 = 1
const command_size: u64 = macho_segment_command64_size_for(section_count) + macho_symtab_command_size
const data_foa: u64 = macho_header64_size + command_size
const data_size: u64 = 8
const relocation_foa: u64 = data_foa + data_size
const symbol_count: u64 = 2
const symbol_foa: u64 = relocation_foa + macho_relocation_size
const string_foa: u64 = symbol_foa + symbol_count * macho_nlist64_size
const string_size: u64 = 14

region.begin(".macho.header", 0, 0);
macho_file:
macho_obj_header64_x86_64(2, command_size);
macho_segment64("", 0, data_size, data_foa, data_size, macho_vm_prot_read | macho_vm_prot_write, macho_vm_prot_read | macho_vm_prot_write, section_count, 0);
macho_section64("__data", "__DATA", 0, data_size, data_foa, 3, relocation_foa, 1, macho_s_regular, 0, 0, 0);
macho_symtab_command(symbol_foa, symbol_count, string_foa, string_size);

region.begin("__data", 0, data_foa);
start:
data:
emit.u64(0);
region.begin(".reloc", 0, relocation_foa);
reloc:
macho_x86_64_reloc_unsigned_external(0, 1);
region.begin(".symtab", 0, symbol_foa);
macho_nlist64(1, macho_n_sect | macho_n_ext, 1, 0, 0);
macho_nlist64(8, macho_n_undef | macho_n_ext, 0, 0, 0);
region.begin(".strtab", 0, string_foa);
strings:
db(0, "_start", 0, "_data", 0);

defer {
    assert(load.u32(macho_file + 4) == macho_cpu_type_x86_64);
    assert(load.u32(data) == 0);
    assert(load.u32(reloc + 4) == 0x0e000001);
    assert(region_file_size(data) == data_size);
    assert(region_file_size(strings) == string_size);
}

// Mach-O 64 relocatable-object helpers for XIRASM.
//
// This direct layer keeps section indexes, symbol indexes, offsets, and
// relocations explicit. It does not perform linking or resolve extern symbols.
// ARM64 and x86_64 relocation wrappers remain architecture-specific.

import("macho_const.inc");

const macho_header64_size: u64 = 32
const macho_segment_command64_size: u64 = 72
const macho_section64_size: u64 = 80
const macho_symtab_command_size: u64 = 24
const macho_dysymtab_command_size: u64 = 80
const macho_nlist64_size: u64 = 16
const macho_relocation_size: u64 = 8

fn macho_align_up(value: u64, alignment: u64) -> u64 {
    assert(alignment > 0, "Mach-O alignment is zero");
    assert((alignment & (alignment - 1)) == 0, "Mach-O alignment is not a power of two");
    return (value + alignment - 1) & ~(alignment - 1);
}

fn macho_segment_command64_size_for(section_count: u64) -> u64 {
    assert(section_count <= 255, "Mach-O segment has too many sections");
    return macho_segment_command64_size + section_count * macho_section64_size;
}

fn macho_emit_name16(name: string) {
    assert(len(name) <= 16, "Mach-O name exceeds 16 bytes");
    db(name);
    pad(16 - len(name), 0);
}

fn macho_header64(file_type: u64, cpu_type: u64, cpu_subtype: u64, command_count: u64, command_size: u64, flags: u64) {
    assert(file_type == macho_mh_object || file_type == macho_mh_execute || file_type == macho_mh_dylib, "unsupported Mach-O file type");
    emit.u32(macho_magic_64);
    emit.u32(cpu_type);
    emit.u32(cpu_subtype);
    emit.u32(file_type);
    emit.u32(command_count);
    emit.u32(command_size);
    emit.u32(flags);
    emit.u32(0);
}

fn macho_header64_arm64(file_type: u64, command_count: u64, command_size: u64, flags: u64) {
    macho_header64(file_type, macho_cpu_type_arm64, macho_cpu_subtype_arm64_all, command_count, command_size, flags);
}

fn macho_header64_x86_64(file_type: u64, command_count: u64, command_size: u64, flags: u64) {
    macho_header64(file_type, macho_cpu_type_x86_64, macho_cpu_subtype_x86_64_all, command_count, command_size, flags);
}

fn macho_obj_header64_arm64(command_count: u64, command_size: u64) {
    macho_header64_arm64(macho_mh_object, command_count, command_size, macho_mh_subsections_via_symbols);
}

fn macho_obj_header64_x86_64(command_count: u64, command_size: u64) {
    macho_header64_x86_64(macho_mh_object, command_count, command_size, macho_mh_subsections_via_symbols);
}

fn macho_segment64(name: string, vmaddr: u64, vmsize: u64, file_offset: u64, file_size: u64, max_prot: u64, initial_prot: u64, section_count: u64, flags: u64) {
    emit.u32(macho_lc_segment_64);
    emit.u32(macho_segment_command64_size_for(section_count));
    macho_emit_name16(name);
    emit.u64(vmaddr);
    emit.u64(vmsize);
    emit.u64(file_offset);
    emit.u64(file_size);
    emit.u32(max_prot);
    emit.u32(initial_prot);
    emit.u32(section_count);
    emit.u32(flags);
}

fn macho_section64(name: string, segment_name: string, address: u64, size: u64, file_offset: u64, align_power: u64, relocation_offset: u64, relocation_count: u64, flags: u64, reserved1: u64, reserved2: u64, reserved3: u64) {
    assert(align_power < 64, "Mach-O section alignment power is invalid");
    macho_emit_name16(name);
    macho_emit_name16(segment_name);
    emit.u64(address);
    emit.u64(size);
    emit.u32(file_offset);
    emit.u32(align_power);
    emit.u32(relocation_offset);
    emit.u32(relocation_count);
    emit.u32(flags);
    emit.u32(reserved1);
    emit.u32(reserved2);
    emit.u32(reserved3);
}

fn macho_symtab_command(symbol_offset: u64, symbol_count: u64, string_offset: u64, string_size: u64) {
    assert(string_size > 0, "Mach-O string table is empty");
    emit.u32(macho_lc_symtab);
    emit.u32(macho_symtab_command_size);
    emit.u32(symbol_offset);
    emit.u32(symbol_count);
    emit.u32(string_offset);
    emit.u32(string_size);
}

fn macho_dysymtab_command(local_index: u64, local_count: u64, defined_index: u64, defined_count: u64, undefined_index: u64, undefined_count: u64, indirect_offset: u64, indirect_count: u64) {
    emit.u32(macho_lc_dysymtab);
    emit.u32(macho_dysymtab_command_size);
    emit.u32(local_index);
    emit.u32(local_count);
    emit.u32(defined_index);
    emit.u32(defined_count);
    emit.u32(undefined_index);
    emit.u32(undefined_count);
    emit.u32(0);
    emit.u32(0);
    emit.u32(0);
    emit.u32(0);
    emit.u32(0);
    emit.u32(0);
    emit.u32(indirect_offset);
    emit.u32(indirect_count);
    emit.u32(0);
    emit.u32(0);
    emit.u32(0);
    emit.u32(0);
}

fn macho_nlist64(string_index: u64, symbol_type: u64, section_index: u64, description: u64, value: u64) {
    assert((symbol_type & macho_n_stab) == 0, "Mach-O STAB symbols are not supported by this helper");
    emit.u32(string_index);
    emit.u8(symbol_type);
    emit.u8(section_index);
    emit.u16(description);
    emit.u64(value);
}

fn macho_relocation_info(address: u64, symbol_number: u64, pc_relative: u64, length_power: u64, is_external: u64, relocation_type: u64) {
    assert(symbol_number < 0x1000000, "Mach-O relocation symbol number exceeds 24 bits");
    assert(pc_relative <= 1, "Mach-O relocation pcrel flag exceeds one bit");
    assert(length_power <= 3, "Mach-O relocation length exceeds two bits");
    assert(is_external <= 1, "Mach-O relocation external flag exceeds one bit");
    assert(relocation_type <= 15, "Mach-O relocation type exceeds four bits");
    emit.u32(address);
    emit.u32(symbol_number | (pc_relative << 24) | (length_power << 25) | (is_external << 27) | (relocation_type << 28));
}

fn macho_arm64_reloc_branch26_external(address: u64, symbol_index: u64) {
    macho_relocation_info(address, symbol_index, 1, 2, 1, macho_arm64_reloc_branch26);
}

fn macho_arm64_reloc_page21_external(address: u64, symbol_index: u64) {
    macho_relocation_info(address, symbol_index, 1, 2, 1, macho_arm64_reloc_page21);
}

fn macho_arm64_reloc_pageoff12_external(address: u64, symbol_index: u64) {
    macho_relocation_info(address, symbol_index, 0, 2, 1, macho_arm64_reloc_pageoff12);
}

fn macho_x86_64_reloc_branch_external(address: u64, symbol_index: u64) {
    macho_relocation_info(address, symbol_index, 1, 2, 1, macho_x86_64_reloc_branch);
}

fn macho_x86_64_reloc_unsigned_external(address: u64, symbol_index: u64) {
    macho_relocation_info(address, symbol_index, 0, 3, 1, macho_x86_64_reloc_unsigned);
}

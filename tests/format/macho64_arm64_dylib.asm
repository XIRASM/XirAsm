import("../../include/format/macho_dylib.inc");

const command_count: u64 = 6
const id_command_size: u64 = macho_align_up(macho_dylib_id_command_base_size + len("@rpath/libxirtest.dylib") + 1, 8)
const load_command_size: u64 = macho_align_up(macho_dylib_id_command_base_size + len("@rpath/libxirdep.dylib") + 1, 8)
const command_size: u64 = macho_segment_command64_size_for(1) + id_command_size + load_command_size + macho_dylib_build_version_command_size + macho_dylib_export_command_size + macho_segment_command64_size
const text_foa: u64 = macho_align_up(macho_header64_size + command_size, 16)
const text_size: u64 = 4
const linkedit_foa: u64 = macho_align_up(text_foa + text_size, 16)
const text_file_size: u64 = text_foa + text_size
const text_vm_size: u64 = macho_align_up(text_file_size, 0x1000)

region.begin(".macho.header", 0, 0);
macho_file:
macho_dylib_header64_arm64(command_count, command_size);
macho_segment64("__TEXT", 0, text_vm_size, 0, text_file_size, macho_vm_prot_read | macho_vm_prot_execute, macho_vm_prot_read | macho_vm_prot_execute, 1, 0);
macho_section64("__text", "__TEXT", 0x80, text_size, text_foa, 2, 0, 0, macho_s_regular | macho_s_attr_pure_instructions | macho_s_attr_some_instructions, 0, 0, 0);
macho_dylib_id64("@rpath/libxirtest.dylib", 0x00010000, 0x00010000);
macho_dylib_load64("@rpath/libxirdep.dylib", 0x00010000, 0x00010000);
macho_dylib_build_version64(0x000e0000, 0x000e0000);
macho_dylib_exports_trie64(linkedit_foa, macho_dylib_export_entry_trie_size);
macho_segment64("__LINKEDIT", linkedit_foa, 0x1000, linkedit_foa, macho_dylib_export_entry_trie_size, macho_vm_prot_read, macho_vm_prot_read, 0, 0);

region.begin("__text", 0x80, text_foa);
entry:
emit.u32(0xd65f03c0);

region.begin("__LINKEDIT", linkedit_foa, linkedit_foa);
exports:
macho_dylib_export_entry_0x80();

defer {
    assert(load.u32(macho_file) == macho_magic_64);
    assert(load.u32(macho_file + 12) == macho_mh_dylib);
    assert(load.u32(macho_file + 16) == command_count);
    assert(load.u32(macho_file + 20) == command_size);
    assert(load.u32(entry) == 0xd65f03c0);
    assert(region_file_offset(entry) == text_foa);
    assert(region_file_offset(exports) == linkedit_foa);
    assert(region_file_size(exports) == macho_dylib_export_entry_trie_size);
}

import("../../include/format/macho_dylib.inc");

const exports: list = macho_export_use64(
    macho_export_use64(macho_export_new(), "add7", "_add7"),
    "sub3", "_sub3")
const command_count: u64 = 5
const id_command_size: u64 = macho_align_up(macho_dylib_id_command_base_size + len("@rpath/libxirffi.dylib") + 1, 8)
const command_size: u64 = macho_segment_command64_size_for(1) + id_command_size + macho_dylib_build_version_command_size + macho_dylib_export_command_size + macho_segment_command64_size
const export_command_offset: u64 = macho_header64_size + macho_segment_command64_size_for(1) + id_command_size + macho_dylib_build_version_command_size
const linkedit_segment_offset: u64 = export_command_offset + macho_dylib_export_command_size
const text_foa: u64 = macho_align_up(macho_header64_size + command_size, 16)
const text_size: u64 = 8
const linkedit_foa: u64 = macho_align_up(text_foa + text_size, 16)
const text_file_size: u64 = text_foa + text_size
const text_vm_size: u64 = macho_align_up(text_file_size, 0x1000)

region.begin(".macho.header", 0, 0);
macho_file:
macho_dylib_header64_x86_64(command_count, command_size);
macho_segment64("__TEXT", 0, text_vm_size, 0, text_file_size, macho_vm_prot_read | macho_vm_prot_execute, macho_vm_prot_read | macho_vm_prot_execute, 1, 0);
macho_section64("__text", "__TEXT", 0x80, text_size, text_foa, 2, 0, 0, macho_s_regular | macho_s_attr_pure_instructions | macho_s_attr_some_instructions, 0, 0, 0);
macho_dylib_id64("@rpath/libxirffi.dylib", 0x00010000, 0x00010000);
macho_dylib_build_version64(0x000e0000, 0x000e0000);
macho_dylib_exports_trie64(linkedit_foa, 0);
macho_segment64("__LINKEDIT", linkedit_foa, 0x1000, linkedit_foa, 0, macho_vm_prot_read, macho_vm_prot_read, 0, 0);

region.begin("__text", 0x80, text_foa);
add7:
emit.u32(0xd28000e0);
emit.u32(0xd65f03c0);
sub3:
emit.u32(0xd2800060);
emit.u32(0xd65f03c0);

let export_size: u64 = macho_export_trie_size64(exports, 0)

region.begin("__LINKEDIT", linkedit_foa, linkedit_foa);
exports_data:
macho_export_trie_emit64(exports, 0);

defer {
    assert(load.u32(macho_file + 4) == macho_cpu_type_x86_64);
    assert(load.u32(macho_file + 12) == macho_mh_dylib);
    store.u32(macho_file + export_command_offset + 12, export_size);
    store.u64(macho_file + linkedit_segment_offset + 48, export_size);
    assert(region_file_size(exports_data) == export_size);
}

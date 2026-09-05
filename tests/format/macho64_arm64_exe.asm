import("../../include/format/macho_exe.inc");

const image_base: u64 = 0x100000000
const page_size: u64 = macho_target_page_size64(macho_cpu_type_arm64)
const dylinker_size: u64 = macho_align_up(macho_exe_dylinker_command_base_size + len("/usr/lib/dyld") + 1, 8)
const command_count: u64 = 6
const command_size: u64 = macho_exe_pagezero_command_size + macho_exe_text_command_size + macho_segment_command64_size + dylinker_size + macho_exe_main_command_size + macho_exe_build_version_command_size
const text_foa: u64 = macho_align_up(macho_header64_size + command_size, 16)
const text_size: u64 = 8
const text_vaddr: u64 = image_base + text_foa
const text_file_size: u64 = text_foa + text_size
const text_vm_size: u64 = macho_align_up(text_file_size, page_size)

region.begin(".macho.header", image_base, 0);
macho_file:
macho_exe_header64_arm64(command_count, command_size);
macho_exe_pagezero64(image_base);
macho_exe_text_segment64(image_base, text_vm_size, text_vm_size, text_vaddr, text_size, text_foa);
macho_segment64("__LINKEDIT", image_base + text_vm_size, 0, text_vm_size, 0, macho_vm_prot_read, macho_vm_prot_read, 0, 0);
macho_exe_load_dylinker64("/usr/lib/dyld");
macho_exe_main64(text_foa, 0);
macho_exe_build_version64(macho_exe_macos_version(14, 0, 0), macho_exe_macos_version(14, 0, 0));

region.begin("__text", text_vaddr, text_foa);
entry:
    emit.u32(0xd2800000);
    emit.u32(0xd65f03c0);

defer {
    assert(load.u32(macho_file) == macho_magic_64);
    assert(load.u32(macho_file + 4) == macho_cpu_type_arm64);
    assert(load.u32(macho_file + 12) == macho_mh_execute);
    assert(load.u32(macho_file + 16) == command_count);
    assert(load.u32(macho_file + 20) == command_size);
    assert(load.u64(entry) == 0xd65f03c0d2800000);
    assert(region_file_offset(entry) == text_foa);
    assert(region_file_size(entry) == text_size);
}

region.begin("__LINKEDIT", image_base + text_vm_size, text_vm_size);

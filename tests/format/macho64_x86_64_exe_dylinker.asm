import("../../include/format/macho_exe.inc");

const image_base: u64 = 0x100000000
const dylinker_command_size: u64 = macho_align_up(macho_exe_dylinker_command_base_size + len("/usr/lib/dyld") + 1, 8)
const command_count: u64 = 5
const command_size: u64 = macho_exe_pagezero_command_size + macho_exe_text_command_size + dylinker_command_size + macho_exe_main_command_size + macho_exe_build_version_command_size
const text_foa: u64 = macho_align_up(macho_header64_size + command_size, 16)
const text_size: u64 = 3
const text_vaddr: u64 = image_base + text_foa
const text_file_size: u64 = text_foa + text_size
const text_vm_size: u64 = macho_align_up(text_file_size, macho_exe_page_size)

region.begin(".macho.header", image_base, 0);
macho_file:
macho_exe_header64_x86_64(command_count, command_size);
macho_exe_pagezero64(image_base);
macho_exe_text_segment64(image_base, text_vm_size, text_file_size, text_vaddr, text_size, text_foa);
macho_exe_load_dylinker64("/usr/lib/dyld");
macho_exe_main64(text_foa, 0);
macho_exe_build_version64(macho_exe_macos_version(14, 0, 0), macho_exe_macos_version(14, 0, 0));

region.begin("__text", text_vaddr, text_foa);
entry:
emit.u8(0x31);
emit.u8(0xc0);
emit.u8(0xc3);

defer {
    assert(load.u32(macho_file + 4) == macho_cpu_type_x86_64);
    assert(load.u32(macho_file + 16) == command_count);
    assert(load.u32(macho_file + 20) == command_size);
    assert(load.u32(macho_file + macho_header64_size + macho_exe_pagezero_command_size + macho_exe_text_command_size) == macho_lc_load_dylinker);
    assert(region_file_offset(entry) == text_foa);
}

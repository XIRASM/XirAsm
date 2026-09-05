// Minimal self-contained Mach-O 64 executable helpers.
//
// This layer emits a fixed command set suitable for a small MH_EXECUTE image.
// Dynamic-import tables and ISA-specific stubs live in macho_import.inc.

import("macho_obj.inc");

const macho_exe_pagezero_command_size: u64 = macho_segment_command64_size
const macho_exe_text_command_size: u64 = macho_segment_command64_size_for(1)
const macho_exe_main_command_size: u64 = 24
const macho_exe_build_version_command_size: u64 = 24
const macho_exe_dylinker_command_base_size: u64 = 12
const macho_exe_dyld_info_command_size: u64 = 48
const macho_exe_dynamic_flags: u64 = macho_mh_noundefs | macho_mh_dyldlink | macho_mh_twolevel | macho_mh_pie

fn macho_exe_header64_arm64(command_count: u64, command_size: u64) {
    macho_header64_arm64(macho_mh_execute, command_count, command_size, macho_exe_dynamic_flags);
}

fn macho_exe_header64_x86_64(command_count: u64, command_size: u64) {
    macho_header64(macho_mh_execute, macho_cpu_type_x86_64,
        macho_cpu_subtype_x86_64_all | macho_cpu_subtype_lib64,
        command_count, command_size, macho_exe_dynamic_flags);
}

fn macho_exe_pagezero64(vmsize: u64) {
    macho_segment64("__PAGEZERO", 0, vmsize, 0, 0, 0, 0, 0, 0);
}

fn macho_exe_load_dylinker64(name: string) {
    assert(len(name) > 0, "Mach-O dynamic linker path is empty");
    const name_size: u64 = len(name) + 1;
    const command_size: u64 = macho_align_up(macho_exe_dylinker_command_base_size + name_size, 8);
    emit.u32(macho_lc_load_dylinker);
    emit.u32(command_size);
    emit.u32(macho_exe_dylinker_command_base_size);
    db(name);
    db(0);
    pad(command_size - macho_exe_dylinker_command_base_size - name_size, 0);
}

fn macho_exe_text_segment64(vmaddr: u64, vmsize: u64, file_size: u64, section_address: u64, section_size: u64, section_file_offset: u64) {
    macho_segment64("__TEXT", vmaddr, vmsize, 0, file_size, macho_vm_prot_read | macho_vm_prot_execute, macho_vm_prot_read | macho_vm_prot_execute, 1, 0);
    macho_section64("__text", "__TEXT", section_address, section_size, section_file_offset, 2, 0, 0, macho_s_regular | macho_s_attr_pure_instructions | macho_s_attr_some_instructions, 0, 0, 0);
}

fn macho_exe_main64(entry_offset: u64, stack_size: u64) {
    emit.u32(macho_lc_main);
    emit.u32(macho_exe_main_command_size);
    emit.u64(entry_offset);
    emit.u64(stack_size);
}

fn macho_exe_build_version64(minos: u64, sdk: u64) {
    emit.u32(macho_lc_build_version);
    emit.u32(macho_exe_build_version_command_size);
    emit.u32(macho_platform_macos);
    emit.u32(minos);
    emit.u32(sdk);
    emit.u32(0);
}

fn macho_exe_dyld_info_only64(rebase_offset: u64, rebase_size: u64, bind_offset: u64, bind_size: u64, weak_bind_offset: u64, weak_bind_size: u64, lazy_bind_offset: u64, lazy_bind_size: u64, export_offset: u64, export_size: u64) {
    emit.u32(macho_lc_dyld_info_only);
    emit.u32(macho_exe_dyld_info_command_size);
    emit.u32(rebase_offset);
    emit.u32(rebase_size);
    emit.u32(bind_offset);
    emit.u32(bind_size);
    emit.u32(weak_bind_offset);
    emit.u32(weak_bind_size);
    emit.u32(lazy_bind_offset);
    emit.u32(lazy_bind_size);
    emit.u32(export_offset);
    emit.u32(export_size);
}

fn macho_exe_macos_version(major: u64, minor: u64, patch: u64) -> u64 {
    assert(major < 0x10000, "Mach-O version major exceeds 16 bits");
    assert(minor < 0x100, "Mach-O version minor exceeds 8 bits");
    assert(patch < 0x100, "Mach-O version patch exceeds 8 bits");
    return (major << 16) | (minor << 8) | patch;
}

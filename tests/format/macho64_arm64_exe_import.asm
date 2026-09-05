import("../../include/format/macho_import.inc");

const library: string = "@executable_path/libxirarmffi.dylib"
const library2: string = "@executable_path/libxirconstants.dylib"
const imports: list = macho_import_use64_as(
    macho_import_use64(
        macho_import_use64(macho_import_new(), library, "_entry"),
        library2,
        "_answer"),
    library2,
    "_entry",
    "_entry_constants_stub",
    "_entry_constants_got")
const image_base: u64 = 0x100000000
const page_size: u64 = macho_target_page_size64(macho_cpu_type_arm64)
const dylinker_size: u64 = macho_align_up(macho_exe_dylinker_command_base_size + len("/usr/lib/dyld") + 1, 8)
const dylib_size: u64 = macho_import_load_dylibs_size64(imports)
const command_count: u64 = 12
const command_size: u64 = macho_exe_pagezero_command_size + macho_segment_command64_size_for(2) + macho_segment_command64_size_for(2) + macho_segment_command64_size + macho_exe_dyld_info_command_size + macho_symtab_command_size + macho_dysymtab_command_size + dylinker_size + dylib_size + macho_exe_build_version_command_size + macho_exe_main_command_size
const text_foa: u64 = macho_align_up(macho_header64_size + command_size, 16)
const text_vaddr: u64 = image_base + text_foa
const code_size: u64 = 4
const stubs_foa: u64 = text_foa + code_size
const stubs_vaddr: u64 = image_base + stubs_foa
const stubs_size: u64 = len(imports) * macho_import_arm64_stub_size
const data_foa: u64 = macho_align_up(stubs_foa + stubs_size, page_size)
const data_vaddr: u64 = image_base + data_foa
const data_size: u64 = 8
const got_offset: u64 = 0x20
const slots_foa: u64 = data_foa + got_offset
const slots_vaddr: u64 = data_vaddr + got_offset
const slots_size: u64 = len(imports) * macho_import_pointer_size64
const linkedit_foa: u64 = macho_align_up(slots_foa + slots_size, page_size)
const linkedit_vaddr: u64 = image_base + linkedit_foa
const bind_foa: u64 = linkedit_foa
const bind_size: u64 = macho_import_bind_size64_at(imports, got_offset)
const symbol_foa: u64 = macho_align_up(bind_foa + bind_size, 8)
const symbol_size: u64 = len(imports) * macho_nlist64_size
const indirect_foa: u64 = symbol_foa + symbol_size
const indirect_count: u64 = len(imports) * 2
const string_foa: u64 = indirect_foa + indirect_count * 4
const string_size: u64 = macho_import_names_size64(imports)
const linkedit_size: u64 = string_foa + string_size - linkedit_foa

region.begin(".macho.header", image_base, 0);
macho_file:
macho_import_header64_arm64(command_count, command_size);
macho_exe_pagezero64(image_base);
macho_segment64("__TEXT", image_base, data_foa, 0, data_foa, macho_vm_prot_read | macho_vm_prot_execute, macho_vm_prot_read | macho_vm_prot_execute, 2, 0);
macho_section64("__text", "__TEXT", text_vaddr, code_size, text_foa, 2, 0, 0, macho_s_regular | macho_s_attr_pure_instructions | macho_s_attr_some_instructions, 0, 0, 0);
macho_section64("__stubs", "__TEXT", stubs_vaddr, stubs_size, stubs_foa, 2, 0, 0, macho_s_symbol_stubs | macho_s_attr_pure_instructions | macho_s_attr_some_instructions, 0, macho_import_arm64_stub_size, 0);
macho_segment64("__DATA", data_vaddr, linkedit_foa - data_foa, data_foa, linkedit_foa - data_foa, macho_vm_prot_read | macho_vm_prot_write, macho_vm_prot_read | macho_vm_prot_write, 2, 0);
macho_section64("__data", "__DATA", data_vaddr, data_size, data_foa, 3, 0, 0, macho_s_regular, 0, 0, 0);
macho_section64("__got", "__DATA", slots_vaddr, slots_size, slots_foa, 3, 0, 0, macho_s_non_lazy_symbol_pointers, len(imports), 0, 0);
macho_segment64("__LINKEDIT", linkedit_vaddr, linkedit_size, linkedit_foa, linkedit_size, macho_vm_prot_read, macho_vm_prot_read, 0, 0);
macho_exe_dyld_info_only64(0, 0, bind_foa, bind_size, 0, 0, 0, 0, 0, 0);
macho_symtab_command(symbol_foa, len(imports), string_foa, string_size);
macho_dysymtab_command(0, 0, 0, 0, 0, len(imports), indirect_foa, indirect_count);
macho_exe_load_dylinker64("/usr/lib/dyld");
macho_import_emit_load_dylibs64(imports, 0x00010000, 0x00010000);
macho_exe_build_version64(macho_exe_macos_version(14, 0, 0), macho_exe_macos_version(14, 0, 0));
macho_exe_main64(text_foa, 0);

region.begin("__text", text_vaddr, text_foa);
entry:
emit.u32(0x14000001);
macho_import_emit_stubs_arm64(imports, stubs_vaddr, slots_vaddr);

region.begin("__data", data_vaddr, data_foa);
emit.u64(0);

region.begin("__got", slots_vaddr, slots_foa);
slots:
macho_import_emit_slots64(imports);

region.begin("__LINKEDIT", linkedit_vaddr, linkedit_foa);
bind_data:
macho_import_emit_bind64_at(imports, 2, got_offset);
symbols:
macho_import_emit_symbols64(imports);
indirect:
macho_import_emit_indirect64(imports);
strings:
macho_import_emit_strings64(imports);

defer {
    assert(region_file_offset(entry) == text_foa);
    assert(region_file_offset(slots) == slots_foa);
    assert(region_file_offset(bind_data) == bind_foa);
    assert(symbols - bind_data == bind_size);
    assert(bind_foa + symbols - bind_data == symbol_foa);
    assert(bind_foa + indirect - bind_data == indirect_foa);
    assert(bind_foa + strings - bind_data == string_foa);
    assert(region_file_size(bind_data) == linkedit_size);
    assert(load.u32(macho_file + 4) == macho_cpu_type_arm64);
    assert((load.u32(macho_file + 24) & macho_exe_dynamic_flags) == macho_exe_dynamic_flags);
}

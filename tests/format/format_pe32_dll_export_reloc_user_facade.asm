import("format/format.inc");

let image: map = format_pe32(
    format_pe_dll | format_pe_console | format_pe_nx | format_pe_aslr_required,
    list.of(
        format_section(".text", format_code | format_readable | format_executable),
        format_section(".bss", format_uninitialized_data | format_readable | format_writeable),
        format_section(".idata", format_imports | format_readable | format_writeable),
        format_section(".edata", format_exports | format_readable),
        format_section(".rsrc", format_resources | format_readable),
        format_section(".reloc", format_fixups | format_readable | format_discardable)
    )
)
let imports: map = format_pe_import_new()
format_pe_import_many_mut(image, imports, "KERNEL32.DLL", list.of("GetCurrentProcessId"))
let exports: list = format_pe_export_new()
format_pe_export_pairs_mut(
    image,
    exports,
    list.of("dll_main", "xir_answer", "absolute_slot", "xir_absolute_slot")
)
format_begin(image);

format_section_begin(image, ".text");
dll_main:
    mov eax, 42
    ret
absolute_slot:
    dd(0);
format_section_end(image, ".text");

format_section_begin(image, ".bss");
    rb(64);
format_section_end(image, ".bss");

format_pe_import_section(image, ".idata", imports);
format_pe_export_section(image, ".edata", exports, "xirasm_facade32.dll");

format_section_begin(image, ".rsrc");
    emit.u32(0);
format_section_end(image, ".rsrc");

let relocs: list = pe_reloc_new()
format_pe_reloc_add_mut(image, relocs, absolute_slot)
format_pe_reloc_section(image, ".reloc", relocs);

format_entry_mut(image, dll_main)
format_finish(image);

defer {
    store.u32(absolute_slot, dll_main);
    assert(load.u16(region_base() + pe_file_header_foa + 2) == 6);
    assert(load.u32(region_base() + pe_opt_size_of_uninit_data_foa) == 64);
    assert(load.u32(region_base() + pe_row32_foa(1) + pe_sec_virtual_size_foa) == 64);
    assert(load.u32(region_base() + pe_row32_foa(1) + pe_sec_raw_size_foa) == 0);
    assert(load.u32(region_base() + pe_row32_foa(1) + pe_sec_raw_ptr_foa) == 0);
    assert(
        load.u32(region_base() + pe_row32_foa(2) + pe_sec_raw_ptr_foa) ==
        load.u32(region_base() + pe_row32_foa(0) + pe_sec_raw_ptr_foa) +
        load.u32(region_base() + pe_row32_foa(0) + pe_sec_raw_size_foa)
    );
    assert(
        load.u32(region_base() + pe_row32_foa(2) + pe_sec_rva_foa) >
        load.u32(region_base() + pe_row32_foa(1) + pe_sec_rva_foa)
    );
    assert(
        load.u32(region_base() + pe_row32_foa(2) + pe_sec_rva_foa) % pe_default_section_align == 0
    );
    assert(load.u32(region_base() + pe_dir32_rva_foa(pe_dir_import)) != 0);
    assert(load.u32(region_base() + pe_dir32_rva_foa(pe_dir_export)) != 0);
    assert(load.u32(region_base() + pe_dir32_rva_foa(pe_dir_basereloc)) != 0);
    assert((load.u16(region_base() + pe_file_header_foa + 18) & pe_file_dll) == pe_file_dll);
    assert((load.u16(region_base() + pe_opt_dll_chars_foa) & pe_dll_dynamic_base) == pe_dll_dynamic_base);
    assert(bytes.eq(load.bytes(pe_export_name_0, len("xir_absolute_slot")), b"xir_absolute_slot"));
    assert(bytes.eq(load.bytes(pe_export_name_1, len("xir_answer")), b"xir_answer"));
    assert(load.u32(absolute_slot) == dll_main);
}

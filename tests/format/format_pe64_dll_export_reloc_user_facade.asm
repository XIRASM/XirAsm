import("format/format.inc");

const imports0: map = pe_import_new()
const imports: map = pe_import_use64(imports0, "KERNEL32.DLL", "GetCurrentProcessId")
const exports0: list = pe_export_new()
const exports1: list = pe_export_use64(exports0, "dll_main", "xir_answer")
const exports: list = pe_export_use64(exports1, "absolute_slot", "xir_absolute_slot")

const image0: map = format_pe64(
    format_pe_dll | format_pe_console | format_pe_nx | format_pe_aslr_auto,
    list.of(
        format_section(".text", format_code | format_readable | format_executable),
        format_section(".bss", format_uninitialized_data | format_readable | format_writeable),
        format_section(".idata", format_imports | format_readable | format_writeable),
        format_section(".edata", format_exports | format_readable),
        format_section(".rsrc", format_resources | format_readable),
        format_section(".reloc", format_fixups | format_readable | format_discardable)
    )
)
format_begin(image0);

format_section_begin(image0, ".text");
dll_main:
    mov eax, 42
    ret
absolute_slot:
    dq(0);
format_section_end(image0, ".text");

format_section_begin(image0, ".bss");
    rb(64);
format_section_end(image0, ".bss");

format_pe_import_section(image0, ".idata", imports);
format_pe_export_section(image0, ".edata", exports, "xirasm_facade64.dll");

format_section_begin(image0, ".rsrc");
    emit.u32(0);
format_section_end(image0, ".rsrc");

const relocs0: list = pe_reloc_new()
const relocs: list = format_pe_reloc_add(image0, relocs0, absolute_slot)
format_pe_reloc_section(image0, ".reloc", relocs);

const image: map = format_entry(image0, dll_main)
format_finish(image);

defer {
    store.u64(absolute_slot, dll_main);
    assert(load.u16(region_base() + pe_file_header_foa + 2) == 6);
    assert(load.u32(region_base() + pe_opt_size_of_uninit_data_foa) == 64);
    assert(load.u32(region_base() + pe_row_foa(1) + pe_sec_virtual_size_foa) == 64);
    assert(load.u32(region_base() + pe_row_foa(1) + pe_sec_raw_size_foa) == 0);
    assert(load.u32(region_base() + pe_row_foa(1) + pe_sec_raw_ptr_foa) == 0);
    assert(
        load.u32(region_base() + pe_row_foa(2) + pe_sec_raw_ptr_foa) ==
        load.u32(region_base() + pe_row_foa(0) + pe_sec_raw_ptr_foa) +
        load.u32(region_base() + pe_row_foa(0) + pe_sec_raw_size_foa)
    );
    assert(
        load.u32(region_base() + pe_row_foa(2) + pe_sec_rva_foa) >
        load.u32(region_base() + pe_row_foa(1) + pe_sec_rva_foa)
    );
    assert(
        load.u32(region_base() + pe_row_foa(2) + pe_sec_rva_foa) % pe_default_section_align == 0
    );
    assert(load.u32(region_base() + pe_dir_rva_foa(pe_dir_import)) != 0);
    assert(load.u32(region_base() + pe_dir_rva_foa(pe_dir_export)) != 0);
    assert(load.u32(region_base() + pe_dir_rva_foa(pe_dir_basereloc)) != 0);
    assert((load.u16(region_base() + pe_file_header_foa + 18) & pe_file_dll) == pe_file_dll);
    assert((load.u16(region_base() + pe_opt_dll_chars_foa) & pe_dll_dynamic_base) == pe_dll_dynamic_base);
    assert(bytes.eq(load.bytes(pe_export_name_0, len("xir_absolute_slot")), b"xir_absolute_slot"));
    assert(bytes.eq(load.bytes(pe_export_name_1, len("xir_answer")), b"xir_answer"));
    assert(load.u64(absolute_slot) == dll_main);
}

import("format/format.inc");

const imports0: map = pe_import_new()
const imports: map = pe_import_use32(imports0, "KERNEL32.DLL", "ExitProcess")

const image0: map = format_pe32(
    format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_disabled,
    list.of(
        format_section(".text", format_code | format_readable | format_executable),
        format_section(".bss", format_uninitialized_data | format_readable | format_writeable),
        format_section(".idata", format_imports | format_readable | format_writeable),
        format_section(".rsrc", format_resources | format_readable),
        format_section(".reloc", format_fixups | format_readable | format_discardable)
    )
)
format_begin(image0);

format_section_begin(image0, ".text");
start:
    xor eax, eax
    ret
absolute_slot:
    dd(0);
format_section_end(image0, ".text");

format_section_begin(image0, ".bss");
    rb(64);
format_section_end(image0, ".bss");

format_pe_import_section(image0, ".idata", imports);

format_pe_resource_section(
    image0,
    ".rsrc",
    "data/pe_resource_named_multilang.res"
);

const relocs0: list = pe_reloc_new()
const relocs: list = format_pe_reloc_add(image0, relocs0, absolute_slot)
format_pe_reloc_section(image0, ".reloc", relocs);

const image: map = format_entry(image0, start)
format_finish(image);

defer {
    store.u32(absolute_slot, start);
}

format_pe_checksum(image);

defer {
    assert(load.u16(region_base()) == pe_magic_mz);
    assert(load.u16(region_base() + pe_file_header_foa) == pe_machine_i386);
    assert(load.u16(region_base() + pe_file_header_foa + 2) == 5);
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
    assert(load.u32(region_base() + pe_dir32_rva_foa(pe_dir_resource)) != 0);
    assert(load.u32(region_base() + pe_dir32_rva_foa(pe_dir_basereloc)) != 0);
    assert(load.u32(region_base() + pe_opt_checksum_foa) != 0);
    assert((load.u16(region_base() + pe_opt_dll_chars_foa) & pe_dll_dynamic_base) == 0);
    assert(load.u32(absolute_slot) == start);
}

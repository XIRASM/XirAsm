// AArch64 PE32+ image through the format.inc user layer. The container, the
// import directory, and the DIR64 base relocations are the same as for x86-64;
// only the file header machine and the instruction encoding differ.
import("format/format.inc");
import("arm/a64-macros.inc");

let image: map = format_pe64_arm64(
    format_pe_exe | format_pe_gui | format_pe_nx | format_pe_aslr_auto,
    list.of(
        format_section(".text", format_code | format_readable | format_executable),
        format_section(".bss", format_uninitialized_data | format_readable | format_writeable),
        format_section(".idata", format_imports | format_readable | format_writeable),
        format_section(".reloc", format_fixups | format_readable | format_discardable)
    )
)
let imports: map = format_pe_import_new()
format_pe_import_pairs_mut(
    image,
    imports,
    "KERNEL32.DLL",
    list.of("exit_process", "ExitProcess")
)
format_begin(image);

format_section_begin(image, ".text");
start:
    mov x0, #0
    ret
absolute_slot:
    dq(0);
format_section_end(image, ".text");

format_section_begin(image, ".bss");
    rb(64);
format_section_end(image, ".bss");

format_pe_import_section(image, ".idata", imports);

let relocs: list = pe_reloc_new()
format_pe_reloc_add_mut(image, relocs, absolute_slot)
format_pe_reloc_section(image, ".reloc", relocs);

format_entry_mut(image, start)
format_finish(image);

defer {
    store.u64(absolute_slot, start);
}

format_pe_checksum(image);

assert(file_cursor_real() == 2560, "AArch64 PE image size drifted");

defer {
    assert(load.u16(region_base()) == pe_magic_mz);
    assert(load.u16(region_base() + pe_file_header_foa) == pe_machine_arm64);
    assert(load.u16(region_base() + pe_file_header_foa + 2) == 4);
    assert(load.u16(region_base() + pe_optional_header_foa) == pe_opt64_magic);
    assert(load.u16(region_base() + format_pe_opt_subsystem_foa) == pe_subsystem_gui);
    assert(load.u32(region_base() + pe_row_foa(1) + pe_sec_raw_ptr_foa) == 0);
    assert(load.u32(region_base() + pe_dir_rva_foa(pe_dir_import)) != 0);
    assert(load.u32(region_base() + pe_dir_rva_foa(pe_dir_basereloc)) != 0);
    assert(load.u32(region_base() + pe_opt_checksum_foa) != 0);
    assert((load.u16(region_base() + pe_opt_dll_chars_foa) & pe_dll_dynamic_base) == pe_dll_dynamic_base);
    assert(load.u64(absolute_slot) == start);
}

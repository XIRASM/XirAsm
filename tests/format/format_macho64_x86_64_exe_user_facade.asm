import("format/format.inc");

const version: u64 = macho_exe_macos_version(14, 0, 0)
let image: map = format_macho64_exe(
    format_macho64_target_x86_64(version, version),
    list.of(
        format_macho64_segment(
            "__TEXT",
            format_load | format_readable | format_executable,
            list.of(
                format_section("__text", format_code | format_readable | format_executable),
                format_section("__const", format_data | format_readable)
            )
        ),
        format_macho64_segment(
            "__DATA",
            format_load | format_readable | format_writeable,
            list.of(
                format_section("__data", format_data | format_readable | format_writeable),
                format_section("__bss", format_uninitialized_data | format_readable | format_writeable)
            )
        )
    )
)

format_begin(image);
format_section_begin(image, "__text");
entry:
    db(0x31, 0xc0, 0xc3);
format_section_end(image, "__text");

format_section_begin(image, "__const");
    emit.u64(0x1122334455667788);
format_section_end(image, "__const");

format_section_begin(image, "__data");
    emit.u64(7);
format_section_end(image, "__data");

format_section_begin(image, "__bss");
    rb(32);
format_section_end(image, "__bss");

format_entry_mut(image, entry);
format_finish(image);

defer {
    assert(load.u32(format_macho64_image_base + 0) == macho_magic_64);
    assert(load.u32(format_macho64_image_base + 4) == macho_cpu_type_x86_64);
    assert(load.u32(format_macho64_image_base + 8) == (macho_cpu_subtype_x86_64_all | macho_cpu_subtype_lib64));
    assert((load.u32(format_macho64_image_base + 24) & macho_exe_dynamic_flags) == macho_exe_dynamic_flags);
}

import("../../include/format/format.inc");

const version: u64 = macho_exe_macos_version(14, 0, 0)
let image: map = format_macho64_exe(
    format_macho64_target_arm64(version, version),
    list.of(
        format_macho64_segment("__TEXT", format_load | format_readable | format_executable, list.of(
            format_section("common", format_code | format_readable | format_executable)
        )),
        format_macho64_segment("__DATA", format_load | format_readable | format_writeable, list.of(
            format_section("common", format_data | format_readable | format_writeable)
        ))
    )
)

format_begin(image);
format_macho64_section_begin(image, "__TEXT", "common");
entry:
emit.u32(0xd65f03c0);
format_macho64_section_end(image, "__TEXT", "common");
format_macho64_section_begin(image, "__DATA", "common");
data:
emit.u64(0x1122334455667788);
format_macho64_section_end(image, "__DATA", "common");
format_entry_mut(image, entry);
format_finish(image);

defer {
    assert(region_file_offset(data) == macho_page_size_arm64);
    assert(data == format_macho64_image_base + macho_page_size_arm64);
    assert(load.u32(entry) == 0xd65f03c0);
    assert(load.u64(data) == 0x1122334455667788);
}

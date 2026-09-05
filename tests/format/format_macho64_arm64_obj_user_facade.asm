import("format/format.inc");

const version: u64 = macho_exe_macos_version(14, 0, 0)
let image: map = format_macho64_object(
    format_macho64_target_arm64(version, version),
    list.of(
        format_section("__text", format_code | format_readable | format_executable),
        format_section("__data", format_data | format_readable | format_writeable),
        format_section("__bss", format_uninitialized_data | format_readable | format_writeable)
    )
)

format_begin(image);
format_section_begin(image, "__text");
code:
    emit.u32(0xd65f03c0);
format_section_end(image, "__text");

format_section_begin(image, "__data");
value:
    emit.u64(42);
format_section_end(image, "__data");

format_section_begin(image, "__bss");
    rb(24);
format_section_end(image, "__bss");
format_finish(image);

defer {
    assert(load.u32(0) == macho_magic_64);
    assert(load.u32(4) == macho_cpu_type_arm64);
    assert(load.u32(12) == macho_mh_object);
    assert(code == 0);
    assert(value == 8);
}

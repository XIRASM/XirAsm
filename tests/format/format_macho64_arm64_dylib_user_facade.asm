import("format/format.inc");

const version: u64 = macho_exe_macos_version(14, 0, 0)
let image: map = format_macho64_dylib(
    format_macho64_target_arm64(version, version),
    "@rpath/libxirfacade.dylib",
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
            list.of(format_section("__data", format_data | format_readable | format_writeable))
        )
    )
)
let exports: list = macho_export_use64(macho_export_new(), "answer", "_answer")
format_macho64_exports_mut(image, exports);

format_begin(image);
format_section_begin(image, "__text");
answer:
    emit.u32(0xd2800540);
    emit.u32(0xd65f03c0);
format_section_end(image, "__text");

format_section_begin(image, "__const");
    emit.u64(42);
format_section_end(image, "__const");

format_section_begin(image, "__data");
    emit.u64(7);
format_section_end(image, "__data");

format_finish(image);

defer {
    assert(load.u32(0) == macho_magic_64);
    assert(load.u32(4) == macho_cpu_type_arm64);
    assert(load.u32(12) == macho_mh_dylib);
    assert(region_file_offset(answer) == answer);
}

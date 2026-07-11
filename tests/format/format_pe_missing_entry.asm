import("format/format.inc");

const image: map = format_pe64(
    format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_disabled,
    list.of(
        format_section(".text", format_code | format_readable | format_executable)
    )
)
format_begin(image);

format_section_begin(image, ".text");
    ret
format_section_end(image, ".text");

format_finish(image);

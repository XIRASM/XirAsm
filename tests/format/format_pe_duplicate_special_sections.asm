import("format/format.inc");

const image: map = format_pe64(
    format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_disabled,
    list.of(
        format_section(".idata", format_imports | format_readable),
        format_section(".imp2", format_imports | format_readable)
    )
)

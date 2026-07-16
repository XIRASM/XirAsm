import("format/format.inc");

let object: map = format_coff64(
    list.of(
        format_section(
            ".text",
            format_code | format_readable | format_executable
        )
    )
)
format_entry_mut(object, 1)

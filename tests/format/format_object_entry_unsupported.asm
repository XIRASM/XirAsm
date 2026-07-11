import("format/format.inc");

const object0: map = format_coff64(
    list.of(
        format_section(
            ".text",
            format_code | format_readable | format_executable
        )
    )
)
const object: map = format_entry(object0, 1)

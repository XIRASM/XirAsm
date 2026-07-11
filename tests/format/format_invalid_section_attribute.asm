import("format/format.inc");

const section: map = format_section(
    ".text",
    format_code
        | format_load
        | format_readable
        | format_executable
)

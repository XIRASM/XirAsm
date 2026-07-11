import("format/format.inc");

const object: map = format_elfobj64(
    list.of(
        format_section(
            ".text",
            format_code
                | format_readable
                | format_executable
                | format_discardable
        )
    )
)

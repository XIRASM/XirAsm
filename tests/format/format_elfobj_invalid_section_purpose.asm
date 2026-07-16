import("format/format.inc");

let object: map = format_elfobj64(
    list.of(
        format_section(
            ".imports",
            format_imports | format_readable
        )
    )
)

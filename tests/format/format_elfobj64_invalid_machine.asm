import("format/format.inc");

let object: map = format_elfobj64_machine(
    list.of(
        format_section(".text", format_code | format_readable | format_executable)
    ),
    999
)

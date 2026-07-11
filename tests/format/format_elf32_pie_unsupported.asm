import("format/format.inc");

const image: map = format_elf32(
    format_elf_pie,
    list.of(
        format_segment(".text", format_load | format_readable | format_executable)
    )
)

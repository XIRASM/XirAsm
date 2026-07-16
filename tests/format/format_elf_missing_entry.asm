import("format/format.inc");

let image: map = format_elf64(
    format_elf_exec,
    list.of(
        format_segment(".text", format_load | format_readable | format_executable)
    )
)
format_begin(image);

format_segment_begin(image, ".text");
    ret
format_segment_end(image, ".text");

format_finish(image);

import("format/format.inc");

const image0: map = format_elf64(
    format_elf_pie,
    list.of(
        format_segment(".text", format_load | format_readable | format_executable)
    )
)
const imports: list = list.of(
    format_elfexe_import_plt("libc.so.6", "getpid", "getpid_gotplt", "getpid_plt")
)
const image: map = format_elfexe_tables(image0, imports)

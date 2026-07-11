import("format/format.inc");

const image0: map = format_elf64_so(
    "libxirasm_import_user.so",
    list.of(
        format_segment(".text", format_load | format_readable | format_executable),
        format_segment(".bss", format_load | format_readable | format_writeable),
        format_segment(".data", format_load | format_readable | format_writeable)
    )
)
const exports: list = list.of(
    format_elfso_export("exported_call_puts", "exported_call_puts", ".text", 13)
)
const imports: list = list.of(
    format_elfso_import_plt("libc.so.6", "puts", "puts_gotplt", "puts_plt")
)
const image: map = format_elfso_tables(image0, exports, imports)
format_begin(image);

format_segment_begin(image, ".text");
exported_call_puts:
    lea rdi, [rel message_text]
    call puts_plt
    ret
format_segment_end(image, ".text");

format_segment_begin(image, ".bss");
import_scratch:
    reserve(64);
format_segment_end(image, ".bss");

format_segment_begin(image, ".data");
message_text:
    db("xirasm user facade", 0);
format_segment_end(image, ".data");

format_finish(image);

const section_count: u64 = len(map.get(image, "segments")) + 9
const section_table_address: u64 = here() - section_count * elfso_shdr64_size
const bss_row: u64 = format_segment_row(image, ".bss") + 1
defer {
    assert(
        load.u32(section_table_address + bss_row * elfso_shdr64_size + elfso_sh_type_foa) == elf_sht_nobits,
        "ELF shared-object BSS section must use SHT_NOBITS"
    );
}

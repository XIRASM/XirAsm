// api-matrix-fixture: format_elfso_export_new(
// api-matrix-fixture: format_elfso_export_many_mut(
// api-matrix-fixture: format_elfso_export_pairs_mut(
// api-matrix-fixture: format_elfso_import_new(
// api-matrix-fixture: format_elfso_import_many_mut(
// api-matrix-fixture: format_elfso_import_pairs_mut(

import("format/format.inc");

let image: map = format_elf64_so(
    "libxirasm_import_user.so",
    list.of(
        format_segment(".text", format_load | format_readable | format_executable),
        format_segment(".bss", format_load | format_readable | format_writeable),
        format_segment(".data", format_load | format_readable | format_writeable)
    )
)
let exports: list = format_elfso_export_new()
format_elfso_export_pairs_mut(exports, list.of("exported_call_puts", "exported_call_puts"), ".text", 13)
let imports: list = format_elfso_import_new()
format_elfso_import_pairs_mut(imports, "libc.so.6", list.of("puts", "puts"))
format_elfso_tables_mut(image, exports, imports)
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

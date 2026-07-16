import("format/format.inc");

let image: map = format_elf64_so(
    "libxirasm_user.so",
    list.of(
        format_segment(".text", format_load | format_readable | format_executable),
        format_segment(".data", format_load | format_readable | format_writeable)
    )
)
let exports: list = format_elfso_export_new()
format_elfso_export_many_mut(exports, list.of("x_add7", "x_sub3"), ".text", 4)
format_elfso_tables_mut(image, exports, list.new())
format_begin(image);

format_segment_begin(image, ".text");
x_add7:
    db(0x8d, 0x47, 0x07, 0xc3);
x_sub3:
    db(0x8d, 0x47, 0xfd, 0xc3);
format_segment_end(image, ".text");

format_segment_begin(image, ".data");
export_data:
    dq(0x1122334455667788);
format_segment_end(image, ".data");

format_finish(image);

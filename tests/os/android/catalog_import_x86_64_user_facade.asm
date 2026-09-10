// x86-64 counterpart of catalog_import_user_facade.asm. The same generated
// catalog files drive this target, but x86-64 reaches an import through the PLT,
// so the fixture uses the PLT helper and calls the <name>_plt labels.
//
// Between the two fixtures the catalog covers both shared-object import paths:
// android_import_<alias>_add_mut on x86-64 and
// android_import_<alias>_add_slots_mut on AArch64.
//
// api-matrix-fixture: format_elf64_so(
// api-matrix-fixture: android_import_log_add_mut(
// api-matrix-fixture: android_import_android_add_mut(

import("format/format.inc");
import("os/android/imports/liblog.inc");
import("os/android/imports/libandroid.inc");

let image: map = format_elf64_so(
    "libcatalog64.so",
    list.of(
        format_segment(".text", format_load | format_readable | format_executable),
        format_segment(".data", format_load | format_readable | format_writeable)
    )
)
let exports: list = format_elfso_export_new()
format_elfso_export_many_mut(exports, list.of("ANativeActivity_onCreate"), ".text", 16)
let imports: list = format_elfso_import_new()
android_import_log_add_mut(imports, list.of(
    android_import_log___android_log_write
))
android_import_android_add_mut(imports, list.of(
    android_import_android_ANativeWindow_getWidth
))
format_elfso_tables_mut(image, exports, imports)
format_begin(image);

format_segment_begin(image, ".text");
ANativeActivity_onCreate:
    sub rsp, 40
    call ANativeWindow_getWidth_plt
    mov rdi, rax
    call __android_log_write_plt
    add rsp, 40
    ret
format_segment_end(image, ".text");

format_segment_begin(image, ".data");
pad:
    dq(0)
format_segment_end(image, ".data");

format_finish(image);

defer {
    assert(load.u16(region_base() + 18) == elf_machine_x86_64, "ELF machine must be x86-64");
    assert(android_import_android_min_api == 21, "libandroid must be usable from API 21");
}

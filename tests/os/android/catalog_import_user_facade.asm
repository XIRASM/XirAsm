// Android platform imports driven by the generated symbol catalog: the library
// names come from os/android/imports/*.inc, so nothing here types "liblog.so".
//
// The catalog also knows which API level each symbol needs; liblog and libGLESv2
// are both available from API 21, which is why this fixture works at the default
// minimum. Assembling it produces an AArch64 shared object whose DT_NEEDED and
// dynamic symbol table name exactly the libraries the catalog reported.
//
// api-matrix-fixture: format_elf64_so_aarch64(
// api-matrix-fixture: android_import_log_add_slots_mut(
// api-matrix-fixture: android_import_glesv2_add_slots_mut(
// api-matrix-fixture: format_elfso_import_slots_mut(

import("format/format.inc");
import("os/android/imports/liblog.inc");
import("os/android/imports/libGLESv2.inc");
import("arm/a64-macros.inc");

let image: map = format_elf64_so_aarch64(
    "libcatalog.so",
    list.of(
        format_segment(".text", format_load | format_readable | format_executable),
        format_segment(".data", format_load | format_readable | format_writeable)
    )
)
let exports: list = format_elfso_export_new()
format_elfso_export_many_mut(exports, list.of("ANativeActivity_onCreate"), ".text", 40)
let imports: list = format_elfso_import_new()
android_import_log_add_slots_mut(imports, list.of(
    android_import_log___android_log_write
))
android_import_glesv2_add_slots_mut(imports, list.of(
    android_import_glesv2_glClearColor,
    android_import_glesv2_glClear
))
format_elfso_tables_mut(image, exports, imports)
format_begin(image);

format_segment_begin(image, ".text");
ANativeActivity_onCreate:
    ldr x8, __android_log_write
    mov w0, #4
    ldr x1, tag_ptr
    ldr x2, text_ptr
    blr x8
    mov w10, #0
    mov w11, #0
    mov w12, #0
    ldr x9, glClearColor
    blr x9
    ldr x9, glClear
    blr x9
    ret
format_segment_end(image, ".text");

format_segment_begin(image, ".data");
tag_ptr:
    dq(0)
text_ptr:
    dq(0)
log_tag:
    db("XIRASM", 0);
log_text:
    db("catalog import", 0);
format_segment_end(image, ".data");

format_finish(image);

defer {
    assert(load.u16(region_base() + 18) == elf_machine_aarch64, "ELF machine must be AArch64");
    assert(load.u64(region_base() + elfso64_phdr_foa(1) + elfso64_phdr_align_foa) == elf_android_page_align, "second LOAD must align to the Android page size");
    assert(android_import_log_min_api == 21, "liblog must be usable from API 21");
    assert(android_import_glesv2_min_api == 21, "libGLESv2 must be usable from API 21");
}

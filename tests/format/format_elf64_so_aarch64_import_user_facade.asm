// api-matrix-fixture: format_elf64_so_aarch64(
// api-matrix-fixture: format_elfso_import_slots_mut(
// api-matrix-fixture: elfso_begin64_machine(
// api-matrix-fixture: elfso_import_emit_rela64_type(

// Android-ready AArch64 shared object through the user facade: 16 KiB LOAD
// alignment, DT_SONAME, DT_NEEDED liblog.so, one exported entry, and a
// GLOB_DAT import slot called through an AArch64 literal load.
import("../../include/format/format.inc");
import("../../include/arm/a64-macros.inc");

let image: map = format_elf64_so_aarch64(
    "libmain.so",
    list.of(
        format_segment(".text", format_load | format_readable | format_executable),
        format_segment(".data", format_load | format_readable | format_writeable)
    )
)
let exports: list = format_elfso_export_new()
format_elfso_export_many_mut(exports, list.of("ANativeActivity_onCreate"), ".text", 24)
let imports: list = format_elfso_import_new()
format_elfso_import_slots_mut(imports, "liblog.so", list.of("__android_log_write"))
format_elfso_tables_mut(image, exports, imports)
format_begin(image);

format_segment_begin(image, ".text");
ANativeActivity_onCreate:
    mov w0, #4
    ldr x1, log_tag_ptr
    ldr x2, log_text_ptr
    ldr x8, __android_log_write
    blr x8
    ret
format_segment_end(image, ".text");

format_segment_begin(image, ".data");
log_tag_ptr:
    dq(0)
log_text_ptr:
    dq(0)
log_tag:
    db("XIRASM", 0);
log_text:
    db("stage3 aarch64 onCreate", 0);
format_segment_end(image, ".data");

format_finish(image);

// The .got slot, the export, and the SONAME land in the stable image; assert
// the loader-facing facts that bionic will consume.
defer {
    assert(load.u16(region_base() + 18) == elf_machine_aarch64, "ELF machine must be AArch64");
    assert(load.u64(region_base() + elfso64_phdr_foa(1) + elfso64_phdr_align_foa) == elf_android_page_align, "second LOAD must align to the Android page size");
}

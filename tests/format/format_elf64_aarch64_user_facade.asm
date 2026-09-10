// AArch64 ELF executable through the format.inc user layer. The plan carries
// the machine field, so the same segment description yields an AArch64 image
// instead of the x86-64 default. Assemble it and inspect it with any ELF
// reader: e_machine is 183 (AArch64).
import("format/format.inc");
import("arm/a64-macros.inc");

let image: map = format_elf64_aarch64(
    format_elf_exec,
    list.of(
        format_segment(".text", format_load | format_readable | format_executable),
        format_segment(".data", format_load | format_readable | format_writeable)
    )
)
format_begin(image);

format_segment_begin(image, ".text");
start:
    mov x8, #93
    mov x0, #0
    svc #0
format_segment_end(image, ".text");

format_segment_begin(image, ".data");
data_start:
    dq(0x1122334455667788);
format_segment_end(image, ".data");

format_entry_mut(image, start)
format_finish(image);

assert(file_cursor_real() == 196, "AArch64 EXEC image size drifted");

defer {
    assert(load.u32(region_base()) == elf_magic);
    assert(load.u8(region_base() + 4) == elf_class_64);
    assert(load.u16(region_base() + 16) == elf_type_exec);
    assert(load.u16(region_base() + 18) == elf_machine_aarch64, "EXEC image must declare the AArch64 machine");
    assert(load.u16(region_base() + elf64_phnum_foa) == 2);
    assert(load.u64(region_base() + elf64_entry_foa) == start);
    assert(load.u32(region_base() + elf64_phdr_foa(0) + elf64_phdr_type_foa) == elf_pt_load);
    assert(load.u32(region_base() + elf64_phdr_foa(0) + elf64_phdr_flags_foa) == elf_pf_r | elf_pf_x);
    assert(load.u64(region_base() + elf64_phdr_foa(0) + elf64_phdr_align_foa) == elf_android_page_align);
    assert(load.u64(region_base() + elf64_phdr_foa(1) + elf64_phdr_offset_foa) == region_file_offset(data_start));
    assert(load.u64(region_base() + elf64_phdr_foa(1) + elf64_phdr_align_foa) == elf_android_page_align);
    assert(
        load.u64(region_base() + elf64_phdr_foa(1) + elf64_phdr_vaddr_foa) % elf_android_page_align ==
        load.u64(region_base() + elf64_phdr_foa(1) + elf64_phdr_offset_foa) % elf_android_page_align
    );
}

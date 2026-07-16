import("format/format.inc");

let image: map = format_elf64(
    format_elf_exec,
    list.of(
        format_segment(".text", format_load | format_readable | format_executable),
        format_segment(".data", format_load | format_readable | format_writeable),
        format_segment(".bss", format_load | format_readable | format_writeable),
        format_segment(".extra", format_load | format_readable)
    )
)
format_begin(image);

format_segment_begin(image, ".text");
start:
    mov eax, 60
    xor edi, edi
    syscall
format_segment_end(image, ".text");

format_segment_begin(image, ".data");
data_start:
    dd(0);
format_segment_end(image, ".data");

format_segment_begin(image, ".bss");
bss_start:
    rb(128);
format_segment_end(image, ".bss");

format_segment_begin(image, ".extra");
extra_start:
    dq(0x1122334455667788);
format_segment_end(image, ".extra");

format_entry_mut(image, start)
format_finish(image);

defer {
    assert(load.u32(region_base()) == elf_magic);
    assert(load.u8(region_base() + 4) == elf_class_64);
    assert(load.u16(region_base() + 16) == elf_type_exec);
    assert(load.u16(region_base() + elf64_phnum_foa) == 4);
    assert(load.u64(region_base() + elf64_entry_foa) == start);
    assert(load.u32(region_base() + elf64_phdr_foa(0) + elf64_phdr_type_foa) == elf_pt_load);
    assert(load.u32(region_base() + elf64_phdr_foa(0) + elf64_phdr_flags_foa) == elf_pf_r | elf_pf_x);
    assert(load.u32(region_base() + elf64_phdr_foa(1) + elf64_phdr_flags_foa) == elf_pf_r | elf_pf_w);
    assert(load.u64(region_base() + elf64_phdr_foa(1) + elf64_phdr_offset_foa) == region_file_offset(data_start));
    assert(load.u64(region_base() + elf64_phdr_foa(2) + elf64_phdr_filesz_foa) == 0);
    assert(load.u64(region_base() + elf64_phdr_foa(2) + elf64_phdr_memsz_foa) == 128);
    assert(
        load.u64(region_base() + elf64_phdr_foa(3) + elf64_phdr_offset_foa) ==
        load.u64(region_base() + elf64_phdr_foa(2) + elf64_phdr_offset_foa)
    );
    assert(
        load.u64(region_base() + elf64_phdr_foa(3) + elf64_phdr_vaddr_foa) >
        load.u64(region_base() + elf64_phdr_foa(2) + elf64_phdr_vaddr_foa)
    );
    assert(
        load.u64(region_base() + elf64_phdr_foa(3) + elf64_phdr_vaddr_foa) % elf_default_page_align ==
        load.u64(region_base() + elf64_phdr_foa(3) + elf64_phdr_offset_foa) % elf_default_page_align
    );
}

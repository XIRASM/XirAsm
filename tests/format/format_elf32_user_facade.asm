import("format/format.inc");

x86.use32();

const image0: map = format_elf32(
    format_elf_exec,
    list.of(
        format_segment(".text", format_load | format_readable | format_executable),
        format_segment(".bss", format_load | format_readable | format_writeable),
        format_segment(".extra", format_load | format_readable)
    )
)
format_begin(image0);

format_segment_begin(image0, ".text");
start:
    mov eax, 1
    xor ebx, ebx
    int 0x80
format_segment_end(image0, ".text");

format_segment_begin(image0, ".bss");
bss_start:
    rb(64);
format_segment_end(image0, ".bss");

format_segment_begin(image0, ".extra");
extra_start:
    dd(0x11223344);
format_segment_end(image0, ".extra");

const image: map = format_entry(image0, start)
format_finish(image);

defer {
    assert(load.u32(region_base()) == elf_magic);
    assert(load.u8(region_base() + 4) == elf_class_32);
    assert(load.u16(region_base() + 16) == elf_type_exec);
    assert(load.u16(region_base() + elf32_phnum_foa) == 3);
    assert(load.u32(region_base() + elf32_entry_foa) == start);
    assert(load.u32(region_base() + elf32_phdr_foa(0) + elf32_phdr_type_foa) == elf_pt_load);
    assert(load.u32(region_base() + elf32_phdr_foa(0) + elf32_phdr_flags_foa) == elf_pf_r | elf_pf_x);
    assert(load.u32(region_base() + elf32_phdr_foa(1) + elf32_phdr_filesz_foa) == 0);
    assert(load.u32(region_base() + elf32_phdr_foa(1) + elf32_phdr_memsz_foa) == 64);
    assert(
        load.u32(region_base() + elf32_phdr_foa(2) + elf32_phdr_offset_foa) ==
        load.u32(region_base() + elf32_phdr_foa(1) + elf32_phdr_offset_foa)
    );
    assert(
        load.u32(region_base() + elf32_phdr_foa(2) + elf32_phdr_vaddr_foa) >
        load.u32(region_base() + elf32_phdr_foa(1) + elf32_phdr_vaddr_foa)
    );
    assert(
        load.u32(region_base() + elf32_phdr_foa(2) + elf32_phdr_vaddr_foa) % elf_default_page_align ==
        load.u32(region_base() + elf32_phdr_foa(2) + elf32_phdr_offset_foa) % elf_default_page_align
    );
}

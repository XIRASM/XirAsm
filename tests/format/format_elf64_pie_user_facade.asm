import("format/format.inc");

const image0: map = format_elf64(
    format_elf_pie,
    list.of(
        format_segment(".text", format_load | format_readable | format_executable),
        format_segment(".bss", format_load | format_readable | format_writeable),
        format_segment(".rodata", format_load | format_readable)
    )
)
format_begin(image0);

format_segment_begin(image0, ".text");
start:
    lea rbx, [rel scratch]
    mov dword [rbx], 0x5a
    cmp dword [rbx], 0x5a
    jne failed

    mov eax, 1
    mov edi, 1
    lea rsi, [rel message]
    mov edx, message_end - message
    syscall

    xor edi, edi
    jmp finish

failed:
    mov edi, 1

finish:
    mov eax, 60
    syscall
format_segment_end(image0, ".text");

format_segment_begin(image0, ".bss");
scratch:
    rb(64);
format_segment_end(image0, ".bss");

format_segment_begin(image0, ".rodata");
message:
    db("XIRASM PIE", 10);
message_end:
format_segment_end(image0, ".rodata");

const image: map = format_entry(image0, start)
format_finish(image);

defer {
    assert(load.u32(region_base()) == elf_magic);
    assert(load.u8(region_base() + 4) == elf_class_64);
    assert(load.u16(region_base() + 16) == elf_type_dyn);
    assert(load.u16(region_base() + elf64_phnum_foa) == 3);
    assert(load.u64(region_base() + elf64_entry_foa) == start);
    assert(load.u32(region_base() + elf64_phdr_foa(0) + elf64_phdr_type_foa) == elf_pt_load);
    assert(load.u32(region_base() + elf64_phdr_foa(0) + elf64_phdr_flags_foa) == elf_pf_r | elf_pf_x);
    assert(load.u32(region_base() + elf64_phdr_foa(1) + elf64_phdr_type_foa) == elf_pt_load);
    assert(load.u32(region_base() + elf64_phdr_foa(1) + elf64_phdr_flags_foa) == elf_pf_r | elf_pf_w);
    assert(load.u64(region_base() + elf64_phdr_foa(1) + elf64_phdr_filesz_foa) == 0);
    assert(load.u64(region_base() + elf64_phdr_foa(1) + elf64_phdr_memsz_foa) == 64);
    assert(load.u32(region_base() + elf64_phdr_foa(2) + elf64_phdr_type_foa) == elf_pt_load);
    assert(load.u32(region_base() + elf64_phdr_foa(2) + elf64_phdr_flags_foa) == elf_pf_r);
    assert(load.u64(region_base() + elf64_phdr_foa(2) + elf64_phdr_filesz_foa) == 11);
}

import("../../include/format/elf32.inc");

x86.use32();

const text_foa: u64 = elf32_first_foa(1)

elf32_exe(1);

elf32_segment(".text");
text_start:
start:
    mov eax, 1
    xor ebx, ebx
    int 0x80
reserve(0x20000);
text_end:
elf32_end_segment();

elf32_finish_load(0, start, text_start, elf32_rx);

defer {
    assert(load.u32(region_base()) == elf_magic);
    assert(region_file_offset(text_start) == text_foa);
    assert(load.u32(region_base() + elf32_phdr_foa(0) + elf32_phdr_offset_foa) == text_foa);
    assert(load.u32(region_base() + elf32_phdr_foa(0) + elf32_phdr_vaddr_foa) == elf32_vaddr(text_foa));
    assert(load.u32(region_base() + elf32_phdr_foa(0) + elf32_phdr_filesz_foa) == 16);
    assert(load.u32(region_base() + elf32_phdr_foa(0) + elf32_phdr_memsz_foa) == text_end - text_start);
    assert(region_file_size(text_start) == 16);
    assert(region_logical_size(text_start) == text_end - text_start);
}

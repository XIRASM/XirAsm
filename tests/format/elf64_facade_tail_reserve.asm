import("../../include/format/elf64.inc");

const text_foa: u64 = elf64_first_foa(1)

elf64_exe(1);

elf64_segment(".text");
text_start:
start:
    mov eax, 60
    xor edi, edi
    syscall
reserve(0x20000);
text_end:
elf64_end_segment();

elf64_finish_load(0, start, text_start, elf_rx);

defer {
    assert(load.u32(region_base()) == elf_magic);
    assert(region_file_offset(text_start) == text_foa);
    assert(load.u64(region_base() + elf64_phdr_foa(0) + elf64_phdr_offset_foa) == text_foa);
    assert(load.u64(region_base() + elf64_phdr_foa(0) + elf64_phdr_vaddr_foa) == elf64_vaddr(text_foa));
    assert(load.u64(region_base() + elf64_phdr_foa(0) + elf64_phdr_filesz_foa) == 16);
    assert(load.u64(region_base() + elf64_phdr_foa(0) + elf64_phdr_memsz_foa) == text_end - text_start);
    assert(region_file_size(text_start) == 16);
    assert(region_logical_size(text_start) == text_end - text_start);
}

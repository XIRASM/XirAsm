// api-matrix-fixture: elf64_exe(
// api-matrix-fixture: elf64_first_foa(
// api-matrix-fixture: elf64_segment(
// api-matrix-fixture: elf64_end_segment(
// api-matrix-fixture: elf64_finish_load(
// api-matrix-fixture: elf_rx

import("../../include/format/elf64.inc");

const text_foa: u64 = elf64_first_foa(1)

elf64_exe(1);

elf64_segment(".text");
text_start:
start:
    mov eax, 60
    xor edi, edi
    syscall
text_end:
elf64_end_segment();

elf64_finish_load(0, start, text_start, elf_rx);

defer {
    assert(load.u32(region_base()) == elf_magic);
    assert(load.u8(region_base() + 4) == elf_class_64);
    assert(load.u16(region_base() + 16) == elf_type_exec);
    assert(load.u16(region_base() + 18) == elf_machine_x86_64);
    assert(region_file_offset(text_start) == text_foa);
    assert(load.u64(region_base() + elf64_entry_foa) == elf_default_base64 + region_file_offset(text_start) + (start - text_start));
    assert(load.u64(region_base() + elf64_phdr_foa(0) + elf64_phdr_vaddr_foa) == elf_default_base64 + region_file_offset(text_start));
    assert(load.u64(region_base() + elf64_phdr_foa(0) + elf64_phdr_filesz_foa) == region_file_size(text_start));
    assert(load.u64(region_base() + elf64_phdr_foa(0) + elf64_phdr_memsz_foa) == region_file_size(text_start));
}

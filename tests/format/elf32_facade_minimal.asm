// api-matrix-fixture: elf32_exe(
// api-matrix-fixture: elf32_first_foa(
// api-matrix-fixture: elf32_segment(
// api-matrix-fixture: elf32_end_segment(
// api-matrix-fixture: elf32_finish_load(
// api-matrix-fixture: elf32_rx

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
text_end:
elf32_end_segment();

elf32_finish_load(0, start, text_start, elf32_rx);

defer {
    assert(load.u32(region_base()) == elf_magic);
    assert(load.u8(region_base() + 4) == elf_class_32);
    assert(load.u16(region_base() + 16) == elf_type_exec);
    assert(load.u16(region_base() + 18) == elf_machine_386);
    assert(region_file_offset(text_start) == text_foa);
    assert(load.u32(region_base() + elf32_entry_foa) == elf_default_base32 + region_file_offset(text_start) + (start - text_start));
    assert(load.u32(region_base() + elf32_phdr_foa(0) + elf32_phdr_vaddr_foa) == elf_default_base32 + region_file_offset(text_start));
    assert(load.u32(region_base() + elf32_phdr_foa(0) + elf32_phdr_filesz_foa) == region_file_size(text_start));
    assert(load.u32(region_base() + elf32_phdr_foa(0) + elf32_phdr_memsz_foa) == region_file_size(text_start));
}

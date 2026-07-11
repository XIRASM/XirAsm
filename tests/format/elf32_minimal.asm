// api-matrix-fixture: elfexe_finalize_entry32(
// api-matrix-fixture: elfexe_finalize_load32(
import("../../include/format/elfexe.inc");

x86.use32();

const text_foa: u64 = elf32_first_segment_foa(1)
const text_vaddr: u64 = elf_segment_vaddr(elf_default_base32, text_foa)

elfexe_begin32(1);

elfexe_begin_segment32(".text", text_foa);
text_start:
start:
    mov eax, 1
    xor ebx, ebx
    int 0x80
text_end:
elfexe_end_segment(16);

elfexe_finalize_entry32(start, text_start, text_vaddr);
elfexe_finalize_load32(0, text_foa, text_vaddr, text_start, text_end, elf_pf_r | elf_pf_x);

defer {

    assert(load.u32(region_base()) == elf_magic);
    assert(load.u8(region_base() + 4) == elf_class_32);
    assert(load.u16(region_base() + 16) == elf_type_exec);
    assert(load.u16(region_base() + 18) == elf_machine_386);
    assert(load.u32(region_base() + elf32_entry_foa) == text_vaddr + (start - text_start));
    assert(load.u32(region_base() + elf32_phdr_foa(0) + elf32_phdr_vaddr_foa) == text_vaddr);
}

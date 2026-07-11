// api-matrix-fixture: elfexe_finalize_load64(
import("../../include/format/elfexe.inc");

const text_foa: u64 = elf64_first_segment_foa(1)
const text_vaddr: u64 = elf_segment_vaddr(elf_default_base64, text_foa)

elfexe_begin64(1);

elfexe_begin_segment64(".text", text_foa);
text_start:
start:
    mov eax, 60
    xor edi, edi
    syscall
text_end:
elfexe_end_segment(16);

elfexe_finalize_entry64(start, text_start, text_vaddr);
elfexe_finalize_load64(0, text_foa, text_vaddr, text_start, text_end, elf_pf_r | elf_pf_x);

defer {

    assert(load.u32(region_base()) == elf_magic);
    assert(load.u8(region_base() + 4) == elf_class_64);
    assert(load.u16(region_base() + 16) == elf_type_exec);
    assert(load.u16(region_base() + 18) == elf_machine_x86_64);
    assert(load.u64(region_base() + elf64_entry_foa) == text_vaddr + (start - text_start));
    assert(load.u64(region_base() + elf64_phdr_foa(0) + elf64_phdr_vaddr_foa) == text_vaddr);
}

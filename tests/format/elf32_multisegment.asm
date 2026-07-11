// api-matrix-fixture: elfexe_finalize_phdr32(
import("../../include/format/elfexe.inc");

x86.use32();

const ph_count: u16 = 2
const text_foa: u64 = elf32_first_segment_foa(ph_count)
const text_vaddr: u64 = elf_default_base32 + text_foa

elfexe_begin32(ph_count);

region.begin(".text", text_vaddr, text_foa);
text_start:
start:
    mov ebx, [data_start]
    mov eax, 1
    int 0x80
text_end:
region.file_align(1);

const data_foa: u64 = file_offset()
const data_vaddr: u64 = elf_default_base32 + elf_default_page_align + data_foa

region.begin(".data", data_vaddr, data_foa);
data_start:
    dd(0);
    rb(64);
data_end:
region.file_align(1);

elfexe_finalize_entry32(start, text_start, text_vaddr);
elfexe_finalize_phdr32(
    0,
    elf_pt_load,
    elf_pf_r | elf_pf_x,
    text_foa,
    text_vaddr,
    text_end - text_start,
    text_end - text_start,
    elf_default_page_align
);
elfexe_finalize_phdr32(
    1,
    elf_pt_load,
    elf_pf_r | elf_pf_w,
    data_foa,
    data_vaddr,
    4,
    data_end - data_start,
    elf_default_page_align
);

defer {
    assert(load.u16(region_base() + elf32_phnum_foa) == ph_count);
    assert(load.u32(region_base() + elf32_entry_foa) == text_vaddr);
    assert(load.u32(region_base() + elf32_phdr_foa(0) + elf32_phdr_offset_foa) == text_foa);
    assert(load.u32(region_base() + elf32_phdr_foa(0) + elf32_phdr_vaddr_foa) == text_vaddr);
    assert(load.u32(region_base() + elf32_phdr_foa(0) + elf32_phdr_filesz_foa) == 13);
    assert(load.u32(region_base() + elf32_phdr_foa(0) + elf32_phdr_memsz_foa) == 13);
    assert(load.u32(region_base() + elf32_phdr_foa(1) + elf32_phdr_offset_foa) == data_foa);
    assert(load.u32(region_base() + elf32_phdr_foa(1) + elf32_phdr_vaddr_foa) == data_vaddr);
    assert(load.u32(region_base() + elf32_phdr_foa(1) + elf32_phdr_filesz_foa) == 4);
    assert(load.u32(region_base() + elf32_phdr_foa(1) + elf32_phdr_memsz_foa) == 68);
    assert(load.u32(region_base() + elf32_phdr_foa(0) + elf32_phdr_flags_foa) == elf_pf_r | elf_pf_x);
    assert(load.u32(region_base() + elf32_phdr_foa(1) + elf32_phdr_flags_foa) == elf_pf_r | elf_pf_w);
    assert((text_vaddr % elf_default_page_align) == (text_foa % elf_default_page_align));
    assert((data_vaddr % elf_default_page_align) == (data_foa % elf_default_page_align));
}

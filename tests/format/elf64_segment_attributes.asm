// api-matrix-fixture: elf64_finish_note(
// api-matrix-fixture: elf64_finish_gnu_stack(
// api-matrix-fixture: elf64_finish_gnu_eh_frame(
// api-matrix-fixture: elf64_finish_gnu_relro(
// api-matrix-fixture: elfexe_finalize_region64(

import("../../include/format/elf64.inc");

const ph_count: u16 = 5
const text_foa: u64 = elf64_first_foa(ph_count)
const note_foa: u64 = text_foa + 16
const eh_frame_foa: u64 = note_foa + 16
const relro_foa: u64 = eh_frame_foa + 16
const stack_foa: u64 = relro_foa + 16

elf64_exe(ph_count);

elf64_segment_raw(".text", text_foa);
text_start:
start:
    mov eax, 60
    xor edi, edi
    syscall
elf64_end_segment_raw(16);

elf64_segment_raw(".note", note_foa);
note_start:
dd(4);
dd(4);
dd(1);
dd(0x00524958);
elf64_end_segment_raw(16);

elf64_segment_raw(".eh_frame_hdr", eh_frame_foa);
eh_frame_start:
dd(0x3b031b01);
dd(0);
dd(0);
dd(0);
elf64_end_segment_raw(16);

elf64_segment_raw(".data.rel.ro", relro_foa);
relro_start:
dq(0x1122334455667788);
dq(0x99aabbccddeeff00);
elf64_end_segment_raw(16);

elf64_finish_load_raw(0, start, text_foa, text_start, text_start + 16, elf_rx);
elf64_finish_note(1, note_start, elf_r);
elf64_finish_gnu_eh_frame(2, eh_frame_start, elf_r);
elf64_finish_gnu_relro(3, relro_start, elf_rw);
elf64_finish_gnu_stack(4, stack_foa, elf_rw);

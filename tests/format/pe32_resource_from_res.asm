import("../../include/format/pe32.inc");
import("../../include/format/pe_resource.inc");

x86.use32();

const text_rva: u64 = pe_section_rva(0, pe_default_section_align)
const rsrc_rva: u64 = pe_section_rva(1, pe_default_section_align)

pe32_exe(2);

pe32_section(".text", 0);
text_start:
start:
    mov eax, 1
    ret
text_end:
pe32_end_section(0);

pe32_section(".rsrc", 1);
rsrc_start:
pe_resource_emit_from_res("data/pe_resource_named_multilang.res", rsrc_rva);
pe32_end_section(1);

pe32_finish_text(0, start, text_start, text_end, pe_text_chars);
pe32_finish_resource_section(1, rsrc_start, pe_resource_end);

// api-matrix-fixture: pe_resource_emit_from_res(

import("../../include/format/pe64.inc");
import("../../include/format/pe_resource.inc");

const text_rva: u64 = pe_section_rva(0, pe_default_section_align)
const rsrc_rva: u64 = pe_section_rva(1, pe_default_section_align)

pe64_exe(2);

pe64_section(".text", 0);
text_start:
start:
    mov eax, 1
    ret
text_end:
pe64_end_section(0);

pe64_section(".rsrc", 1);
rsrc_start:
pe_resource_emit_from_res("data/pe_resource_named_multilang.res", rsrc_rva);
pe64_end_section(1);

pe64_finish_text(0, start, text_start, text_end, pe_text_chars);
pe64_finish_resource_section(1, rsrc_start, pe_resource_end);

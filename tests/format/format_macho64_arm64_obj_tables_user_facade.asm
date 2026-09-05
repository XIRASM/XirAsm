import("format/format.inc");

// Two public symbols and one extern across two sections, with relocations in
// both sections, exercising the format_macho64_* symbol and relocation API.

const version: u64 = macho_exe_macos_version(14, 0, 0)
let image: map = format_macho64_object(
    format_macho64_target_arm64(version, version),
    list.of(
        format_section("__text", format_code | format_readable | format_executable),
        format_section("__data", format_data | format_readable | format_writeable)
    )
)

format_begin(image);
format_section_begin(image, "__text");
text_start:
call_site:
    emit.u32(0x94000000);
page_site:
    emit.u32(0x90000000);
entry:
    emit.u32(0x91000000);
    emit.u32(0xd65f03c0);
format_section_end(image, "__text");

format_section_begin(image, "__data");
data_start:
pointer_slot:
    emit.u64(0);
answer:
    emit.u64(42);
format_section_end(image, "__data");

const symbols: list = list.of(
    format_macho64_public("_entry", "__text", text_start, entry, macho_n_sect | macho_n_ext),
    format_macho64_public("_answer", "__data", data_start, answer, macho_n_sect | macho_n_ext),
    format_macho64_extern("_printf")
)
const relocs: list = list.of(
    format_macho64_arm64_reloc("__text", text_start, call_site, "_printf", macho_arm64_reloc_branch26),
    format_macho64_arm64_reloc("__text", text_start, page_site, "_answer", macho_arm64_reloc_page21),
    format_macho64_arm64_reloc("__data", data_start, pointer_slot, "_printf", macho_arm64_reloc_unsigned)
)
format_macho64_tables_mut(image, symbols, relocs)
format_finish(image);

// Layout facts: header 32, segment command 232, build version 24, symtab
// command 24, so section content starts at 312 and the section commands sit at
// 104 and 184. Section data ends at 344, and the tables region holds two text
// relocations at 344, one data relocation at 360, three nlist entries at 368,
// and a 24-byte string table at 416.
defer {
    assert(load.u32(0) == macho_magic_64);
    assert(load.u32(12) == macho_mh_object);
    assert(load.u32(16) == 3);
    assert(load.u32(20) == 280);
    assert(load.u32(288) == macho_lc_symtab);
    assert(load.u32(292) == macho_symtab_command_size);
    assert(load.u32(296) == 368);
    assert(load.u32(300) == 3);
    assert(load.u32(304) == 416);
    assert(load.u32(308) == 24);
    assert(load.u32(160) == 344);
    assert(load.u32(164) == 2);
    assert(load.u32(240) == 360);
    assert(load.u32(244) == 1);

    // _printf BRANCH26: symbol 2, pcrel, length 2, external, type 2.
    assert(load.u32(344) == 0);
    assert(load.u32(348) == 0x2d000002);
    // _answer PAGE21: symbol 1, pcrel, length 2, external, type 3.
    assert(load.u32(352) == 4);
    assert(load.u32(356) == 0x3d000001);
    // _printf UNSIGNED in __data: symbol 2, not pcrel, length 3, external.
    assert(load.u32(360) == 0);
    assert(load.u32(364) == 0x0e000002);

    const symoff: u64 = load.u32(296)
    // _entry: N_SECT | N_EXT in __text, value 8.
    assert(load.u32(symoff) == 1);
    assert(load.u8(symoff + 4) == (macho_n_sect | macho_n_ext));
    assert(load.u8(symoff + 5) == 1);
    assert(load.u64(symoff + 8) == 8);
    // _answer: N_SECT | N_EXT in __data, value 8.
    assert(load.u32(symoff + 16) == 8);
    assert(load.u8(symoff + 20) == (macho_n_sect | macho_n_ext));
    assert(load.u8(symoff + 21) == 2);
    assert(load.u64(symoff + 24) == 8);
    // _printf: N_UNDF | N_EXT, no section, zero value.
    assert(load.u32(symoff + 32) == 16);
    assert(load.u8(symoff + 36) == (macho_n_undef | macho_n_ext));
    assert(load.u8(symoff + 37) == 0);
    assert(load.u64(symoff + 40) == 0);
}

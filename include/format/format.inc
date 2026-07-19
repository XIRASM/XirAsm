// User-facing executable-format API layer.
//
// This layer owns declarative format plans and named section lookup. The
// family-specific include files remain available as advanced row-level APIs.

import("pe32.inc");
import("pe64.inc");
import("pe_export.inc");
import("pe_import.inc");
import("pe_reloc.inc");
import("pe_resource.inc");
import("coff.inc");
import("elfexe.inc");
import("elfexe_import.inc");
import("elfobj.inc");
import("elf_export.inc");
import("elfso_import.inc");

const format_kind_pe32: u64 = 1
const format_kind_pe64: u64 = 2
const format_kind_elf32: u64 = 3
const format_kind_elf64: u64 = 4
const format_kind_coff32: u64 = 5
const format_kind_coff64: u64 = 6
const format_kind_elfobj32: u64 = 7
const format_kind_elfobj64: u64 = 8
const format_kind_elfso64: u64 = 9

const format_coff_symbol_public: u64 = 1
const format_coff_symbol_extern: u64 = 2
const format_elfobj_symbol_public: u64 = 3
const format_elfobj_symbol_extern: u64 = 4

const format_pe_exe: u64 = 0x0001
const format_pe_dll: u64 = 0x0002
const format_pe_console: u64 = 0x0004
const format_pe_gui: u64 = 0x0008
const format_pe_nx: u64 = 0x0010
const format_pe_aslr_auto: u64 = 0x0020
const format_pe_aslr_required: u64 = 0x0040
const format_pe_aslr_disabled: u64 = 0x0080

const format_elf_exec: u64 = 0x0001
const format_elf_pie: u64 = 0x0002

const format_code: u64 = 0x0001
const format_data: u64 = 0x0002
const format_uninitialized_data: u64 = 0x0004
const format_imports: u64 = 0x0008
const format_exports: u64 = 0x0010
const format_resources: u64 = 0x0020
const format_fixups: u64 = 0x0040

const format_readable: u64 = 0x0100
const format_writeable: u64 = 0x0200
const format_executable: u64 = 0x0400
const format_discardable: u64 = 0x0800

const format_load: u64 = 0x00010000

const format_section_purpose_mask: u64 = format_code | format_data | format_uninitialized_data | format_imports | format_exports | format_resources | format_fixups
const format_section_unique_purpose_mask: u64 = format_imports | format_exports | format_resources | format_fixups
const format_permission_mask: u64 = format_readable | format_writeable | format_executable | format_discardable
const format_segment_permission_mask: u64 = format_readable | format_writeable | format_executable
const format_segment_purpose_mask: u64 = format_load

const format_pe_kind_mask: u64 = format_pe_exe | format_pe_dll
const format_pe_subsystem_mask: u64 = format_pe_console | format_pe_gui
const format_pe_aslr_mask: u64 = format_pe_aslr_auto | format_pe_aslr_required | format_pe_aslr_disabled
const format_pe_option_mask: u64 = format_pe_kind_mask | format_pe_subsystem_mask | format_pe_nx | format_pe_aslr_mask
const format_elf_option_mask: u64 = format_elf_exec | format_elf_pie

const format_pe_opt_subsystem_foa: u64 = pe_optional_header_foa + 68

fn format_section(name: string, attributes: u64) -> map {
    assert(len(name) > 0, "format section name is empty");
    assert(
        (attributes & ~(format_section_purpose_mask | format_permission_mask)) == 0,
        "unknown format section attribute"
    );

    const purpose: u64 = attributes & format_section_purpose_mask
    assert(purpose != 0, "format section requires one purpose");
    assert((purpose & (purpose - 1)) == 0, "format section has multiple purposes");

    let section: map = map.new()
    map.set_mut(section, "name", name);
    map.set_mut(section, "attributes", attributes);
    return section;
}

fn format_validate_sections(sections: list) -> bool {
    assert(len(sections) > 0, "format plan requires at least one section");
    assert(len(sections) <= pe_max_image_sections, "format plan has too many PE sections");

    for i in range(0, len(sections)) {
        const current: map = list.get(sections, i)
        const current_name: string = map.get(current, "name")
        const current_attributes: u64 = map.get(current, "attributes")
        const current_purpose: u64 = current_attributes & format_section_purpose_mask
        assert(len(current_name) > 0, "format section name is empty");

        for j in range(i + 1, len(sections)) {
            const other: map = list.get(sections, j)
            assert(map.get(other, "name") != current_name, "format section name is duplicated");

            const other_attributes: u64 = map.get(other, "attributes")
            const other_purpose: u64 = other_attributes & format_section_purpose_mask
            if (current_purpose & format_section_unique_purpose_mask) != 0 {
                assert(other_purpose != current_purpose, "format special-purpose section is duplicated");
            }
        }
    }

    return true;
}

fn format_validate_short_section_names(sections: list) -> bool {
    for section in sections {
        assert(
            len(map.get(section, "name")) <= 8,
            "PE/COFF section names must fit in eight bytes"
        );
    }
    return true;
}

fn format_validate_pe_options(options: u64) -> bool {
    assert((options & ~format_pe_option_mask) == 0, "unknown PE format option");

    const kind: u64 = options & format_pe_kind_mask
    assert(kind != 0, "PE format requires EXE or DLL");
    assert((kind & (kind - 1)) == 0, "PE format cannot be both EXE and DLL");

    const subsystem: u64 = options & format_pe_subsystem_mask
    assert(subsystem != 0, "PE format requires console or GUI subsystem");
    assert((subsystem & (subsystem - 1)) == 0, "PE format has multiple subsystems");

    const aslr: u64 = options & format_pe_aslr_mask
    assert(aslr != 0, "PE format requires an ASLR policy");
    assert((aslr & (aslr - 1)) == 0, "PE format has multiple ASLR policies");

    return true;
}

fn format_pe_plan(kind: u64, options: u64, sections: list) -> map {
    assert(format_validate_pe_options(options), "invalid PE format options");
    assert(format_validate_sections(sections), "invalid PE section list");
    assert(format_validate_short_section_names(sections), "invalid PE section names");

    let plan: map = map.new()
    map.set_mut(plan, "kind", kind);
    map.set_mut(plan, "options", options);
    map.set_mut(plan, "sections", sections);
    map.set_mut(plan, "entry", 0);
    return plan;
}

fn format_pe32(options: u64, sections: list) -> map {
    return format_pe_plan(format_kind_pe32, options, sections);
}

fn format_pe64(options: u64, sections: list) -> map {
    return format_pe_plan(format_kind_pe64, options, sections);
}

fn format_pe_import_new() -> map {
    return pe_import_new();
}

fn format_pe_import_many_mut(plan: map, let imports: map, dll: string, names: list) {
    const kind: u64 = map.get(plan, "kind")
    if kind == format_kind_pe32 {
        imports = pe_import_use32_many(imports, dll, names);
    } else {
        assert(kind == format_kind_pe64, "format plan is not a PE image");
        imports = pe_import_use64_many(imports, dll, names);
    }
}

fn format_pe_import_pairs_mut(plan: map, let imports: map, dll: string, pairs: list) {
    const kind: u64 = map.get(plan, "kind")
    if kind == format_kind_pe32 {
        imports = pe_import_use32_pairs(imports, dll, pairs);
    } else {
        assert(kind == format_kind_pe64, "format plan is not a PE image");
        imports = pe_import_use64_pairs(imports, dll, pairs);
    }
}

fn format_pe_export_new() -> list {
    return pe_export_new();
}

fn format_pe_export_many_mut(plan: map, let exports: list, names: list) {
    const kind: u64 = map.get(plan, "kind")
    if kind == format_kind_pe32 {
        exports = pe_export_use32_many(exports, names);
    } else {
        assert(kind == format_kind_pe64, "format plan is not a PE image");
        exports = pe_export_use64_many(exports, names);
    }
}

fn format_pe_export_pairs_mut(plan: map, let exports: list, pairs: list) {
    const kind: u64 = map.get(plan, "kind")
    if kind == format_kind_pe32 {
        exports = pe_export_use32_pairs(exports, pairs);
    } else {
        assert(kind == format_kind_pe64, "format plan is not a PE image");
        exports = pe_export_use64_pairs(exports, pairs);
    }
}

fn format_validate_coff_sections(sections: list) -> bool {
    assert(format_validate_sections(sections), "invalid COFF section list");
    assert(format_validate_short_section_names(sections), "invalid COFF section names");
    for section in sections {
        const attributes: u64 = map.get(section, "attributes")
        const purpose: u64 = attributes & format_section_purpose_mask
        assert(
            purpose == format_code ||
            purpose == format_data ||
            purpose == format_uninitialized_data,
            "COFF format API supports code, data, and uninitialized-data sections"
        );
        assert((attributes & format_discardable) == 0, "COFF format API does not expose discardable sections");
    }
    return true;
}

fn format_coff_plan(kind: u64, sections: list) -> map {
    assert(format_validate_coff_sections(sections), "invalid COFF section list");
    let plan: map = map.new()
    map.set_mut(plan, "kind", kind);
    map.set_mut(plan, "sections", sections);
    map.set_mut(plan, "symbols", list.new());
    map.set_mut(plan, "relocs", list.new());
    map.set_mut(plan, "entry", 0);
    return plan;
}

fn format_coff32(sections: list) -> map {
    return format_coff_plan(format_kind_coff32, sections);
}

fn format_coff64(sections: list) -> map {
    return format_coff_plan(format_kind_coff64, sections);
}

fn format_coff_public(name: string, section_name: string, section_start: u64, address: u64, sym_type: u16) -> map {
    assert(len(name) > 0 && len(name) <= 8, "COFF symbol names must fit in eight bytes");
    assert(len(section_name) > 0, "COFF public symbol requires a section name");
    assert(address >= section_start, "COFF public symbol is before its section start");
    let symbol: map = map.new()
    map.set_mut(symbol, "kind", format_coff_symbol_public);
    map.set_mut(symbol, "name", name);
    map.set_mut(symbol, "section", section_name);
    map.set_mut(symbol, "value", address - section_start);
    map.set_mut(symbol, "type", sym_type);
    return symbol;
}

fn format_coff_extern(name: string, sym_type: u16) -> map {
    assert(len(name) > 0 && len(name) <= 8, "COFF symbol names must fit in eight bytes");
    let symbol: map = map.new()
    map.set_mut(symbol, "kind", format_coff_symbol_extern);
    map.set_mut(symbol, "name", name);
    map.set_mut(symbol, "section", "");
    map.set_mut(symbol, "value", 0);
    map.set_mut(symbol, "type", sym_type);
    return symbol;
}

fn format_coff_reloc(section_name: string, section_start: u64, address: u64, symbol_name: string, reloc_type: u16) -> map {
    assert(len(section_name) > 0, "COFF relocation requires a section name");
    assert(len(symbol_name) > 0 && len(symbol_name) <= 8, "COFF relocation symbol names must fit in eight bytes");
    assert(address >= section_start, "COFF relocation is before its section start");
    let reloc: map = map.new()
    map.set_mut(reloc, "section", section_name);
    map.set_mut(reloc, "offset", address - section_start);
    map.set_mut(reloc, "symbol", symbol_name);
    map.set_mut(reloc, "type", reloc_type);
    return reloc;
}

fn format_coff_symbol_index(symbols: list, name: string) -> u64 {
    for i in range(0, len(symbols)) {
        const symbol: map = list.get(symbols, i)
        if map.get(symbol, "name") == name {
            return i;
        }
    }
    assert(false, "COFF relocation target symbol is not declared");
    return 0;
}

fn format_validate_coff_tables(plan: map, symbols: list, relocs: list) -> bool {
    assert(len(symbols) > 0, "COFF format API requires at least one symbol");
    for i in range(0, len(symbols)) {
        const symbol: map = list.get(symbols, i)
        const name: string = map.get(symbol, "name")
        const symbol_kind: u64 = map.get(symbol, "kind")
        if symbol_kind == format_coff_symbol_public {
            const section_row: u64 = format_section_row(plan, map.get(symbol, "section"))
            assert(section_row < len(map.get(plan, "sections")), "COFF public symbol section is invalid");
        }
        assert(
            symbol_kind == format_coff_symbol_public ||
            symbol_kind == format_coff_symbol_extern,
            "unknown COFF format symbol kind"
        );
        for j in range(i + 1, len(symbols)) {
            const other: map = list.get(symbols, j)
            assert(map.get(other, "name") != name, "COFF symbol name is duplicated");
        }
    }
    for reloc in relocs {
        const section_row: u64 = format_section_row(plan, map.get(reloc, "section"))
        const symbol_index: u64 = format_coff_symbol_index(symbols, map.get(reloc, "symbol"))
        assert(section_row < len(map.get(plan, "sections")), "COFF relocation section is invalid");
        assert(symbol_index < len(symbols), "COFF relocation symbol index is invalid");
    }
    return true;
}

fn format_coff_tables_mut(let plan: map, symbols: list, relocs: list) {
    const kind: u64 = map.get(plan, "kind")
    assert(kind == format_kind_coff32 || kind == format_kind_coff64, "format plan is not a COFF object");
    assert(format_validate_coff_tables(plan, symbols, relocs), "invalid COFF format API tables");
    map.set_mut(plan, "symbols", symbols);
    map.set_mut(plan, "relocs", relocs);
}

fn format_validate_elfobj_sections(sections: list) -> bool {
    assert(format_validate_sections(sections), "invalid ELF object section list");
    for section in sections {
        const attributes: u64 = map.get(section, "attributes")
        const purpose: u64 = attributes & format_section_purpose_mask
        assert(
            purpose == format_code ||
            purpose == format_data ||
            purpose == format_uninitialized_data,
            "ELF object format API supports code, data, and uninitialized-data sections"
        );
        assert(
            (attributes & format_discardable) == 0,
            "ELF object format API does not expose discardable sections"
        );
    }
    return true;
}

fn format_elfobj_plan(kind: u64, sections: list) -> map {
    assert(kind == format_kind_elfobj32 || kind == format_kind_elfobj64, "invalid ELF object kind");
    assert(format_validate_elfobj_sections(sections), "invalid ELF object section list");

    let plan: map = map.new()
    map.set_mut(plan, "kind", kind);
    map.set_mut(plan, "sections", sections);
    map.set_mut(plan, "symbols", list.new());
    map.set_mut(plan, "relocs", list.new());
    map.set_mut(plan, "entry", 0);
    return plan;
}

fn format_elfobj32(sections: list) -> map {
    return format_elfobj_plan(format_kind_elfobj32, sections);
}

fn format_elfobj64(sections: list) -> map {
    return format_elfobj_plan(format_kind_elfobj64, sections);
}

fn format_elfobj_public(name: string, section_name: string, section_start: u64, address: u64, symbol_size: u64, symbol_type: u8) -> map {
    assert(len(name) > 0, "ELF object public symbol name is empty");
    assert(len(section_name) > 0, "ELF object public symbol requires a section name");
    assert(address >= section_start, "ELF object public symbol is before its section start");

    let symbol: map = map.new()
    map.set_mut(symbol, "kind", format_elfobj_symbol_public);
    map.set_mut(symbol, "name", name);
    map.set_mut(symbol, "section", section_name);
    map.set_mut(symbol, "value", address - section_start);
    map.set_mut(symbol, "size", symbol_size);
    map.set_mut(symbol, "type", symbol_type);
    return symbol;
}

fn format_elfobj_extern(name: string, symbol_type: u8) -> map {
    assert(len(name) > 0, "ELF object external symbol name is empty");

    let symbol: map = map.new()
    map.set_mut(symbol, "kind", format_elfobj_symbol_extern);
    map.set_mut(symbol, "name", name);
    map.set_mut(symbol, "section", "");
    map.set_mut(symbol, "value", 0);
    map.set_mut(symbol, "size", 0);
    map.set_mut(symbol, "type", symbol_type);
    return symbol;
}

fn format_elfobj_reloc(section_name: string, section_start: u64, address: u64, symbol_name: string, reloc_type: u64, addend: u64) -> map {
    assert(len(section_name) > 0, "ELF object relocation requires a section name");
    assert(len(symbol_name) > 0, "ELF object relocation symbol name is empty");
    assert(address >= section_start, "ELF object relocation is before its section start");

    let reloc: map = map.new()
    map.set_mut(reloc, "section", section_name);
    map.set_mut(reloc, "offset", address - section_start);
    map.set_mut(reloc, "address", address);
    map.set_mut(reloc, "symbol", symbol_name);
    map.set_mut(reloc, "type", reloc_type);
    map.set_mut(reloc, "addend", addend);
    return reloc;
}

fn format_elfobj_symbol_index(plan: map, symbols: list, name: string) -> u64 {
    const sections: list = map.get(plan, "sections")
    for i in range(0, len(symbols)) {
        const symbol: map = list.get(symbols, i)
        if map.get(symbol, "name") == name {
            return 1 + len(sections) + i;
        }
    }
    assert(false, "ELF object relocation target symbol is not declared");
    return 0;
}

fn format_validate_elfobj_tables(plan: map, symbols: list, relocs: list) -> bool {
    assert(len(symbols) > 0, "ELF object format API requires at least one symbol");
    for i in range(0, len(symbols)) {
        const symbol: map = list.get(symbols, i)
        const name: string = map.get(symbol, "name")
        const symbol_kind: u64 = map.get(symbol, "kind")
        if symbol_kind == format_elfobj_symbol_public {
            const section_row: u64 = format_section_row(plan, map.get(symbol, "section"))
            assert(section_row < len(map.get(plan, "sections")), "ELF object public symbol section is invalid");
        }
        assert(
            symbol_kind == format_elfobj_symbol_public ||
            symbol_kind == format_elfobj_symbol_extern,
            "unknown ELF object format symbol kind"
        );
        for j in range(i + 1, len(symbols)) {
            const other: map = list.get(symbols, j)
            assert(map.get(other, "name") != name, "ELF object symbol name is duplicated");
        }
    }
    for reloc in relocs {
        const section_row: u64 = format_section_row(plan, map.get(reloc, "section"))
        const symbol_index: u64 = format_elfobj_symbol_index(plan, symbols, map.get(reloc, "symbol"))
        assert(section_row < len(map.get(plan, "sections")), "ELF object relocation section is invalid");
        assert(symbol_index > len(map.get(plan, "sections")), "ELF object relocation symbol index is invalid");
    }
    return true;
}

fn format_elfobj_tables_mut(let plan: map, symbols: list, relocs: list) {
    const kind: u64 = map.get(plan, "kind")
    assert(kind == format_kind_elfobj32 || kind == format_kind_elfobj64, "format plan is not an ELF object");
    assert(format_validate_elfobj_tables(plan, symbols, relocs), "invalid ELF object format API tables");
    map.set_mut(plan, "symbols", symbols);
    map.set_mut(plan, "relocs", relocs);
}

fn format_segment(name: string, attributes: u64) -> map {
    assert(len(name) > 0, "format segment name is empty");
    assert((attributes & ~(format_segment_purpose_mask | format_segment_permission_mask)) == 0, "unknown format segment attribute");

    const purpose: u64 = attributes & format_segment_purpose_mask
    assert(purpose != 0, "format segment requires one purpose");
    assert((purpose & (purpose - 1)) == 0, "format segment has multiple purposes");

    let segment: map = map.new()
    map.set_mut(segment, "name", name);
    map.set_mut(segment, "attributes", attributes);
    return segment;
}

fn format_validate_segments(segments: list) -> bool {
    assert(len(segments) > 0, "format plan requires at least one segment");
    assert(len(segments) <= 65535, "format plan has too many ELF segments");

    for i in range(0, len(segments)) {
        const current: map = list.get(segments, i)
        const current_name: string = map.get(current, "name")

        assert(len(current_name) > 0, "format segment name is empty");

        for j in range(i + 1, len(segments)) {
            const other: map = list.get(segments, j)
            assert(map.get(other, "name") != current_name, "format segment name is duplicated");
        }
    }

    return true;
}

fn format_validate_elf_options(kind: u64, options: u64) -> bool {
    assert((options & ~format_elf_option_mask) == 0, "unknown ELF format option");
    assert(options != 0, "ELF format requires executable or PIE mode");
    assert((options & (options - 1)) == 0, "ELF format has multiple file modes");
    if kind == format_kind_elf32 {
        assert(options == format_elf_exec, "format.inc ELF32 layer currently supports executable mode");
    }
    return true;
}

fn format_elf_plan(kind: u64, options: u64, segments: list) -> map {
    assert(format_validate_elf_options(kind, options), "invalid ELF format options");
    assert(format_validate_segments(segments), "invalid ELF segment list");

    let plan: map = map.new()
    map.set_mut(plan, "kind", kind);
    map.set_mut(plan, "options", options);
    map.set_mut(plan, "segments", segments);
    map.set_mut(plan, "entry", 0);
    map.set_mut(plan, "imports", list.new());
    return plan;
}

fn format_elf32(options: u64, segments: list) -> map {
    return format_elf_plan(format_kind_elf32, options, segments);
}

fn format_elf64(options: u64, segments: list) -> map {
    return format_elf_plan(format_kind_elf64, options, segments);
}

fn format_elfexe_import_new() -> list {
    return elfexe_import_new();
}

fn format_elfexe_import_many_mut(let imports: list, library: string, names: list) {
    imports = elfexe_import_use64_plt_many(imports, library, names);
}

fn format_elfexe_import_pairs_mut(let imports: list, library: string, pairs: list) {
    imports = elfexe_import_use64_plt_pairs(imports, library, pairs);
}

fn format_validate_elfexe_tables(plan: map, imports: list) -> bool {
    assert(map.get(plan, "kind") == format_kind_elf64, "ELF executable imports require ELF64");
    assert(map.get(plan, "options") == format_elf_exec, "ELF executable imports require fixed-address EXEC mode");
    assert(len(imports) > 0, "ELF executable import table is empty");

    const segments: list = map.get(plan, "segments")
    for segment in segments {
        assert(map.get(segment, "name") != ".elfexe.plt", "ELF executable segment uses a reserved internal name");
        assert(map.get(segment, "name") != ".elfexe.imports", "ELF executable segment uses a reserved internal name");
    }

    for i in range(0, len(imports)) {
        const current: map = list.get(imports, i)
        const current_slot: string = map.get(current, "slot")
        const current_plt: string = map.get(current, "plt")
        for j in range(i + 1, len(imports)) {
            const other: map = list.get(imports, j)
            assert(map.get(other, "slot") != current_slot, "ELF executable import slot is duplicated");
            assert(map.get(other, "plt") != current_plt, "ELF executable import PLT label is duplicated");
        }
    }
    return true;
}

fn format_elfexe_tables_mut(let plan: map, imports: list) {
    assert(format_validate_elfexe_tables(plan, imports), "invalid ELF executable import table");
    map.set_mut(plan, "imports", imports);
}

fn format_elf64_so(soname: string, segments: list) -> map {
    assert(len(soname) > 0, "ELF shared object SONAME is empty");
    assert(format_validate_segments(segments), "invalid ELF shared-object segment list");

    let plan: map = map.new()
    map.set_mut(plan, "kind", format_kind_elfso64);
    map.set_mut(plan, "options", 0);
    map.set_mut(plan, "segments", segments);
    map.set_mut(plan, "soname", soname);
    map.set_mut(plan, "exports", list.new());
    map.set_mut(plan, "imports", list.new());
    map.set_mut(plan, "entry", 0);
    return plan;
}

fn format_elfso_export_new() -> list {
    return list.new();
}

fn format_elfso_export_many_mut(let exports: list, names: list, segment_name: string, symbol_size: u64) {
    assert(len(segment_name) > 0, "ELF shared-object export segment name is empty");
    assert(symbol_size > 0, "ELF shared-object export size is zero");
    for name in names {
        assert(len(name) > 0, "ELF shared-object export name is empty");
        let entry: map = map.new()
        map.set_mut(entry, "target", name);
        map.set_mut(entry, "name", name);
        map.set_mut(entry, "segment", segment_name);
        map.set_mut(entry, "size", symbol_size);
        list.push_mut(exports, entry);
    }
}

fn format_elfso_export_pairs_mut(let exports: list, pairs: list, segment_name: string, symbol_size: u64) {
    assert(len(pairs) % 2 == 0, "ELF shared-object export pairs require target/name entries");
    assert(len(pairs) <= 128, "ELF shared-object export pairs exceed the batch limit");
    assert(len(segment_name) > 0, "ELF shared-object export segment name is empty");
    assert(symbol_size > 0, "ELF shared-object export size is zero");
    let index: u64 = 0
    while index < len(pairs) {
        const target_label: string = list.get(pairs, index)
        const export_name: string = list.get(pairs, index + 1)
        assert(len(target_label) > 0, "ELF shared-object export target label is empty");
        assert(len(export_name) > 0, "ELF shared-object export name is empty");
        let entry: map = map.new()
        map.set_mut(entry, "target", target_label);
        map.set_mut(entry, "name", export_name);
        map.set_mut(entry, "segment", segment_name);
        map.set_mut(entry, "size", symbol_size);
        list.push_mut(exports, entry);
        index = index + 2
    }
}

fn format_elfso_import_new() -> list {
    return elfso_import_new();
}

fn format_elfso_import_many_mut(let imports: list, library: string, names: list) {
    imports = elfso_import_use64_plt_many(imports, library, names);
}

fn format_elfso_import_pairs_mut(let imports: list, library: string, pairs: list) {
    imports = elfso_import_use64_plt_pairs(imports, library, pairs);
}

fn format_validate_elfso_tables(plan: map, exports: list, imports: list) -> bool {
    assert(map.get(plan, "kind") == format_kind_elfso64, "format plan is not an ELF64 shared object");
    assert(len(exports) > 0, "ELF shared-object format API requires at least one export");

    for i in range(0, len(exports)) {
        const export0: map = list.get(exports, i)
        const export_name: string = map.get(export0, "name")
        const segment_row: u64 = format_segment_row(plan, map.get(export0, "segment"))
        assert(segment_row < len(map.get(plan, "segments")), "ELF shared-object export segment is invalid");
        for j in range(i + 1, len(exports)) {
            const other: map = list.get(exports, j)
            assert(map.get(other, "name") != export_name, "ELF shared-object export name is duplicated");
        }
    }

    for i in range(0, len(imports)) {
        const import0: map = list.get(imports, i)
        const import_name: string = map.get(import0, "name")
        const slot_name: string = map.get(import0, "slot")
        const plt_name: string = map.get(import0, "plt")
        for export0 in exports {
            assert(map.get(export0, "name") != import_name, "ELF shared-object symbol cannot be both imported and exported");
        }
        for j in range(i + 1, len(imports)) {
            const other: map = list.get(imports, j)
            assert(map.get(other, "slot") != slot_name, "ELF shared-object import slot is duplicated");
            assert(map.get(other, "plt") != plt_name, "ELF shared-object import PLT label is duplicated");
        }
    }
    return true;
}

fn format_elfso_tables_mut(let plan: map, exports: list, imports: list) {
    assert(format_validate_elfso_tables(plan, exports, imports), "invalid ELF shared-object format API tables");
    map.set_mut(plan, "exports", exports);
    map.set_mut(plan, "imports", imports);
}

fn format_entry_mut(let plan: map, address: u64) {
    const kind: u64 = map.get(plan, "kind")
    assert(
        kind == format_kind_pe32 ||
        kind == format_kind_pe64 ||
        kind == format_kind_elf32 ||
        kind == format_kind_elf64,
        "format plan does not use an executable entry"
    );
    assert(address != 0, "format entry address is zero");
    map.set_mut(plan, "entry", address);
}

fn format_section_row(plan: map, name: string) -> u64 {
    const sections: list = map.get(plan, "sections")
    for i in range(0, len(sections)) {
        const section: map = list.get(sections, i)
        if map.get(section, "name") == name {
            return i;
        }
    }
    assert(false, "format section is not declared");
    return 0;
}

fn format_section_purpose(plan: map, name: string) -> u64 {
    const row: u64 = format_section_row(plan, name)
    const sections: list = map.get(plan, "sections")
    const section: map = list.get(sections, row)
    const attributes: u64 = map.get(section, "attributes")
    return attributes & format_section_purpose_mask;
}

fn format_segment_row(plan: map, name: string) -> u64 {
    const segments: list = map.get(plan, "segments")
    for i in range(0, len(segments)) {
        const segment: map = list.get(segments, i)
        if map.get(segment, "name") == name {
            return i;
        }
    }
    assert(false, "format segment is not declared");
    return 0;
}

fn format_elf_logical_offset(file_offset: u64, potential_offset: u64) -> u64 {
    const file_mod: u64 = file_offset % elf_default_page_align
    const potential_mod: u64 = potential_offset % elf_default_page_align
    let delta = 0
    if potential_mod <= file_mod {
        delta = file_mod - potential_mod
    }
    if potential_mod > file_mod {
        delta = elf_default_page_align - (potential_mod - file_mod)
    }
    return potential_offset + delta;
}

fn format_elf_next_logical_offset(image_base: u64, file_offset: u64) -> u64 {
    let potential_offset = file_cursor_potential()
    const current: u64 = here()
    if current >= image_base {
        const current_offset: u64 = current - image_base
        if current_offset > potential_offset {
            potential_offset = current_offset
        }
    }
    return format_elf_logical_offset(file_offset, potential_offset);
}

fn format_elf_next_load_logical_offset(image_base: u64, file_offset: u64, separate_page: u64) -> u64 {
    let logical_offset = format_elf_next_logical_offset(image_base, file_offset)
    if separate_page == 0 {
        return logical_offset;
    }

    const current: u64 = here()
    if current <= image_base {
        return logical_offset;
    }

    const current_offset: u64 = current - image_base
    const previous_page: u64 = (current_offset - 1) / elf_default_page_align
    if logical_offset / elf_default_page_align <= previous_page {
        logical_offset = logical_offset + elf_default_page_align
    }
    return logical_offset;
}

fn format_elf_segment_flags(attributes: u64) -> u64 {
    let flags = 0
    if (attributes & format_readable) != 0 {
        flags = flags | elf_pf_r
    }
    if (attributes & format_writeable) != 0 {
        flags = flags | elf_pf_w
    }
    if (attributes & format_executable) != 0 {
        flags = flags | elf_pf_x
    }
    return flags;
}

fn format_elfobj_section_flags(attributes: u64) -> u64 {
    let flags = elf_shf_alloc
    if (attributes & format_writeable) != 0 {
        flags = flags | elf_shf_write
    }
    if (attributes & format_executable) != 0 {
        flags = flags | elf_shf_execinstr
    }
    return flags;
}

fn format_elfobj_section_type(attributes: u64) -> u64 {
    const purpose: u64 = attributes & format_section_purpose_mask
    if purpose == format_uninitialized_data {
        return elf_sht_nobits;
    }
    return elf_sht_progbits;
}

fn format_elfobj_section_alignment(kind: u64, attributes: u64) -> u64 {
    const purpose: u64 = attributes & format_section_purpose_mask
    if purpose == format_code {
        return 16;
    }
    if kind == format_kind_elfobj64 {
        return 8;
    }
    return 4;
}

fn format_elfobj_section_start_label(name: string) -> string {
    return sym.join("__xirasm_elfobj_start", name);
}

fn format_pe_section_start_label(name: string) -> string {
    return sym.join("__xirasm_pe_start", name);
}

fn format_elfobj_section_end_label(name: string) -> string {
    return sym.join("__xirasm_elfobj_end", name);
}

fn format_elfso_segment_start_label(name: string) -> string {
    return sym.join("__xirasm_elfso_start", name);
}

fn format_elfso_segment_end_label(name: string) -> string {
    return sym.join("__xirasm_elfso_end", name);
}

fn format_elfso_section_flags(attributes: u64) -> u64 {
    let flags = elf_shf_alloc
    if (attributes & format_writeable) != 0 {
        flags = flags | elf_shf_write
    }
    if (attributes & format_executable) != 0 {
        flags = flags | elf_shf_execinstr
    }
    return flags;
}

fn format_elfso_section_alignment(attributes: u64) -> u64 {
    if (attributes & format_executable) != 0 {
        return 16;
    }
    return 8;
}

fn format_pe_section_chars(attributes: u64) -> u64 {
    let chars = 0
    const purpose: u64 = attributes & format_section_purpose_mask

    if purpose == format_code {
        chars = chars | pe_scn_cnt_code
    }
    if purpose == format_uninitialized_data {
        chars = chars | pe_scn_cnt_uninit_data
    }
    if purpose != format_code && purpose != format_uninitialized_data {
        chars = chars | pe_scn_cnt_init_data
    }
    if (attributes & format_readable) != 0 {
        chars = chars | pe_scn_mem_read
    }
    if (attributes & format_writeable) != 0 {
        chars = chars | pe_scn_mem_write
    }
    if (attributes & format_executable) != 0 {
        chars = chars | pe_scn_mem_execute
    }
    if (attributes & format_discardable) != 0 || purpose == format_fixups {
        chars = chars | pe_scn_mem_discardable
    }

    return chars;
}

fn format_coff_section_chars(attributes: u64) -> u64 {
    let chars = 0
    const purpose: u64 = attributes & format_section_purpose_mask
    if purpose == format_code {
        chars = chars | coff_scn_cnt_code | coff_scn_align_16bytes
    }
    if purpose == format_data {
        chars = chars | coff_scn_cnt_init_data | coff_scn_align_4bytes
    }
    if purpose == format_uninitialized_data {
        chars = chars | coff_scn_cnt_uninit_data | coff_scn_align_4bytes
    }
    if (attributes & format_readable) != 0 {
        chars = chars | coff_scn_mem_read
    }
    if (attributes & format_writeable) != 0 {
        chars = chars | coff_scn_mem_write
    }
    if (attributes & format_executable) != 0 {
        chars = chars | coff_scn_mem_execute
    }
    return chars;
}

fn format_has_section_purpose(sections: list, purpose: u64) -> bool {
    for section in sections {
        if (map.get(section, "attributes") & purpose) != 0 {
            return true;
        }
    }
    return false;
}

fn format_pe_subsystem(options: u64) -> u64 {
    if (options & format_pe_gui) != 0 {
        return pe_subsystem_gui;
    }
    return pe_subsystem_console;
}

fn format_pe_dll_chars(kind: u64, options: u64, sections: list) -> u64 {
    let chars = 0
    if (options & format_pe_nx) != 0 {
        chars = chars | pe_dll_nx_compat
    }

    const has_fixups: bool = format_has_section_purpose(sections, format_fixups)
    if (options & format_pe_aslr_required) != 0 {
        assert(has_fixups, "PE ASLR required needs a fixups section");
    }
    if (options & format_pe_aslr_disabled) == 0 && has_fixups {
        chars = chars | pe_dll_dynamic_base
        if kind == format_kind_pe64 {
            chars = chars | pe_dll_high_entropy_va
        }
    }

    return chars;
}

fn format_pe_emit_section_rows(sections: list) {
    for section in sections {
        const name: string = map.get(section, "name")
        db(name);
        pad(8 - len(name), 0);
        emit.u32(0);
        emit.u32(0);
        emit.u32(0);
        emit.u32(0);
        emit.u32(0);
        emit.u32(0);
        emit.u16(0);
        emit.u16(0);
        emit.u32(0);
    }
}

fn format_pe_begin32(options: u64, sections: list) {
    const section_count: u64 = len(sections)
    const subsystem: u64 = format_pe_subsystem(options)
    const dll_chars: u64 = format_pe_dll_chars(format_kind_pe32, options, sections)

    x86.use32();
    pe_begin32();

    let characteristics = pe_file_executable_image | pe_file_32bit_machine
    if (options & format_pe_dll) != 0 {
        characteristics = characteristics | pe_file_dll
    }
    emit.struct(PeFileHeader32 { sections: section_count, characteristics: characteristics });
    emit.struct(PeOptionalHeader32A {});
    emit.struct(PeOptionalHeader32B { subsystem: subsystem, dll_chars: dll_chars });

    for i in range(0, pe_data_dir_count) {
        emit.struct(PeDataDir {});
    }
    format_pe_emit_section_rows(sections);
    align(pe_default_file_align, 0);
    const header_size: u64 = file_offset()
    defer {
        store.u32(region_base() + pe_opt_size_of_headers_foa, header_size);
    }
}

fn format_pe_begin64(options: u64, sections: list) {
    const section_count: u64 = len(sections)
    const subsystem: u64 = format_pe_subsystem(options)
    const dll_chars: u64 = format_pe_dll_chars(format_kind_pe64, options, sections)

    x86.use64();
    pe_begin64();

    let characteristics = pe_file_executable_image | pe_file_large_address_aware
    if (options & format_pe_dll) != 0 {
        characteristics = characteristics | pe_file_dll
    }
    emit.struct(PeFileHeader64 { sections: section_count, characteristics: characteristics });
    emit.struct(PeOptionalHeader64A {});
    emit.struct(PeOptionalHeader64B { subsystem: subsystem, dll_chars: dll_chars });

    for i in range(0, pe_data_dir_count) {
        emit.struct(PeDataDir {});
    }
    format_pe_emit_section_rows(sections);
    align(pe_default_file_align, 0);
    const header_size: u64 = file_offset()
    defer {
        store.u32(region_base() + pe_opt_size_of_headers_foa, header_size);
    }
}

fn format_coff_emit_section_rows(sections: list) {
    for section in sections {
        const name: string = map.get(section, "name")
        db(name);
        pad(8 - len(name), 0);
        emit.u32(0);
        emit.u32(0);
        emit.u32(0);
        emit.u32(0);
        emit.u32(0);
        emit.u32(0);
        emit.u16(0);
        emit.u16(0);
        emit.u32(0);
    }
}

fn format_coff_begin_file(machine: u16, characteristics: u16, sections: list) {
    coff_file:
    emit.struct(CoffFileHeader {
        machine: machine,
        sections: len(sections),
        symbol_ptr: 0,
        symbol_count: 1,
        characteristics: characteristics,
    });
    coff_sections:
    format_coff_emit_section_rows(sections);
}

fn format_coff_begin32(sections: list) {
    x86.use32();
    format_coff_begin_file(
        coff_machine_i386,
        coff_file_32bit_machine | coff_file_line_nums_stripped,
        sections
    );
}

fn format_coff_begin64(sections: list) {
    x86.use64();
    format_coff_begin_file(coff_machine_amd64, coff_file_line_nums_stripped, sections);
}

fn format_elfobj_begin32() {
    x86.use32();
    elfobj_begin32_deferred();
    align(16);
}

fn format_elfobj_begin64() {
    x86.use64();
    elfobj_begin64_deferred();
    align(16);
}

fn format_coff_finalize_section_row(row: u64, start: u64, chars: u64, purpose: u64) {
    defer {
        let raw_size = region_file_size(start)
        let raw_ptr = region_file_offset(start)
        if purpose == format_uninitialized_data {
            raw_size = region_logical_size(start)
            raw_ptr = 0
        }
        store.u32(coff_sections + row * coff_section_header_size + coff_sec_raw_size_foa, raw_size);
        store.u32(coff_sections + row * coff_section_header_size + coff_sec_raw_ptr_foa, raw_ptr);
        store.u32(coff_sections + row * coff_section_header_size + coff_sec_chars_foa, chars);
    }
}

fn format_elfso_finalize_first_load_region(start: u64, flags: u64) {
    defer {
        const start_offset: u64 = region_file_offset(start)
        const file_size: u64 = start_offset + region_file_size(start)
        let memory_size = start_offset + region_logical_size(start)
        if memory_size < file_size {
            memory_size = file_size
        }
        store.u32(region_base() + elfso64_phdr_foa(0) + elfso64_phdr_type_foa, elf_pt_load);
        store.u32(region_base() + elfso64_phdr_foa(0) + elfso64_phdr_flags_foa, flags);
        store.u64(region_base() + elfso64_phdr_foa(0) + elfso64_phdr_offset_foa, 0);
        store.u64(region_base() + elfso64_phdr_foa(0) + elfso64_phdr_vaddr_foa, 0);
        store.u64(region_base() + elfso64_phdr_foa(0) + elfso64_phdr_paddr_foa, 0);
        store.u64(region_base() + elfso64_phdr_foa(0) + elfso64_phdr_filesz_foa, file_size);
        store.u64(region_base() + elfso64_phdr_foa(0) + elfso64_phdr_memsz_foa, memory_size);
        store.u64(region_base() + elfso64_phdr_foa(0) + elfso64_phdr_align_foa, elf_default_page_align);
    }
}

fn format_elfso_finalize_load_region(row: u64, start: u64, flags: u64) {
    defer {
        const offset: u64 = region_file_offset(start)
        const file_size: u64 = region_file_size(start)
        let memory_size = region_logical_size(start)
        if memory_size < file_size {
            memory_size = file_size
        }
        store.u32(region_base() + elfso64_phdr_foa(row) + elfso64_phdr_type_foa, elf_pt_load);
        store.u32(region_base() + elfso64_phdr_foa(row) + elfso64_phdr_flags_foa, flags);
        store.u64(region_base() + elfso64_phdr_foa(row) + elfso64_phdr_offset_foa, offset);
        store.u64(region_base() + elfso64_phdr_foa(row) + elfso64_phdr_vaddr_foa, start);
        store.u64(region_base() + elfso64_phdr_foa(row) + elfso64_phdr_paddr_foa, start);
        store.u64(region_base() + elfso64_phdr_foa(row) + elfso64_phdr_filesz_foa, file_size);
        store.u64(region_base() + elfso64_phdr_foa(row) + elfso64_phdr_memsz_foa, memory_size);
        store.u64(region_base() + elfso64_phdr_foa(row) + elfso64_phdr_align_foa, elf_default_page_align);
        assert(start % elf_default_page_align == offset % elf_default_page_align, "ELF LOAD virtual and file offsets are not page congruent");
    }
}

fn format_elfso_finalize_section_region(row_address: u64, start: u64, end: u64) {
    defer {
        if region_file_size(start) == 0 && end > start {
            store.u32(row_address + elfso_sh_type_foa, elf_sht_nobits);
        }
        store.u64(row_address + elfso64_sh_addr_foa, start);
        store.u64(row_address + elfso64_sh_offset_foa, region_file_offset(start));
        store.u64(row_address + elfso64_sh_size_foa, end - start);
    }
}

fn format_elfso_finalize_header64(section_table_foa: u64, section_count: u64, shstrndx: u64) {
    defer {
        store.u64(region_base() + elfso64_shoff_foa, section_table_foa);
        store.u16(region_base() + elfso64_shnum_foa, section_count);
        store.u16(region_base() + elfso64_shstrndx_foa, shstrndx);
    }
}

fn format_elf_begin32(segments: list) {
    elfexe_begin32(len(segments));
    align(16);
}

fn format_elf_begin64(plan: map) {
    const options: u64 = map.get(plan, "options")
    const segments: list = map.get(plan, "segments")
    const imports: list = map.get(plan, "imports")
    let segment_count = len(segments)
    if len(imports) > 0 {
        segment_count = segment_count + 4
    }
    if options == format_elf_exec {
        elfexe_begin64(segment_count);
        align(16);
    }
    if options == format_elf_pie {
        elfexe_begin64_at(segment_count, elf_type_dyn, 0);
        align(16);
    }
}

fn format_elfso_begin64(plan: map) {
    const segments: list = map.get(plan, "segments")
    const imports: list = map.get(plan, "imports")
    let ph_count = len(segments) + 2
    if len(imports) > 0 {
        ph_count = ph_count + 1
    }
    x86.use64();
    elfso_begin64(ph_count, 0, 1, 0);
    align(16);
}

fn format_begin(plan: map) {
    const kind: u64 = map.get(plan, "kind")

    if kind == format_kind_pe32 {
        const options: u64 = map.get(plan, "options")
        const sections: list = map.get(plan, "sections")
        format_pe_begin32(options, sections);
    }
    if kind == format_kind_pe64 {
        const options: u64 = map.get(plan, "options")
        const sections: list = map.get(plan, "sections")
        format_pe_begin64(options, sections);
    }
    if kind == format_kind_elf32 {
        const segments: list = map.get(plan, "segments")
        format_elf_begin32(segments);
    }
    if kind == format_kind_elf64 {
        format_elf_begin64(plan);
    }
    if kind == format_kind_coff32 {
        const sections: list = map.get(plan, "sections")
        format_coff_begin32(sections);
    }
    if kind == format_kind_coff64 {
        const sections: list = map.get(plan, "sections")
        format_coff_begin64(sections);
    }
    if kind == format_kind_elfobj32 {
        format_elfobj_begin32();
    }
    if kind == format_kind_elfobj64 {
        format_elfobj_begin64();
    }
    if kind == format_kind_elfso64 {
        format_elfso_begin64(plan);
    }
    assert(
        kind == format_kind_pe32 ||
        kind == format_kind_pe64 ||
        kind == format_kind_elf32 ||
        kind == format_kind_elf64 ||
        kind == format_kind_coff32 ||
        kind == format_kind_coff64 ||
        kind == format_kind_elfobj32 ||
        kind == format_kind_elfobj64 ||
        kind == format_kind_elfso64,
        "unsupported format plan kind"
    );
}

fn format_section_begin(plan: map, name: string) {
    const row: u64 = format_section_row(plan, name)
    const kind: u64 = map.get(plan, "kind")
    const sections: list = map.get(plan, "sections")
    const section: map = list.get(sections, row)
    const attributes: u64 = map.get(section, "attributes")
    const purpose: u64 = attributes & format_section_purpose_mask

    if kind == format_kind_pe32 {
        const chars: u64 = format_pe_section_chars(attributes)
        pe32_section(name, row);
        label.define(format_pe_section_start_label(name));
        format_pe_finalize_section32_row(row, here(), chars, purpose);
    }
    if kind == format_kind_pe64 {
        const chars: u64 = format_pe_section_chars(attributes)
        pe64_section(name, row);
        label.define(format_pe_section_start_label(name));
        format_pe_finalize_section64_row(row, here(), chars, purpose);
    }
    if kind == format_kind_coff32 || kind == format_kind_coff64 {
        const chars: u64 = format_coff_section_chars(attributes)
        region.begin(name, file_cursor_potential(), file_cursor_real());
        format_coff_finalize_section_row(row, here(), chars, purpose);
    }
    if kind == format_kind_elfobj32 || kind == format_kind_elfobj64 {
        region.begin(name, file_offset(), file_offset());
        label.define(format_elfobj_section_start_label(name));
    }
    assert(
        kind == format_kind_pe32 ||
        kind == format_kind_pe64 ||
        kind == format_kind_coff32 ||
        kind == format_kind_coff64 ||
        kind == format_kind_elfobj32 ||
        kind == format_kind_elfobj64,
        "unsupported format plan kind"
    );
}

fn format_section_end(plan: map, name: string) {
    const row: u64 = format_section_row(plan, name)
    const kind: u64 = map.get(plan, "kind")

    if kind == format_kind_pe32 {
        pe32_end_section(row);
    }
    if kind == format_kind_pe64 {
        pe64_end_section(row);
    }
    if kind == format_kind_coff32 || kind == format_kind_coff64 {
        coff_align_section_file();
    }
    if kind == format_kind_elfobj32 || kind == format_kind_elfobj64 {
        const sections: list = map.get(plan, "sections")
        const section: map = list.get(sections, row)
        const attributes: u64 = map.get(section, "attributes")
        assert(format_elfobj_section_alignment(kind, attributes) <= 16, "ELF object section alignment exceeds format.inc layer limit");
        label.define(format_elfobj_section_end_label(name));
        region.file_align(16);
    }
    assert(
        kind == format_kind_pe32 ||
        kind == format_kind_pe64 ||
        kind == format_kind_coff32 ||
        kind == format_kind_coff64 ||
        kind == format_kind_elfobj32 ||
        kind == format_kind_elfobj64,
        "unsupported format plan kind"
    );
}

fn format_pe_reloc_add_mut(plan: map, let relocs: list, address: u64) {
    const kind: u64 = map.get(plan, "kind")
    if kind == format_kind_pe32 {
        relocs = pe_reloc_add_highlow(relocs, address - pe_default_image_base32);
    } else {
        assert(kind == format_kind_pe64, "format plan is not a PE image");
        relocs = pe_reloc_add_dir64(relocs, address - pe_default_image_base64);
    }
}

fn format_pe_import_section32(plan: map, name: string, imports: map) {
    assert(format_section_purpose(plan, name) == format_imports, "format PE import section has the wrong purpose");
    format_section_begin(plan, name);
    const start: u64 = here()
    const rva: u64 = start - pe_default_image_base32
    pe_import_emit32(imports, rva, start);
    format_section_end(plan, name);
    pe_finalize_import_dir32(rva, start, pe_import_descriptors, pe_import_descriptors_end);
}

fn format_pe_import_section64(plan: map, name: string, imports: map) {
    assert(format_section_purpose(plan, name) == format_imports, "format PE import section has the wrong purpose");
    format_section_begin(plan, name);
    const start: u64 = here()
    const rva: u64 = start - pe_default_image_base64
    pe_import_emit64(imports, rva, start);
    format_section_end(plan, name);
    pe_finalize_import_dir64(rva, start, pe_import_descriptors, pe_import_descriptors_end);
}

fn format_pe_import_section(plan: map, name: string, imports: map) {
    const kind: u64 = map.get(plan, "kind")
    if kind == format_kind_pe32 {
        format_pe_import_section32(plan, name, imports);
    }
    if kind == format_kind_pe64 {
        format_pe_import_section64(plan, name, imports);
    }
    assert(kind == format_kind_pe32 || kind == format_kind_pe64, "format plan is not a PE image");
}

fn format_pe_export_section32(plan: map, name: string, exports: list, dll_name: string) {
    assert(format_section_purpose(plan, name) == format_exports, "format PE export section has the wrong purpose");
    format_section_begin(plan, name);
    const start: u64 = here()
    const rva: u64 = start - pe_default_image_base32
    pe_export_emit32(exports, dll_name, rva, start);
    format_section_end(plan, name);
    pe_finalize_export_dir32(rva, start, pe_export_directory, pe_export_directory_end);
}

fn format_pe_export_section64(plan: map, name: string, exports: list, dll_name: string) {
    assert(format_section_purpose(plan, name) == format_exports, "format PE export section has the wrong purpose");
    format_section_begin(plan, name);
    const start: u64 = here()
    const rva: u64 = start - pe_default_image_base64
    pe_export_emit64(exports, dll_name, rva, start);
    format_section_end(plan, name);
    pe_finalize_export_dir64(rva, start, pe_export_directory, pe_export_directory_end);
}

fn format_pe_export_section(plan: map, name: string, exports: list, dll_name: string) {
    const kind: u64 = map.get(plan, "kind")
    if kind == format_kind_pe32 {
        format_pe_export_section32(plan, name, exports, dll_name);
    }
    if kind == format_kind_pe64 {
        format_pe_export_section64(plan, name, exports, dll_name);
    }
    assert(kind == format_kind_pe32 || kind == format_kind_pe64, "format plan is not a PE image");
}

fn format_pe_resource_section32(plan: map, name: string, path: string) {
    assert(format_section_purpose(plan, name) == format_resources, "format PE resource section has the wrong purpose");
    format_section_begin(plan, name);
    const start: u64 = here()
    const rva: u64 = start - pe_default_image_base32
    pe_resource_emit_from_res(path, rva);
    format_section_end(plan, name);
    pe_finalize_resource_dir32(rva, start, pe_resource_root, pe_resource_end);
}

fn format_pe_resource_section64(plan: map, name: string, path: string) {
    assert(format_section_purpose(plan, name) == format_resources, "format PE resource section has the wrong purpose");
    format_section_begin(plan, name);
    const start: u64 = here()
    const rva: u64 = start - pe_default_image_base64
    pe_resource_emit_from_res(path, rva);
    format_section_end(plan, name);
    pe_finalize_resource_dir64(rva, start, pe_resource_root, pe_resource_end);
}

fn format_pe_resource_section(plan: map, name: string, path: string) {
    const kind: u64 = map.get(plan, "kind")
    if kind == format_kind_pe32 {
        format_pe_resource_section32(plan, name, path);
    }
    if kind == format_kind_pe64 {
        format_pe_resource_section64(plan, name, path);
    }
    assert(kind == format_kind_pe32 || kind == format_kind_pe64, "format plan is not a PE image");
}

fn format_pe_reloc_section32(plan: map, name: string, relocs: list) {
    assert(format_section_purpose(plan, name) == format_fixups, "format PE relocation section has the wrong purpose");
    assert(len(relocs) > 0, "format PE relocation section requires at least one relocation");
    format_section_begin(plan, name);
    const start: u64 = here()
    const rva: u64 = start - pe_default_image_base32
    pe_reloc_emit_grouped_sorted(relocs);
    format_section_end(plan, name);
    pe_finalize_reloc_dir32(rva, start, pe_reloc_grouped_start, pe_reloc_grouped_end);
}

fn format_pe_reloc_section64(plan: map, name: string, relocs: list) {
    assert(format_section_purpose(plan, name) == format_fixups, "format PE relocation section has the wrong purpose");
    assert(len(relocs) > 0, "format PE relocation section requires at least one relocation");
    format_section_begin(plan, name);
    const start: u64 = here()
    const rva: u64 = start - pe_default_image_base64
    pe_reloc_emit_grouped_sorted(relocs);
    format_section_end(plan, name);
    pe_finalize_reloc_dir64(rva, start, pe_reloc_grouped_start, pe_reloc_grouped_end);
}

fn format_pe_reloc_section(plan: map, name: string, relocs: list) {
    const kind: u64 = map.get(plan, "kind")
    if kind == format_kind_pe32 {
        format_pe_reloc_section32(plan, name, relocs);
    }
    if kind == format_kind_pe64 {
        format_pe_reloc_section64(plan, name, relocs);
    }
    assert(kind == format_kind_pe32 || kind == format_kind_pe64, "format plan is not a PE image");
}

fn format_pe_checksum(plan: map) {
    const kind: u64 = map.get(plan, "kind")
    assert(kind == format_kind_pe32 || kind == format_kind_pe64, "format plan is not a PE image");

    const sections: list = map.get(plan, "sections")
    assert(len(sections) > 0, "PE checksum requires at least one section");

    pe_checksum_begin();
    for section in sections {
        const name: string = map.get(section, "name")
        pe_checksum_add_region(label_addr(format_pe_section_start_label(name)));
    }

    const last_section: map = list.get(sections, len(sections) - 1)
    const last_name: string = map.get(last_section, "name")
    pe_checksum_finish(label_addr(format_pe_section_start_label(last_name)));
}

fn format_segment_begin(plan: map, name: string) {
    const row: u64 = format_segment_row(plan, name)
    const kind: u64 = map.get(plan, "kind")
    const options: u64 = map.get(plan, "options")
    const segments: list = map.get(plan, "segments")
    const segment: map = list.get(segments, row)
    const attributes: u64 = map.get(segment, "attributes")
    const purpose: u64 = attributes & format_segment_purpose_mask
    const flags: u64 = format_elf_segment_flags(attributes)
    const file_offset: u64 = file_cursor_real()
    let image_base = 0
    if kind == format_kind_elf32 {
        image_base = elf_default_base32
    }
    if kind == format_kind_elf64 && options == format_elf_exec {
        image_base = elf_default_base64
    }
    const logical_offset: u64 = format_elf_next_load_logical_offset(image_base, file_offset, row)

    assert(purpose == format_load, "format.inc ELF layer supports LOAD segments only");

    if kind == format_kind_elf32 {
        region.begin(name, elf_default_base32 + logical_offset, file_offset);
        format_elf_finalize_load32(row, here(), flags);
    }
    if kind == format_kind_elf64 {
        const imports: list = map.get(plan, "imports")
        if options == format_elf_exec {
            region.begin(name, elf_default_base64 + logical_offset, file_offset);
        }
        if options == format_elf_pie {
            region.begin(name, logical_offset, file_offset);
        }
        if len(imports) > 0 && row == 0 {
            format_elfexe_finalize_first_load64(here(), flags);
        }
        if len(imports) == 0 || row > 0 {
            format_elf_finalize_load64(row, here(), flags);
        }
    }
    if kind == format_kind_elfso64 {
        region.begin(name, logical_offset, file_offset);
        label.define(format_elfso_segment_start_label(name));
        if row == 0 {
            format_elfso_finalize_first_load_region(here(), flags);
        }
        if row > 0 {
            format_elfso_finalize_load_region(row, here(), flags);
        }
    }
    assert(
        kind == format_kind_elf32 ||
        kind == format_kind_elf64 ||
        kind == format_kind_elfso64,
        "format plan is not an ELF executable or shared object"
    );
}

fn format_segment_end(plan: map, name: string) {
    const row: u64 = format_segment_row(plan, name)
    const kind: u64 = map.get(plan, "kind")
    const options: u64 = map.get(plan, "options")
    const segments: list = map.get(plan, "segments")
    const segment: map = list.get(segments, row)
    const attributes: u64 = map.get(segment, "attributes")
    const purpose: u64 = attributes & format_segment_purpose_mask

    assert(purpose == format_load, "format.inc ELF layer supports LOAD segments only");

    if kind == format_kind_elf32 {
        region.file_align(1);
    }
    if kind == format_kind_elf64 && options == format_elf_exec {
        region.file_align(1);
    }
    if kind == format_kind_elf64 && options == format_elf_pie {
        region.file_align(1);
    }
    if kind == format_kind_elfso64 {
        label.define(format_elfso_segment_end_label(name));
        region.file_align(1);
    }
    assert(
        kind == format_kind_elf32 ||
        kind == format_kind_elf64 ||
        kind == format_kind_elfso64,
        "format plan is not an ELF executable or shared object"
    );
}

fn format_pe_finalize_section32_row(row: u64, start: u64, chars: u64, purpose: u64) {
    defer {
        let logical_size = region_logical_size(start)
        let file_size = region_file_size(start)
        let rva = start - pe_default_image_base32
        let row_foa = pe_row32_foa(row)
        let raw_ptr = 0
        if file_size > 0 {
            raw_ptr = region_file_offset(start)
        }

        store.u32(region_base() + row_foa + pe_sec_virtual_size_foa, logical_size);
        store.u32(region_base() + row_foa + pe_sec_rva_foa, rva);
        store.u32(region_base() + row_foa + pe_sec_raw_size_foa, file_size);
        store.u32(region_base() + row_foa + pe_sec_raw_ptr_foa, raw_ptr);
        store.u32(region_base() + row_foa + pe_sec_chars_foa, chars);

        if purpose == format_code {
            store.u32(
                region_base() + pe_opt_size_of_code_foa,
                load.u32(region_base() + pe_opt_size_of_code_foa) + file_size
            );
            let current_code_base = load.u32(region_base() + pe_opt_base_of_code_foa)
            if current_code_base == 0 || rva < current_code_base {
                store.u32(region_base() + pe_opt_base_of_code_foa, rva);
            }
        }
        if purpose == format_uninitialized_data {
            store.u32(
                region_base() + pe_opt_size_of_uninit_data_foa,
                load.u32(region_base() + pe_opt_size_of_uninit_data_foa) + logical_size
            );
            let current_data_base = load.u32(region_base() + pe_opt32_base_of_data_foa)
            if current_data_base == 0 || rva < current_data_base {
                store.u32(region_base() + pe_opt32_base_of_data_foa, rva);
            }
        }
        if purpose != format_code && purpose != format_uninitialized_data {
            store.u32(
                region_base() + pe_opt_size_of_init_data_foa,
                load.u32(region_base() + pe_opt_size_of_init_data_foa) + file_size
            );
            let current_data_base = load.u32(region_base() + pe_opt32_base_of_data_foa)
            if current_data_base == 0 || rva < current_data_base {
                store.u32(region_base() + pe_opt32_base_of_data_foa, rva);
            }
        }

        let section_image_end = align_up(rva + logical_size, pe_default_section_align)
        if section_image_end > load.u32(region_base() + pe_opt_size_of_image_foa) {
            store.u32(region_base() + pe_opt_size_of_image_foa, section_image_end);
        }
    }
}

fn format_pe_finalize_section64_row(row: u64, start: u64, chars: u64, purpose: u64) {
    defer {
        let logical_size = region_logical_size(start)
        let file_size = region_file_size(start)
        let rva = start - pe_default_image_base64
        let row_foa = pe_row_foa(row)
        let raw_ptr = 0
        if file_size > 0 {
            raw_ptr = region_file_offset(start)
        }

        store.u32(region_base() + row_foa + pe_sec_virtual_size_foa, logical_size);
        store.u32(region_base() + row_foa + pe_sec_rva_foa, rva);
        store.u32(region_base() + row_foa + pe_sec_raw_size_foa, file_size);
        store.u32(region_base() + row_foa + pe_sec_raw_ptr_foa, raw_ptr);
        store.u32(region_base() + row_foa + pe_sec_chars_foa, chars);

        if purpose == format_code {
            store.u32(
                region_base() + pe_opt_size_of_code_foa,
                load.u32(region_base() + pe_opt_size_of_code_foa) + file_size
            );
            let current_code_base = load.u32(region_base() + pe_opt_base_of_code_foa)
            if current_code_base == 0 || rva < current_code_base {
                store.u32(region_base() + pe_opt_base_of_code_foa, rva);
            }
        }
        if purpose == format_uninitialized_data {
            store.u32(
                region_base() + pe_opt_size_of_uninit_data_foa,
                load.u32(region_base() + pe_opt_size_of_uninit_data_foa) + logical_size
            );
        }
        if purpose != format_code && purpose != format_uninitialized_data {
            store.u32(
                region_base() + pe_opt_size_of_init_data_foa,
                load.u32(region_base() + pe_opt_size_of_init_data_foa) + file_size
            );
        }

        let section_image_end = align_up(rva + logical_size, pe_default_section_align)
        if section_image_end > load.u32(region_base() + pe_opt_size_of_image_foa) {
            store.u32(region_base() + pe_opt_size_of_image_foa, section_image_end);
        }
    }
}

fn format_pe_finalize_entry32(entry_address: u64) {
    defer {
        store.u32(region_base() + pe_opt_entry_rva_foa, entry_address - pe_default_image_base32);
    }
}

fn format_pe_finalize_entry64(entry_address: u64) {
    defer {
        store.u32(region_base() + pe_opt_entry_rva_foa, entry_address - pe_default_image_base64);
    }
}

fn format_elf_finalize_load32(row: u64, start: u64, flags: u64) {
    defer {
        let filesz = region_file_size(start)
        let memsz = region_logical_size(start)
        if memsz < filesz {
            memsz = filesz
        }
        let offset = region_file_offset(start)

        store.u32(region_base() + elf32_phdr_foa(row) + elf32_phdr_type_foa, elf_pt_load);
        store.u32(region_base() + elf32_phdr_foa(row) + elf32_phdr_offset_foa, offset);
        store.u32(region_base() + elf32_phdr_foa(row) + elf32_phdr_vaddr_foa, start);
        store.u32(region_base() + elf32_phdr_foa(row) + elf32_phdr_paddr_foa, start);
        store.u32(region_base() + elf32_phdr_foa(row) + elf32_phdr_filesz_foa, filesz);
        store.u32(region_base() + elf32_phdr_foa(row) + elf32_phdr_memsz_foa, memsz);
        store.u32(region_base() + elf32_phdr_foa(row) + elf32_phdr_flags_foa, flags);
        store.u32(region_base() + elf32_phdr_foa(row) + elf32_phdr_align_foa, elf_default_page_align);
        assert(start % elf_default_page_align == offset % elf_default_page_align, "ELF LOAD virtual and file offsets are not page congruent");
    }
}

fn format_elf_finalize_load64(row: u64, start: u64, flags: u64) {
    defer {
        let filesz = region_file_size(start)
        let memsz = region_logical_size(start)
        if memsz < filesz {
            memsz = filesz
        }
        let offset = region_file_offset(start)

        store.u32(region_base() + elf64_phdr_foa(row) + elf64_phdr_type_foa, elf_pt_load);
        store.u32(region_base() + elf64_phdr_foa(row) + elf64_phdr_flags_foa, flags);
        store.u64(region_base() + elf64_phdr_foa(row) + elf64_phdr_offset_foa, offset);
        store.u64(region_base() + elf64_phdr_foa(row) + elf64_phdr_vaddr_foa, start);
        store.u64(region_base() + elf64_phdr_foa(row) + elf64_phdr_paddr_foa, start);
        store.u64(region_base() + elf64_phdr_foa(row) + elf64_phdr_filesz_foa, filesz);
        store.u64(region_base() + elf64_phdr_foa(row) + elf64_phdr_memsz_foa, memsz);
        store.u64(region_base() + elf64_phdr_foa(row) + elf64_phdr_align_foa, elf_default_page_align);
        assert(start % elf_default_page_align == offset % elf_default_page_align, "ELF LOAD virtual and file offsets are not page congruent");
    }
}

fn format_elfexe_finalize_first_load64(start: u64, flags: u64) {
    defer {
        let filesz = region_file_offset(start) + region_file_size(start)
        let memsz = region_file_offset(start) + region_logical_size(start)
        if memsz < filesz {
            memsz = filesz
        }

        store.u32(region_base() + elf64_phdr_foa(0) + elf64_phdr_type_foa, elf_pt_load);
        store.u32(region_base() + elf64_phdr_foa(0) + elf64_phdr_flags_foa, flags);
        store.u64(region_base() + elf64_phdr_foa(0) + elf64_phdr_offset_foa, 0);
        store.u64(region_base() + elf64_phdr_foa(0) + elf64_phdr_vaddr_foa, elf_default_base64);
        store.u64(region_base() + elf64_phdr_foa(0) + elf64_phdr_paddr_foa, elf_default_base64);
        store.u64(region_base() + elf64_phdr_foa(0) + elf64_phdr_filesz_foa, filesz);
        store.u64(region_base() + elf64_phdr_foa(0) + elf64_phdr_memsz_foa, memsz);
        store.u64(region_base() + elf64_phdr_foa(0) + elf64_phdr_align_foa, elf_default_page_align);
    }
}

fn format_elf_finalize_entry32(entry_address: u64) {
    defer {
        store.u32(region_base() + elf32_entry_foa, entry_address);
    }
}

fn format_elf_finalize_entry64(entry_address: u64) {
    defer {
        store.u64(region_base() + elf64_entry_foa, entry_address);
    }
}

fn format_coff_reloc_count_for_section(relocs: list, section_name: string) -> u64 {
    let count = 0
    for reloc in relocs {
        if map.get(reloc, "section") == section_name {
            count = count + 1
        }
    }
    return count;
}

fn format_coff_finalize_reloc_row(row: u64, reloc_ptr: u64, reloc_count: u64) {
    defer {
        store.u32(coff_sections + row * coff_section_header_size + coff_sec_reloc_ptr_foa, reloc_ptr);
        store.u16(coff_sections + row * coff_section_header_size + coff_sec_reloc_count_foa, reloc_count);
    }
}

fn format_coff_finalize_symbol_header(symbol_table_foa: u64, symbol_count: u64) {
    defer {
        store.u32(coff_file + 8, symbol_table_foa);
        store.u32(coff_file + 12, symbol_count);
    }
}

fn format_coff_emit_symbol(plan: map, symbol: map) {
    const name: string = map.get(symbol, "name")
    const symbol_kind: u64 = map.get(symbol, "kind")
    const sym_type: u64 = map.get(symbol, "type")
    let value = 0
    let section_number = 0
    let storage_class = coff_sym_class_external

    if symbol_kind == format_coff_symbol_public {
        value = map.get(symbol, "value")
        section_number = format_section_row(plan, map.get(symbol, "section")) + 1
    }
    assert(
        symbol_kind == format_coff_symbol_public ||
        symbol_kind == format_coff_symbol_extern,
        "unknown COFF format symbol kind"
    );

    db(name);
    pad(8 - len(name), 0);
    emit.u32(value);
    emit.u16(section_number);
    emit.u16(sym_type);
    emit.u8(storage_class);
    emit.u8(0);
}

fn format_coff_finish_tables(plan: map) {
    const sections: list = map.get(plan, "sections")
    const symbols: list = map.get(plan, "symbols")
    const relocs: list = map.get(plan, "relocs")
    assert(len(symbols) > 0, "COFF format API requires format_coff_tables_mut before format_finish");

    region.begin(".coff.tables", file_cursor_potential(), file_cursor_real());
    for row in range(0, len(sections)) {
        const section: map = list.get(sections, row)
        const section_name: string = map.get(section, "name")
        const reloc_count: u64 = format_coff_reloc_count_for_section(relocs, section_name)
        if reloc_count > 0 {
            const reloc_ptr: u64 = file_cursor_real()
            for reloc in relocs {
                if map.get(reloc, "section") == section_name {
                    const symbol_index: u64 = format_coff_symbol_index(symbols, map.get(reloc, "symbol"))
                    emit.struct(CoffRelocation {
                        virtual_address: map.get(reloc, "offset"),
                        symbol_index: symbol_index,
                        reloc_type: map.get(reloc, "type"),
                    });
                }
            }
            format_coff_finalize_reloc_row(row, reloc_ptr, reloc_count);
        }
    }

    align(4);
    const symbol_table_foa: u64 = file_cursor_real()
    format_coff_finalize_symbol_header(symbol_table_foa, len(symbols));
    for symbol in symbols {
        format_coff_emit_symbol(plan, symbol);
    }
    emit.u32(coff_string_table_min_size);
}

fn format_string_table_offset(values: list, index: u64) -> u64 {
    assert(index < len(values), "format string table index is out of range");
    let offset = 1
    for i in range(0, index) {
        offset = offset + len(list.get(values, i)) + 1
    }
    return offset;
}

fn format_emit_string_table(values: list) {
    db(0);
    for value in values {
        db(value, 0);
    }
}

fn format_elfobj_reloc_count_for_section(relocs: list, section_name: string) -> u64 {
    let count = 0
    for reloc in relocs {
        if map.get(reloc, "section") == section_name {
            count = count + 1
        }
    }
    return count;
}

fn format_elfobj_reloc_section_name(kind: u64, section_name: string) -> string {
    if kind == format_kind_elfobj32 {
        return sym.join(".rel", section_name);
    }
    assert(kind == format_kind_elfobj64, "invalid ELF object relocation section kind");
    return sym.join(".rela", section_name);
}

fn format_elfobj_finalize_rel32_addend(address: u64, addend: u64) {
    defer {
        store.u32(address, addend);
    }
}

fn format_elfobj_finalize_shdr32(row_foa: u64, start: u64, end: u64) {
    defer {
        store.u32(region_base() + row_foa + elfobj32_sh_offset_foa, region_file_offset(start));
        store.u32(region_base() + row_foa + elfobj32_sh_size_foa, end - start);
    }
}

fn format_elfobj_finalize_shdr64(row_foa: u64, start: u64, end: u64) {
    defer {
        store.u64(region_base() + row_foa + elfobj64_sh_offset_foa, region_file_offset(start));
        store.u64(region_base() + row_foa + elfobj64_sh_size_foa, end - start);
    }
}

fn format_elfobj_emit_user_symbol32(plan: map, symbol: map, name_offset: u64) {
    const symbol_kind: u64 = map.get(symbol, "kind")
    let section_index = elf_shn_undef
    let value = 0
    if symbol_kind == format_elfobj_symbol_public {
        section_index = format_section_row(plan, map.get(symbol, "section")) + 1
        value = map.get(symbol, "value")
    }
    assert(
        symbol_kind == format_elfobj_symbol_public ||
        symbol_kind == format_elfobj_symbol_extern,
        "unknown ELF object format symbol kind"
    );
    elfobj_sym32(
        name_offset,
        elfobj_st_info(elfobj_stb_global, map.get(symbol, "type")),
        section_index,
        value,
        map.get(symbol, "size")
    );
}

fn format_elfobj_emit_user_symbol64(plan: map, symbol: map, name_offset: u64) {
    const symbol_kind: u64 = map.get(symbol, "kind")
    let section_index = elf_shn_undef
    let value = 0
    if symbol_kind == format_elfobj_symbol_public {
        section_index = format_section_row(plan, map.get(symbol, "section")) + 1
        value = map.get(symbol, "value")
    }
    assert(
        symbol_kind == format_elfobj_symbol_public ||
        symbol_kind == format_elfobj_symbol_extern,
        "unknown ELF object format symbol kind"
    );
    elfobj_sym64(
        name_offset,
        elfobj_st_info(elfobj_stb_global, map.get(symbol, "type")),
        section_index,
        value,
        map.get(symbol, "size")
    );
}

fn format_elfobj_finish_tables(plan: map) {
    const kind: u64 = map.get(plan, "kind")
    const sections: list = map.get(plan, "sections")
    const symbols: list = map.get(plan, "symbols")
    const relocs: list = map.get(plan, "relocs")
    assert(len(symbols) > 0, "ELF object format API requires format_elfobj_tables_mut before format_finish");

    let table_alignment = 4
    if kind == format_kind_elfobj64 {
        table_alignment = 8
    }

    region.begin(".elfobj.tables", file_offset(), file_offset());

    let relocation_sections = list.new()
    for row in range(0, len(sections)) {
        const section: map = list.get(sections, row)
        const section_name: string = map.get(section, "name")
        const relocation_count: u64 = format_elfobj_reloc_count_for_section(relocs, section_name)
        if relocation_count > 0 {
            align(table_alignment);
            const relocation_foa: u64 = file_cursor_real()
            for reloc in relocs {
                if map.get(reloc, "section") == section_name {
                    const symbol_index: u64 = format_elfobj_symbol_index(plan, symbols, map.get(reloc, "symbol"))
                    if kind == format_kind_elfobj32 {
                        format_elfobj_finalize_rel32_addend(map.get(reloc, "address"), map.get(reloc, "addend"));
                        elfobj_rel32(map.get(reloc, "offset"), symbol_index, map.get(reloc, "type"));
                    }
                    if kind == format_kind_elfobj64 {
                        elfobj_rela64(map.get(reloc, "offset"), symbol_index, map.get(reloc, "type"), map.get(reloc, "addend"));
                    }
                }
            }
            const relocation_size: u64 = file_cursor_real() - relocation_foa
            let relocation = map.new()
            map.set_mut(relocation, "name", format_elfobj_reloc_section_name(kind, section_name));
            map.set_mut(relocation, "target_row", row);
            map.set_mut(relocation, "offset", relocation_foa);
            map.set_mut(relocation, "size", relocation_size);
            list.push_mut(relocation_sections, relocation);
        }
    }

    align(table_alignment);
    const symtab_foa: u64 = file_cursor_real()
    if kind == format_kind_elfobj32 {
        elfobj_sym32(0, 0, elf_shn_undef, 0, 0);
        for row in range(0, len(sections)) {
            elfobj_sym32(0, elfobj_st_info(elfobj_stb_local, elfobj_stt_section), row + 1, 0, 0);
        }
        for i in range(0, len(symbols)) {
            format_elfobj_emit_user_symbol32(plan, list.get(symbols, i), format_string_table_offset(format_elfobj_symbol_names(symbols), i));
        }
    }
    if kind == format_kind_elfobj64 {
        elfobj_sym64(0, 0, elf_shn_undef, 0, 0);
        for row in range(0, len(sections)) {
            elfobj_sym64(0, elfobj_st_info(elfobj_stb_local, elfobj_stt_section), row + 1, 0, 0);
        }
        for i in range(0, len(symbols)) {
            format_elfobj_emit_user_symbol64(plan, list.get(symbols, i), format_string_table_offset(format_elfobj_symbol_names(symbols), i));
        }
    }

    const strtab_foa: u64 = file_cursor_real()
    const symbol_names: list = format_elfobj_symbol_names(symbols)
    format_emit_string_table(symbol_names);

    let section_names = list.new()
    for section in sections {
        list.push_mut(section_names, map.get(section, "name"));
    }
    for relocation_section in relocation_sections {
        list.push_mut(section_names, map.get(relocation_section, "name"));
    }
    const symtab_name_index: u64 = len(section_names)
    list.push_mut(section_names, ".symtab");
    const strtab_name_index: u64 = len(section_names)
    list.push_mut(section_names, ".strtab");
    const shstrtab_name_index: u64 = len(section_names)
    list.push_mut(section_names, ".shstrtab");
    const stack_note_name_index: u64 = len(section_names)
    list.push_mut(section_names, ".note.GNU-stack");

    const shstrtab_foa: u64 = file_cursor_real()
    format_emit_string_table(section_names);

    align(table_alignment);
    const section_table_foa: u64 = file_cursor_real()
    const symtab_index: u64 = 1 + len(sections) + len(relocation_sections)
    const strtab_index: u64 = symtab_index + 1
    const shstrtab_index: u64 = strtab_index + 1
    const stack_note_index: u64 = shstrtab_index + 1
    const section_count: u64 = stack_note_index + 1

    if kind == format_kind_elfobj32 {
        elfobj_shdr32(0, elf_sht_null, 0, 0, 0, 0, 0, 0, 0);
        for row in range(0, len(sections)) {
            const section: map = list.get(sections, row)
            const section_name: string = map.get(section, "name")
            const attributes: u64 = map.get(section, "attributes")
            const row_foa: u64 = file_cursor_real()
            elfobj_shdr32(
                format_string_table_offset(section_names, row),
                format_elfobj_section_type(attributes),
                format_elfobj_section_flags(attributes),
                0,
                0,
                0,
                0,
                format_elfobj_section_alignment(kind, attributes),
                0
            );
            format_elfobj_finalize_shdr32(
                row_foa,
                label_addr(format_elfobj_section_start_label(section_name)),
                label_addr(format_elfobj_section_end_label(section_name))
            );
        }
        for i in range(0, len(relocation_sections)) {
            const relocation_section: map = list.get(relocation_sections, i)
            elfobj_shdr32(
                format_string_table_offset(section_names, len(sections) + i),
                elf_sht_rel,
                0,
                map.get(relocation_section, "offset"),
                map.get(relocation_section, "size"),
                symtab_index,
                map.get(relocation_section, "target_row") + 1,
                4,
                elfobj_rel32_size
            );
        }
        elfobj_shdr32(
            format_string_table_offset(section_names, symtab_name_index),
            elf_sht_symtab,
            0,
            symtab_foa,
            strtab_foa - symtab_foa,
            strtab_index,
            1 + len(sections),
            4,
            elfobj_sym32_size
        );
        elfobj_shdr32(
            format_string_table_offset(section_names, strtab_name_index),
            elf_sht_strtab,
            0,
            strtab_foa,
            shstrtab_foa - strtab_foa,
            0,
            0,
            1,
            0
        );
        elfobj_shdr32(
            format_string_table_offset(section_names, shstrtab_name_index),
            elf_sht_strtab,
            0,
            shstrtab_foa,
            section_table_foa - shstrtab_foa,
            0,
            0,
            1,
            0
        );
        elfobj_shdr32(
            format_string_table_offset(section_names, stack_note_name_index),
            elf_sht_progbits,
            0,
            0,
            0,
            0,
            0,
            1,
            0
        );
        elfobj_patch_header32(section_table_foa, section_count, shstrtab_index);
    }

    if kind == format_kind_elfobj64 {
        elfobj_shdr64(0, elf_sht_null, 0, 0, 0, 0, 0, 0, 0);
        for row in range(0, len(sections)) {
            const section: map = list.get(sections, row)
            const section_name: string = map.get(section, "name")
            const attributes: u64 = map.get(section, "attributes")
            const row_foa: u64 = file_cursor_real()
            elfobj_shdr64(
                format_string_table_offset(section_names, row),
                format_elfobj_section_type(attributes),
                format_elfobj_section_flags(attributes),
                0,
                0,
                0,
                0,
                format_elfobj_section_alignment(kind, attributes),
                0
            );
            format_elfobj_finalize_shdr64(
                row_foa,
                label_addr(format_elfobj_section_start_label(section_name)),
                label_addr(format_elfobj_section_end_label(section_name))
            );
        }
        for i in range(0, len(relocation_sections)) {
            const relocation_section: map = list.get(relocation_sections, i)
            elfobj_shdr64(
                format_string_table_offset(section_names, len(sections) + i),
                elf_sht_rela,
                0,
                map.get(relocation_section, "offset"),
                map.get(relocation_section, "size"),
                symtab_index,
                map.get(relocation_section, "target_row") + 1,
                8,
                elfobj_rela64_size
            );
        }
        elfobj_shdr64(
            format_string_table_offset(section_names, symtab_name_index),
            elf_sht_symtab,
            0,
            symtab_foa,
            strtab_foa - symtab_foa,
            strtab_index,
            1 + len(sections),
            8,
            elfobj_sym64_size
        );
        elfobj_shdr64(
            format_string_table_offset(section_names, strtab_name_index),
            elf_sht_strtab,
            0,
            strtab_foa,
            shstrtab_foa - strtab_foa,
            0,
            0,
            1,
            0
        );
        elfobj_shdr64(
            format_string_table_offset(section_names, shstrtab_name_index),
            elf_sht_strtab,
            0,
            shstrtab_foa,
            section_table_foa - shstrtab_foa,
            0,
            0,
            1,
            0
        );
        elfobj_shdr64(
            format_string_table_offset(section_names, stack_note_name_index),
            elf_sht_progbits,
            0,
            0,
            0,
            0,
            0,
            1,
            0
        );
        elfobj_patch_header64(section_table_foa, section_count, shstrtab_index);
    }
}

fn format_elfobj_symbol_names(symbols: list) -> list {
    let names = list.new()
    for symbol in symbols {
        list.push_mut(names, map.get(symbol, "name"));
    }
    return names;
}

fn format_string_table_size(values: list) -> u64 {
    let size = 1
    for value in values {
        size = size + len(value) + 1
    }
    return size;
}

fn format_elfso_exports64(plan: map, exports: list) -> list {
    let values = elf_export_new()
    for export0 in exports {
        const target: string = map.get(export0, "target")
        const name: string = map.get(export0, "name")
        const segment: string = map.get(export0, "segment")
        const size: u64 = map.get(export0, "size")
        const section_index: u64 = format_segment_row(plan, segment) + 1
        values = elf_export_use64_pairs(values, list.of(target, name), section_index, size)
    }
    return values;
}

fn format_elfso_section_names(plan: map, has_imports: bool) -> list {
    let names = list.new()
    for segment in map.get(plan, "segments") {
        list.push_mut(names, map.get(segment, "name"));
    }
    if has_imports {
        list.push_mut(names, ".plt");
        list.push_mut(names, ".got.plt");
    }
    list.push_mut(names, ".dynsym");
    list.push_mut(names, ".dynstr");
    list.push_mut(names, ".hash");
    if has_imports {
        list.push_mut(names, ".rela.plt");
    }
    list.push_mut(names, ".dynamic");
    list.push_mut(names, ".shstrtab");
    return names;
}

fn format_elfso_section_index(section_names: list, name: string) -> u64 {
    for i in range(0, len(section_names)) {
        if list.get(section_names, i) == name {
            return i + 1;
        }
    }
    assert(false, "ELF shared-object internal section is missing");
    return 0;
}

fn format_elfso_emit_dynsym64(imports: list, exports: list, export_name_start: u64) {
    elfso_import_emit_dynsym64(imports, 1);
    for i in range(0, len(exports)) {
        const export0: map = list.get(exports, i)
        elfso_sym64(
            export_name_start + elf_export_name_offset(exports, i),
            elfso_st_info(elf_stb_global, elf_stt_func),
            map.get(export0, "section"),
            label_addr(map.get(export0, "target")),
            map.get(export0, "size")
        );
    }
}

fn format_elfso_emit_dynstr64(imports: list, exports: list, soname: string) {
    db(0);
    for import0 in imports {
        db(map.get(import0, "name"), 0);
    }
    for export0 in exports {
        db(map.get(export0, "name"), 0);
    }
    db(soname, 0);
    for library in elfso_import_libraries(imports) {
        db(library, 0);
    }
}

fn format_elfso_dynstr_size(imports: list, exports: list, soname: string) -> u64 {
    return 1 + elfso_import_names_size(imports) + elf_export_names_size(exports) + len(soname) + 1 + elfso_import_libraries_size(elfso_import_libraries(imports));
}

fn format_elfso_emit_hash(symbol_count: u64) {
    assert(symbol_count > 0, "ELF shared-object hash requires the null symbol");
    dd(1);
    dd(symbol_count);
    if symbol_count > 1 {
        dd(1);
    }
    if symbol_count == 1 {
        dd(0);
    }
    for i in range(0, symbol_count) {
        let next = 0
        if i > 0 && i + 1 < symbol_count {
            next = i + 1
        }
        dd(next);
    }
}

fn format_elfso_hash_size(symbol_count: u64) -> u64 {
    return (3 + symbol_count) * 4;
}

fn format_elfso_dynamic_size(imports: list) -> u64 {
    if len(imports) == 0 {
        return 7 * elfso_dyn64_size;
    }
    return (11 + len(elfso_import_libraries(imports))) * elfso_dyn64_size;
}

fn format_elfso_emit_dynamic64(imports: list, dynstr_foa: u64, dynstr_size: u64, dynsym_foa: u64, hash_foa: u64, gotplt_foa: u64, rela_plt_foa: u64, rela_plt_size: u64, soname_offset: u64, first_needed_offset: u64) {
    if len(imports) == 0 {
        elf_export_emit_dynamic64(dynstr_foa, dynstr_size, dynsym_foa, hash_foa, soname_offset);
    }
    if len(imports) > 0 {
        elfso_dyn64(elf_dt_hash, hash_foa);
        elfso_dyn64(elf_dt_strtab, dynstr_foa);
        elfso_dyn64(elf_dt_strsz, dynstr_size);
        elfso_dyn64(elf_dt_symtab, dynsym_foa);
        elfso_dyn64(elf_dt_syment, elfso_sym64_size);
        elfso_dyn64(elf_dt_pltgot, gotplt_foa);
        elfso_dyn64(elf_dt_pltrelsz, rela_plt_size);
        elfso_dyn64(elf_dt_pltrel, elf_dt_rela);
        elfso_dyn64(elf_dt_jmprel, rela_plt_foa);
        elfso_dyn64(elf_dt_soname, soname_offset);
        const libraries: list = elfso_import_libraries(imports)
        for i in range(0, len(libraries)) {
            elfso_dyn64(elf_dt_needed, first_needed_offset + elfso_import_library_offset(libraries, i));
        }
        elfso_dyn64(elf_dt_null, 0);
    }
}

fn format_elfso_emit_user_section_headers(plan: map, section_names: list) {
    const segments: list = map.get(plan, "segments")
    for row in range(0, len(segments)) {
        const segment: map = list.get(segments, row)
        const name: string = map.get(segment, "name")
        const attributes: u64 = map.get(segment, "attributes")
        const row_address: u64 = here()
        elfso_shdr64(
            format_string_table_offset(section_names, row),
            elf_sht_progbits,
            format_elfso_section_flags(attributes),
            0,
            0,
            0,
            0,
            0,
            format_elfso_section_alignment(attributes),
            0
        );
        format_elfso_finalize_section_region(
            row_address,
            label_addr(format_elfso_segment_start_label(name)),
            label_addr(format_elfso_segment_end_label(name))
        );
    }
}

fn format_elfso_finish_tables(plan: map) {
    const segments: list = map.get(plan, "segments")
    const exports: list = format_elfso_exports64(plan, map.get(plan, "exports"))
    const imports: list = map.get(plan, "imports")
    const soname: string = map.get(plan, "soname")
    const has_imports: bool = len(imports) > 0
    const section_names: list = format_elfso_section_names(plan, has_imports)
    const section_count: u64 = len(section_names) + 1
    const shstrndx: u64 = format_elfso_section_index(section_names, ".shstrtab")
    const dynsym_index: u64 = format_elfso_section_index(section_names, ".dynsym")
    const dynstr_index: u64 = format_elfso_section_index(section_names, ".dynstr")

    const import_count: u64 = len(imports)
    const export_count: u64 = len(exports)
    const symbol_count: u64 = 1 + import_count + export_count
    const first_import_symbol: u64 = 1
    const export_name_start: u64 = 1 + elfso_import_names_size(imports)
    const soname_offset: u64 = export_name_start + elf_export_names_size(exports)
    const first_needed_offset: u64 = soname_offset + len(soname) + 1

    let plt_foa = 0
    let plt_size = 0
    let plt_vaddr = 0
    let metadata_foa = elfso_align_up(file_cursor_real(), 16)
    let metadata_vaddr = format_elf_next_load_logical_offset(0, metadata_foa, 1)
    if has_imports {
        plt_foa = elfso_align_up(file_cursor_real(), 16)
        plt_size = elfso_import_plt_size(imports)
        metadata_foa = elfso_align_up(plt_foa + plt_size, 8)
        plt_vaddr = format_elf_next_load_logical_offset(0, plt_foa, 1)
        metadata_vaddr = format_elf_logical_offset(metadata_foa, plt_vaddr + plt_size)
        const plt_last_page: u64 = (plt_vaddr + plt_size - 1) / elf_default_page_align
        if metadata_vaddr / elf_default_page_align <= plt_last_page {
            metadata_vaddr = metadata_vaddr + elf_default_page_align
        }
    }

    let gotplt_foa = 0
    let gotplt_size = 0
    let dynsym_foa = elfso_align_up(metadata_foa, 8)
    if has_imports {
        gotplt_foa = metadata_foa
        gotplt_size = elfso_import_gotplt_size(imports)
        dynsym_foa = elfso_align_up(gotplt_foa + gotplt_size, 8)
    }
    const dynsym_size: u64 = symbol_count * elfso_sym64_size
    const dynstr_foa: u64 = dynsym_foa + dynsym_size
    const dynstr_size: u64 = format_elfso_dynstr_size(imports, exports, soname)
    const hash_foa: u64 = elfso_align_up(dynstr_foa + dynstr_size, 4)
    const hash_size: u64 = format_elfso_hash_size(symbol_count)
    let rela_plt_foa = 0
    let rela_plt_size = 0
    let dynamic_foa = elfso_align_up(hash_foa + hash_size, 8)
    if has_imports {
        rela_plt_foa = elfso_align_up(hash_foa + hash_size, 8)
        rela_plt_size = elfso_import_rela_plt_size(imports)
        dynamic_foa = elfso_align_up(rela_plt_foa + rela_plt_size, 8)
    }
    const dynamic_size: u64 = format_elfso_dynamic_size(imports)
    const shstrtab_foa: u64 = dynamic_foa + dynamic_size
    const shstrtab_size: u64 = format_string_table_size(section_names)
    const section_table_foa: u64 = elfso_align_up(shstrtab_foa + shstrtab_size, 8)
    let gotplt_vaddr = 0
    let rela_plt_vaddr = 0
    if has_imports {
        gotplt_vaddr = metadata_vaddr + (gotplt_foa - metadata_foa)
        rela_plt_vaddr = metadata_vaddr + (rela_plt_foa - metadata_foa)
    }
    const dynsym_vaddr: u64 = metadata_vaddr + (dynsym_foa - metadata_foa)
    const dynstr_vaddr: u64 = metadata_vaddr + (dynstr_foa - metadata_foa)
    const hash_vaddr: u64 = metadata_vaddr + (hash_foa - metadata_foa)
    const dynamic_vaddr: u64 = metadata_vaddr + (dynamic_foa - metadata_foa)

    let plt_start = 0
    if has_imports {
        region.begin(".elfso.plt", plt_vaddr, plt_foa);
        plt_start = here()
        assert(file_cursor_real() == plt_foa, "ELF shared-object PLT layout mismatch");
        elfso_import_emit_plt64(imports, plt_vaddr, gotplt_vaddr);
        region.file_align(1);
    }

    region.begin(".elfso.metadata", metadata_vaddr, metadata_foa);
    const metadata_start: u64 = here()
    if has_imports {
        align(8);
        assert(file_cursor_real() == gotplt_foa, "ELF shared-object GOTPLT layout mismatch");
        elfso_import_emit_gotplt64(imports, dynamic_vaddr, plt_vaddr);
    }

    align(8);
    assert(file_cursor_real() == dynsym_foa, "ELF shared-object DYNSYM layout mismatch");
    format_elfso_emit_dynsym64(imports, exports, export_name_start);

    assert(file_cursor_real() == dynstr_foa, "ELF shared-object DYNSTR layout mismatch");
    format_elfso_emit_dynstr64(imports, exports, soname);

    align(4);
    assert(file_cursor_real() == hash_foa, "ELF shared-object HASH layout mismatch");
    format_elfso_emit_hash(symbol_count);

    if has_imports {
        align(8);
        assert(file_cursor_real() == rela_plt_foa, "ELF shared-object RELA.PLT layout mismatch");
        elfso_import_emit_rela_plt64(imports, first_import_symbol);
    }

    align(8);
    assert(file_cursor_real() == dynamic_foa, "ELF shared-object DYNAMIC layout mismatch");
    format_elfso_emit_dynamic64(
        imports,
        dynstr_vaddr,
        dynstr_size,
        dynsym_vaddr,
        hash_vaddr,
        gotplt_vaddr,
        rela_plt_vaddr,
        rela_plt_size,
        soname_offset,
        first_needed_offset
    );

    assert(file_cursor_real() == shstrtab_foa, "ELF shared-object SHSTRTAB layout mismatch");
    format_emit_string_table(section_names);

    align(8);
    assert(file_cursor_real() == section_table_foa, "ELF shared-object section-table layout mismatch");
    elfso_shdr64(0, elf_sht_null, 0, 0, 0, 0, 0, 0, 0, 0);
    format_elfso_emit_user_section_headers(plan, section_names);

    if has_imports {
        const plt_index: u64 = format_elfso_section_index(section_names, ".plt")
        const gotplt_index: u64 = format_elfso_section_index(section_names, ".got.plt")
        elfso_shdr64(
            format_string_table_offset(section_names, plt_index - 1),
            elf_sht_progbits,
            elf_shf_alloc | elf_shf_execinstr,
            plt_vaddr,
            plt_foa,
            plt_size,
            0,
            0,
            16,
            elfso_import_plt_entry_size
        );
        elfso_shdr64(
            format_string_table_offset(section_names, gotplt_index - 1),
            elf_sht_progbits,
            elf_shf_alloc | elf_shf_write,
            gotplt_vaddr,
            gotplt_foa,
            gotplt_size,
            0,
            0,
            8,
            elfso_import_gotplt_entry_size
        );
    }

    elfso_shdr64(
        format_string_table_offset(section_names, dynsym_index - 1),
        elf_sht_dynsym,
        elf_shf_alloc,
        dynsym_vaddr,
        dynsym_foa,
        dynsym_size,
        dynstr_index,
        1,
        8,
        elfso_sym64_size
    );
    elfso_shdr64(
        format_string_table_offset(section_names, dynstr_index - 1),
        elf_sht_strtab,
        elf_shf_alloc,
        dynstr_vaddr,
        dynstr_foa,
        dynstr_size,
        0,
        0,
        1,
        0
    );
    const hash_index: u64 = format_elfso_section_index(section_names, ".hash")
    elfso_shdr64(
        format_string_table_offset(section_names, hash_index - 1),
        elf_sht_hash,
        elf_shf_alloc,
        hash_vaddr,
        hash_foa,
        hash_size,
        dynsym_index,
        0,
        4,
        4
    );
    if has_imports {
        const rela_plt_index: u64 = format_elfso_section_index(section_names, ".rela.plt")
        elfso_shdr64(
            format_string_table_offset(section_names, rela_plt_index - 1),
            elf_sht_rela,
            elf_shf_alloc,
            rela_plt_vaddr,
            rela_plt_foa,
            rela_plt_size,
            dynsym_index,
            0,
            8,
            elfso_import_rela64_size
        );
    }
    const dynamic_index: u64 = format_elfso_section_index(section_names, ".dynamic")
    elfso_shdr64(
        format_string_table_offset(section_names, dynamic_index - 1),
        elf_sht_dynamic,
        elf_shf_alloc | elf_shf_write,
        dynamic_vaddr,
        dynamic_foa,
        dynamic_size,
        dynstr_index,
        0,
        8,
        elfso_dyn64_size
    );
    elfso_shdr64(
        format_string_table_offset(section_names, shstrndx - 1),
        elf_sht_strtab,
        0,
        0,
        shstrtab_foa,
        shstrtab_size,
        0,
        0,
        1,
        0
    );

    let metadata_row = len(segments)
    if has_imports {
        const plt_row: u64 = len(segments)
        metadata_row = plt_row + 1
        format_elfso_finalize_load_region(plt_row, plt_start, elf_pf_r | elf_pf_x);
    }
    format_elfso_finalize_load_region(metadata_row, metadata_start, elf_pf_r | elf_pf_w);
    elfso_finalize_phdr64(
        metadata_row + 1,
        elf_pt_dynamic,
        elf_pf_r | elf_pf_w,
        dynamic_foa,
        dynamic_vaddr,
        dynamic_size,
        dynamic_size,
        8
    );
    format_elfso_finalize_header64(section_table_foa, section_count, shstrndx);
}

fn format_elfexe_finish_tables(plan: map) {
    const segments: list = map.get(plan, "segments")
    const imports: list = map.get(plan, "imports")
    assert(len(imports) > 0, "ELF executable import table is empty");

    const first_import_symbol: u64 = 1
    const dynstr_name_start: u64 = 1
    const dynstr_needed_start: u64 = dynstr_name_start + elfexe_import_names_size(imports)

    const plt_foa: u64 = elfexe_align_up(file_cursor_real(), 16)
    const plt_size: u64 = elfexe_import_plt_size(imports)
    const metadata_foa: u64 = elfexe_align_up(plt_foa + plt_size, 8)

    const plt_logical_offset: u64 = format_elf_next_load_logical_offset(elf_default_base64, plt_foa, 1)
    const plt_vaddr: u64 = elf_default_base64 + plt_logical_offset
    let metadata_logical_offset = format_elf_logical_offset(metadata_foa, plt_logical_offset + plt_size)
    const plt_last_page: u64 = (plt_logical_offset + plt_size - 1) / elf_default_page_align
    if metadata_logical_offset / elf_default_page_align <= plt_last_page {
        metadata_logical_offset = metadata_logical_offset + elf_default_page_align
    }
    const metadata_vaddr: u64 = elf_default_base64 + metadata_logical_offset

    const gotplt_foa: u64 = metadata_foa
    const gotplt_size: u64 = elfexe_import_gotplt_size(imports)
    const interp_foa: u64 = gotplt_foa + gotplt_size
    const interp_size: u64 = len(elfexe_import_default_interp64) + 1
    const dynsym_foa: u64 = elfexe_align_up(interp_foa + interp_size, 8)
    const dynsym_size: u64 = (1 + len(imports)) * elfexe_import_sym64_size
    const dynstr_foa: u64 = dynsym_foa + dynsym_size
    const dynstr_size: u64 = elfexe_import_dynstr_size(imports)
    const hash_foa: u64 = elfexe_align_up(dynstr_foa + dynstr_size, 4)
    const hash_size: u64 = elfexe_import_hash_size(imports)
    const rela_plt_foa: u64 = elfexe_align_up(hash_foa + hash_size, 8)
    const rela_plt_size: u64 = elfexe_import_rela_plt_size(imports)
    const dynamic_foa: u64 = elfexe_align_up(rela_plt_foa + rela_plt_size, 8)
    const dynamic_size: u64 = elfexe_import_dynamic_plt_size(imports)

    const gotplt_vaddr: u64 = metadata_vaddr + (gotplt_foa - metadata_foa)
    const interp_vaddr: u64 = metadata_vaddr + (interp_foa - metadata_foa)
    const dynsym_vaddr: u64 = metadata_vaddr + (dynsym_foa - metadata_foa)
    const dynstr_vaddr: u64 = metadata_vaddr + (dynstr_foa - metadata_foa)
    const hash_vaddr: u64 = metadata_vaddr + (hash_foa - metadata_foa)
    const rela_plt_vaddr: u64 = metadata_vaddr + (rela_plt_foa - metadata_foa)
    const dynamic_vaddr: u64 = metadata_vaddr + (dynamic_foa - metadata_foa)

    region.begin(".elfexe.plt", plt_vaddr, plt_foa);
    const plt_start: u64 = here()
    assert(file_cursor_real() == plt_foa, "ELF executable PLT layout mismatch");
    elfexe_import_emit_plt64(imports, plt_vaddr, gotplt_vaddr);
    region.file_align(1);

    region.begin(".elfexe.imports", metadata_vaddr, metadata_foa);
    const metadata_start: u64 = here()
    assert(file_cursor_real() == gotplt_foa, "ELF executable GOTPLT layout mismatch");
    elfexe_import_emit_gotplt64(imports, dynamic_vaddr, plt_vaddr);

    assert(file_cursor_real() == interp_foa, "ELF executable INTERP layout mismatch");
    db(elfexe_import_default_interp64, 0);

    align(8);
    assert(file_cursor_real() == dynsym_foa, "ELF executable DYNSYM layout mismatch");
    elfexe_import_emit_dynsym64(imports, dynstr_name_start);

    assert(file_cursor_real() == dynstr_foa, "ELF executable DYNSTR layout mismatch");
    elfexe_import_emit_dynstr64(imports);

    align(4);
    assert(file_cursor_real() == hash_foa, "ELF executable HASH layout mismatch");
    elfexe_import_hash(imports);

    align(8);
    assert(file_cursor_real() == rela_plt_foa, "ELF executable RELA.PLT layout mismatch");
    elfexe_import_emit_rela_plt64(imports, first_import_symbol);

    align(8);
    assert(file_cursor_real() == dynamic_foa, "ELF executable DYNAMIC layout mismatch");
    elfexe_import_emit_dynamic64_plt(imports, dynstr_vaddr, dynstr_size, dynsym_vaddr, hash_vaddr, gotplt_vaddr, rela_plt_vaddr, rela_plt_size, dynstr_needed_start);

    const plt_row: u64 = len(segments)
    const metadata_row: u64 = plt_row + 1
    format_elf_finalize_load64(plt_row, plt_start, elf_pf_r | elf_pf_x);
    format_elf_finalize_load64(metadata_row, metadata_start, elf_pf_r | elf_pf_w);
    elfexe_finalize_phdr64(metadata_row + 1, elf_pt_interp, elf_pf_r, interp_foa, interp_vaddr, interp_size, interp_size, 1);
    elfexe_finalize_phdr64(metadata_row + 2, elf_pt_dynamic, elf_pf_r | elf_pf_w, dynamic_foa, dynamic_vaddr, dynamic_size, dynamic_size, 8);
}

fn format_finish(plan: map) {
    const kind: u64 = map.get(plan, "kind")
    const entry_address: u64 = map.get(plan, "entry")

    if kind == format_kind_pe32 {
        assert(entry_address != 0, "PE executable or DLL requires an entry address");
        format_pe_finalize_entry32(entry_address);
    }
    if kind == format_kind_pe64 {
        assert(entry_address != 0, "PE executable or DLL requires an entry address");
        format_pe_finalize_entry64(entry_address);
    }
    if kind == format_kind_elf32 {
        assert(entry_address != 0, "ELF executable requires an entry address");
        format_elf_finalize_entry32(entry_address);
    }
    if kind == format_kind_elf64 {
        assert(entry_address != 0, "ELF executable requires an entry address");
        const imports: list = map.get(plan, "imports")
        if len(imports) > 0 {
            format_elfexe_finish_tables(plan);
        }
        format_elf_finalize_entry64(entry_address);
    }
    if kind == format_kind_coff32 || kind == format_kind_coff64 {
        format_coff_finish_tables(plan);
    }
    if kind == format_kind_elfobj32 || kind == format_kind_elfobj64 {
        format_elfobj_finish_tables(plan);
    }
    if kind == format_kind_elfso64 {
        format_elfso_finish_tables(plan);
    }
    assert(
        kind == format_kind_pe32 ||
        kind == format_kind_pe64 ||
        kind == format_kind_elf32 ||
        kind == format_kind_elf64 ||
        kind == format_kind_coff32 ||
        kind == format_kind_coff64 ||
        kind == format_kind_elfobj32 ||
        kind == format_kind_elfobj64 ||
        kind == format_kind_elfso64,
        "unsupported format plan kind"
    );
}

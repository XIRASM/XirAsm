// ELF64 shared-object export helpers for XIRASM.
//
// Export sets are explicit immutable Meta values. Including a large catalog
// should define metadata and helper wrappers only; nothing is emitted until
// elf_export_* emitters are called at the chosen .dynsym/.dynstr/.hash/.dynamic
// placement points. This keeps export generation deterministic and avoids a
// hidden global state machine.

import("elfso.inc");

fn elf_export_new() -> list {
    return list.new();
}

fn elf_export_use64(exports: list, target_label: string, export_name: string, section_index: u64, symbol_size: u64) -> list {
    assert(len(target_label) > 0, "ELF export target label is empty");
    assert(len(export_name) > 0, "ELF export name is empty");

    for entry in exports {
        if (map.get(entry, "name") == export_name) {
            assert(map.get(entry, "target") == target_label, "ELF export name already maps to a different target");
            return exports;
        }
    }

    const next: map = elf_export_entry(target_label, export_name, section_index, symbol_size);
    return list.push(exports, next);
}

fn elf_export_entry(target_label: string, export_name: string, section_index: u64, symbol_size: u64) -> map {
    const entry0: map = map.new();
    const entry1: map = map.set(entry0, "target", target_label);
    const entry2: map = map.set(entry1, "name", export_name);
    const entry3: map = map.set(entry2, "section", section_index);
    return map.set(entry3, "size", symbol_size);
}

fn elf_export_emit_dynsym64(exports: list, first_export_name_offset: u64) {
    elfso_sym64(0, 0, elf_shn_undef, 0, 0);
    for i in range(0, len(exports)) {
        const entry: map = list.get(exports, i);
        elfso_sym64(first_export_name_offset + elf_export_name_offset(exports, i), elfso_st_info(elf_stb_global, elf_stt_func), map.get(entry, "section"), label_addr(map.get(entry, "target")), map.get(entry, "size"));
    }
}

fn elf_export_emit_dynstr64(exports: list, soname: string) {
    db(0);
    for entry in exports {
        db(map.get(entry, "name"), 0);
    }
    db(soname, 0);
}

fn elf_export_emit_dynamic64(dynstr_vaddr: u64, dynstr_size: u64, dynsym_vaddr: u64, hash_vaddr: u64, soname_offset: u64) {
    elfso_dyn64(elf_dt_hash, hash_vaddr);
    elfso_dyn64(elf_dt_strtab, dynstr_vaddr);
    elfso_dyn64(elf_dt_strsz, dynstr_size);
    elfso_dyn64(elf_dt_symtab, dynsym_vaddr);
    elfso_dyn64(elf_dt_syment, elfso_sym64_size);
    elfso_dyn64(elf_dt_soname, soname_offset);
    elfso_dyn64(elf_dt_null, 0);
}

fn elf_export_hash(exports: list) {
    dd(1);
    dd(len(exports) + 1);
    if (len(exports) > 0) {
        dd(1);
    }
    if (len(exports) == 0) {
        dd(0);
    }
    dd(0);
    for i in range(1, len(exports) + 1) {
        if (i < len(exports)) {
            dd(i + 1);
        }
        if (i == len(exports)) {
            dd(0);
        }
    }
}

fn elf_export_hash_size(exports: list) -> u64 {
    return 12 + (len(exports) + 1) * 4;
}

fn elf_export_dynstr_size(exports: list, soname: string) -> u64 {
    return 1 + elf_export_names_size(exports) + len(soname) + 1;
}

fn elf_export_names_size(exports: list) -> u64 {
    const size: u64 = 0;
    return elf_export_names_size_from(exports, 0, size);
}

fn elf_export_names_size_from(exports: list, index: u64, size: u64) -> u64 {
    if (index == len(exports)) {
        return size;
    }
    const entry: map = list.get(exports, index);
    return elf_export_names_size_from(exports, index + 1, size + len(map.get(entry, "name")) + 1);
}

fn elf_export_name_offset(exports: list, index: u64) -> u64 {
    const offset: u64 = 0;
    return elf_export_name_offset_from(exports, index, 0, offset);
}

fn elf_export_name_offset_from(exports: list, target_index: u64, index: u64, offset: u64) -> u64 {
    if (index == target_index) {
        return offset;
    }
    const entry: map = list.get(exports, index);
    return elf_export_name_offset_from(exports, target_index, index + 1, offset + len(map.get(entry, "name")) + 1);
}

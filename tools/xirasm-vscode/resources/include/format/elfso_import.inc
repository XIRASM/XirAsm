// ELF64 shared-object import helpers for XIRASM.
//
// This layer deliberately models imports as an explicit immutable Meta value.
// Including a large catalog should only define helper wrappers and metadata;
// nothing is emitted until elfso_import_* emitters are called with the final
// import set. The current usable model emits writable import slots plus
// .dynsym, .dynstr, .rela.dyn, and .dynamic entries. Each slot receives a
// R_X86_64_64 dynamic relocation, so generated code can load or call through
// the slot without hardcoding the final imported address:
//
//     call [rel puts_slot]
//     mov rax, [rel puts_slot]
//
// PLT/GOT helpers are explicit too: callers choose the .plt, .got.plt and
// .rela.plt placement, then emit DT_JMPREL/DT_PLTRELSZ/DT_PLTREL/DT_PLTGOT
// rows through elfso_import_emit_dynamic64_plt.

import("elfso.inc");

const elfso_import_rela64_size: u64 = 24
const elfso_import_plt0_size: u64 = 16
const elfso_import_plt_entry_size: u64 = 16
const elfso_import_gotplt_reserved_entries: u64 = 3
const elfso_import_gotplt_entry_size: u64 = 8

packed struct ElfSoRela64 {
    offset: u64,
    info: u64,
    addend: u64 = 0,
}

fn elfso_import_new() -> list {
    return list.new();
}

fn elfso_import_use64(imports: list, library: string, name: string) -> list {
    return elfso_import_use64_as(imports, library, name, name);
}

fn elfso_import_use64_as(imports: list, library: string, name: string, slot: string) -> list {
    assert(len(library) > 0, "ELF SO import library name is empty");
    assert(len(name) > 0, "ELF SO import symbol name is empty");
    assert(len(slot) > 0, "ELF SO import slot label is empty");

    for entry in imports {
        if (map.get(entry, "slot") == slot) {
            assert(map.get(entry, "library") == library, "ELF SO import slot already maps to a different library");
            assert(map.get(entry, "name") == name, "ELF SO import slot already maps to a different symbol");
            return imports;
        }
    }

    const next: map = elfso_import_entry(library, name, slot);
    return list.push(imports, next);
}

fn elfso_import_use64_plt(imports: list, library: string, name: string) -> list {
    return elfso_import_use64_plt_as(imports, library, name, sym.join(name, "_gotplt"), sym.join(name, "_plt"));
}

fn elfso_import_use64_plt_as(imports: list, library: string, name: string, slot: string, plt: string) -> list {
    assert(len(plt) > 0, "ELF SO import PLT label is empty");
    const next_imports: list = elfso_import_use64_as(imports, library, name, slot);
    const last_index: u64 = len(next_imports) - 1;
    const entry: map = list.get(next_imports, last_index);
    const with_plt: map = map.set(entry, "plt", plt);
    return list.set(next_imports, last_index, with_plt);
}

fn elfso_import_entry(library: string, name: string, slot: string) -> map {
    const entry0: map = map.new();
    const entry1: map = map.set(entry0, "library", library);
    const entry2: map = map.set(entry1, "name", name);
    return map.set(entry2, "slot", slot);
}

fn elfso_import_r_info64(symbol_index: u64, reloc_type: u64) -> u64 {
    return symbol_index * 0x100000000 + reloc_type;
}

fn elfso_import_rela64(offset: u64, symbol_index: u64, reloc_type: u64, addend: u64) {
    emit.struct(ElfSoRela64 { offset: offset, info: elfso_import_r_info64(symbol_index, reloc_type), addend: addend });
}

fn elfso_import_rel32(target: u64, next_ip: u64) -> u64 {
    if (target >= next_ip) {
        const delta: u64 = target - next_ip;
        assert(delta <= 0x7fffffff, "ELF SO PLT forward displacement does not fit rel32");
        return delta;
    }
    const delta: u64 = next_ip - target;
    assert(delta <= 0x80000000, "ELF SO PLT backward displacement does not fit rel32");
    return 0x100000000 - delta;
}

fn elfso_import_plt_size(imports: list) -> u64 {
    return elfso_import_plt0_size + len(imports) * elfso_import_plt_entry_size;
}

fn elfso_import_gotplt_size(imports: list) -> u64 {
    return (elfso_import_gotplt_reserved_entries + len(imports)) * elfso_import_gotplt_entry_size;
}

fn elfso_import_rela_plt_size(imports: list) -> u64 {
    return len(imports) * elfso_import_rela64_size;
}

fn elfso_import_dynamic_plt_size(imports: list) -> u64 {
    return (10 + len(elfso_import_libraries(imports))) * elfso_dyn64_size;
}

fn elfso_import_emit_slots64(imports: list) {
    for entry in imports {
        label.define(map.get(entry, "slot"));
        dq(0);
    }
}

fn elfso_import_emit_plt64(imports: list, plt_vaddr: u64, gotplt_vaddr: u64) {
    db(0xff, 0x35);
    dd(elfso_import_rel32(gotplt_vaddr + 8, plt_vaddr + 6));
    db(0xff, 0x25);
    dd(elfso_import_rel32(gotplt_vaddr + 16, plt_vaddr + 12));
    db(0x0f, 0x1f, 0x40, 0x00);

    for i in range(0, len(imports)) {
        const entry: map = list.get(imports, i);
        const entry_vaddr: u64 = plt_vaddr + elfso_import_plt0_size + i * elfso_import_plt_entry_size;
        const got_slot_vaddr: u64 = gotplt_vaddr + (elfso_import_gotplt_reserved_entries + i) * elfso_import_gotplt_entry_size;
        label.define(map.get(entry, "plt"));
        db(0xff, 0x25);
        dd(elfso_import_rel32(got_slot_vaddr, entry_vaddr + 6));
        db(0x68);
        dd(i);
        db(0xe9);
        dd(elfso_import_rel32(plt_vaddr, entry_vaddr + elfso_import_plt_entry_size));
    }
}

fn elfso_import_emit_gotplt64(imports: list, dynamic_vaddr: u64, plt_vaddr: u64) {
    dq(dynamic_vaddr);
    dq(0);
    dq(0);
    for i in range(0, len(imports)) {
        const entry: map = list.get(imports, i);
        label.define(map.get(entry, "slot"));
        dq(plt_vaddr + elfso_import_plt0_size + i * elfso_import_plt_entry_size + 6);
    }
}

fn elfso_import_emit_dynstr64(imports: list, soname: string) {
    db(0);
    for entry in imports {
        db(map.get(entry, "name"), 0);
    }
    db(soname, 0);
    for library in elfso_import_libraries(imports) {
        db(library, 0);
    }
}

fn elfso_import_emit_dynsym64(imports: list, first_import_name_offset: u64) {
    elfso_sym64(0, 0, elf_shn_undef, 0, 0);
    for i in range(0, len(imports)) {
        const entry: map = list.get(imports, i);
        elfso_sym64(first_import_name_offset + elfso_import_name_offset(imports, i), elfso_st_info(elf_stb_global, elf_stt_func), elf_shn_undef, 0, 0);
    }
}

fn elfso_import_emit_rela64(imports: list, first_import_symbol: u64) {
    for i in range(0, len(imports)) {
        const entry: map = list.get(imports, i);
        elfso_import_rela64(label_addr(map.get(entry, "slot")), first_import_symbol + i, elf_r_x86_64_64, 0);
    }
}

fn elfso_import_emit_rela_plt64(imports: list, first_import_symbol: u64) {
    for i in range(0, len(imports)) {
        const entry: map = list.get(imports, i);
        elfso_import_rela64(label_addr(map.get(entry, "slot")), first_import_symbol + i, elf_r_x86_64_jump_slot, 0);
    }
}

fn elfso_import_emit_dynamic64(imports: list, dynstr_vaddr: u64, dynstr_size: u64, dynsym_vaddr: u64, hash_vaddr: u64, rela_vaddr: u64, rela_size: u64, first_needed_offset: u64) {
    elfso_dyn64(elf_dt_hash, hash_vaddr);
    elfso_dyn64(elf_dt_strtab, dynstr_vaddr);
    elfso_dyn64(elf_dt_strsz, dynstr_size);
    elfso_dyn64(elf_dt_symtab, dynsym_vaddr);
    elfso_dyn64(elf_dt_syment, elfso_sym64_size);
    elfso_dyn64(elf_dt_rela, rela_vaddr);
    elfso_dyn64(elf_dt_relasz, rela_size);
    elfso_dyn64(elf_dt_relaent, elfso_import_rela64_size);

    const libraries: list = elfso_import_libraries(imports);
    for i in range(0, len(libraries)) {
        elfso_dyn64(elf_dt_needed, first_needed_offset + elfso_import_library_offset(libraries, i));
    }
    elfso_dyn64(elf_dt_null, 0);
}

fn elfso_import_emit_dynamic64_plt(imports: list, dynstr_vaddr: u64, dynstr_size: u64, dynsym_vaddr: u64, hash_vaddr: u64, gotplt_vaddr: u64, rela_plt_vaddr: u64, rela_plt_size: u64, first_needed_offset: u64) {
    elfso_dyn64(elf_dt_hash, hash_vaddr);
    elfso_dyn64(elf_dt_strtab, dynstr_vaddr);
    elfso_dyn64(elf_dt_strsz, dynstr_size);
    elfso_dyn64(elf_dt_symtab, dynsym_vaddr);
    elfso_dyn64(elf_dt_syment, elfso_sym64_size);
    elfso_dyn64(elf_dt_pltgot, gotplt_vaddr);
    elfso_dyn64(elf_dt_pltrelsz, rela_plt_size);
    elfso_dyn64(elf_dt_pltrel, elf_dt_rela);
    elfso_dyn64(elf_dt_jmprel, rela_plt_vaddr);

    const libraries: list = elfso_import_libraries(imports);
    for i in range(0, len(libraries)) {
        elfso_dyn64(elf_dt_needed, first_needed_offset + elfso_import_library_offset(libraries, i));
    }
    elfso_dyn64(elf_dt_null, 0);
}

fn elfso_import_hash(imports: list) {
    dd(1);
    dd(len(imports) + 1);
    if (len(imports) > 0) {
        dd(1);
    }
    if (len(imports) == 0) {
        dd(0);
    }
    dd(0);
    for i in range(1, len(imports) + 1) {
        if (i < len(imports)) {
            dd(i + 1);
        }
        if (i == len(imports)) {
            dd(0);
        }
    }
}

fn elfso_import_hash_size(imports: list) -> u64 {
    return 12 + (len(imports) + 1) * 4;
}

fn elfso_import_dynstr_size(imports: list, soname: string) -> u64 {
    return 1 + elfso_import_names_size(imports) + len(soname) + 1 + elfso_import_libraries_size(elfso_import_libraries(imports));
}

fn elfso_import_names_size(imports: list) -> u64 {
    const size: u64 = 0;
    return elfso_import_names_size_from(imports, 0, size);
}

fn elfso_import_names_size_from(imports: list, index: u64, size: u64) -> u64 {
    if (index == len(imports)) {
        return size;
    }
    const entry: map = list.get(imports, index);
    return elfso_import_names_size_from(imports, index + 1, size + len(map.get(entry, "name")) + 1);
}

fn elfso_import_name_offset(imports: list, index: u64) -> u64 {
    const offset: u64 = 0;
    return elfso_import_name_offset_from(imports, index, 0, offset);
}

fn elfso_import_name_offset_from(imports: list, target_index: u64, index: u64, offset: u64) -> u64 {
    if (index == target_index) {
        return offset;
    }
    const entry: map = list.get(imports, index);
    return elfso_import_name_offset_from(imports, target_index, index + 1, offset + len(map.get(entry, "name")) + 1);
}

fn elfso_import_libraries(imports: list) -> list {
    const libraries: list = list.new();
    return elfso_import_libraries_from(imports, 0, libraries);
}

fn elfso_import_libraries_from(imports: list, index: u64, libraries: list) -> list {
    if (index == len(imports)) {
        return libraries;
    }
    const entry: map = list.get(imports, index);
    const library: string = map.get(entry, "library");
    if (elfso_import_list_has(libraries, library)) {
        return elfso_import_libraries_from(imports, index + 1, libraries);
    }
    return elfso_import_libraries_from(imports, index + 1, list.push(libraries, library));
}

fn elfso_import_list_has(values: list, needle: string) -> bool {
    for value in values {
        if (value == needle) {
            return true;
        }
    }
    return false;
}

fn elfso_import_libraries_size(libraries: list) -> u64 {
    const size: u64 = 0;
    return elfso_import_libraries_size_from(libraries, 0, size);
}

fn elfso_import_libraries_size_from(libraries: list, index: u64, size: u64) -> u64 {
    if (index == len(libraries)) {
        return size;
    }
    const library: string = list.get(libraries, index);
    return elfso_import_libraries_size_from(libraries, index + 1, size + len(library) + 1);
}

fn elfso_import_library_offset(libraries: list, index: u64) -> u64 {
    const offset: u64 = 0;
    return elfso_import_library_offset_from(libraries, index, 0, offset);
}

fn elfso_import_library_offset_from(libraries: list, target_index: u64, index: u64, offset: u64) -> u64 {
    if (index == target_index) {
        return offset;
    }
    const library: string = list.get(libraries, index);
    return elfso_import_library_offset_from(libraries, target_index, index + 1, offset + len(library) + 1);
}

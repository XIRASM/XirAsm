// Mach-O export-trie helpers for ordinary defined symbols.
//
// The trie uses one root edge per exported name. This deliberately supports
// the common FFI case (ordinary function exports) without pretending to cover
// re-exports, weak definitions, or stub-and-resolver entries.

import("macho_obj.inc");

const macho_export_terminal_flags_size: u64 = 1

fn macho_export_new() -> list {
    return list.new();
}

fn macho_export_entry(target_label: string, export_name: string) -> map {
    assert(len(target_label) > 0, "Mach-O export target label is empty");
    assert(len(export_name) > 0, "Mach-O export name is empty");
    let entry = map.new();
    map.set_mut(entry, "target", target_label);
    map.set_mut(entry, "name", export_name);
    return entry;
}

fn macho_export_use64(exports: list, target_label: string, export_name: string) -> list {
    let next_exports: list = exports
    for entry in exports {
        if (map.get(entry, "name") == export_name) {
            assert(map.get(entry, "target") == target_label, "Mach-O export name already maps to a different target");
            return exports;
        }
    }
    list.push_mut(next_exports, macho_export_entry(target_label, export_name));
    return next_exports;
}

fn macho_export_uleb_size(value: u64) -> u64 {
    let size: u64 = 1
    let remaining: u64 = value
    while (remaining >= 0x80) {
        remaining = remaining >> 7;
        size = size + 1;
    }
    return size;
}

fn macho_export_child_size(exports: list, index: u64, image_base: u64) -> u64 {
    const entry: map = list.get(exports, index);
    const address: u64 = label_addr(map.get(entry, "target"));
    assert(address >= image_base, "Mach-O export address precedes image base");
    const terminal_size: u64 = macho_export_terminal_flags_size + macho_export_uleb_size(address - image_base);
    return macho_export_uleb_size(terminal_size) + terminal_size + 1;
}

fn macho_export_root_size_fixpoint(exports: list, image_base: u64) -> u64 {
    let root_size: u64 = 2
    let next_root_size: u64 = 0
    while (root_size != next_root_size) {
        next_root_size = 2;
        let child_offset: u64 = root_size
        let index: u64 = 0
        while (index < len(exports)) {
            const entry: map = list.get(exports, index);
            next_root_size = next_root_size + len(map.get(entry, "name")) + 1 + macho_export_uleb_size(child_offset);
            child_offset = child_offset + macho_export_child_size(exports, index, image_base);
            index = index + 1;
        }
        root_size = next_root_size;
    }
    return root_size;
}

fn macho_export_emit_uleb(value: u64) {
    let remaining: u64 = value
    while (remaining >= 0x80) {
        emit.u8((remaining & 0x7f) | 0x80);
        remaining = remaining >> 7;
    }
    emit.u8(remaining);
}

fn macho_export_trie_size64(exports: list, image_base: u64) -> u64 {
    if (len(exports) == 0) {
        return 0;
    }
    const root_size: u64 = macho_export_root_size_fixpoint(exports, image_base);
    let size: u64 = root_size
    let index: u64 = 0
    while (index < len(exports)) {
        size = size + macho_export_child_size(exports, index, image_base);
        index = index + 1;
    }
    return size;
}

fn macho_export_trie_emit64(exports: list, image_base: u64) {
    assert(len(exports) > 0, "Mach-O export trie requires at least one export");
    const root_size: u64 = macho_export_root_size_fixpoint(exports, image_base);
    emit.u8(0);
    emit.u8(len(exports));
    let child_offset: u64 = root_size
    let index: u64 = 0
    while (index < len(exports)) {
        const entry: map = list.get(exports, index);
        db(map.get(entry, "name"));
        emit.u8(0);
        macho_export_emit_uleb(child_offset);
        child_offset = child_offset + macho_export_child_size(exports, index, image_base);
        index = index + 1;
    }
    index = 0;
    while (index < len(exports)) {
        const entry: map = list.get(exports, index);
        const address: u64 = label_addr(map.get(entry, "target"));
        assert(address >= image_base, "Mach-O export address precedes image base");
        const terminal_size: u64 = macho_export_terminal_flags_size + macho_export_uleb_size(address - image_base);
        macho_export_emit_uleb(terminal_size);
        macho_export_emit_uleb(0);
        macho_export_emit_uleb(address - image_base);
        emit.u8(0);
        index = index + 1;
    }
}

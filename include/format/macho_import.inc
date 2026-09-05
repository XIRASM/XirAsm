// Minimal Mach-O 64 executable imports using classic non-lazy dyld binding.
//
// Generic symbol, bind, GOT, and indirect-table records are shared by arm64
// and x86_64. Stub instruction bytes remain architecture-specific.

import("macho_exe.inc");
import("macho_dylib.inc");

const macho_import_pointer_size64: u64 = 8
const macho_import_arm64_stub_size: u64 = 12
const macho_import_x86_64_stub_size: u64 = 6
const macho_import_first_library_ordinal: u64 = 1

fn macho_import_header64_arm64(command_count: u64, command_size: u64) {
    macho_header64_arm64(macho_mh_execute, command_count, command_size,
        macho_mh_dyldlink | macho_mh_twolevel | macho_mh_pie);
}

fn macho_import_header64_x86_64(command_count: u64, command_size: u64) {
    macho_header64_x86_64(macho_mh_execute, command_count, command_size,
        macho_mh_dyldlink | macho_mh_twolevel | macho_mh_pie);
}

fn macho_import_new() -> list {
    return list.new();
}

fn macho_import_use64(imports: list, library: string, name: string) -> list {
    return macho_import_use64_as(imports, library, name, sym.join(name, "_stub"), sym.join(name, "_got"));
}

fn macho_import_use64_as(imports: list, library: string, name: string, stub: string, slot: string) -> list {
    assert(len(library) > 0, "Mach-O import library name is empty");
    assert(len(name) > 0, "Mach-O import symbol name is empty");
    assert(len(stub) > 0, "Mach-O import stub label is empty");
    assert(len(slot) > 0, "Mach-O import slot label is empty");

    for entry in imports {
        if (map.get(entry, "name") == name || map.get(entry, "stub") == stub || map.get(entry, "slot") == slot) {
            assert(map.get(entry, "name") == name, "Mach-O import label already maps to a different symbol");
            assert(map.get(entry, "stub") == stub, "Mach-O import symbol already maps to a different stub label");
            assert(map.get(entry, "slot") == slot, "Mach-O import symbol already maps to a different slot label");
            return imports;
        }
    }

    let entry: map = map.new()
    map.set_mut(entry, "library", library);
    map.set_mut(entry, "name", name);
    map.set_mut(entry, "stub", stub);
    map.set_mut(entry, "slot", slot);
    let next_imports: list = imports
    list.push_mut(next_imports, entry);
    return next_imports;
}

fn macho_import_libraries64(imports: list) -> list {
    let libraries: list = list.new()
    for entry in imports {
        const library: string = map.get(entry, "library")
        let found: bool = false
        for existing in libraries {
            if (existing == library) {
                found = true
            }
        }
        if (!found) {
            list.push_mut(libraries, library)
        }
    }
    return libraries;
}

fn macho_import_library_ordinal64(imports: list, library: string) -> u64 {
    const libraries: list = macho_import_libraries64(imports)
    for i in range(0, len(libraries)) {
        if (list.get(libraries, i) == library) {
            const ordinal: u64 = macho_import_first_library_ordinal + i
            assert(ordinal <= 15, "Mach-O import library ordinal exceeds immediate range");
            return ordinal;
        }
    }
    assert(false, "Mach-O import library is not present in import table");
    return 0;
}

fn macho_import_load_dylibs_size64(imports: list) -> u64 {
    let size: u64 = 0
    const libraries: list = macho_import_libraries64(imports)
    for library in libraries {
        size = size + macho_align_up(macho_dylib_id_command_base_size + len(library) + 1, 8)
    }
    return size;
}

fn macho_import_emit_load_dylibs64(imports: list, current_version: u64, compatibility_version: u64) {
    const libraries: list = macho_import_libraries64(imports)
    for library in libraries {
        macho_dylib_load64(library, current_version, compatibility_version)
    }
}

fn macho_import_use64_many(imports: list, library: string, names: list) -> list {
    let next_imports: list = imports
    for name in names {
        next_imports = macho_import_use64(next_imports, library, name)
    }
    return next_imports;
}

fn macho_import_uleb_size(value: u64) -> u64 {
    let size: u64 = 1
    let remaining: u64 = value
    while remaining >= 0x80 {
        remaining = remaining >> 7;
        size = size + 1;
    }
    return size;
}

fn macho_import_emit_uleb(value: u64) {
    let remaining: u64 = value
    while remaining >= 0x80 {
        emit.u8((remaining & 0x7f) | 0x80);
        remaining = remaining >> 7;
    }
    emit.u8(remaining);
}

fn macho_import_bind_size64(imports: list) -> u64 {
    assert(len(imports) > 0, "Mach-O import table is empty");
    let size: u64 = 2
    for i in range(0, len(imports)) {
        const entry: map = list.get(imports, i)
        size = size + 1 + 1 + len(map.get(entry, "name")) + 1 + 1 + macho_import_uleb_size(i * macho_import_pointer_size64) + 1;
    }
    return size;
}

fn macho_import_emit_bind64(imports: list, data_segment_index: u64) {
    assert(len(imports) > 0, "Mach-O import table is empty");
    assert(data_segment_index < 16, "Mach-O bind segment index exceeds immediate range");
    emit.u8(macho_bind_opcode_set_type_imm | macho_bind_type_pointer);
    for i in range(0, len(imports)) {
        const entry: map = list.get(imports, i)
        const ordinal: u64 = macho_import_library_ordinal64(imports, map.get(entry, "library"))
        emit.u8(macho_bind_opcode_set_dylib_ordinal_imm | ordinal);
        emit.u8(macho_bind_opcode_set_symbol_trailing_flags_imm);
        db(map.get(entry, "name"), 0);
        emit.u8(macho_bind_opcode_set_segment_and_offset_uleb | data_segment_index);
        macho_import_emit_uleb(i * macho_import_pointer_size64);
        emit.u8(macho_bind_opcode_do_bind);
    }
    emit.u8(macho_bind_opcode_done);
}

fn macho_import_names_size64(imports: list) -> u64 {
    let size: u64 = 1
    for entry in imports {
        size = size + len(map.get(entry, "name")) + 1;
    }
    return size;
}

fn macho_import_name_offset64(imports: list, target_index: u64) -> u64 {
    assert(target_index < len(imports), "Mach-O import index is out of bounds");
    let offset: u64 = 1
    let index: u64 = 0
    while index < target_index {
        offset = offset + len(map.get(list.get(imports, index), "name")) + 1;
        index = index + 1;
    }
    return offset;
}

fn macho_import_emit_symbols64(imports: list) {
    for i in range(0, len(imports)) {
        const entry: map = list.get(imports, i)
        const ordinal: u64 = macho_import_library_ordinal64(imports, map.get(entry, "library"))
        macho_nlist64(macho_import_name_offset64(imports, i), macho_n_undef | macho_n_ext, 0, ordinal << 8, 0);
    }
}

fn macho_import_emit_strings64(imports: list) {
    db(0);
    for entry in imports {
        db(map.get(entry, "name"), 0);
    }
}

fn macho_import_emit_indirect64(imports: list) {
    for i in range(0, len(imports)) {
        emit.u32(i);
    }
    for i in range(0, len(imports)) {
        emit.u32(i);
    }
}

fn macho_import_emit_slots64(imports: list) {
    for entry in imports {
        label.define(map.get(entry, "slot"));
        emit.u64(0);
    }
}

fn macho_import_rel32(target: u64, next_ip: u64) -> u64 {
    if target >= next_ip {
        const delta: u64 = target - next_ip
        assert(delta <= 0x7fffffff, "Mach-O x86_64 stub displacement exceeds rel32");
        return delta;
    }
    const delta: u64 = next_ip - target
    assert(delta <= 0x80000000, "Mach-O x86_64 stub displacement exceeds rel32");
    return 0x100000000 - delta;
}

fn macho_import_emit_stubs_x86_64(imports: list, stubs_vaddr: u64, slots_vaddr: u64) {
    for i in range(0, len(imports)) {
        const entry: map = list.get(imports, i)
        const stub_vaddr: u64 = stubs_vaddr + i * macho_import_x86_64_stub_size
        const slot_vaddr: u64 = slots_vaddr + i * macho_import_pointer_size64
        label.define(map.get(entry, "stub"));
        emit.u8(0xff);
        emit.u8(0x25);
        emit.u32(macho_import_rel32(slot_vaddr, stub_vaddr + macho_import_x86_64_stub_size));
    }
}

fn macho_import_arm64_adrp(rd: u64, instruction_vaddr: u64, target_vaddr: u64) -> u64 {
    assert(rd < 32, "Mach-O arm64 ADRP register is invalid");
    const instruction_page: u64 = instruction_vaddr & ~0xfff
    const target_page: u64 = target_vaddr & ~0xfff
    let immediate: u64 = 0
    if target_page >= instruction_page {
        immediate = (target_page - instruction_page) >> 12;
        assert(immediate <= 0xfffff, "Mach-O arm64 ADRP forward target is out of range");
    }
    if target_page < instruction_page {
        const delta: u64 = (instruction_page - target_page) >> 12
        assert(delta <= 0x100000, "Mach-O arm64 ADRP backward target is out of range");
        immediate = 0x200000 - delta;
    }
    return 0x90000000 | ((immediate & 3) << 29) | (((immediate >> 2) & 0x7ffff) << 5) | rd;
}

fn macho_import_arm64_ldr_x(rt: u64, rn: u64, target_vaddr: u64) -> u64 {
    assert(rt < 32 && rn < 32, "Mach-O arm64 LDR register is invalid");
    const page_offset: u64 = target_vaddr & 0xfff
    assert((page_offset & 7) == 0, "Mach-O arm64 pointer slot is not eight-byte aligned");
    return 0xf9400000 | ((page_offset >> 3) << 10) | (rn << 5) | rt;
}

fn macho_import_emit_stubs_arm64(imports: list, stubs_vaddr: u64, slots_vaddr: u64) {
    for i in range(0, len(imports)) {
        const entry: map = list.get(imports, i)
        const stub_vaddr: u64 = stubs_vaddr + i * macho_import_arm64_stub_size
        const slot_vaddr: u64 = slots_vaddr + i * macho_import_pointer_size64
        label.define(map.get(entry, "stub"));
        emit.u32(macho_import_arm64_adrp(16, stub_vaddr, slot_vaddr));
        emit.u32(macho_import_arm64_ldr_x(16, 16, slot_vaddr));
        emit.u32(0xd61f0200);
    }
}

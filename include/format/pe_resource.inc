// PE resource directory helpers for XIRASM.
//
// The explicit numeric helper remains available for small hand-authored trees.
// The compiled-resource facade parses one standard .res file, sorts and groups
// its records deterministically, and emits the PE type/name/language tree.

import("pe.inc");

const pe_resource_directory_size: u64 = 16
const pe_resource_directory_entry_size: u64 = 8
const pe_resource_data_entry_size: u64 = 16
const pe_resource_subdirectory_flag: u64 = 0x80000000
const pe_resource_name_flag: u64 = 0x80000000
const pe_resource_res_fixed_header_size: u64 = 16

const pe_resource_single_type_dir_offset: u64 = pe_resource_directory_size + pe_resource_directory_entry_size
const pe_resource_single_id_dir_offset: u64 = pe_resource_single_type_dir_offset + pe_resource_directory_size + pe_resource_directory_entry_size
const pe_resource_single_data_entry_offset: u64 = pe_resource_single_id_dir_offset + pe_resource_directory_size + pe_resource_directory_entry_size
const pe_resource_single_data_offset: u64 = pe_resource_single_data_entry_offset + pe_resource_data_entry_size

const pe_resource_type_version: u64 = 16
const pe_resource_lang_en_us: u64 = 0x0409

fn pe_resource_directory(named_count: u64, id_count: u64) {
    assert(named_count <= 0xffff, "PE resource named-entry count is out of range");
    assert(id_count <= 0xffff, "PE resource id-entry count is out of range");
    emit.u32(0);
    emit.u32(0);
    emit.u16(0);
    emit.u16(0);
    emit.u16(named_count);
    emit.u16(id_count);
}

fn pe_resource_directory_entry(name_or_id: u64, offset: u64) {
    assert(name_or_id <= 0x7fffffff, "PE resource numeric id is out of range");
    pe_resource_directory_entry_raw(name_or_id, offset);
}

fn pe_resource_directory_entry_raw(name_or_id: u64, offset: u64) {
    assert(name_or_id <= 0xffffffff, "PE resource directory name/id field is out of range");
    assert(offset <= 0xffffffff, "PE resource directory offset is out of range");
    emit.u32(name_or_id);
    emit.u32(offset);
}

fn pe_resource_data_entry(data_rva: u64, size: u64, codepage: u64) {
    assert(data_rva <= 0xffffffff, "PE resource data RVA is out of range");
    assert(size <= 0xffffffff, "PE resource data size is out of range");
    assert(codepage <= 0xffffffff, "PE resource codepage is out of range");
    emit.u32(data_rva);
    emit.u32(size);
    emit.u32(codepage);
    emit.u32(0);
}

fn pe_resource_emit_from_res(path: string, rsrc_rva: u64) {
    const input: bytes = fs.read_bytes(path);
    const input_size: u64 = len(input)
    assert(input_size >= 8, "compiled PE resource file is too small");

    virtual.begin(0);
    const input_base: u64 = here()
    emit.bytes(input);

    let records = list.new()
    let cursor = 0
    let input_order = 0
    while cursor < input_size {
        assert(input_size - cursor >= 8, "compiled PE resource record header is truncated");
        const data_size: u64 = load.u32(input_base + cursor)
        const header_size: u64 = load.u32(input_base + cursor + 4)
        assert(header_size >= 32, "compiled PE resource HeaderSize is too small");
        assert(header_size <= input_size - cursor, "compiled PE resource header exceeds the input file");

        const header_end: u64 = cursor + header_size
        const type_info: map = pe_resource_parse_res_identifier(input_base, cursor + 8, header_end);
        const name_info: map = pe_resource_parse_res_identifier(input_base, map.get(type_info, "next"), header_end);
        const fixed_header: u64 = align_up(map.get(name_info, "next"), 4)
        assert(fixed_header <= header_end, "compiled PE resource fixed header starts outside HeaderSize");
        assert(header_end - fixed_header >= pe_resource_res_fixed_header_size, "compiled PE resource fixed header is truncated");

        const language_id: u64 = load.u16(input_base + fixed_header + 6)
        assert(data_size <= input_size - header_end, "compiled PE resource payload exceeds the input file");
        const payload_end: u64 = header_end + data_size
        const next_record: u64 = align_up(payload_end, 4)
        assert(next_record <= input_size, "compiled PE resource padding exceeds the input file");

        if data_size > 0 {
            const payload: bytes = load.bytes(input_base + header_end, data_size)
            const record: map = pe_resource_record(type_info, name_info, language_id, payload, data_size, input_order);
            records = list.push(records, record)
            input_order = input_order + 1
        }
        cursor = next_record
    }
    const sorted_records: list = pe_resource_sort_records(records)
    virtual.end();
    assert(len(sorted_records) > 0, "compiled PE resource file contains no non-empty records");

    const nodes: map = pe_resource_build_nodes(sorted_records);
    const types: list = map.get(nodes, "types");
    const names: list = map.get(nodes, "names");
    const name_strings: list = pe_resource_collect_name_strings(types, names);

    const root_size: u64 = pe_resource_directory_size + len(types) * pe_resource_directory_entry_size
    const type_directories_size: u64 = pe_resource_type_directories_size(types)
    const name_directories_size: u64 = pe_resource_name_directories_size(names)
    const directories_size: u64 = root_size + type_directories_size + name_directories_size
    const name_strings_size: u64 = pe_resource_name_strings_size(name_strings)
    const data_entries_offset: u64 = align_up(directories_size + name_strings_size, 4)
    const payloads_offset: u64 = align_up(data_entries_offset + len(sorted_records) * pe_resource_data_entry_size, 4)

    label.define("pe_resource_root");
    pe_resource_emit_root(types, name_strings, directories_size);
    pe_resource_emit_type_directories(types, names, name_strings, directories_size);
    pe_resource_emit_name_directories(names, sorted_records, data_entries_offset);
    pe_resource_emit_name_strings(name_strings);
    align(4, 0);
    assert(here() - pe_resource_root == data_entries_offset, "PE resource data-entry layout mismatch");
    pe_resource_emit_data_entries(sorted_records, rsrc_rva, payloads_offset);
    align(4, 0);
    assert(here() - pe_resource_root == payloads_offset, "PE resource payload layout mismatch");
    pe_resource_emit_payloads(sorted_records);
    label.define("pe_resource_end");
}

fn pe_resource_parse_res_identifier(input_base: u64, offset: u64, header_end: u64) -> map {
    assert(offset <= header_end, "compiled PE resource identifier starts after HeaderSize");
    assert(header_end - offset >= 2, "compiled PE resource identifier is truncated");

    const first: u64 = load.u16(input_base + offset)
    if first == 0xffff {
        assert(header_end - offset >= 4, "compiled PE resource ordinal identifier is truncated");
        return pe_resource_identifier(1, load.u16(input_base + offset + 2), 0, 0, bytes.new(), offset + 4);
    }

    let cursor = offset
    let units = 0
    let terminated = 0
    while cursor < header_end && terminated == 0 {
        assert(header_end - cursor >= 2, "compiled PE resource UTF-16 identifier has an odd byte length");
        const code_unit: u64 = load.u16(input_base + cursor)
        cursor = cursor + 2
        if code_unit == 0 {
            terminated = 1
        }
        if code_unit != 0 {
            units = units + 1
        }
    }
    assert(terminated != 0, "compiled PE resource UTF-16 identifier is unterminated");
    assert(units > 0, "compiled PE resource UTF-16 identifier is empty");
    assert(units <= 0xffff, "compiled PE resource UTF-16 identifier is too long");

    const value: bytes = load.bytes(input_base + offset, units * 2)
    return pe_resource_identifier(0, 0, input_base + offset, units, value, cursor);
}

fn pe_resource_identifier(is_id: u64, id: u64, address: u64, units: u64, value: bytes, next: u64) -> map {
    const result0: map = map.set(map.new(), "is_id", is_id);
    const result1: map = map.set(result0, "id", id);
    const result2: map = map.set(result1, "address", address);
    const result3: map = map.set(result2, "units", units);
    const result4: map = map.set(result3, "bytes", value);
    return map.set(result4, "next", next);
}

fn pe_resource_record(type_info: map, name_info: map, language_id: u64, payload: bytes, payload_size: u64, input_order: u64) -> map {
    const result0: map = map.set(map.new(), "type_is_id", map.get(type_info, "is_id"));
    const result1: map = map.set(result0, "type_id", map.get(type_info, "id"));
    const result2: map = map.set(result1, "type_name_address", map.get(type_info, "address"));
    const result3: map = map.set(result2, "type_name_units", map.get(type_info, "units"));
    const result4: map = map.set(result3, "type_name", map.get(type_info, "bytes"));
    const result5: map = map.set(result4, "name_is_id", map.get(name_info, "is_id"));
    const result6: map = map.set(result5, "name_id", map.get(name_info, "id"));
    const result7: map = map.set(result6, "name_address", map.get(name_info, "address"));
    const result8: map = map.set(result7, "name_units", map.get(name_info, "units"));
    const result9: map = map.set(result8, "name", map.get(name_info, "bytes"));
    const result10: map = map.set(result9, "language_id", language_id);
    const result11: map = map.set(result10, "payload", payload);
    const result12: map = map.set(result11, "payload_size", payload_size);
    return map.set(result12, "input_order", input_order);
}

fn pe_resource_sort_records(records: list) -> list {
    let sorted = records
    let index = 1
    while index < len(records) {
        const record: map = list.get(sorted, index);
        let insert_index = index
        let scanning = 1
        while insert_index > 0 && scanning != 0 {
            const previous: map = list.get(sorted, insert_index - 1);
            const should_move: bool = pe_resource_record_less(record, previous);
            if should_move {
                sorted = list.set(sorted, insert_index, previous)
                insert_index = insert_index - 1
            }
            if !should_move {
                scanning = 0
            }
        }
        sorted = list.set(sorted, insert_index, record)
        index = index + 1
    }
    return sorted;
}

fn pe_resource_record_less(left: map, right: map) -> bool {
    const left_type_is_id: u64 = map.get(left, "type_is_id")
    const right_type_is_id: u64 = map.get(right, "type_is_id")
    if left_type_is_id != right_type_is_id {
        return left_type_is_id < right_type_is_id;
    }
    if left_type_is_id != 0 {
        const left_type_id: u64 = map.get(left, "type_id")
        const right_type_id: u64 = map.get(right, "type_id")
        if left_type_id != right_type_id {
            return left_type_id < right_type_id;
        }
    }
    if left_type_is_id == 0 && !bytes.eq(map.get(left, "type_name"), map.get(right, "type_name")) {
        return pe_resource_utf16_less(map.get(left, "type_name_address"), map.get(left, "type_name_units"), map.get(right, "type_name_address"), map.get(right, "type_name_units"));
    }

    const left_name_is_id: u64 = map.get(left, "name_is_id")
    const right_name_is_id: u64 = map.get(right, "name_is_id")
    if left_name_is_id != right_name_is_id {
        return left_name_is_id < right_name_is_id;
    }
    if left_name_is_id != 0 {
        const left_name_id: u64 = map.get(left, "name_id")
        const right_name_id: u64 = map.get(right, "name_id")
        if left_name_id != right_name_id {
            return left_name_id < right_name_id;
        }
    }
    if left_name_is_id == 0 && !bytes.eq(map.get(left, "name"), map.get(right, "name")) {
        return pe_resource_utf16_less(map.get(left, "name_address"), map.get(left, "name_units"), map.get(right, "name_address"), map.get(right, "name_units"));
    }

    const left_language: u64 = map.get(left, "language_id")
    const right_language: u64 = map.get(right, "language_id")
    if left_language != right_language {
        return left_language < right_language;
    }
    return map.get(left, "input_order") < map.get(right, "input_order");
}

fn pe_resource_utf16_less(left_address: u64, left_units: u64, right_address: u64, right_units: u64) -> bool {
    let common_units = left_units
    if right_units < common_units {
        common_units = right_units
    }
    let index = 0
    let result = 0
    let decided = 0
    while index < common_units && decided == 0 {
        const left_unit: u64 = load.u16(left_address + index * 2)
        const right_unit: u64 = load.u16(right_address + index * 2)
        if left_unit < right_unit {
            result = 1
            decided = 1
        }
        if left_unit > right_unit {
            decided = 1
        }
        index = index + 1
    }
    if decided == 0 {
        return left_units < right_units;
    }
    return result != 0;
}

fn pe_resource_build_nodes(records: list) -> map {
    let types = list.new()
    let names = list.new()
    let index = 0
    let current_type_index = 0
    while index < len(records) {
        const record: map = list.get(records, index);
        let new_type = 0
        if index == 0 {
            new_type = 1
        }
        if index > 0 && !pe_resource_same_type(record, list.get(records, index - 1)) {
            new_type = 1
        }

        if new_type != 0 {
            current_type_index = len(types)
            types = list.push(types, pe_resource_type_node(record, index, len(names)))
        }
        if new_type == 0 {
            const current_type: map = list.get(types, current_type_index);
            types = list.set(types, current_type_index, map.set(current_type, "record_count", map.get(current_type, "record_count") + 1))
        }

        let new_name = new_type
        if new_type == 0 && !pe_resource_same_name(record, list.get(records, index - 1)) {
            new_name = 1
        }
        if new_name != 0 {
            names = list.push(names, pe_resource_name_node(record, index, current_type_index))
            const current_type: map = list.get(types, current_type_index);
            types = list.set(types, current_type_index, map.set(current_type, "name_count", map.get(current_type, "name_count") + 1))
        }
        if new_name == 0 {
            const current_name_index: u64 = len(names) - 1
            const current_name: map = list.get(names, current_name_index);
            names = list.set(names, current_name_index, map.set(current_name, "record_count", map.get(current_name, "record_count") + 1))
        }
        index = index + 1
    }

    const result0: map = map.set(map.new(), "types", types);
    return map.set(result0, "names", names);
}

fn pe_resource_type_node(record: map, first_record: u64, first_name: u64) -> map {
    const result0: map = map.set(map.new(), "is_id", map.get(record, "type_is_id"));
    const result1: map = map.set(result0, "id", map.get(record, "type_id"));
    const result2: map = map.set(result1, "name", map.get(record, "type_name"));
    const result3: map = map.set(result2, "first_record", first_record);
    const result4: map = map.set(result3, "record_count", 1);
    const result5: map = map.set(result4, "first_name", first_name);
    return map.set(result5, "name_count", 0);
}

fn pe_resource_name_node(record: map, first_record: u64, type_index: u64) -> map {
    const result0: map = map.set(map.new(), "is_id", map.get(record, "name_is_id"));
    const result1: map = map.set(result0, "id", map.get(record, "name_id"));
    const result2: map = map.set(result1, "name", map.get(record, "name"));
    const result3: map = map.set(result2, "first_record", first_record);
    const result4: map = map.set(result3, "record_count", 1);
    return map.set(result4, "type_index", type_index);
}

fn pe_resource_same_type(left: map, right: map) -> bool {
    if map.get(left, "type_is_id") != map.get(right, "type_is_id") {
        return false;
    }
    if map.get(left, "type_is_id") != 0 {
        return map.get(left, "type_id") == map.get(right, "type_id");
    }
    return bytes.eq(map.get(left, "type_name"), map.get(right, "type_name"));
}

fn pe_resource_same_name(left: map, right: map) -> bool {
    if !pe_resource_same_type(left, right) {
        return false;
    }
    if map.get(left, "name_is_id") != map.get(right, "name_is_id") {
        return false;
    }
    if map.get(left, "name_is_id") != 0 {
        return map.get(left, "name_id") == map.get(right, "name_id");
    }
    return bytes.eq(map.get(left, "name"), map.get(right, "name"));
}

fn pe_resource_collect_name_strings(types: list, names: list) -> list {
    let strings = list.new()
    for type_node in types {
        if map.get(type_node, "is_id") == 0 {
            strings = pe_resource_add_unique_name(strings, map.get(type_node, "name"))
        }
    }
    for name_node in names {
        if map.get(name_node, "is_id") == 0 {
            strings = pe_resource_add_unique_name(strings, map.get(name_node, "name"))
        }
    }
    return strings;
}

fn pe_resource_add_unique_name(strings: list, value: bytes) -> list {
    for current in strings {
        if bytes.eq(current, value) {
            return strings;
        }
    }
    return list.push(strings, value);
}

fn pe_resource_type_directories_size(types: list) -> u64 {
    let size = 0
    for type_node in types {
        size = size + pe_resource_directory_size + map.get(type_node, "name_count") * pe_resource_directory_entry_size
    }
    return size;
}

fn pe_resource_name_directories_size(names: list) -> u64 {
    let size = 0
    for name_node in names {
        size = size + pe_resource_directory_size + map.get(name_node, "record_count") * pe_resource_directory_entry_size
    }
    return size;
}

fn pe_resource_name_strings_size(strings: list) -> u64 {
    let size = 0
    for value in strings {
        assert(len(value) % 2 == 0, "PE resource UTF-16 name has an odd byte length");
        assert(len(value) / 2 <= 0xffff, "PE resource UTF-16 name is too long");
        size = size + 2 + len(value)
    }
    return size;
}

fn pe_resource_type_directory_offset(types: list, type_index: u64) -> u64 {
    let offset = pe_resource_directory_size + len(types) * pe_resource_directory_entry_size
    let index = 0
    while index < type_index {
        const type_node: map = list.get(types, index);
        offset = offset + pe_resource_directory_size + map.get(type_node, "name_count") * pe_resource_directory_entry_size
        index = index + 1
    }
    return offset;
}

fn pe_resource_name_directory_offset(types: list, names: list, name_index: u64) -> u64 {
    let offset = pe_resource_directory_size + len(types) * pe_resource_directory_entry_size + pe_resource_type_directories_size(types)
    let index = 0
    while index < name_index {
        const name_node: map = list.get(names, index);
        offset = offset + pe_resource_directory_size + map.get(name_node, "record_count") * pe_resource_directory_entry_size
        index = index + 1
    }
    return offset;
}

fn pe_resource_name_string_offset(strings: list, value: bytes, directories_size: u64) -> u64 {
    let offset = directories_size
    let found = 0
    let result = 0
    for current in strings {
        if found == 0 && bytes.eq(current, value) {
            result = offset
            found = 1
        }
        if found == 0 {
            offset = offset + 2 + len(current)
        }
    }
    assert(found != 0, "PE resource UTF-16 name is missing from the name table");
    return result;
}

fn pe_resource_payload_offset(records: list, record_index: u64, payloads_offset: u64) -> u64 {
    let offset = payloads_offset
    let index = 0
    while index < record_index {
        offset = offset + align_up(map.get(list.get(records, index), "payload_size"), 4)
        index = index + 1
    }
    return offset;
}

fn pe_resource_named_type_count(types: list) -> u64 {
    let count = 0
    for type_node in types {
        if map.get(type_node, "is_id") == 0 {
            count = count + 1
        }
    }
    return count;
}

fn pe_resource_named_name_count(names: list, type_index: u64) -> u64 {
    let count = 0
    for name_node in names {
        if map.get(name_node, "type_index") == type_index && map.get(name_node, "is_id") == 0 {
            count = count + 1
        }
    }
    return count;
}

fn pe_resource_directory_name_value(is_id: u64, id: u64, name: bytes, strings: list, directories_size: u64) -> u64 {
    if is_id != 0 {
        assert(id <= 0x7fffffff, "PE resource numeric id is out of range");
        return id;
    }
    const name_offset: u64 = pe_resource_name_string_offset(strings, name, directories_size)
    assert(name_offset <= 0x7fffffff, "PE resource name offset is out of range");
    return pe_resource_name_flag | name_offset;
}

fn pe_resource_emit_root(types: list, strings: list, directories_size: u64) {
    const named_count: u64 = pe_resource_named_type_count(types)
    pe_resource_directory(named_count, len(types) - named_count);
    let type_index = 0
    while type_index < len(types) {
        const type_node: map = list.get(types, type_index);
        const name_value: u64 = pe_resource_directory_name_value(map.get(type_node, "is_id"), map.get(type_node, "id"), map.get(type_node, "name"), strings, directories_size)
        const directory_offset: u64 = pe_resource_type_directory_offset(types, type_index)
        assert(directory_offset <= 0x7fffffff, "PE resource type-directory offset is out of range");
        pe_resource_directory_entry_raw(name_value, pe_resource_subdirectory_flag | directory_offset);
        type_index = type_index + 1
    }
}

fn pe_resource_emit_type_directories(types: list, names: list, strings: list, directories_size: u64) {
    let type_index = 0
    while type_index < len(types) {
        const type_node: map = list.get(types, type_index);
        const named_count: u64 = pe_resource_named_name_count(names, type_index)
        pe_resource_directory(named_count, map.get(type_node, "name_count") - named_count);

        const first_name: u64 = map.get(type_node, "first_name")
        const name_count: u64 = map.get(type_node, "name_count")
        let offset = 0
        while offset < name_count {
            const name_index: u64 = first_name + offset
            const name_node: map = list.get(names, name_index);
            const name_value: u64 = pe_resource_directory_name_value(map.get(name_node, "is_id"), map.get(name_node, "id"), map.get(name_node, "name"), strings, directories_size)
            const directory_offset: u64 = pe_resource_name_directory_offset(types, names, name_index)
            assert(directory_offset <= 0x7fffffff, "PE resource name-directory offset is out of range");
            pe_resource_directory_entry_raw(name_value, pe_resource_subdirectory_flag | directory_offset);
            offset = offset + 1
        }
        type_index = type_index + 1
    }
}

fn pe_resource_emit_name_directories(names: list, records: list, data_entries_offset: u64) {
    for name_node in names {
        const record_count: u64 = map.get(name_node, "record_count")
        pe_resource_directory(0, record_count);
        const first_record: u64 = map.get(name_node, "first_record")
        let offset = 0
        while offset < record_count {
            const record_index: u64 = first_record + offset
            const record: map = list.get(records, record_index);
            const language_id: u64 = map.get(record, "language_id")
            assert(language_id <= 0xffff, "PE resource language id is out of range");
            const data_entry_offset: u64 = data_entries_offset + record_index * pe_resource_data_entry_size
            assert(data_entry_offset <= 0x7fffffff, "PE resource data-entry offset is out of range");
            pe_resource_directory_entry(language_id, data_entry_offset);
            offset = offset + 1
        }
    }
}

fn pe_resource_emit_name_strings(strings: list) {
    for value in strings {
        emit.u16(len(value) / 2);
        emit.bytes(value);
    }
}

fn pe_resource_emit_data_entries(records: list, rsrc_rva: u64, payloads_offset: u64) {
    let record_index = 0
    while record_index < len(records) {
        const record: map = list.get(records, record_index);
        const payload_offset: u64 = pe_resource_payload_offset(records, record_index, payloads_offset)
        pe_resource_data_entry(rsrc_rva + payload_offset, map.get(record, "payload_size"), 0);
        record_index = record_index + 1
    }
}

fn pe_resource_emit_payloads(records: list) {
    for record in records {
        emit.bytes(map.get(record, "payload"));
        align(4, 0);
    }
}

fn pe_resource_emit_single_numeric(resource_type: u64, resource_id: u64, language_id: u64) {
    assert(resource_type <= 0x7fffffff, "PE resource type id is out of range");
    assert(resource_id <= 0x7fffffff, "PE resource id is out of range");
    assert(language_id <= 0x7fffffff, "PE resource language id is out of range");

    label.define("pe_resource_root");
    pe_resource_directory(0, 1);
    pe_resource_directory_entry(resource_type, pe_resource_subdirectory_flag | pe_resource_single_type_dir_offset);

    label.define("pe_resource_type_directory");
    pe_resource_directory(0, 1);
    pe_resource_directory_entry(resource_id, pe_resource_subdirectory_flag | pe_resource_single_id_dir_offset);

    label.define("pe_resource_id_directory");
    pe_resource_directory(0, 1);
    pe_resource_directory_entry(language_id, pe_resource_single_data_entry_offset);

    label.define("pe_resource_data_entry");
    pe_resource_data_entry(0, 0, 0);

    label.define("pe_resource_data");
}

fn pe_resource_finish_single_numeric(rsrc_rva: u64, rsrc_start: u64, data_end: u64, codepage: u64) {
    assert(data_end >= pe_resource_data, "PE resource data end is before data start");
    assert(codepage <= 0xffffffff, "PE resource codepage is out of range");
    defer {
        store.u32(pe_resource_data_entry, rsrc_rva + (pe_resource_data - rsrc_start));
        store.u32(pe_resource_data_entry + 4, data_end - pe_resource_data);
        store.u32(pe_resource_data_entry + 8, codepage);
        store.u32(pe_resource_data_entry + 12, 0);
    }
    align(4, 0);
    label.define("pe_resource_end");
}

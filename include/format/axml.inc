// Binary Android XML (AXML) encoder for XIRASM.
//
// Design boundary (mirrors pe.inc / zip.inc):
// - The document is a plain compile-time map built with value-style calls
//   (every builder returns the updated document; nothing is emitted until
//   axml_build runs). This keeps AXML generation data-driven: manifests and
//   other Android XML trees are described as element/attribute lists.
// - Chunk layout follows an aapt2-linked reference byte for byte: UTF-16LE
//   string pool, optional resource map (attribute name -> framework id),
//   namespace chunks, and start/end element chunks with 20-byte attributes.
// - String values are interned into one deduplicated pool. The transcoder
//   accepts ASCII input only; non-ASCII text enters through data files
//   once the stage-4 string work lands.
// - The builder emits inside a scratch virtual area and copies the finished
//   chunk tree out as `bytes`, ready for zip_entry or further patching.

const axml_res_xml_type: u64 = 0x0003
const axml_res_string_pool_type: u64 = 0x0001
const axml_res_xml_resource_map_type: u64 = 0x0180
const axml_res_start_ns_type: u64 = 0x0100
const axml_res_end_ns_type: u64 = 0x0101
const axml_res_start_element_type: u64 = 0x0102
const axml_res_end_element_type: u64 = 0x0103

const axml_value_type_reference: u64 = 0x01
const axml_value_type_string: u64 = 0x03
const axml_value_type_int_dec: u64 = 0x10
const axml_value_type_int_hex: u64 = 0x11
const axml_value_type_boolean: u64 = 0x12
const axml_none: u64 = 0xffffffff

fn axml_new() -> map {
    let doc: map = map.new()
    map.set_mut(doc, "pool", list.new());
    map.set_mut(doc, "lookup", map.new());
    map.set_mut(doc, "resmap", map.new());
    map.set_mut(doc, "nodes", list.new());
    return doc;
}

// Intern a string into the pool. Explicit interning lets callers fix the
// pool order (aapt2 keeps attribute names first for the resource map);
// element builders intern anything still missing in first-use order.
fn axml_pool_intern(doc: map, text: string) -> map {
    const lookup: map = map.get(doc, "lookup")
    if map.has(lookup, text) {
        return doc;
    }
    let pool: list = map.get(doc, "pool")
    list.push_mut(pool, text);
    let linked: map = map.set(doc, "lookup", map.set(lookup, text, len(pool) - 1))
    return map.set(linked, "pool", pool);
}

fn axml_pool_index(doc: map, text: string) -> u64 {
    const lookup: map = map.get(doc, "lookup")
    assert(map.has(lookup, text), "axml string was not interned");
    return map.get(lookup, text);
}

// Register a framework resource id for an attribute name; the resource map
// chunk emits one row per registered attribute in pool order.
fn axml_attr_resource_id(doc: map, attr_name: string, resource_id: u64) -> map {
    const resmap: map = map.get(doc, "resmap")
    return map.set(doc, "resmap", map.set(resmap, attr_name, resource_id));
}

fn axml_attr_entry(name: string, ns: string, kind: u64, data: u64, value_text: string) -> map {
    let attr: map = map.new()
    map.set_mut(attr, "name", name);
    map.set_mut(attr, "ns", ns);
    map.set_mut(attr, "kind", kind);
    map.set_mut(attr, "data", data);
    map.set_mut(attr, "value_text", value_text);
    return attr;
}

// An empty ns means the attribute carries no namespace (the package-level
// "package" attribute); otherwise ns is the namespace URI text.
fn axml_attr_string(name: string, ns: string, value: string) -> map {
    return axml_attr_entry(name, ns, axml_value_type_string, 0, value);
}

fn axml_attr_int(name: string, ns: string, value: u64) -> map {
    return axml_attr_entry(name, ns, axml_value_type_int_dec, value, "");
}

fn axml_attr_hex(name: string, ns: string, value: u64) -> map {
    return axml_attr_entry(name, ns, axml_value_type_int_hex, value, "");
}

// aapt2 encodes booleans as INT_BOOLEAN with data 0 for false and -1 for true.
fn axml_attr_bool(name: string, ns: string, value: u64) -> map {
    return axml_attr_entry(name, ns, axml_value_type_boolean, value, "");
}

// A reference to a resource by its full id (for example an application icon).
fn axml_attr_reference(name: string, ns: string, resource_id: u64) -> map {
    return axml_attr_entry(name, ns, axml_value_type_reference, resource_id, "");
}

fn axml_ns_start(doc: map, prefix: string, uri: string) -> map {
    let linked: map = axml_pool_intern(doc, prefix)
    let complete: map = axml_pool_intern(linked, uri)
    let node: map = map.new()
    map.set_mut(node, "kind", axml_res_start_ns_type);
    map.set_mut(node, "prefix_idx", axml_pool_index(complete, prefix));
    map.set_mut(node, "uri_idx", axml_pool_index(complete, uri));
    let nodes: list = map.get(complete, "nodes")
    list.push_mut(nodes, node);
    return map.set(complete, "nodes", nodes);
}

fn axml_ns_end(doc: map, prefix: string, uri: string) -> map {
    let linked: map = axml_pool_intern(doc, prefix)
    let complete: map = axml_pool_intern(linked, uri)
    let node: map = map.new()
    map.set_mut(node, "kind", axml_res_end_ns_type);
    map.set_mut(node, "prefix_idx", axml_pool_index(complete, prefix));
    map.set_mut(node, "uri_idx", axml_pool_index(complete, uri));
    let nodes: list = map.get(complete, "nodes")
    list.push_mut(nodes, node);
    return map.set(complete, "nodes", nodes);
}

fn axml_start(doc: map, name: string, attrs: list) -> map {
    let linked: map = axml_pool_intern(doc, name)
    const name_idx: u64 = axml_pool_index(linked, name)

    let resolved: list = list.new()
    for attr in attrs {
        const ns: string = map.get(attr, "ns")
        let ns_idx: u64 = axml_none
        if ns != "" {
            let ns_linked: map = axml_pool_intern(linked, ns)
            ns_idx = axml_pool_index(ns_linked, ns);
            linked = ns_linked
        }
        const attr_name: string = map.get(attr, "name")
        let named: map = axml_pool_intern(linked, attr_name)
        const attr_name_idx: u64 = axml_pool_index(named, attr_name)

        const kind: u64 = map.get(attr, "kind")
        let raw_idx: u64 = axml_none
        let data: u64 = map.get(attr, "data")
        if kind == axml_value_type_string {
            const value_text: string = map.get(attr, "value_text")
            let valued: map = axml_pool_intern(named, value_text)
            raw_idx = axml_pool_index(valued, value_text);
            data = raw_idx;
            named = valued
        }

        let row: map = map.new()
        map.set_mut(row, "ns_idx", ns_idx);
        map.set_mut(row, "name_idx", attr_name_idx);
        map.set_mut(row, "raw_idx", raw_idx);
        map.set_mut(row, "kind", kind);
        map.set_mut(row, "data", data);
        list.push_mut(resolved, row);
        linked = named
    }

    let node: map = map.new()
    map.set_mut(node, "kind", axml_res_start_element_type);
    map.set_mut(node, "name_idx", name_idx);
    map.set_mut(node, "attrs", resolved);
    let nodes: list = map.get(linked, "nodes")
    list.push_mut(nodes, node);
    return map.set(linked, "nodes", nodes);
}

fn axml_end(doc: map, name: string) -> map {
    let linked: map = axml_pool_intern(doc, name)
    const name_idx: u64 = axml_pool_index(linked, name)
    let node: map = map.new()
    map.set_mut(node, "kind", axml_res_end_element_type);
    map.set_mut(node, "name_idx", name_idx);
    let nodes: list = map.get(linked, "nodes")
    list.push_mut(nodes, node);
    return map.set(linked, "nodes", nodes);
}

fn axml_build(let out, doc: map) {
    const pool: list = map.get(doc, "pool")
    const nodes: list = map.get(doc, "nodes")
    const resmap_ids: map = map.get(doc, "resmap")
    const pool_count: u64 = len(pool)

    let pool_data: u64 = 0
    for text in pool {
        pool_data = pool_data + 4 + 2 * len(text)
    }
    const pool_padding: u64 = (4 - pool_data % 4) % 4
    const pool_size: u64 = 28 + 4 * pool_count + pool_data + pool_padding

    // The resource map is a positional array: row i holds the framework id of
    // string pool entry i, and rows for non-attribute strings stay zero. It
    // must cover every index up to the last attribute name, not only the
    // entries that registered an id.
    let resmap_count: u64 = 0
    let resmap_index: u64 = 0
    while resmap_index < pool_count {
        if map.has(resmap_ids, list.get(pool, resmap_index)) {
            resmap_count = resmap_index + 1
        }
        resmap_index = resmap_index + 1
    }
    let resmap_size: u64 = 0
    if resmap_count > 0 {
        resmap_size = 8 + 4 * resmap_count
    }

    let elements_size: u64 = 0
    for node in nodes {
        const kind: u64 = map.get(node, "kind")
        if kind == axml_res_start_element_type {
            const attrs: list = map.get(node, "attrs")
            elements_size = elements_size + 36 + 20 * len(attrs)
        }
        if kind == axml_res_end_element_type {
            elements_size = elements_size + 24
        }
        if kind == axml_res_start_ns_type {
            elements_size = elements_size + 24
        }
        if kind == axml_res_end_ns_type {
            elements_size = elements_size + 24
        }
    }
    const total: u64 = 8 + pool_size + resmap_size + elements_size

    virtual.begin();
    const base: u64 = here()

    // Wrapper chunk; the total size is patched after assembly.
    emit.u16(axml_res_xml_type);
    emit.u16(8);
    emit.u32(0);

    // String pool: header, zeroed offset table, zeroed data area. The raw
    // ASCII strings ride behind the chunk tree as a scratch band and are
    // transcoded in place below.
    emit.u16(axml_res_string_pool_type);
    emit.u16(28);
    emit.u32(pool_size);
    emit.u32(pool_count);
    emit.u32(0);
    emit.u32(0);
    emit.u32(28 + 4 * pool_count);
    emit.u32(0);
    const offsets_base: u64 = here()
    for i in range(0, pool_count) {
        emit.u32(0);
    }
    const data_base: u64 = here()
    emit.bytes(bytes.repeat(pool_data + pool_padding, 0));

    if resmap_count > 0 {
        emit.u16(axml_res_xml_resource_map_type);
        emit.u16(8);
        emit.u32(resmap_size);
        for i in range(0, resmap_count) {
            const text: string = list.get(pool, i)
            if map.has(resmap_ids, text) {
                emit.u32(map.get(resmap_ids, text));
            } else {
                emit.u32(0);
            }
        }
    }

    for node in nodes {
        const kind: u64 = map.get(node, "kind")
        if kind == axml_res_start_ns_type {
            emit.u16(kind);
            emit.u16(16);
            emit.u32(24);
            emit.u32(0);
            emit.u32(axml_none);
            emit.u32(map.get(node, "prefix_idx"));
            emit.u32(map.get(node, "uri_idx"));
        }
        if kind == axml_res_end_ns_type {
            emit.u16(kind);
            emit.u16(16);
            emit.u32(24);
            emit.u32(0);
            emit.u32(axml_none);
            emit.u32(map.get(node, "prefix_idx"));
            emit.u32(map.get(node, "uri_idx"));
        }
        if kind == axml_res_start_element_type {
            const name_idx: u64 = map.get(node, "name_idx")
            const attrs: list = map.get(node, "attrs")
            emit.u16(kind);
            emit.u16(16);
            emit.u32(36 + 20 * len(attrs));
            emit.u32(0);
            emit.u32(axml_none);
            emit.u32(axml_none);
            emit.u32(name_idx);
            emit.u16(20);
            emit.u16(20);
            emit.u16(len(attrs));
            emit.u16(0);
            emit.u32(0);
            for attr in attrs {
                emit.u32(map.get(attr, "ns_idx"));
                emit.u32(map.get(attr, "name_idx"));
                emit.u32(map.get(attr, "raw_idx"));
                emit.u16(8);
                emit.u8(0);
                emit.u8(map.get(attr, "kind"));
                emit.u32(map.get(attr, "data"));
            }
        }
        if kind == axml_res_end_element_type {
            emit.u16(kind);
            emit.u16(16);
            emit.u32(24);
            emit.u32(0);
            emit.u32(axml_none);
            emit.u32(axml_none);
            emit.u32(map.get(node, "name_idx"));
        }
    }

    assert(here() - base == 8 + pool_size + resmap_size + elements_size, "axml layout drifted");

    // Scratch band: raw ASCII strings behind the AXML body.
    const draft_base: u64 = here()
    for text in pool {
        emit.bytes(text);
    }

    // Transcode in place: pool entry = u16 length, u16 chars, u16 NUL.
    let run: u64 = 0
    let draft_off: u64 = 0
    let i: u64 = 0
    while i < pool_count {
        const text: string = list.get(pool, i)
        const n: u64 = len(text)
        store.u32(offsets_base + 4 * i, run);
        store.u16(data_base + run, n);
        let j: u64 = 0
        while j < n {
            const ch: u64 = load.u8(draft_base + draft_off + j)
            assert(ch < 0x80, "axml strings require ASCII input");
            store.u16(data_base + run + 2 + 2 * j, ch);
            j = j + 1
        }
        store.u16(data_base + run + 2 + 2 * n, 0);
        run = run + 4 + 2 * n;
        draft_off = draft_off + n;
        i = i + 1
    }
    assert(run == pool_data, "axml transcode drifted");

    store.u32(base + 4, total);
    out = load.bytes(base, total);
    virtual.end();
}

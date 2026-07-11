fn align_up(value: u64, align: u64) -> u64 {
    return ((value + align - 1) / align) * align;
}

fn is_page(value: u64) -> bool {
    return value == 0x1000;
}

fn tag() -> string {
    return "OK";
}

fn blob() -> bytes {
    return b"AB";
}

const raw = align_up(3, 0x200)
assert(is_page(0x1000));
emit.u16(raw);
emit.bytes(tag());
emit.bytes(blob());

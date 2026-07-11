fn align_up(value: u64, align: u64) -> u64 {
    return ((value + align - 1) / align) * align;
}

origin(0x4000);

header:
emit.u32(0);
body:
emit.bytes(b"ABC");
end:
pad_to(align_up(end - region_base(), 8), 0);

defer {
    store.u32(header, align_up(end - body, 8));
    assert(load.u32(header) == 8);
}

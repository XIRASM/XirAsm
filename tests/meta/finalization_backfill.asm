origin(0x4000);

header:
emit.u32(0);
emit.u32(0);

body:
emit.bytes(b"ABCD");
tail:
emit.bytes(b"????");
end:

defer {
    store.u32(header, end - body);
    store.u32(header + 4, body - region_base());
    store.bytes(tail, b"OK!!");
    assert(load.u32(header) == 8);
    assert(load.u32(header + 4) == 8);
    assert(load.bytes(tail, 4) == b"OK!!");
}

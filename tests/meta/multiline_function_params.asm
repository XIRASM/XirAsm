fn emit_seven(
    a: u64,
    b: u64,
    c: u64,
    d: u64,
    e: u64,
    f: u64,
    g: u64
) {
    assert(a == 1, "parameter a was not bound");
    assert(g == 7, "parameter g was not bound");
    emit.u8(a);
    emit.u8(b);
    emit.u8(c);
    emit.u8(d);
    emit.u8(e);
    emit.u8(f);
    emit.u8(g);
}

emit_seven(1, 2, 3, 4, 5, 6, 7);

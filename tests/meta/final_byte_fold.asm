origin(0x5000);

checksum:
emit.u16(0);

payload:
emit.bytes(b"ABCD");
payload_end:

defer {
    // api-matrix-fixture: let cursor = payload
    let cursor = payload
    let sum = 0
    // api-matrix-fixture: while cursor < end
    while cursor < payload_end {
        sum = sum + load.u8(cursor)
        // api-matrix-fixture: cursor = cursor + 1
        cursor = cursor + 1
    }
    store.u16(checksum, sum);
    assert(load.u16(checksum) == 266);
}

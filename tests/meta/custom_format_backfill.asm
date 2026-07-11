// Custom/simple formats stay on the flat-output path: emit stable bytes,
// reserve header fields, and use defer only for final backfill/asserts.

origin(0);

magic:
emit.bytes(b"XIF1");
size_field:
emit.u32(0);
payload_foa_field:
emit.u32(0);
checksum_field:
emit.u32(0);

payload:
emit.bytes(b"OK!!");
payload_end:

defer {
    store.u32(size_field, payload_end - magic);
    store.u32(payload_foa_field, payload - region_base());
    store.u32(checksum_field, load.u8(payload) + load.u8(payload + 1));

    assert(load.bytes(magic, 4) == b"XIF1");
    assert(load.u32(size_field) == 20);
    assert(load.u32(payload_foa_field) == payload - magic);
    assert(load.u32(checksum_field) == 0x9a);
}

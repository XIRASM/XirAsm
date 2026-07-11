origin(0)

size_field:
emit.u16(0)

checksum_field:
emit.u16(0)

payload:
emit.bytes(b"AB")

late_layout {
    emit.bytes(b"CD")
}

defer {
    let cursor = payload
    let checksum = 0
    const end = region_base() + region_file_size(payload)

    while cursor < end {
        checksum = checksum + load.u8(cursor)
        cursor = cursor + 1
    }

    store.u16(size_field, region_file_size(size_field))
    store.u16(checksum_field, checksum)

    assert(load.u16(size_field) == 8)
    assert(load.u16(checksum_field) == 0x010a)
    assert(load.bytes(payload, 4) == b"ABCD")
}

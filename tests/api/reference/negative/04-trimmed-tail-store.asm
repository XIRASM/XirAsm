origin(0)

emit.u8(0x11)
reserve(1)

defer {
    store.u8(1, 0x22)
}

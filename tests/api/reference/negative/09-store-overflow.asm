region.begin("data", 0x1000, 0)

slot:
emit.u8(0)

defer {
    store.u8(slot, 0x100)
}

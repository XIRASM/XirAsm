region.begin("data", 0x1000, 0)

slot:
emit.u8(0x11)

defer {
    assert(load.u16(slot) == 0x11)
}

region.begin("data", 0x1000, 0)
emit.u8(0x11)

defer {
    assert(region_file_size(0xffff) == 1)
}

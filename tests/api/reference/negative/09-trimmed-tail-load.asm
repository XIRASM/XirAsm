region.begin("outer", 0x1000, 0)

emit.u8(0x11)
trimmed:
reserve(1)

output.section("next", 0x2000)
emit.u8(0x22)

defer {
    assert(load.u8(trimmed) == 0)
}

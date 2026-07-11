region.begin("outer", 0x1000, 0)

start:
emit.u16(0x2211)

output.section("inner", 0x2000)

inner:
emit.u16(0x4433)

defer {
    let start = inner
    assert(load.u16(start) == 0x4433)
}

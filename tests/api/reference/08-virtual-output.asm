region.begin("main", 0x7000, 0)
emit.u8(0xaa)

virtual.begin()
assert(region_base() == 0x7001)
assert(here() == 0x7001)
emit.u16(0x1234)
reserve(2)
assert(here() == 0x7005)
virtual.end()

assert(region_base() == 0x7000)
assert(here() == 0x7001)
assert(file_cursor_real() == 1)

virtual.begin(0x9000)
assert(region_base() == 0x9000)
reserve(16)
assert(here() == 0x9010)
virtual.end()

emit.u8(0xbb)

region.begin("header", 0x4000, 0x20)

assert(region_base() == 0x4000)
assert(file_offset() == 0x20)
assert(file_cursor_real() == 0x20)
assert(file_cursor_potential() == 0x20)
assert(tail_reserve_size() == 0)

emit.u8(0x11)
reserve(3)

assert(file_offset() == 0x21)
assert(file_cursor_real() == 0x21)
assert(file_cursor_potential() == 0x24)
assert(tail_reserve_size() == 3)

output.section("trimmed", 0x5000)

assert(region_base() == 0x5000)
assert(file_offset() == 0x21)
assert(file_cursor_real() == 0x21)
assert(file_cursor_potential() == 0x21)
assert(tail_reserve_size() == 0)

emit.u8(0x22)
reserve(2)
output.org("preserved", 0x6000)

assert(region_base() == 0x6000)
assert(file_offset() == 0x24)
assert(file_cursor_real() == 0x24)
assert(file_cursor_potential() == 0x24)
assert(tail_reserve_size() == 0)

emit.u8(0x33)
region.file_align(8)

assert(file_offset() == 0x2c)
assert(file_cursor_real() == 0x2c)
assert(file_cursor_potential() == 0x25)
assert(tail_reserve_size() == 0)

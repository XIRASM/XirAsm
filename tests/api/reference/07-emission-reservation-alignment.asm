emit.u8(0x11)
emit.u16(0x2233)
emit.u32(0x44556677)
emit.u64(0x8899aabbccddeeff)

db(0x10, "AZ", b"BC")
dw(0x1234, 0xabcd)
dd(0x10203040)
dq(0x0102030405060708)

emit.bytes(b"XY")
emit.bytes("Z")

reserve(2)
rb(1)
rw(1)
rd(1)
rq(1)
emit.u8(0x44)

pad(2, 0xaa)
pad(1)
pad_to(here() + 3, 0xbb)
align(16, 0xcc)
emit.u8(0x55)

tail_start:
reserve(5)
tail_end:
assert(tail_end - tail_start == 5)

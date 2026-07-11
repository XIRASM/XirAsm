origin(0x1000);
start:
emit.u8(0x11);
emit.u32(0x22334455);
emit.u64(0x0102030405060708);
pad(2, 0xaa);
align(16, 0xcc);
emit.u8(file_offset());
emit.u8(here() - region_base());
emit.u16(label_addr(start) - region_base());


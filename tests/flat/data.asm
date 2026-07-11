emit.u8(0xeb);
reserve(2);
emit.u8(0xfe);
pad_to(8, 0x90);
virtual.begin(0x9000);
emit.u8(0x11);
virtual.end();
emit.u16(0xaa55);

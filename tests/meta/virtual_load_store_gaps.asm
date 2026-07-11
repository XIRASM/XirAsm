virtual.begin(0x3000);
prefix:
emit.u8(0x10);
reserve(3);
after_reserve:
emit.u16(0x2244);
const after_reserve_raw = load.u16(after_reserve)
store.u16(after_reserve, after_reserve_raw ^ 0x00ff);
align(8, 0);
after_align:
emit.u8(0x33);
const after_align_raw = load.u8(after_align)
store.u8(after_align, after_align_raw | 0x80);
virtual.end();

emit.u16(load.u16(after_reserve));
emit.u8(load.u8(after_align));


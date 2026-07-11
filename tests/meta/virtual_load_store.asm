virtual.begin(0x2000);
data:
emit.u16(0x1234);
const raw = load.u16(data)
store.u16(data, raw | 0x4000);
code:
    ret
const encoded = load.u8(code)
store.u8(code, encoded ^ 0xff);
const encrypted = load.u8(code)
wide32:
emit.u32(0x11223344);
const raw32 = load.u32(wide32)
store.u32(wide32, raw32 ^ 0x01010101);
const changed32 = load.u32(wide32)
wide64:
emit.u64(0x0102030405060708);
const raw64 = load.u64(wide64)
store.u64(wide64, raw64 | 0x8080808080808080);
const changed64 = load.u64(wide64)
virtual.end();

emit.u16(raw | 0x4000);
emit.u8(encrypted);
emit.u32(changed32);
emit.u64(changed64);

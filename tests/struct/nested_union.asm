import("nested_union.inc")

assert(sizeof(Point) == 4);
assert(sizeof(ValueBits) == 4);
assert(sizeof(WinLike) == 7);
assert(sizeof(NaturalBox) == 12);
assert(sizeof(NaturalOdd) == 4);
assert(sizeof(PackedOdd) == 3);

assert(offset_of(WinLike, tag) == 0);
assert(offset_of(WinLike, value) == 2);
assert(offset_of(WinLike, tail) == 6);
assert(offset_of(WinLike, value.bytes.y) == 4);
assert(offset_of(NaturalBox, value) == 4);
assert(offset_of(NaturalBox, tail) == 8);
assert(offset_of(NaturalBox, value.bytes.x) == 4);

const active_bytes: ValueBits = ValueBits { bytes: Point { x: 0x5566, y: 0x7788 } }
const win: WinLike = WinLike { tag: 0xabcd, value: active_bytes, tail: 0xef }
emit.struct(win);

const raw_win: WinLike = WinLike { tag: 1, value: ValueBits { raw: 0xaabbccdd }, tail: 2 }
emit.bytes(pack(raw_win));

const nested_value: ValueBits = ValueBits { bytes: Point { x: 0x0a0b, y: 0x0c0d } }
const natural: NaturalBox = NaturalBox { tag: 1, value: nested_value, tail: 2 }
emit.bytes(pack(natural));

emit.u8(offset_of(WinLike, value.bytes.y));
emit.u8(offset_of(NaturalBox, value.bytes.x));

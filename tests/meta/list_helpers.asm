const empty: list = list.new()
const base: list = list.of(1, 2, 3)
const extended: list = list.push(base, 4)
const patched: list = list.set(extended, 1, 0xaa)
const tail: list = list.slice(patched, 1, 2)
const chunks: list = list.concat(list.of(b"OK"), list.of(bytes.le(0x1234, 2)))

assert(len(empty) == 0);
assert(len(base) == 3);
assert(len(extended) == 4);
assert(len(patched) == 4);
assert(list.get(extended, 0) == 1);
assert(list.get(extended, 3) == 4);
assert(list.eq(tail, list.of(0xaa, 3)));
assert(list.eq(patched, list.of(1, 0xaa, 3, 4)));

for byte in patched {
    emit.u8(byte);
}

for chunk in chunks {
    emit.bytes(chunk);
}

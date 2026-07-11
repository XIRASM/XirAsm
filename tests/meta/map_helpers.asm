const empty: map = map.new()
const cfg0: map = map.set(empty, "arch", "x64")
const cfg1: map = map.set(cfg0, "mode", "release")
const cfg2: map = map.set(cfg1, "arch", "rv64")
const payloads: map = map.set(map.set(map.new(), "first", b"A"), "second", b"B")
const nested: map = map.set(cfg2, "tags", list.of("asm", "dsl"))

assert(len(empty) == 0);
assert(len(cfg1) == 2);
assert(len(cfg2) == 2);
assert(map.has(cfg2, "arch"));
assert(!map.has(cfg2, "missing"));
assert(map.get(cfg0, "arch") == "x64");
assert(map.get(cfg2, "arch") == "rv64");
assert(map.get_or(cfg2, "missing", "fallback") == "fallback");
assert(map.eq(map.set(map.set(map.new(), "a", 1), "b", 2), map.set(map.set(map.new(), "b", 2), "a", 1)));
assert(list.eq(map.get(nested, "tags"), list.of("asm", "dsl")));

const keys: list = map.keys(cfg2)
const values: list = map.values(payloads)

for key in keys {
    emit.u8(len(key));
    emit.bytes(key);
}

for value in values {
    emit.bytes(value);
}

emit.bytes(map.get_or(nested, "missing", b"!"));

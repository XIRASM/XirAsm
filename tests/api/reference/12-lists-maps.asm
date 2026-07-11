const empty_list: list = list.new()
const base: list = list.of(1, 2, 3)
const pushed: list = list.push(base, 4)
const patched: list = list.set(pushed, 1, 0xaa)
const middle: list = list.slice(patched, 1, 2)
const combined: list = list.concat(list.of(0x10, 0x11), list.of(0x12))

assert(len(empty_list) == 0)
assert(list.get(base, 1) == 2)
assert(list.eq(base, list.of(1, 2, 3)))
assert(list.eq(pushed, list.of(1, 2, 3, 4)))
assert(list.eq(patched, list.of(1, 0xaa, 3, 4)))
assert(list.eq(middle, list.of(0xaa, 3)))
assert(list.eq(combined, list.of(0x10, 0x11, 0x12)))

const empty_map: map = map.new()
const with_arch: map = map.set(empty_map, "arch", "x64")
const with_mode: map = map.set(with_arch, "mode", 64)
const updated: map = map.set(with_mode, "arch", "rv64")
const tag: map = map.set(map.new(), "kind", "dsl")
const nested: map = map.set(updated, "tags", list.of("asm", tag))

assert(len(empty_map) == 0)
assert(len(nested) == 3)
assert(map.has(nested, "arch"))
assert(!map.has(nested, "missing"))
assert(map.get(with_arch, "arch") == "x64")
assert(map.get(updated, "arch") == "rv64")
assert(map.get_or(nested, "arch", "fallback") == "rv64")
assert(map.get_or(nested, "missing", "fallback") == "fallback")

const keys: list = map.keys(nested)
const values: list = map.values(nested)

assert(list.eq(keys, list.of("arch", "mode", "tags")))
assert(list.get(values, 0) == "rv64")
assert(list.get(values, 1) == 64)
assert(list.eq(list.get(values, 2), list.of("asm", tag)))

const reordered: map = map.set(
    map.set(
        map.set(map.new(), "tags", list.of("asm", map.set(map.new(), "kind", "dsl"))),
        "mode",
        64
    ),
    "arch",
    "rv64"
)

assert(map.eq(nested, reordered))
assert(!map.eq(nested, map.set(reordered, "mode", 32)))

emit.u8(len(empty_list))

for value in combined {
    emit.u8(value)
}

for value in middle {
    emit.u8(value)
}

for key in keys {
    emit.u8(len(key))
}

emit.u8(map.get(updated, "mode"))
emit.u8(len(values))

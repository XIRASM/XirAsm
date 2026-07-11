const padded: string = "  XIRASM  "
const pieces: list = split("red::green::", "::")
const options: map = map.set(map.new(), "mode", "release")
const first_name: string = sym.unique("_local")
const second_name: string = sym.unique("_local")

assert(lengthof("text") == 4)
assert(lengthof(b"AB") == 2)
assert(lengthof(0) == 1)
assert(lengthof(18446744073709551615) == 20)

assert(len("alpha") == 5)
assert(len(b"ABC") == 3)
assert(len(pieces) == 3)
assert(len(options) == 1)

assert(to_string(42) == "42")
assert(to_string(true) == "true")
assert(to_string("ready") == "ready")
assert(to_string(b"AZ") == "415a")

assert(trim(padded) == "XIRASM")
assert(lower("MiXeD-42") == "mixed-42")
assert(upper("MiXeD-42") == "MIXED-42")
assert(starts_with("xirasm", "xir"))
assert(ends_with("xirasm", "asm"))
assert(contains("xirasm", "ras"))
assert(contains(b"ABC", b"BC"))
assert(replace("one fish, one fish", "one", "two") == "two fish, two fish")

assert(join(pieces, "|") == "red|green|")
assert(sym.join("item_", 12, "_", true, "_", b"AZ") == "item_12_true_415a")

assert(first_name != second_name)
assert(starts_with(first_name, "_local__"))
assert(starts_with(second_name, "_local__"))

db(lower(trim(padded)))
db(0)
db(join(pieces, "|"))
db(0)
db(sym.join("v", 2, "_", true))

label.define(first_name)
emit.u8(0xa1)

label.define(second_name)
emit.u8(0xb2)

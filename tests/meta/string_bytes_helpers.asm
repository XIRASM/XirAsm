const raw_name: string = "  Kernel64  "
const name: string = trim(raw_name)
const lower_name: string = lower(name)
const upper_name: string = upper(lower_name)
const banner: bytes = bytes.from_hex("4b45524e")
const empty: bytes = bytes.new()
const with_tail: bytes = bytes.push(empty, 0x11)
const repeated: bytes = bytes.repeat(2, 0xff)
const little: bytes = bytes.le(0x1234, 2)
const inserted: bytes = bytes.insert(banner, 3, b"!")
const replaced_text: string = replace("a,b,c", ",", "|")
const patched: bytes = bytes.replace(inserted, 4, 1, b"$")
const joined: bytes = bytes.concat(patched, repeated)
const hex_text: string = bytes.hex(banner)
const bytes_ok: bool = bytes.eq(banner, bytes.from_hex("4B45524E"))

assert(len(name) == 8);
assert(lengthof(lower_name) == 8);
assert(upper_name == "KERNEL64");
assert(starts_with(lower_name, "kernel"));
assert(ends_with(lower_name, "64"));
assert(contains(lower_name, "nel"));
assert(contains(banner, b"ER"));
assert(replaced_text == "a|b|c");
assert(to_string(123) == "123");
assert(to_string(banner) == hex_text);
assert(hex_text == "4b45524e");
assert(bytes_ok);

emit.bytes(banner);
emit.u8(len(lower_name));
emit.bytes(joined);
emit.bytes(little);
emit.bytes(with_tail);

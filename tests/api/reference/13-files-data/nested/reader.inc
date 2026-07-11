assert(fs.exists("payload.bin"))
assert(!fs.exists("missing.bin"))

const nested_payload: bytes = fs.read_bytes("payload.bin")
const nested_range: bytes = fs.read_bytes("payload.bin", 1, 3)

assert(len(nested_payload) == 6)
assert(bytes.eq(nested_range, b"BCD"))

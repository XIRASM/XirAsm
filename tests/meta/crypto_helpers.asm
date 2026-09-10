const payload: bytes = b"123456789"
const crc: u64 = crypto.crc32(payload)
const adler: u64 = crypto.adler32(payload)
const text_crc: u64 = crypto.crc32("123456789")
const digest_sha1: bytes = crypto.sha1(b"abc")
const digest_sha256: bytes = crypto.sha256(b"abc")
const empty_sha256: bytes = crypto.sha256(b"")

assert(crc == 0xcbf43926);
assert(adler == 0x091e01de);
assert(text_crc == crc);
assert(bytes.hex(digest_sha1) == "a9993e364706816aba3e25717850c26c9cd0d89d");
assert(bytes.hex(digest_sha256) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
assert(bytes.hex(empty_sha256) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
assert(len(digest_sha1) == 20);
assert(len(digest_sha256) == 32);

emit.u32(crc);
emit.bytes(digest_sha1);

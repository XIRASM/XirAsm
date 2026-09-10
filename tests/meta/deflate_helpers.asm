// api-matrix-fixture: deflate.compress(

// Compression through the engine. The stream is raw DEFLATE, which is exactly
// what a ZIP entry of method 8 carries: no zlib header, no checksum trailer, and
// the caller stores the CRC of the uncompressed bytes itself.
//
// The fixture pins the sizes rather than the bytes: a compressed stream is only
// as stable as the compressor, while "it got smaller" and "the level changed the
// size" are properties of this API. That the bytes really are DEFLATE is checked
// where the archive is read back, by a decompressor that is not this assembler.
const text: bytes = b"XIRASM XIRASM XIRASM XIRASM XIRASM XIRASM XIRASM XIRASM"
const level_default: bytes = deflate.compress(text)
const level_fast: bytes = deflate.compress(text, 1)
const level_best: bytes = deflate.compress(text, 9)
const empty: bytes = deflate.compress(b"")

assert(len(text) == 55);
assert(len(level_default) < len(text));
assert(len(level_fast) < len(text));
assert(len(level_best) < len(text));
assert(len(empty) > 0);

// Incompressible input still has to decode, and it may grow.
const ramp: bytes = bytes.repeat(64, 1)
const ramp_compressed: bytes = deflate.compress(ramp)
assert(len(ramp_compressed) > 0);

// Decompression is the inverse, and the decoder is the same one a ZIP reader
// uses, so a round trip here is what an archive entry relies on.
const restored: bytes = deflate.decompress(level_default)
assert(len(restored) == len(text));
assert(bytes.eq(restored, text));
const restored_empty: bytes = deflate.decompress(empty)
assert(len(restored_empty) == 0);

emit.u16(len(text));
emit.u16(len(level_default));
emit.u16(len(level_fast));
emit.u16(len(level_best));
emit.u16(len(empty));
emit.u16(len(restored));
emit.u16(len(restored_empty));

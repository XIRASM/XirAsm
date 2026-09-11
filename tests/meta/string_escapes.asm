// Escape sequences in string and bytes literals. Each case emits exactly the
// bytes the literal must decode to, so any change in decoding shows up as a
// byte diff rather than as a silently different string.
//
// The last two cases are the rule for everything outside the escape set: the
// backslash is kept, so text that treats it as an ordinary character still
// reads as written.
x86.use64();

emit.bytes(b"a\nb")
emit.u8(0xff)
emit.bytes(b"a\tb")
emit.u8(0xff)
emit.bytes(b"a\rb")
emit.u8(0xff)
emit.bytes(b"a\\b")
emit.u8(0xff)
emit.bytes(b"a\"b")
emit.u8(0xff)
emit.bytes(b"a""b")
emit.u8(0xff)
emit.bytes(b"a\qb")
emit.u8(0xff)
emit.u8(len("\\"))
emit.u8(len("\u0041"))
// `\uXXXX` decodes to the code point, which is why generated platform text
// carries control bytes rather than the six characters that spell them.
emit.bytes(b"\u0041")
emit.u8(0xff)
emit.bytes(b"\u0000\u001e")
emit.u8(0xff)
emit.bytes(b"\u00e9")
emit.u8(0xff)
// A malformed one is not an escape and keeps its characters.
emit.bytes(b"\u41")
emit.u8(0xff)
// A plain string argument is a literal too, so it decodes the same way.
emit.bytes("a\nb")
emit.u8(0xff)
// And an argument that merely starts and ends with a quote is still a
// comparison expression, not one long string.
assert("a" == "a")
assert("a" != "b")

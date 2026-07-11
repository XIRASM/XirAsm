// output.org continues after the potential file cursor, so a reserve before it
// becomes a middle gap once the following area emits initialized bytes.

emit.u8(0x41);
reserve(3);
output.org("next", 0x2000);
emit.u8(0x42);

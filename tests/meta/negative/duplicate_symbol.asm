// The same name defined twice is a duplicate. The message has to say that, not
// repeat the error name back at the reader.
x86.use64();

same:
emit.u8(1)
same:
emit.u8(2)

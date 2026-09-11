// A scratch region is opened and never closed. Nothing on the offending line
// fails while it runs, so the error is only found after the last statement has
// executed: it has to name the line that opened the region, or the reader gets
// an anonymous `assembly failed` with no file and no line to look at.
x86.use64();

virtual.begin(0x3000);
emit.u8(0x11);

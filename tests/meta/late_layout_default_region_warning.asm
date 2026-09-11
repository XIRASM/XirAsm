// A late_layout block starts with the default region active, not the region the
// source was in where the block was written. A block that appends without
// choosing a region therefore writes somewhere other than where the source
// reads, so it says so instead of moving bytes quietly.
x86.use64();

region.begin("text", 0x2000, 0)
entry:
late_layout {
    emit.u8(0xee)
}

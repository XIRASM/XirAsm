// A finalizer patches bytes that are already in the file, so writing past the
// end of the image must name the address, the width, and the file length
// instead of failing with an internal error name and no location.
emit.u8(0xaa)

defer {
    store.u64(0, 0x1122334455667788)
}

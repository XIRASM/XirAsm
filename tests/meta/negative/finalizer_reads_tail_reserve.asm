// `reserve` grows the logical address range but stays out of the raw file, so a
// finalizer cannot read those bytes: the image it patches does not hold them.
emit.u8(0xaa)
reserve(0x100)

defer {
    print(load.u8(1))
}

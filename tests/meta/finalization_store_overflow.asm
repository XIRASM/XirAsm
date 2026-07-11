emit.u8(0);

defer {
    store.u8(region_base(), 0x100);
}
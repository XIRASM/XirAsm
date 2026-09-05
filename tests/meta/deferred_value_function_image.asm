fn read_word(address: u64) -> u64 {
    return load.u32(address)
}

fn patch_here(value: u64) {
    defer {
        store.u32(here(), value)
    }
}

slot:
emit.u32(0)

defer {
    store.u32(slot, 0x12345678)
}

patch_here(0x11223344)

here_target_a:
emit.u32(0)

patch_here(0x55667788)

here_target_b:
emit.u32(0)

defer {
    assert(read_word(slot) == 0x12345678)
    assert(load.u32(here_target_a) == 0x11223344)
    assert(load.u32(here_target_b) == 0x55667788)
}

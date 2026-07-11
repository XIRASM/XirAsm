fn bad() -> u64 {
    emit.u8(1);
    return 1;
}

const y = bad()

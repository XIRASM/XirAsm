fn bad() -> u64 {
    isa("ret");
    return 1;
}

const value = bad()

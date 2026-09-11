// A value function is reached from an expression, where the call-site span has to
// survive into the runtime or the reader gets "an expression is not valid" with no
// counts and no name.
x86.use64();

fn twice(v: u64) -> u64 {
    return v * 2
}

emit.u8(1)
emit.u8(twice())

// A value that does not match the declared parameter type names the argument
// position, the function, and both types. The expression layer keeps only the
// fact that an operand failed, so the runtime has to say this itself.
x86.use64();

fn twice(v: u64) -> u64 {
    return v * 2
}

emit.u8(twice("text"))

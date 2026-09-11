// A value function body that fails has to lead back to the call, exactly like a
// procedure body does: the statement that evaluated the expression is the line
// the reader wrote, so the diagnostic chain has to name it.
x86.use64();

fn checked(v: u64) -> u64 {
    if v == 0 {
        err("zero is not allowed here")
    }
    return v
}

emit.u8(1)
emit.u8(checked(0))

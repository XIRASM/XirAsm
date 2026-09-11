// A library procedure reports its own line, because that is where the failing
// statement is. The reader wrote the call, so the diagnostic chain has to lead
// back to it: the notes name the invocation site in this file as well as the
// procedure's definition.
fn check(value: u64) {
    if value == 0 {
        err("value must not be zero")
    }
}

emit.u8(1)

check(0)

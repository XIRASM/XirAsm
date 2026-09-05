const a: u64 = 1
const b: u64 = 2

fn pair(a: u64, b: u64) {
    db(a, b)
}

fn pair_value(a: u64, b: u64) -> u64 {
    return a * 10 + b
}

fn recursive_pair(a: u64, b: u64) -> u64 {
    if a == 0 {
        return b
    }
    return recursive_pair(a - 1, a + b)
}

fn swap(let a: u64, let b: u64) {
    const old_a = a
    a = b
    b = old_a
}

fn check_local_arguments() {
    let a: u64 = 3
    let b: u64 = 4
    assert(pair_value(b, a) == 43)
    assert(pair_value(b, a + 10) == 53)
    swap(b, a)
    assert(a == 4)
    assert(b == 3)
}

pair(b, a)
db(pair_value(b, a))
assert(a == 1)
assert(b == 2)
assert(recursive_pair(3, 0) == 6)
check_local_arguments()
db(0x1e+1, 0x1e-1, 0X1E+1, 0X1E-1)

// A literal that leaves a field out says which kind of mistake it is, instead of
// reaching the reader as "an expression in this statement is not valid".
x86.use64();

struct Pair {
    left: u32
    right: u32
}

const p: Pair = Pair { left: 1 }

emit.u8(p.left)

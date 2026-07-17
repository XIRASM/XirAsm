origin(0)
x86.use64()
const CONDITION: u64 = 0x9

entry:
    ccmpl CONDITION, rdx, r30

fn increment(n: u64) -> u64 {
    return n + 1
}

macro byte(value) {
    assert(len(operand.text(value)) > 0)
    assert(len(operand.split(value)) == 1)
    const original: operand = operand.slice(value, 0, len(operand.text(value)))
    const LIMIT: u64 = 99
    emit.u8(operand.eval(original))
}

macro twice(value) {
    byte value
    byte value
}

macro many(...values) {
    for item in values {
        byte item
    }
}

const LIMIT: u64 = 7
twice LIMIT + 1
byte increment(LIMIT)
many 1, 2, 3
for i in range(0, 3) {
    byte i
}

macro register_copy(dst, src) {
    mov dst, src
}
register_copy eax, ebx

macro nop() {
    emit.u8(0x90)
}
nop

const value = 1

{
    let value = 2
    value = value + 1
    assert(value == 3)
}

assert(
    value == 1
)

start:
    mov rax, 1

emit.u8(value)

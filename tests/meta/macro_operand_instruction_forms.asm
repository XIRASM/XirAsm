// The forms that do work: a macro parameter used directly in an instruction
// operand is substituted as text, and an expression over it is folded before
// the encoder sees it.
x86.use64();

macro setv(value) {
    mov rax, value
    mov rbx, value + 1
}

setv 42

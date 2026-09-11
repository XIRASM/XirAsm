// A macro parameter is captured operand text. Writing an operand builtin
// straight into an instruction operand leaves a reference the encoder cannot
// turn into bytes, and the failure has to name that text and point at the line
// instead of ending as a bare unresolved-fixup count.
x86.use64();

macro setv(value) {
    mov rax, operand.eval(value)
}

setv 42

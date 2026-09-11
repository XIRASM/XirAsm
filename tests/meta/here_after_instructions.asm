// The current address must account for the instructions written before it. An
// instruction fragment only gets a size when it is encoded, so anything that
// reads the address while lowering needs the cursor made current first; before
// that, `here()` after even one instruction reported zero.
x86.use64();

nop
nop
emit.u32(here())
mov rax, here()
ret

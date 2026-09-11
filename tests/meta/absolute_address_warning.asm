// A 64-bit absolute address cannot fit the 32-bit displacement field this form
// carries, so the encoder cuts it down to that field. That changes which address
// the instruction reads, which is exactly what must not happen quietly.
//
// The bytes are what the reference assembler produces for the same input, and
// the warning is the point: the address reads as 0x0, not as 0x1_0000_0000.
x86.use64();

mov rax, [0x100000000]

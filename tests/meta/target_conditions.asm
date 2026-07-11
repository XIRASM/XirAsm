if target.bits == 64 {
    emit.u8(0x64);
}
if target.bits != 32 {
    emit.u8(0x65);
}
if target.isa == .x86_64 {
    emit.u8(0x86);
}
x86.use32();
if target.bits == 32 {
    emit.u8(0x32);
}
x86.use64();
if target.bits == 64 {
    emit.u8(0x66);
}
riscv.use32();
if target.isa == .riscv64 {
    emit.u8(0x52);
}
if target.bits == 32 {
    emit.u8(0x33);
}
riscv.use64();
if target.bits == 64 {
    emit.u8(0x72);
}

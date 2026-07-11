origin(0x1000)

final_label_field:
emit.u64(0)

if target.isa == .x86_64 {
    emit.u8(0x86)
}
assert(target.bits == 64)

start:
emit.u8(0xaa)

const generated_name = "generated_label"
label.define(generated_name)

assert(here() == 0x100a)
assert(label_addr(start) == 0x1009)
assert(label_addr(generated_name) == 0x100a)

emit.u16(label_addr(start) - 0x1000)
emit.u16(label_addr(generated_name) - 0x1000)

x86.use16()
assert(target.bits == 16)
isa("mov ax, 0x1234")

x86.use32()
assert(target.bits == 32)
isa("mov eax, 0x12345678")

x86.use64()
assert(target.bits == 64)
isa("mov rax, 0x0102030405060708")

riscv.use32()
if target.isa == .riscv64 {
    assert(target.bits == 32)
}
isa("addi x1, x0, 1")

riscv.use64()
if target.isa == .riscv64 {
    assert(target.bits == 64)
}
isa("addi x2, x0, 2")

after_code:

defer {
    store.u64(final_label_field, label_addr(after_code))
    assert(label_addr(after_code) == 0x1028)
}

import("arm/arm64-macros.inc")

const VALUE: u64 = 42
const OFFSET: u64 = 16

macro copy_twice(dst, src) {
    mov dst, src
    mov dst, src
}

start:
nop
movz x0, #VALUE
movk x0, #0x1234, lsl #16
copy_twice x1, x0
add x2, x1, #(VALUE + 1)
sub x3, x2, x1, lsl #2
ldr x4, [x5, #OFFSET]
str x4, [sp, #-16]!
ldr x4, [sp], #16
ldur x6, [x7, #-8]
stp x0, x1, [sp, #-16]
cbz x0, done
b.eq done
b start
done:
ret

defer {
    assert(load.u32(start) == 0xd503201f)
}

riscv.use64();

start:
    addi x1, x0, 1
    addi a0, a1, -2048
    lui t0, 0x12345
    auipc t1, 0x23456
    add a0, a1, a2
    sub a3, a4, a5
    slli t0, t1, 31
    srai t2, t3, 17
    mul a0, a1, a2
    divu a3, a4, a5
    rem a6, a7, s0
    ld a0, -16(sp)
    sd a1, 24(sp)
    beq a0, a1, forward
    bne a2, a3, start
forward:
    jal ra, done
    jalr zero, 0(ra)
done:
    addi zero, zero, 0

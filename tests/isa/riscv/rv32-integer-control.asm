riscv.use32();

start:
    addi x1, x0, 1
    slti a0, a1, -1
    xori a2, a3, 0x5a
    slli t0, t1, 15
    srai t2, t3, 7
    add a0, a1, a2
    sub a3, a4, a5
    mulh a0, a1, a2
    div a3, a4, a5
    remu a6, a7, s0
    lw a0, -16(sp)
    sw a1, 12(sp)
    bltu a0, a1, forward
    bge a2, a3, start
forward:
    jal ra, done
    jalr zero, 0(ra)
done:
    addi zero, zero, 0

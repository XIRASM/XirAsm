riscv.use64();

start:
    c.nop
    c.beqz s0, forward
    c.bnez s1, start
forward:
    c.j done
    c.nop
done:
    c.jr ra

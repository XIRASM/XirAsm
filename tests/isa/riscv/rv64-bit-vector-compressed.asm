riscv.use64();

andn a0, a1, a2
orn a3, a4, a5
xnor a6, a7, s0
clz t0, t1
ctz t2, t3
cpop a0, a1
sh1add a2, a3, a4
bset a5, a6, a7
ror s0, s1, s2
vsetvli t0, a2, e8, m8, ta, ma
vle8.v v0, (a1)
vse8.v v0, (a0)
vadd.vv v1, v2, v3
vadd.vx v4, v5, a0, v0.t
c.addi s0, 1
c.mv s1, a0
c.jr ra
c.nop

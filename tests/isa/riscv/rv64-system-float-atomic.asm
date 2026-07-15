riscv.use64();

fence rw, rw
fence.i
ecall
ebreak
csrrw t0, mstatus, t1
csrrsi t1, mie, 3
amoadd.w.aqrl a0, a1, (a2)
lr.d.aq a3, (a4)
sc.d.rl a5, a6, (a7)
flw fa0, 16(sp)
fsw fa1, 20(sp)
fadd.s fa0, fa1, fa2, rne
fmadd.d fa3, fa4, fa5, fa6, rtz
fcvt.w.s a0, fa0, rtz
fclass.d a1, fa1

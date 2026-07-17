origin(0x80000000)
x86.use64()

entry:
    cmp qword [rel slot], target
target:
    ret
slot:
    dq(0)

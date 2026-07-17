origin(0x10000)
x86.use64()

entry:
    add ax, target
target:
    ret

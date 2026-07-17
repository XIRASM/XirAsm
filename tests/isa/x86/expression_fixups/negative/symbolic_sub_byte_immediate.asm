origin(0)
x86.use64()

entry:
    ccmpl target, rdx, r30
target:
    ret

origin(0)
x86.use64()

entry:
    jne short too_far
    for i in range(0, 128) {
        nop
    }
too_far:
    ret

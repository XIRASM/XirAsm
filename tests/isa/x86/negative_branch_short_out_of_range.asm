origin(0x3000)
x86.use64()

entry:
    jmp short too_far
    for i in range(0, 128) {
        nop
    }
too_far:
    ret

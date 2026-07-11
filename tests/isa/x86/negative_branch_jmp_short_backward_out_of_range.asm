origin(0)
x86.use64()

target:
    ret
    for i in range(0, 126) {
        nop
    }
    jmp short target

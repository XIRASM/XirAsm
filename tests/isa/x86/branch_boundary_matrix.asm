origin(0x3000)
x86.use64()

entry:
    jmp short short_forward_min
short_forward_min:
    nop
    jmp short short_forward_max
    for i in range(0, 127) {
        nop
    }
short_forward_max:
    nop
short_back_base:
    for i in range(0, 126) {
        nop
    }
    jmp short short_back_base
    jmp near near_target + 1
    call near_target + 2
    jne near_target + 3
    nop
near_target:
    ret

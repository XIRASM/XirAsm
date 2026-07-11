origin(0)
x86.use64()

entry:
    jmp short jmp_fwd_127
    for i in range(0, 127) {
        nop
    }
jmp_fwd_127:
    jmp near jmp_fwd_128
    for i in range(0, 128) {
        nop
    }
jmp_fwd_128:
    jne short jcc_fwd_127
    for i in range(0, 127) {
        nop
    }
jcc_fwd_127:
    jne near jcc_fwd_128
    for i in range(0, 128) {
        nop
    }
jcc_fwd_128:
    call call_fwd_127
    for i in range(0, 127) {
        nop
    }
call_fwd_127:
    call call_fwd_128
    for i in range(0, 128) {
        nop
    }
call_fwd_128:
    ret

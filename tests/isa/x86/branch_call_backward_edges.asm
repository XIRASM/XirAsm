origin(0)
x86.use64()

jmp_back_128:
    for i in range(0, 126) {
        nop
    }
    jmp short jmp_back_128
jmp_back_129:
    for i in range(0, 124) {
        nop
    }
    jmp near jmp_back_129
jcc_back_128:
    for i in range(0, 126) {
        nop
    }
    jne short jcc_back_128
jcc_back_129:
    for i in range(0, 123) {
        nop
    }
    jne near jcc_back_129
call_back_128:
    for i in range(0, 123) {
        nop
    }
    call call_back_128
call_back_129:
    for i in range(0, 124) {
        nop
    }
    call call_back_129

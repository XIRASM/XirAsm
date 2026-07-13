origin(0)
x86.use64()

const SOME_CONST: u64 = 7
const FIELD_OFFSET: u64 = 8

state:
    emit.u64(0)
    emit.u64(0)
state_end:

thunk_table:
    emit.u64(0)
    emit.u64(0)

entry:
    cmp rdx, SOME_CONST
    mov eax, [rel state + FIELD_OFFSET]
    mov ecx, [rel state_end - FIELD_OFFSET]
    lea rbx, [rel state_end - FIELD_OFFSET]
    cmp qword [rel state + FIELD_OFFSET], -1
    cmp dword [rel state_end - FIELD_OFFSET], 0
    call qword [rel thunk_table + FIELD_OFFSET]
    jmp qword [rel thunk_table]
    ret

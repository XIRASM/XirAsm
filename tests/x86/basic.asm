origin(0x7c00);
start:
    mov rax, 1 // ISA instructions accept XIRASM line comments.
    add rax, 2 // Comments do not reach the x86 backend operand parser.
    ret

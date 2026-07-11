origin(0)
x86.use16()

entry:
    mov ax, [bx+si]
    mov ax, [bx+di]
    mov ax, [bp+si]
    mov ax, [bp+di]
    mov ax, [si]
    mov ax, [di]
    mov ax, [bp]
    mov ax, [bx]
    mov ax, [bx+si+127]
    mov ax, [bx+si+128]
    mov ax, [bx+si-128]
    mov ax, [bx+si-129]

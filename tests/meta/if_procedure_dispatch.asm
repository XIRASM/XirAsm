origin(0)
x86.use64()

fn emit_read_mode() {
    mov eax, 0x11
}

fn emit_write_mode() {
    mov eax, 0x22
}

fn emit_poison_mode() {
    int3
}

fn dispatch_io_mode(kind: string) {
    if kind == "read" {
        emit_read_mode();
    } else {
        if kind == "write" {
            emit_write_mode();
        } else {
            emit_poison_mode();
        }
    }
}

entry:
dispatch_io_mode("read");
dispatch_io_mode("write");
ret

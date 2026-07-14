import("io/windows.inc");
x86.use64();

io_read_stdin_label("input_buffer", 0x100000000);

input_buffer:
    db(0);

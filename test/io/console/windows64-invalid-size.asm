import("io/windows.inc");
x86.use64();

io_write_stdout_label("message", 0x100000000);
message:
    db(0);

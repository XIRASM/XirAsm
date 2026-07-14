// 编译期契约测试：单次文件传输不能超过 32 位 WinAPI 长度。

import("io/windows.inc");
x86.use64();

io_file_write_label("data", 0x100000000);
data:
    db(0);

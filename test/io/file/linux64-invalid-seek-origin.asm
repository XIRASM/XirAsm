// 编译期契约测试：seek origin 只能是 begin/current/end。

import("io/linux.inc");
x86.use64();

io_file_seek(3);

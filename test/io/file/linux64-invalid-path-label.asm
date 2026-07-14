// 编译期契约测试：路径标签不能为空。

import("io/linux.inc");
x86.use64();

io_file_open_read_label("");

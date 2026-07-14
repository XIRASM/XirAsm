// Linux x86-64 whole-file 编译期负例：load 标签包装拒绝空缓冲区标签。

import("format/format.inc");
import("io/linux.inc");
x86.use64();

io_file_load_label("path0", "", 1);

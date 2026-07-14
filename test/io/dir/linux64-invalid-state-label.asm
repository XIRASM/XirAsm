// Linux x86-64 dir 编译期负例：标签包装拒绝空状态块标签。

import("format/format.inc");
import("io/linux.inc");
x86.use64();

io_dir_open_label("", "dir_path");

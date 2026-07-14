// Windows x64 dir 编译期负例：标签包装拒绝空路径标签。

import("format/format.inc");
import("io/windows.inc");
x86.use64();

io_dir_open_label("dir_state", "");

// Linux x86-64 map 编译期负例：标签包装拒绝零长度映射。

import("format/format.inc");
import("io/linux.inc");
x86.use64();

io_map_create_label("state0", "path0", 0);

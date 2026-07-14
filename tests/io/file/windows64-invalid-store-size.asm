// Windows x64 whole-file 编译期负例：store 标签包装拒绝超过便携上限的大小。

import("format/format.inc");
import("io/windows.inc");
x86.use64();

io_file_store_label("path0", "data0", io_max_transfer_size + 1);

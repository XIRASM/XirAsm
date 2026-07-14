// Windows stream 编译期负例：调用方缓冲区容量必须大于 0。

import("io/windows.inc");
x86.use64();

io_stream_open_read_label("stream_state", "file_path", "stream_buffer", 0);

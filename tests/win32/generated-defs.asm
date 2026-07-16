import("os/win32/defs/foundation.inc")

assert(win32_Foundation_MAX_PATH == 260)
assert(win32_Foundation_INVALID_HANDLE_VALUE == 0xffffffff)
assert(win32_Foundation_POINT_size32 == 8)
assert(win32_Foundation_POINT_size64 == 8)
assert(win32_Foundation_POINT_field_y_offset64 == 4)
assert(win32_Foundation_FILETIME_size32 == 8)
assert(win32_Foundation_FILETIME_size64 == 8)
assert(win32_Foundation_FILETIME_field_dwHighDateTime_offset32 == 4)
assert(win32_Foundation_FILETIME_field_dwHighDateTime_offset64 == 4)
assert(win32_Foundation_WIN32_ERROR_WAIT_FAILED == 0xffffffff)
assert(sizeof(win32_Foundation_POINT32) == win32_Foundation_POINT_size32)
assert(sizeof(win32_Foundation_POINT64) == win32_Foundation_POINT_size64)
assert(offset_of(win32_Foundation_POINT64, y) == win32_Foundation_POINT_field_y_offset64)

const point: win32_Foundation_POINT64 = win32_Foundation_POINT64 {
    x: 1,
    y: 2
}

emit.struct(point)
emit.u8(0x57)

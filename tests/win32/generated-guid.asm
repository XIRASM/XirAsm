import("os/win32/guid.inc")
import("os/win32/comdefs/ui_shell.inc")

const iid_taskbar: bytes = win32_guid(
    0x56fdf342,
    0xfd6d,
    0x11d0,
    0x958a,
    0x006097c9a090
)

assert(win32_com_UI_Shell_ITaskbarList_iid_text == "56fdf342-fd6d-11d0-958a-006097c9a090")
assert(win32_com_UI_Shell_TaskbarList_clsid_text == "56fdf344-fd6d-11d0-958a-006097c9a090")
assert(bytes.eq(iid_taskbar, win32_com_UI_Shell_ITaskbarList_iid_bytes))

emit.bytes(iid_taskbar)
emit.bytes(win32_com_UI_Shell_TaskbarList_clsid_bytes)

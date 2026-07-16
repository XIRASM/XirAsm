import("format/com64.inc")
import("os/win32/comdefs/system_com.inc")

assert(win32_com_System_Com_IUnknown_method_count64 == 3)
assert(win32_com_System_Com_IUnknown_QueryInterface_offset64 == 0)
assert(win32_com_System_Com_IUnknown_AddRef_offset64 == 8)
assert(win32_com_System_Com_IUnknown_Release_offset64 == 16)

start:
    xor ecx, ecx
    com64_call_rcx(win32_com_System_Com_IUnknown_AddRef_offset64)
    ret

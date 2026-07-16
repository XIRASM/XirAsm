import("format/com32.inc")
import("os/win32/comdefs/system_com.inc")

assert(win32_com_System_Com_IUnknown_method_count32 == 3)
assert(win32_com_System_Com_IUnknown_QueryInterface_offset32 == 0)
assert(win32_com_System_Com_IUnknown_AddRef_offset32 == 4)
assert(win32_com_System_Com_IUnknown_Release_offset32 == 8)

start:
    push 2
    push 1
    xor eax, eax
    com32_call_eax(win32_com_System_Com_IUnknown_QueryInterface_offset32)
    ret

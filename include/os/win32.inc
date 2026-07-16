// Common Win32 metadata convenience import for XIRASM.
// Use os/win32/imports.inc, defs.inc, or comdefs.inc for full catalogs.
// Import partitioned files directly when only one DLL or namespace is needed.

import("os/win32/guid.inc")

import("os/win32/imports/kernel32.inc")
import("os/win32/imports/user32.inc")
import("os/win32/imports/advapi32.inc")
import("os/win32/imports/shell32.inc")
import("os/win32/imports/gdi32.inc")
import("os/win32/imports/ole32.inc")
import("os/win32/imports/oleaut32.inc")
import("os/win32/imports/ntdll.inc")

import("os/win32/defs/foundation.inc")
import("os/win32/defs/storage_filesystem.inc")
import("os/win32/defs/system_console.inc")
import("os/win32/defs/system_diagnostics_debug.inc")
import("os/win32/defs/system_memory.inc")
import("os/win32/defs/system_processstatus.inc")
import("os/win32/defs/system_threading.inc")

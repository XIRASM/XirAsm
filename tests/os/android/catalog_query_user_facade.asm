// The lookup side of the catalog: asking it about a symbol by name, which is what
// tooling and diagnostics do ("which library provides this", "from which API",
// "is it in the ABI I target").
//
// The same data drives os/android/imports/*.inc for normal use; this fixture
// checks the runtime queries against the generated table.
//
// api-matrix-fixture: android_symbol_library(
// api-matrix-fixture: android_symbol_libraries(
// api-matrix-fixture: android_symbol_library_api(
// api-matrix-fixture: android_symbol_min_api(
// api-matrix-fixture: android_symbol_available_at(
// api-matrix-fixture: android_symbol_abis(
// api-matrix-fixture: android_symbol_version(
// api-matrix-fixture: android_symbol_kind(

import("os/android/catalog.inc");
import("os/android/imports/libnativewindow.inc");

const syms: map = android_symbols()

assert(android_symbol_library(syms, "__android_log_write") == "liblog.so", "the log symbol must come from liblog");
assert(android_symbol_library(syms, "glClearColor") == "libGLESv1_CM.so", "library order decides the first provider");
assert(len(android_symbol_libraries(syms, "glClearColor")) == 3, "glClearColor lives in three GLES libraries");
assert(android_symbol_min_api(syms, "ANativeWindow_acquire") == 21, "the earliest provider decides");
assert(android_symbol_library_api(syms, "ANativeWindow_acquire", "libnativewindow.so") == 26, "libnativewindow arrived later");
assert(android_symbol_library_api(syms, "ANativeWindow_acquire", "libandroid.so") == 21, "libandroid had it first");
assert(android_symbol_min_api(syms, "dlvsym") == 24, "dlvsym arrived with API 24");
assert(android_import_nativewindow_min_api == 26, "libnativewindow itself arrived with API 26");
assert(android_symbol_available_at(syms, "dlvsym", 24), "dlvsym is available at API 24");
assert(android_symbol_available_at(syms, "dlvsym", 21) == false, "dlvsym is not available at API 21");
assert(android_symbol_abis(syms, "__aeabi_memcpy") == 2, "ARM EABI helpers are 32-bit ARM only");
assert(android_symbol_abis(syms, "__android_log_write") == 31, "the log symbol is on every catalogued ABI");
assert(android_symbol_version(syms, "dlopen") == "LIBC", "dlopen carries the LIBC version tag");
assert(android_symbol_kind(syms, "glClear") == "func", "glClear is a function");

// Emit the answer as a byte so the fixture has an output to pin: dlvsym needs
// API 24, so this byte is 24.
db(android_symbol_min_api(syms, "dlvsym"));

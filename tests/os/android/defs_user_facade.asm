// Android platform constants and structure layouts, generated from the NDK
// headers: os/android/defs/*.inc carries the enumerators the headers declare and
// the byte offsets of the structures they define, so a source never counts a
// field by hand again.
//
// The offsets used here are what the demo installs its callbacks with, and
// tests/os/validate_android_constants.py compiles every one of them against the
// NDK headers as a _Static_assert for both data models.
//
// api-matrix-fixture: format_elf64_so_aarch64(
// api-matrix-fixture: format_elfso_export_many_mut(
// api-matrix-fixture: format_elfso_tables_mut(

import("format/format.inc");
import("os/android/defs/native_activity.inc");
import("os/android/defs/native_window.inc");
import("os/android/defs/input.inc");
import("os/android/defs/keycodes.inc");
import("arm/a64-macros.inc");

// The callback table sits at the front of ANativeActivity, and its entries are
// declared in a fixed order.
assert(android_layout_ANativeActivity_callbacks_offset64 == 0, "callbacks is the first field");
assert(android_layout_ANativeActivity_size64 == 80, "ANativeActivity is 80 bytes on 64-bit ABIs");
assert(android_layout_ANativeActivity_size32 == 40, "and 40 bytes on 32-bit ones");
assert(android_layout_ANativeActivityCallbacks_onDestroy_offset64 == 40, "onDestroy is the fifth pointer");
assert(android_layout_ANativeActivityCallbacks_onDestroy_offset32 == 20, "and the fifth pointer on 32-bit");
assert(android_layout_ANativeActivityCallbacks_onNativeWindowCreated_offset64 == 56, "created is the eighth");
assert(android_layout_ANativeActivityCallbacks_size64 == 128, "sixteen pointers on 64-bit ABIs");

// A buffer's fields, which a renderer reads after ANativeWindow_lock.
assert(android_layout_ANativeWindow_Buffer_width_offset64 == 0, "width comes first");
assert(android_layout_ANativeWindow_Buffer_stride_offset64 == 8, "stride follows the two dimensions");
assert(android_layout_ANativeWindow_Buffer_format_offset64 == 12, "then the format");
assert(android_layout_ANativeWindow_Buffer_bits_offset64 == 16, "and the pixel pointer");
assert(android_layout_ANativeWindow_Buffer_size64 == 48, "48 bytes on 64-bit ABIs");

// Enumerators from three more headers, to keep the fixtures on more than one file.
assert(android_native_window_WINDOW_FORMAT_RGBA_8888 == 1, "the legacy RGBA format");
assert(android_input_AINPUT_EVENT_TYPE_MOTION == 2, "motion events are type 2");
assert(android_input_AMOTION_EVENT_ACTION_MASK == 255, "the action mask");
assert(android_keycodes_AKEYCODE_HOME == 3, "the home key");

let image: map = format_elf64_so_aarch64(
    "libdefs.so",
    list.of(
        format_segment(".text", format_load | format_readable | format_executable)
    )
)
let exports: list = format_elfso_export_new()
format_elfso_export_many_mut(exports, list.of("ANativeActivity_onCreate"), ".text", 20)
format_elfso_tables_mut(image, exports, format_elfso_import_new())
format_begin(image);
format_segment_begin(image, ".text");
ANativeActivity_onCreate:
    ldr x1, [x0]
    adrp x2, defs_callback
    add x2, x2, :lo12:defs_callback
    str x2, [x1, #android_layout_ANativeActivityCallbacks_onDestroy_offset64]
    ret
defs_callback:
    ret
// The key code travels with the image so the generated constants are part of the
// product, not just of the assertions above.
db(android_keycodes_AKEYCODE_HOME);
db(android_input_AINPUT_EVENT_TYPE_MOTION);
format_segment_end(image, ".text");
format_finish(image);

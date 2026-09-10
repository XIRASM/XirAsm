# XIRASM Android Includes

[简体中文](README.zh-CN.md)

These includes carry the Android platform symbol catalog: which platform library
provides a symbol, the first API level it appears in, and the ABIs that have it.
The table is generated from the NDK stub libraries (release r27d) and covers 25
libraries, 4137 symbols and 4416 symbol/library rows across API 21 to 35 and five
ABIs. Counts, provenance and a digest of the exact stub files are in
`catalog/manifest.json`.

The point of the catalog is that a source never spells a platform library name by
hand: the generated helper welds the library onto the import list, so a symbol
cannot be imported from a library that does not export it.

## Choose What to Import

For a small source scan, import only the libraries the program uses:

```asm
import("format/format.inc")
import("os/android/imports/libandroid.inc")
import("os/android/imports/libEGL.inc")
import("os/android/imports/libGLESv2.inc")
```

`import("os/android.inc")` is a convenient starter containing libandroid, liblog,
libEGL, libGLESv2, libGLESv3, libm, libdl and libz. `imports.inc` imports all 25
libraries, and `catalog.inc` exposes the lookup queries; ordinary sources should
import the library files they use.

## Add Platform Imports to a Shared Object

Each library file exposes one name constant per symbol plus two procedures, one
per import mechanism, and the target picks the right one:

| Procedure | Import mechanism |
| --- | --- |
| `android_import_<alias>_add_mut(imports, names)` | x86-64: a `.plt` stub with a `.got.plt` slot and `R_X86_64_JUMP_SLOT`; call it as `call <symbol>_plt` |
| `android_import_<alias>_add_slots_mut(imports, names)` | AArch64: a `.got` slot with `R_AARCH64_GLOB_DAT`; call it as `ldr x8, <symbol>` then `blr x8` |

The alias is the soname without its `lib` prefix and `.so` suffix, lowercased:
`libGLESv2.so` is `glesv2`, `libandroid.so` is `android`.

```asm
// x86-64
import("os/android/imports/liblog.inc")
import("os/android/imports/libGLESv2.inc")

let imports: list = format_elfso_import_new()
android_import_log_add_mut(imports, list.of(android_import_log___android_log_write))
android_import_glesv2_add_mut(imports, list.of(
    android_import_glesv2_glClearColor,
    android_import_glesv2_glClear))
```

```asm
// AArch64: the same selection through GOT slots, inside a shared object
import("format/format.inc")
import("os/android/imports/libGLESv2.inc")
import("arm/a64-macros.inc")

let image: map = format_elf64_so_aarch64(
    "libclear.so",
    list.of(format_segment(".text", format_load | format_readable | format_executable))
)
let exports: list = format_elfso_export_new()
format_elfso_export_many_mut(exports, list.of("ANativeActivity_onCreate"), ".text", 12)
let imports: list = format_elfso_import_new()
android_import_glesv2_add_slots_mut(imports, list.of(
    android_import_glesv2_glClearColor,
    android_import_glesv2_glClear))
format_elfso_tables_mut(image, exports, imports)
format_begin(image);
format_segment_begin(image, ".text");
ANativeActivity_onCreate:
    ldr x8, glClearColor
    blr x8
    ret
format_segment_end(image, ".text");
format_finish(image);
```

The import slot carries the symbol name, so the call site loads that slot and
branches to it. Both procedures append to the same import list, so a library can
be added in one call per library and the emitted `DT_NEEDED`, dynamic symbol table
and relocations follow from it. A larger worked example -- the GLES2 renderer for
both ABIs, packaged as an APK -- is `tests/format/android_gl_demo/`.

## Look a Symbol Up by Name

Tooling and diagnostics can ask the catalog instead of importing a library file:

```asm
import("os/android/catalog.inc")

const syms: map = android_symbols()
const library: string = android_symbol_library(syms, "__android_log_write")
const api: u64 = android_symbol_min_api(syms, "__android_log_write")
const now: bool = android_symbol_available_at(syms, "dlvsym", 24)
const early: bool = android_symbol_available_at(syms, "dlvsym", 21)
assert(library == "liblog.so", "liblog provides __android_log_write");
assert(api == 21, "__android_log_write appears in API 21");
assert(now, "dlvsym appears in API 24");
assert(!early, "dlvsym is not available in API 21");
```

Loading the table is deferred until the first query reads it, and one load
answers any number of queries. The queries are
`android_symbol_library`, `android_symbol_libraries`, `android_symbol_min_api`,
`android_symbol_library_api`, `android_symbol_available_at`, `android_symbol_abis`,
`android_symbol_version` and `android_symbol_kind`; `android_catalog_meta()`
returns the `[meta]` table.

## API Levels

Every symbol records the first API level in which the stubs declare it. Each
library file exposes that level for the library itself, which is what a project
usually has to compare against its minimum SDK:

```asm
import("os/android/imports/libGLESv2.inc")

assert(android_import_glesv2_min_api <= 26, "libGLESv2 is newer than the project's minimum SDK");
```

Read the same fact for one symbol with `android_symbol_min_api(syms, name)` or
`android_symbol_available_at(syms, name, min_sdk)`.

## Constants and Structure Offsets

The same headers declare the enumerators a native program passes to the platform
(window formats, event actions, key codes, asset modes) and the structures the
platform hands back. `defs/*.inc` carries both, one file per header, so a source
neither spells a magic number nor counts a structure field by hand.

```asm
import("os/android/defs/native_activity.inc")
import("os/android/defs/native_window.inc")
import("arm/a64-macros.inc")

// ANativeActivityCallbacks: sixteen function pointers, in declaration order.
str x2, [x1, #android_layout_ANativeActivityCallbacks_onDestroy_offset64]

// The buffer ANativeWindow_lock fills, read back field by field.
ldr w3, [x0, #android_layout_ANativeWindow_Buffer_width_offset64]
ldr w4, [x0, #android_layout_ANativeWindow_Buffer_height_offset64]
ldr w5, [x0, #android_layout_ANativeWindow_Buffer_format_offset64]

assert(android_native_window_WINDOW_FORMAT_RGBA_8888 == 1, "the legacy RGBA format");
```

Naming:

| Surface | Pattern |
| --- | --- |
| Enumerator or macro | `android_<header>_<NAME>` |
| Structure size | `android_layout_<Struct>_size64` / `_size32` |
| Field offset | `android_layout_<Struct>_<field>_offset64` / `_offset32` |

The `64` and `32` suffixes are the two Android data models (LP64 for arm64 and
x86-64, ILP32 for armv7 and i686); a structure whose members are pointers or
`size_t` is a different size in each. Members of an anonymous `struct` or `union`
are reported on the outer structure, the way C11 makes them accessible.

Every number is checked against clang: `tests/os/validate_android_constants.py`
rewrites the generated partitions as `_Static_assert`s, includes the NDK headers
and compiles them for both data models, so a value that the headers do not imply
fails there rather than in a program months later. `defs.inc` imports every
partition; ordinary sources import the headers they use.

## What the Catalog Is Not

- **A device exports more than the catalog lists.** The stubs are a link-time
  view and a curated subset: on Android 15, liblog exports 63 symbols where the
  catalog names 18, and libGLESv2 exports 846 where the catalog names 204. A
  symbol missing here is therefore not proof that no device provides it.
- **A few catalogued symbols are not exported at run time.** The stub of libz
  declares internals that the platform library keeps private. On the Android 15
  images used during development the entries concerned are the eight libz
  internals (`_dist_code`, `_length_code`, `_tr_align`, `_tr_flush_bits`,
  `_tr_flush_block`, `_tr_init`, `_tr_stored_block`, `_tr_tally`),
  `vkGetImageSubresourceLayout2EXT` in libvulkan and
  `eglCreateNativeClientBufferANDROID` in libEGL. Importing one of them fails the
  load of the whole library, in both ABIs, because the loader binds imports
  before the first instruction runs.
- **Check a target device instead of assuming.** Copy that device's own
  libraries out and compare their exports against the catalog:

  ```powershell
  python tests/os/check_catalog_vs_device.py --catalog include/os/android `
      --device-libs <directory of copied libraries> --abi arm64 --llvm-nm <path to llvm-nm>
  ```

  `--abi` matters: a library file per ABI directory, so compare an ARM64 device
  against the ARM64 copy. For the Android 15 images used here, 3906 of 3916
  catalogued symbols were exported for both x86_64 and ARM64 (99.74%), with the
  entries above as the only gaps.
- **A load-time check is cheap.** `tests/os/make_android_smoke.py` writes a source
  that imports a sample from every library, so assembling and loading it checks the
  symbol-to-library mapping on the device in one shot. `--only-libraries` restricts
  the sample to libraries the device actually has, and `--avoid` skips symbols it
  does not export.
- **One symbol, several libraries.** 212 symbols are provided by more than one
  library (`glClearColor` is in GLESv1, GLESv2 and GLESv3). An import slot is
  keyed by symbol name, so a single import list can only pick one provider; the
  catalog lists every provider and the choice is the program's.

## Naming Summary

| Surface | Pattern |
| --- | --- |
| Library soname | `android_import_<alias>_so` |
| Library API level | `android_import_<alias>_min_api` |
| Symbol name | `android_import_<alias>_<Symbol>` |
| Add imports, x86-64 | `android_import_<alias>_add_mut(imports, names)` |
| Add imports, AArch64 | `android_import_<alias>_add_slots_mut(imports, names)` |
| Query by name | `android_symbol_library(syms, name)` and friends in `catalog.inc` |

See `NOTICE.md` for the data source and license, and `catalog/manifest.json` for
the counts, the scanned API range and the digest of the stub files used.

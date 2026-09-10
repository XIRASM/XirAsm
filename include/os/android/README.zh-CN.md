# XIRASM 安卓平台 include

[English](README.md)

这套 include 提供**安卓平台符号目录**：某个符号由哪个平台库提供、它从哪个 API 级别开始
可用、哪些 ABI 有它。目录由 NDK 的 stub 库（r27d）生成，覆盖 **25 个库、4137 个符号、
4416 条（符号, 库）记录**，范围是 API 21–35 与 5 个 ABI；计数、来源与所用 stub 文件的摘要
记在 `catalog/manifest.json`。

目录的用处是：**源码里永远不用手打平台库名** —— 生成的辅助函数把库名焊在导入列表上，
因此不可能把符号挂到一个并不导出它的库上。

## 按需导入

源码只用到哪几个库，就只 import 哪几个：

```asm
import("format/format.inc")
import("os/android/imports/libandroid.inc")
import("os/android/imports/libEGL.inc")
import("os/android/imports/libGLESv2.inc")
```

`import("os/android.inc")` 是便利入口（libandroid、liblog、libEGL、libGLESv2、libGLESv3、
libm、libdl、libz）；`imports.inc` 一次导入全部 25 个库；`catalog.inc` 是对外查询入口。
日常源码应当只 import 自己用到的库文件。

## 把平台导入挂到共享对象上

每个库文件为符号提供一条名字常量，外加**两个辅助函数**（对应两种导入机制，由目标决定用哪个）：

| 辅助函数 | 导入机制 |
| --- | --- |
| `android_import_<别名>_add_mut(imports, names)` | x86-64：`.plt` 桩 + `.got.plt` 槽位 + `R_X86_64_JUMP_SLOT`；调用写法 `call <符号>_plt` |
| `android_import_<别名>_add_slots_mut(imports, names)` | AArch64：`.got` 槽位 + `R_AARCH64_GLOB_DAT`；调用写法 `ldr x8, <符号>` 然后 `blr x8` |

别名 = soname 去掉 `lib` 前缀与 `.so` 后缀再转小写：`libGLESv2.so` → `glesv2`、
`libandroid.so` → `android`。

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
// AArch64：同一个选择，走 GOT 槽位，放进一个共享对象里
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

导入槽用符号名做标签，所以调用点就是"取那个槽、跳过去"。两个辅助函数都往同一个导入列表里
追加，所以**每个库一次调用**即可；产物的 `DT_NEEDED`、动态符号表与重定位都由这个列表推出。
更大的例子（两个 ABI 的 GLES2 渲染器 + 打成 APK）在 `tests/format/android_gl_demo/`。

## 按名字查符号

工具与诊断可以不 import 任何库文件，直接查目录：

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

数据表**第一次查询时才解析**，一次解析可回答任意多次查询。可用的查询有
`android_symbol_library`、`android_symbol_libraries`、`android_symbol_min_api`、
`android_symbol_library_api`、`android_symbol_available_at`、`android_symbol_abis`、
`android_symbol_version`、`android_symbol_kind`；`android_catalog_meta()` 返回 `[meta]` 表。

## API 级别

每个符号记录它**首次出现**的 API 级别。每个库文件另外给出该库自身的级别，工程通常用它
和 minSdk 对比：

```asm
import("os/android/imports/libGLESv2.inc")

assert(android_import_glesv2_min_api <= 26, "libGLESv2 is newer than the project's minimum SDK");
```

单个符号的同一事实用 `android_symbol_min_api(syms, name)`，或直接用
`android_symbol_available_at(syms, name, min_sdk)` 判断。

## 常量与结构体偏移

同一批头文件还声明了原生程序要传给平台的**枚举常量**（窗口格式、事件动作、键码、asset 模式），
以及平台**回传给你的结构体**。`defs/*.inc` 把两者都收编了，一个头文件一个文件，源码里既不用
写魔法数字，也不用自己数字段。

```asm
import("os/android/defs/native_activity.inc")
import("os/android/defs/native_window.inc")
import("arm/a64-macros.inc")

// ANativeActivityCallbacks：十六个函数指针，按声明顺序排布
str x2, [x1, #android_layout_ANativeActivityCallbacks_onDestroy_offset64]

// ANativeWindow_lock 填好的缓冲区，逐字段读回
ldr w3, [x0, #android_layout_ANativeWindow_Buffer_width_offset64]
ldr w4, [x0, #android_layout_ANativeWindow_Buffer_height_offset64]
ldr w5, [x0, #android_layout_ANativeWindow_Buffer_format_offset64]

assert(android_native_window_WINDOW_FORMAT_RGBA_8888 == 1, "the legacy RGBA format");
```

命名规则：

| 表面 | 形式 |
| --- | --- |
| 枚举成员或宏 | `android_<头文件>_<名字>` |
| 结构体大小 | `android_layout_<Struct>_size64` / `_size32` |
| 字段偏移 | `android_layout_<Struct>_<字段>_offset64` / `_offset32` |

`64` / `32` 后缀是安卓的两种数据模型（arm64 与 x86-64 是 LP64，armv7 与 i686 是 ILP32）；
成员里有指针或 `size_t` 的结构体，两者大小不同。匿名 `struct`/`union` 的成员按 C11 的规则
**报在外层结构体上**（`event->x` 这样直接可访问）。

每个数字都经过 clang 核对：`tests/os/validate_android_constants.py` 会把生成的分区改写成
`_Static_assert`，包含 NDK 头文件后按两种数据模型各编译一遍 —— 头文件推不出来的值会当场失败，
而不是几个月后在程序里炸。`defs.inc` 一次导入全部分区；日常源码只 import 自己用到的头文件。

## 目录不是设备全量（重要）

- **设备导出的比目录列的多。** stub 是**链接期视图**且是精选子集：Android 15 上 liblog
  实际导出 63 个符号，目录里是 18 个；libGLESv2 实际 846，目录 204。所以**目录里没有
  不等于设备没有**。
- **有个别目录条目在运行时并不存在。** libz 的 stub 声明了一些平台库并不导出的内部符号。
  在开发所用的 Android 15 镜像上，这类条目是 8 个 libz 内部符号（`_dist_code`、
  `_length_code`、`_tr_align`、`_tr_flush_bits`、`_tr_flush_block`、`_tr_init`、
  `_tr_stored_block`、`_tr_tally`）、libvulkan 里的 `vkGetImageSubresourceLayout2EXT`、
  libEGL 里的 `eglCreateNativeClientBufferANDROID`。**导入其中任何一个都会让整个库装载失败**
  （两个 ABI 都一样），因为加载器在执行第一条指令之前就完成导入绑定。
- **拿目标设备自查，别猜。** 把该设备自己的库取出来，与目录比对：

  ```powershell
  python tests/os/check_catalog_vs_device.py --catalog include/os/android `
      --device-libs <取出的库所在目录> --abi arm64 --llvm-nm <llvm-nm 路径>
  ```

  `--abi` 必须写对（一个 ABI 一个库目录，别拿 ARM64 设备去比 32 位那一套）。在本机所用的
  Android 15 镜像上，**x86_64 与 ARM64 都是 3916 条里 3906 条被真实导出（99.74%）**，
  缺口就是上面那 10 条。
- **装载即验证，成本很低。** `tests/os/make_android_smoke.py` 会生成一个"每个库抽样导入"
  的源码：汇编出来装到设备上，装载过程就顺手验证了几百条"符号→库"映射。
  `--only-libraries` 把抽样限制在设备确实有的库上，`--avoid` 跳过设备不导出的符号。
- **一个符号可能属于多个库。** 有 212 个符号被多个库提供（`glClearColor` 在 GLESv1/2/3 都有）。
  导入槽按**符号名**唯一，所以一个导入列表里只能选一个提供者；目录把全部提供者列出，
  选哪个由程序决定。

## 命名速查

| 表面 | 形式 |
| --- | --- |
| 库 soname | `android_import_<别名>_so` |
| 库的 API 级别 | `android_import_<别名>_min_api` |
| 符号名 | `android_import_<别名>_<符号>` |
| 挂导入（x86-64） | `android_import_<别名>_add_mut(imports, names)` |
| 挂导入（AArch64） | `android_import_<别名>_add_slots_mut(imports, names)` |
| 按名查询 | `android_symbol_library(syms, name)` 等，见 `catalog.inc` |

数据来源与许可见 `NOTICE.md`；计数、扫描范围与 stub 文件摘要见 `catalog/manifest.json`。

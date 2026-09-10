# 用 XIRASM 写 Android 平台代码：符号目录与头文件事实

写安卓原生代码时，最琐碎也最容易出错的三件事是：**平台库名要手打**（写错就
`DT_NEEDED` 指向不存在的库，装到设备上才崩）、**API 级别要记**（编译能过、装到低版本设备
才崩）、**结构体字段要自己数**（`ANativeActivity` 的回调表在第几个指针上）。这三件事在
XIRASM 里都由生成物负责：`include/os/android/` 下的目录与 `defs/` 下的常量。

本文是这套东西的说明书；怎么把 native 库包成 APK 见 [Android 打包指南](apk.md)。

## 目录提供了什么

| 数据 | 规模 | 来源 |
| --- | --- | --- |
| 符号 → 库、首次可用 API、ABI 掩码、版本标签 | **25 个库 / 4,137 个符号 / 4,416 条组合**，API 21–35 × 5 个 ABI | NDK r27d（`Pkg.Revision = 27.3.13750724`）的 stub 库 |
| 头文件常量与结构体布局 | **1,168 个常量 / 25 个结构体 / 161 个字段偏移**，来自 33 个 C 头文件 | 同一份 NDK 的 `sysroot/usr/include/android/*.h` |

两条使用路径，日常只用第一条：

- **常量路径（主）**：`import("os/android/imports/liblog.inc")` 之后用
  `android_import_log___android_log_write`；库名被焊死在生成的辅助函数里。
- **查询路径（辅）**：`import("os/android/catalog.inc")` 之后按名字问目录
  （`android_symbol_library(syms, "__android_log_write")` → `"liblog.so"`），给工具与诊断用。

## 挂平台导入：一个 .so 两种写法

导入接口本来就是"库名 + 符号名"绑在一起的，目录把库名那一半接管了。x86-64 走 PLT，
AArch64 走 GOT 槽位，**目标决定用哪个辅助函数**：

| 目标 | 辅助函数 | 调用写法 |
| --- | --- | --- |
| x86-64 | `android_import_<别名>_add_mut(imports, names)` | `call <符号>_plt` |
| AArch64 | `android_import_<别名>_add_slots_mut(imports, names)` | `ldr x8, <符号>` 然后 `blr x8` |

下面是一份完整可汇编的 AArch64 共享库，库名一个都没有手写：

```asm
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

产物里会出现 `NEEDED [libGLESv2.so]`、两个 `U glClearColor`/`U glClear` 与两条
`R_AARCH64_GLOB_DAT` —— 全部由目录给出的库名推出。

## 常量与结构体偏移

同一批头文件还声明了要传给平台的枚举（窗口格式、事件动作、键码）和平台回传的结构体。
`defs/<头文件>.inc` 把两者都收编，命名规则是：

| 表面 | 形式 |
| --- | --- |
| 枚举成员或宏 | `android_<头文件>_<名字>` |
| 结构体大小 | `android_layout_<Struct>_size64` / `_size32` |
| 字段偏移 | `android_layout_<Struct>_<字段>_offset64` / `_offset32` |

`64`/`32` 后缀是安卓的两种数据模型：arm64 与 x86-64 是 LP64，armv7 与 i686 是 ILP32。
成员里有指针或 `size_t` 的结构体，两者大小不同，所以偏移分两套给出。匿名 `struct`/`union`
的成员按 C11 规则报在**外层**结构体上。

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

`import("os/android/defs.inc")` 一次导入全部 33 个分区；日常源码只 import 自己用到的头文件。

## 按名字查目录

工具、诊断与编辑器补全走查询路径。数据表**第一次查询时才解析**，一次解析回答任意多次查询：

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

可用的查询：`android_symbol_library`、`android_symbol_libraries`、
`android_symbol_min_api`、`android_symbol_library_api`、`android_symbol_available_at`、
`android_symbol_abis`、`android_symbol_version`、`android_symbol_kind`；
`android_catalog_meta()` 返回 `[meta]` 表。

## API 级别怎么用

每个符号记录**首次可用**的 API 级别，每个库也有自己的级别。工程通常这样守住 minSdk：

```asm
import("os/android/imports/libGLESv2.inc")

assert(android_import_glesv2_min_api <= 26, "libGLESv2 is newer than the project's minimum SDK");
```

单个符号用 `android_symbol_min_api(syms, name)` 或 `android_symbol_available_at(syms, name, min_sdk)`。

## 一条完整链路

`tests/format/android_gl_demo/` 是一个只用 XIRASM 写成的 GLES2 渲染器：EGL 初始化、
shader 编译、汇编期生成的纹理、九参数 `glTexImage2D`、`glDrawArrays` 全在里面，x86-64 与
AArch64 两份源码都由目录取库名、由 `defs` 取回调偏移。三个归档变体（x86-64、arm64-v8a、
两个 ABI 的通用包）由 `tests/format/check_apk.py` 独立验收，通用包在设备上按 ABI 取对应库。

## 生成物是怎么保证正确的

| 手段 | 做什么 |
| --- | --- |
| 生成器 `tests/os/generate_android_symbols.py` | 纯 Python 解析 stub 的动态符号表与版本表；`--check` 逐字节比对，产物可复现 |
| 校验器 `tests/os/validate_android_symbols.py` | 用 `llvm-nm` **批量重算**全部事实并与产物比对（六项差异全 0） |
| 生成器 `tests/os/generate_android_constants.py` | 纯 Python 解析头文件（含 `#define`、枚举、结构体布局），`--check` 可复现 |
| 校验器 `tests/os/validate_android_constants.py` | 把每个常量与偏移改写成 `_Static_assert`，交给 NDK 的 clang 按 **LP64 与 ILP32** 两模型编译 |
| 检查器 `tests/os/check_android_symbols.py` | 编译期覆盖：4,416 个常量全部引用、25 个库辅助函数、查询 API、`defs` 分区全量加载 |
| 检查器 `tests/os/check_android_docs.py` | 本文与目录 README 里的**每个示例都汇编一遍**，文档不能与语言脱节 |
| 设备侧 `tests/os/check_catalog_vs_device.py` | 把目标设备自己的 `.so` 取出来，与其真实导出比对 |
| 设备侧 `tests/os/make_android_smoke.py` | 生成"每个库抽样导入"的冒烟 `.so`：装载即验证几百条映射 |

## 这套目录的限度

- **来源是 NDK stub（链接期语义）**，不是设备全量：Android 15 上 liblog 实际导出 63 个符号，
  目录里 18 个；libGLESv2 实际 846，目录 204。**目录里没有不等于设备没有**。
- **个别条目真机不导出**：libz 的 8 个内部符号（`_dist_code`、`_length_code`、`_tr_*`）、
  `vkGetImageSubresourceLayout2EXT`、`eglCreateNativeClientBufferANDROID`。安卓的加载器在
  **两个 ABI 上都是装载时急切重定位**，所以导入其中任何一个会让**整个库装载失败** ——
  这条已经实测（导入但从不调用的符号，依然让 `dlopen` 报 `cannot locate symbol`）。
  在开发所用的 Android 15 镜像上，x86_64 与 arm64 的命中率都是 **3,906/3,916 = 99.74%**，
  缺口就是上面那 10 个。
- **一个符号可能属于多个库**（212 个如此，`glClearColor` 在 GLESv1/2/3 都有）。导入槽按符号名
  唯一，所以一个导入列表里只能选一个提供者，目录把全部提供者列出。
- **C++ 头未收编**：9 个 binder/aidl 头只有 C++ 侧能用，不在 `defs/` 里。
- **常量未带 `__INTRODUCED_IN` 可用性**：目前只有符号轴有 min API；常量轴以后可加。

## 再生成

```powershell
$ndk = "<android-ndk-r27d>"
python tests/os/generate_android_symbols.py  --ndk $ndk --check
python tests/os/generate_android_constants.py --ndk $ndk --check
python tests/os/validate_android_symbols.py  --ndk $ndk
python tests/os/validate_android_constants.py --ndk $ndk
python tests/os/check_android_symbols.py --assembler zig-out/bin/xirasm.exe
python tests/os/check_android_docs.py    --xirasm zig-out/bin/xirasm.exe
```

升级 NDK 时先跑 `--check` 看差异，再重新生成并跑两遍校验器；`manifest.json` 与
`defs-manifest.json` 记录版本、计数与所用文件的摘要。

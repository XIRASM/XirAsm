# 用 XIRASM 生成 Android Native APK

XIRASM 可以把一份汇编源码直接变成可安装的 Android APK：二进制清单、资源表、
图标与资源条目、ZIP 容器、native 共享库全部由汇编器自产，不需要资源编译器参与
构造。签名是唯一的外部步骤，交给 Android SDK 自带的签名工具即可。

本文覆盖 NativeActivity 类纯原生应用：没有 Java/Kotlin 业务代码，界面和逻辑都在
native 层。适合工具、示例、图形程序、需要精确控制加载内容的场景，以及不想引入
重量级构建链的场合。

## 这条链路

| 产物 | 由谁生成 |
| --- | --- |
| `AndroidManifest.xml`（二进制 AXML） | XIRASM，`format/axml.inc` |
| `resources.arsc`（资源表） | XIRASM，`format/arsc.inc` |
| 图标、字符串、资源与 assets 条目 | XIRASM，`format/apk.inc`（含 `res/` 目录扫描） |
| ZIP 容器、CRC-32、条目对齐 | XIRASM，`format/zip.inc` |
| `lib/<abi>/*.so`（ELF 共享库） | XIRASM，`format/format.inc` |
| `classes.dex`（启动占位） | XIRASM，`format/apk.inc` |
| APK 签名（v1/v2/v3） | 外部签名工具（例如 Android SDK 的 `apksigner`） |

Android 侧负责其余部分：PackageManager 解析清单与资源表，动态链接器加载 native
库，NativeActivity 驱动进程与窗口。构造阶段不需要 `aapt2`；它只在你想独立复核产物
时作为对照器使用。

## 环境

- XIRASM 本体。
- Android SDK Build Tools 36 或更高版本：提供 `aapt2`（对照检查）、`zipalign`
  （对齐检查）、`apksigner`（签名）。
- JDK：只用于运行 `apksigner`，不参与 native 程序运行。
- `adb`：把 APK 装到模拟器或真机。

`aapt2`、`zipalign`、`apksigner`、`adb` 都可以直接放进 `PATH`，也可以在命令行里
写各自的完整路径。

## 生成 native 共享库

NativeActivity 的入口是导出的 `ANativeActivity_onCreate`。AArch64 用
`format_elf64_so_aarch64`，它已经按 Android 15+ 的 16 KiB 页大小对齐 LOAD 段：

```asm
import("format/format.inc")
import("arm/a64-macros.inc")

let image: map = format_elf64_so_aarch64(
    "libdemo.so",
    list.of(format_segment(".text", format_load | format_readable | format_executable))
)
let exports: list = format_elfso_export_new()
format_elfso_export_many_mut(exports, list.of("ANativeActivity_onCreate"), ".text", 24)
format_elfso_tables_mut(image, exports, format_elfso_import_new())
format_begin(image)
format_segment_begin(image, ".text")
ANativeActivity_onCreate:
    mov w0, #0
    ret
format_segment_end(image, ".text")
format_finish(image)
```

x86-64 用 `format_elf64_so`，导入外部函数走 PLT 与 GOT 槽位；AArch64 走 GLOB_DAT
槽位导入（`format_elfso_import_slots_mut`）。

**两层对齐是两件事，都要满足**：ELF 段在文件内的对齐由 `p_align` 决定，APK 内
ZIP 条目起始位置的对齐由打包层决定（见下文 `.so` 条目按 16 KiB 对齐），缺一个都
可能在 16 KiB 页设备上加载失败。

## 一条龙打包

`format/apk.inc` 的 facade 用一份编译期文档描述整个应用，`apk_emit` 一次写出清单、
资源表、图标、assets、启动 DEX 和各个 ABI 的 native 库：

```asm
import("format/apk.inc")

origin(0)

let app: map = apk_new("com.example.tool", 1, "1.0", "demo")
app = apk_set_sdk(app, 26, 34)
app = apk_label_string(app, "app_name", "Example Tool")
app = apk_icon(app, "mdpi", "res/mipmap-mdpi-v4/ic_launcher.png", "icons/mdpi.png")
app = apk_icon(app, "hdpi", "res/mipmap-hdpi-v4/ic_launcher.png", "icons/hdpi.png")
app = apk_asset(app, "assets/readme.txt", "docs/readme.txt")
app = apk_native_lib(app, "arm64-v8a", "libdemo.so", "build/arm64-v8a/libdemo.so")
app = apk_native_lib(app, "x86_64", "libdemo.so", "build/x86_64/libdemo.so")
apk_emit(app)
```

要点：

- `apk_icon` 与 `apk_resource_file` 把资源表条目和归档条目**成对登记**，两者用的
  必须是同一个路径字符串，成对登记后就不可能写岔。`apk_icon_bytes` /
  `apk_asset_bytes` 接受内联字节，适合构建期生成的小文件。
- 只要声明了资源，清单里的 `android:label` / `android:icon` 就写成资源引用，
  `resources.arsc` 一并产出；一个资源都没声明时走固定模板清单。
- `apk_label` 是字面量应用名（不建资源表），`apk_label_string` 建字符串资源并让
  清单引用它，后者优先；`apk_string_resource` 添加不充当应用名的字符串资源。
- 字符串资源的值可以用任何文字（中文、emoji 都可以）；资源名、类型名和包名保持
  ASCII，这也是 Android 对它们的要求。XIRASM 源码本身是 ASCII，所以非 ASCII 文本
  从数据文件读入：

  ```asm
  import("format/apk.inc")

  const raw: string = fs.read_text("strings.txt")
  const values: list = split(raw, "|")

  let app: map = apk_new("com.example.tool", 1, "1.0", "demo")
  app = apk_label_string(app, "app_name", trim(list.get(values, 0)))
  app = apk_string_resource(app, "tagline", trim(list.get(values, 1)))
  ```

  资源池按平台的方式存储文本：补充平面字符（例如 emoji）写成代理对，两半各自
  编码，因此读回来和系统其它应用完全一致。
- 默认写出 112 字节的启动 DEX（应用声明 `hasCode=false`，不执行任何 Java 代码）；
  用 `apk_skip_dex(app)` 可以不写。
- `.so` 条目自动按 16 KiB 对齐，满足 Android 15+ 对未压缩共享库的页对齐要求。
- 条目默认按 STORED（不压缩）写入；需要压缩的条目逐条选择，见下文"压缩条目"。

## 压缩条目

归档条目可以按 DEFLATE（ZIP method 8）写入，压缩由引擎的原生实现完成：

```asm
import("format/apk.inc")

origin(0)

const notes: bytes = b"XIRASM XIRASM XIRASM XIRASM XIRASM XIRASM XIRASM"

let app: map = apk_new("com.example.tool", 1, "1.0", "demo")
app = apk_label(app, "Example Tool")
app = apk_asset_bytes_compressed(app, "assets/notes.txt", notes)
app = apk_asset_compressed(app, "assets/readme.txt", "docs/readme.txt")
app = apk_resource_file_compressed(app, "raw", "notice", "", "res/raw/notice.txt", "docs/readme.txt")
apk_emit(app)
```

规则：

- **压缩是按条目选的，默认不压缩**。资源表（`resources.arsc`）、清单、`.so` 与图标
  保持 STORED + 对齐：前两者是 Android 要求的，后两者本来就压不动。要压的是
  assets、文本、体积大的数据文件这类载荷。
- 归档里记的 CRC-32 是**未压缩**数据的校验值，两种尺寸各记一份，`zip_finish` 的
  自检对压缩条目只核对头部一致性——压缩载荷没法在汇编期再解压一遍核对，所以
  这一步交给真正的解压器：`tests/format/check_apk.py` 用 Python 的 `zipfile`
  把每个条目解出来并核对 CRC。
- 压缩是确定性的：同样的输入与默认级别每次产出相同的字节，因此照样可复现。
- 级别由引擎的 `deflate.compress(data, level)` 承担（1 最快，9 最小）：facade 用默认
  级别，要换级别就走低层入口 `zip_entry_compressed_level(name, data, level)`。
  不要自己压完再交给 `apk_asset_bytes`，那会被再压一次。
- 压不小的载荷按未压缩存更小，因为压缩流自带块头。

## 资源与资源表

facade 的 `apk_label_string` 与 `apk_icon` 覆盖了最常见的两种资源。需要更多资源时，
直接用 `format/arsc.inc` 的值风格 builder 构造资源表，再用
`apk_manifest_res_entry` 让清单引用它：

```asm
let res: map = arsc_new("com.example.tool", 0x7f)
res = arsc_string(res, "app_name", "Example Tool")
res = arsc_string_locale(res, "app_name", "Example Tool ZH", "zh")
res = arsc_file(res, "mipmap", "ic_launcher", "mdpi", "res/mipmap-mdpi-v4/ic_launcher.png")
res = arsc_file(res, "mipmap", "ic_launcher", "hdpi", "res/mipmap-hdpi-v4/ic_launcher.png")
res = arsc_int(res, "integer", "version_slot", 3)
res = arsc_bool(res, "bool", "enabled", true)

apk_manifest_res_entry(res, "com.example.tool", 1, "1.0",
    "string/app_name", "mipmap/ic_launcher", "demo")
apk_resources_entry(res)
apk_res_file_entry("res/mipmap-mdpi-v4/ic_launcher.png", "icons/mdpi.png")
apk_res_file_entry("res/mipmap-hdpi-v4/ic_launcher.png", "icons/hdpi.png")
```

规则：

- **资源 ID 由名字决定，与声明顺序无关**：类型 ID 从 1 开始按类型名字典序分配，
  类型内的条目 ID 按条目名字典序分配。同一组资源无论按什么顺序写，产物字节相同。
- 支持的值类型：`arsc_string` / `arsc_string_locale`（字符串，可带两字母语言
  配置）、`arsc_file` / `arsc_file_locale`（文件，可带密度与语言配置）、
  `arsc_int` / `arsc_hex` / `arsc_bool` / `arsc_reference`。
- 密度用名字写：`ldpi` `mdpi` `tvdpi` `hdpi` `xhdpi` `xxhdpi` `xxxhdpi` `nodpi`。
- `arsc_resolve_id(id, res, "mipmap", "ic_launcher")` 取资源 ID（`0x7f...` 形式的
  整数），可以直接喂给 `axml_attr_reference` 在自定义 XML 里引用资源。
- 资源条目里记录的路径就是 APK 内条目名。用低层入口时要自己保证
  `arsc_file` 的路径与 `apk_res_file_entry` 的路径一致；走 facade 的 `apk_icon`
  时这条自动成立。
- 字符串值可以用任何文字；补充平面字符按平台的代理对方式编码，读回来与系统其它
  应用一致。资源名必须保持 ASCII 标识符。

## 按目录扫描资源

资源多起来之后，逐条声明不如让目录自己说清楚：`res/` 树的形状本身就是资源的坐标，
`apk_res_dir` 把整棵树读进来。

```asm
import("format/apk.inc")

origin(0)

let app: map = apk_new("com.example.tool", 1, "1.0", "demo")
app = apk_set_sdk(app, 26, 34)
app = apk_res_dir(app, "res")
apk_emit(app)
```

目录约定：

| 目录 | 含义 |
| --- | --- |
| `res/values/strings.toml` | 字符串资源，一个键一条；`app_name` 兼作应用名 |
| `res/values-zh/strings.toml` | 两字母语言配置下的同名资源 |
| `res/mipmap-hdpi/ic_launcher.png` | 文件资源：类型 `mipmap`，密度 `hdpi` |
| `res/drawable/logo.png` | 文件资源：默认配置 |

规则：

- 文件目录名写成 `<类型>[-<限定符>...]`。限定符可以是密度名（`ldpi`、`mdpi`、
  `tvdpi`、`hdpi`、`xhdpi`、`xxhdpi`、`xxxhdpi`、`nodpi`）、两字母语言码，或
  `-v4` 这类 API 版本限定符。别的写法（`-land`、`-night`、`-sw600dp`、`-12`）
  直接报错而不是被丢掉——丢掉会让两个不同的值塌进同一个配置。
- 资源表只编译密度与语言两个轴，所以**一个目录最多带一个密度限定符和一个语言
  限定符**，多出来的同样报错。API 版本限定符被接受但不写进配置；如果两个目录因此
  落到同一个配置，重复声明检查会把它们当成冲突报出来。
- 资源名是文件名里第一个点之前的部分，归档条目名保留原文件名。资源表里记的路径和
  归档里的条目名是同一个字符串，写不岔。
- `values*` 目录里放 TOML 表而不是文件，每个键一条字符串资源，值必须是字符串。
  这类目录只认 `.toml` 文件、不接受子目录，限定符只能带语言码或 API 版本（字符串
  没有密度轴）。TOML 只是编译期输入，不进归档。
- 扫描是递归的，跳过点开头的条目，顺序取排序后的目录枚举，所以同一棵树每次产出
  相同字节。同一棵树扫两遍无害；同一个资源配置被两个文件同时声明会报错。
- 声明了资源就要求清单里有应用名：扫描时 `app_name` 会自动绑定；树里没有
  `app_name` 时用 `apk_label` 给字面量，或用 `apk_label_string` 显式建资源。
  `mipmap/ic_launcher` 同理自动成为图标。
- 约定名只在应用**完全没设**应用名/图标时自动绑定，显式设置过的不会被覆盖。想换
  别的资源用 `apk_use_label(app, "name")` 与
  `apk_use_icon(app, "mipmap", "ic_launcher_round")`；这两个调用只是登记引用，
  资源是否存在在写清单时校验，且应用一个资源都没有时它们会报错（固定模板清单没有
  资源可引用）。
- 归档路径默认镜像被扫描的目录，所以 `apk_res_dir(app, "res")` 产出的正是
  `res/...` 条目；目录不叫 `res` 时用 `apk_res_dir_at(app, "app_res", "res")`
  显式给出归档前缀。

`tests/format/apk_res_scan_user_facade.asm` 是一份完整例子：`check_apk.py` 会用
`aapt2` 把扫出来的资源名、密度、语言配置和归档路径逐条读回来复核。

## 整包自产：自己写渲染器

APK 里最容易变成"别人的代码"的是 native 那一层。这条链路允许 `lib/<abi>/*.so`
完全由 XIRASM 产出：`format_elf64_so` 写 ELF 动态库，导入走 PLT，导出只留框架要找
的那个入口符号。仓库里带一个可运行的例子：

| 文件 | 作用 |
| --- | --- |
| `tests/format/android_gl_demo/gl-demo-so.asm` | GLES2 渲染器库：填回调表、建 EGL 上下文、上传汇编期生成的纹理、画一个全屏四边形 |
| `tests/format/android_gl_demo/gl-demo-apk.asm` | 打包成 APK：资源树声明图标与中文应用名，`apk_skip_dex(app)` 省掉 DEX |
| `tests/format/android_gl_demo/res/` | 五档密度图标，由 `tests/format/make_demo_icon.py` 按公式生成 |

构建时把两个源文件与 `res/` 放在同一个目录里（数据路径相对源文件解析）：

```text
xirasm gl-demo-so.asm  -o libmain.so
xirasm gl-demo-apk.asm -o demo-unsigned.apk
zipalign -f -P 16 4 demo-unsigned.apk demo-aligned.apk
apksigner sign --ks debug.keystore --out demo.apk demo-aligned.apk
```

产物在 39 KB 上下，其中库约 6.5 KB：没有 DEX、没有 C++ 运行时、没有第三方素材——
屏幕上的纹理是汇编期按公式算出的 16×16 RGBA，图标是同一套公式生成的 PNG。
`tests/format/check_apk.py` 会把这个例子从源码重建一遍，并用 `aapt2` 与 `zipalign`
复核（清单、中文应用名、五档图标、native code、16 KiB 对齐）。

要点：

- 框架只要求一个导出符号 `ANativeActivity_onCreate`。拿到 `ANativeActivity` 之后
  把回调写进它给的函数表即可：`callbacks` 是首字段，表内 16 个函数指针按声明顺序，
  所以 `onDestroy` 在 +40、`onNativeWindowCreated` 在 +56、
  `onNativeWindowRedrawNeeded` 在 +72、`onNativeWindowDestroyed` 在 +80。
- 不接输入队列也能出画面：窗口创建时建 EGL、画一帧、交换缓冲就够了，不需要事件
  循环（也就没有事件循环写错导致黑屏的余地）。
- 顶点与纹理在汇编期算好写进数据段，运行期只做一次 `glTexImage2D` 上传。
- x86-64 共享库的导入函数名后面加 `_plt` 直接 `call`。AArch64 共享库走 GLOB_DAT
  槽位（`format_elfso_import_slots_mut` + 槽位间接调用），调用序列不同；例子按
  x86-64 给出并在 x86_64 模拟器上跑过。

## 框架资源与主题

清单或资源值里引用 `@android:...` 时，要带上平台自己给这个资源的 ID——形如
`0x01 <类型> <条目>`。仓库里带一份**从平台 jar 生成的目录**：

```asm
import("format/apk.inc");
import("format/android/generated/framework_ids.inc");

origin(0);

const ids: map = android_framework_ids()

let app: map = apk_new("com.example.tool", 1, "1.0", "demo")
app = apk_label_string(app, "app_name", "Example Tool")
app = apk_use_theme_id(app, android_style_id(ids, "Theme.DeviceDefault"));
apk_emit(app)
```

- 表本体是数据文件 `include/format/android/generated/framework_ids.toml`，由
  `tests/format/generate_android_ids.py` 生成：它用 `aapt2` 读平台 jar 的
  `resources.arsc`（**平台自己的读取器**，不是第二个解析器）；随附的 `.inc` 只有
  一层薄封装。
- **只收录公开资源**：平台在表里给公开项打了 `PUBLIC`，应用本来也只该引用这些；
  私有项与 id 高于 `0x7f` 的动态资源类型（RRO 之类）不收录——当前平台上是 17 个
  类型、3037 条。确实需要全表时给生成器加 `--include-private`。
- 用法是**加载一次、查多次**：`android_framework_ids()` 读一次数据文件，之后
  `android_attr_id` / `android_style_id` / `android_string_id` / `android_drawable_id` /
  `android_color_id` … 或通用的 `android_id(ids, "类型", "名字")` 都只是在已加载的
  表里查；名字写错会带名字报错。
- 代价（实测）：import 这个 include 与什么都不导入的基线相当（134 ms），加载一次表
  约 0.2 s，单次查询可忽略。**只有真正要用框架资源的源文件才 import 它**——早期把
  整张表在导入时逐条填进 `map` 的写法要 2 s，现在换成数据文件 + 原生 TOML 解析。
- `apk_use_theme_id` 收的是 **ID** 而不是名字，就是为了让 `format/apk.inc`
  不必背这份目录。
- 固定模板清单（一个资源都没声明时走的那条路）没有属性映射表，所以主题需要
  资源表：只设 `apk_label`/`apk_label_string`/图标其中之一就会走资源表那条路。
- 目录里的 ID 与平台对得上：fixture 断言了 `attr/label=0x01010001`、
  `attr/icon=0x01010002`（与本仓库早先独立验证过的常量一致）、
  `style/Theme.DeviceDefault=0x01030128`、`string/ok=0x0104000a`，验收脚本还会用
  `aapt2` 把写进清单的主题 ID 读回来核对。
- 名字里带点的资源（`Theme.DeviceDefault`）在数据文件里以 `~` 代替点存储，查询
  助手负责换回来：这是为了避开"引号键里的点仍被拆成嵌套表"这一 TOML 解析偏差
  （TOML 规范里引号键是字面量；偏差已记录在工作流状态）。

## 低层打包入口

需要逐步控制时，facade 下面的入口都可以直接用：

```asm
import("format/apk.inc")

origin(0)
apk_set_min_sdk(26)
apk_set_target_sdk(34)
apk_manifest_entry("com.example.tool", 1, "1.0", "Example Tool", "demo")
apk_dex_entry()
apk_lib(b"arm64-v8a", b"libdemo.so", "build/arm64-v8a/libdemo.so")
apk_lib(b"x86_64", b"libdemo.so", "build/x86_64/libdemo.so")
apk_file_entry(b"assets/readme.txt", "docs/readme.txt")
zip_finish()
```

- `apk_manifest_entry` 是固定模板清单：`hasCode=false`、NativeActivity、
  MAIN/LAUNCHER、`android.app.lib_name`。
- `apk_set_min_sdk` / `apk_set_target_sdk` 是模块级设置，默认 24 / 35。
- `apk_lib` 按 ABI 目录收编 native 库并按 16 KiB 对齐；`apk_file_entry` 收编任意
  预制文件。
- `zip_finish` 关闭归档并注册完整性检查：最终镜像里的 CRC-32、条目对齐、中央目录
  与 EOCD 都会在汇编结束前逐项复核。

## 检查

汇编时可以同时输出逐行清单（逻辑地址、文件偏移、字节、源码对照），调试布局很方便：

```text
xirasm app.xir -o app-unsigned.apk --listing app.lst
```

用 Android 自带工具独立复核产物：

```text
aapt2 dump badging app-unsigned.apk
aapt2 dump xmltree app-unsigned.apk --file AndroidManifest.xml
aapt2 dump resources app-unsigned.apk
zipalign -c -v 4 app-unsigned.apk
zipalign -c -v -P 16 4 app-unsigned.apk
```

`badging` 会显示应用名和各密度的图标条目，`xmltree` 显示清单结构，`resources`
逐条列出资源 ID、配置和值。三者都能读通，说明清单和资源表是真被 Android 工具链
认可的二进制格式。

仓库里带一个可复现的验收脚本，它自己汇编 fixture，并用上面的工具当裁判：

```text
python tests/format/check_apk.py --assembler zig-out/bin/xirasm.exe
```

不带工具路径时它只用 Python 标准库做结构自检（ZIP 完整性、CRC-32、4 字节对齐、
AXML 与 resources.arsc 的 chunk 走查）；把 Build Tools 目录通过 `--sdk-bin` 传进来
之后，会额外跑 `aapt2 badging/xmltree/resources` 与 `zipalign` 的全部检查。

## 签名

**签名不在 XIRASM 内，也不在路线图里**：引擎不碰密钥和证书运算，`apk_emit` 产出的是
未签名 APK，交给外部签名工具。Android PackageManager 会拒绝没有证书的 APK，所以
侧载也要签，而这一步用任何能签 APK 的工具都可以——随 Android SDK 发行的 `apksigner`
最直接，其它图形化打包流程、JDK 自带的 `keytool` 加签名工具也都行，开发和内部使用
自签名证书即可，免费，不需要账号或审核。

用 SDK 工具的一条完整命令序列：

```text
keytool -genkeypair -keystore debug.keystore -alias androiddebugkey ^
    -storepass android -keypass android -dname "CN=Android Debug,O=Android,C=US"
zipalign -f -P 16 4 app-unsigned.apk app-aligned.apk
apksigner sign --ks debug.keystore --ks-key-alias androiddebugkey ^
    --ks-pass pass:android --key-pass pass:android --out app-debug.apk app-aligned.apk
apksigner verify --verbose app-debug.apk
```

- 自签名证书的 `-dname` 随便填，只在设备上区分签名身份用；换机器重签要沿用同一个
  keystore，否则覆盖安装会因签名不一致被拒。
- 签名版本（v1/v2/v3）由签名工具按 `--min-sdk-version` 与 `--max-sdk-version`
  决定，XIRASM 侧不需要知道，也不对这些块做任何假设。
- 签名必须在最终布局和对齐完成之后进行。改过 APK 内容就要重新对齐、重新签名。

## 安装和调试

```text
adb install -r app-debug.apk
adb shell monkey -p com.example.tool 1
adb logcat
```

排查 native 加载问题：

```text
adb logcat | findstr /i "PackageManager linker AndroidRuntime DEBUG"
```

常见原因：设备 ABI 与 APK 里的 `lib/<abi>` 不匹配、入口符号没有导出、依赖库缺失、
签名无效，或者设备没有被 `adb` 识别。

## 能力边界

已经内建并经过实机验证：ZIP 容器与 CRC-32、二进制清单、`resources.arsc`（字符串、
文件、整数、布尔、引用五类值，默认配置加密度与语言限定符，字符串值支持任意文字
含补充平面）、密度图标、`hasCode=false` 的启动 DEX、多 ABI native 库收编、按目录
扫描资源、4 字节与 16 KiB 两级对齐。清单与资源表的产物在开发中与 Android 自带资源
编译器的输出逐字节比对过（同输入同字节），仓库内的验收脚本则用 `aapt2` 与
`zipalign` 把这些产物逐项读回来复核。

尚未内建，因此不在覆盖范围内：

- **签名**：由外部工具完成，引擎不做密钥与证书运算（见上文"签名"一节，任何能签
  APK 的工具都可以，自签名证书免费）。
- **压缩条目**：条目默认按 STORED 写入，需要压缩的逐条选择（DEFLATE / method 8，
  见上文"压缩条目"）。资源表、清单与 `.so` 必须保持未压缩与对齐，归档里的 CRC-32
  记的是未压缩数据的校验值。
- **Java/Kotlin 代码**：不编译 DEX 业务代码，应用必须是 `hasCode=false` 的纯原生
  程序。
- **完整资源编译器**：样式、属性表（`styleable` / `attr`）、多包与框架资源 ID 表
  （`@android:` 引用）不在范围内。
- **资源目录限定符**：只编译密度与语言两个配置轴。每个目录最多一个密度加一个语言，
  其余限定符（`-land`、`-night`、`-sw600dp` 等）在扫描时报错，而不是被静默忽略；
  API 版本限定符（`-v4`）被接受但不写进配置。

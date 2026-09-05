# 6. macOS Mach-O

Mach-O helper 是面向 macOS 镜像的 XIRASM DSL 格式层。它根据选择的 CPU 类型
发射格式记录和字节，不增加第二套指令编码器，也不增加原生 ARM 文本解析器。

## 快速开始

先选择产物：`.o` 使用 `macho_obj.inc` 并交给 linker，直接可执行文件使用
`macho_exe.inc`，共享库使用 `macho_dylib.inc`。只有 direct executable 需要
dyld 导入时才加入 `macho_import.inc`。`tests/format/macho64_*` 是 `arm64`
和 `x86_64` 的完整布局样例；复制后一起修改 label、地址和 ISA 字节即可。
格式 helper 不负责汇编指令文本。

## 公共入口

需要所有格式 helper 时，使用正常的格式入口：

```asm
import("format/format.inc");

// facade 支持 arm64（16 KiB 页）和 x86_64（4 KiB 页）。
const version: u64 = macho_exe_macos_version(14, 0, 0)
let image: map = format_macho64_exe(
    format_macho64_target_x86_64(version, version),
    list.of(format_macho64_segment(
        "__TEXT",
        format_load | format_readable | format_executable,
        list.of(format_section("__text", format_code | format_readable | format_executable))
    ))
)

format_begin(image);
format_section_begin(image, "__text");
entry:
db(0x31, 0xc0, 0xc3);
format_section_end(image, "__text");
format_entry_mut(image, entry);
format_finish(image);
```

也可以直接导入 Mach-O 层：

```asm
import("format/macho_obj.inc");
```

## 三种产物

| 产物 | Helper | 后续工具 |
| --- | --- | --- |
| 可重定位目标文件 | `macho_obj.inc` | `ld64` 或 `ld64.lld` |
| 可执行文件 | `macho_exe.inc` | macOS loader；签名由外部工具完成 |
| 共享库 | `macho_dylib.inc` | dyld；导入和签名由外部工具完成 |

高层 `format_macho64_object`、`format_macho64_exe` 和
`format_macho64_dylib` 使用相同的节生命周期。节的身份是
`(segment_name, section_name)`；如果两个段包含同名节，请使用同时指定两个名称的
`format_macho64_section_begin/end`。`MH_OBJECT` facade 只有一个隐含段，因此要求节名唯一。
这一层生成普通代码、数据和 zerofill 节；导入、
重定位、代码签名和 chained fixups 仍由更底层 helper 或 linker 负责。

## 能力矩阵

| 能力 | arm64 | x86_64 | 所属层 |
| --- | --- | --- | --- |
| Mach-O 64 头部/段/节 | 支持 | 支持 | `macho_obj.inc` |
| 直接生成 `MH_EXECUTE` | 支持 | 支持 | `macho_exe.inc` |
| `LC_LOAD_DYLINKER` | 支持 | 支持 | `macho_exe_load_dylinker64` |
| `MH_DYLIB` install name | 支持 | 支持 | `macho_dylib.inc` |
| 普通函数 export trie | 支持 | 支持 | `macho_export.inc` |
| 目标文件重定位 | `BRANCH26`、`PAGE21`、`PAGEOFF12` | `BRANCH`、`UNSIGNED` | ISA 专用包装函数 |
| 直接可执行文件函数导入 | 支持 | 支持 | `macho_import.inc` |

目标文件层发射 `MH_OBJECT`、节表、符号表，以及显式的 AArch64
`BRANCH26`、`PAGE21`、`PAGEOFF12` 重定位记录和 x86_64 外部 `BRANCH` 重定位。
可执行文件和 dylib 的头部
与 CPU 无关，当前提供 ARM64 和 x86_64 包装函数。可执行文件层发射一个小型
`MH_EXECUTE`，包含 `__PAGEZERO`、`__TEXT,__text`、指向 `/usr/lib/dyld` 的
`LC_LOAD_DYLINKER`、`LC_MAIN` 和
`LC_BUILD_VERSION`。dylib 层发射一个带 install name 的最小 `MH_DYLIB`，并
提供 `macho_export_new` 和 `macho_export_use64` 收集普通函数导出。目标 label
完成布局后，使用 `macho_export_trie_size64` 和 `macho_export_trie_emit64`
生成 export trie；其 load-command 大小字段由源代码预留，并在 `defer` 中回填。

## 在直接可执行文件中导入函数

`macho_import.inc` 提供精简的直接可执行文件导入路径。它使用经典 non-lazy
dyld 绑定元数据而不是 chained fixups：undefined `nlist_64` 符号、`LC_SYMTAB`、
`LC_DYSYMTAB`、间接符号表、`__TEXT,__stubs` 和 `__DATA,__got`。通用记录和
绑定 opcode 由两种 ISA 共用，只有 stub 字节区分 arm64 与 x86_64。

```asm
import("format/macho_import.inc");

let imports: list = macho_import_new()
imports = macho_import_use64(imports, "@executable_path/libmath.dylib", "_add7")

// 布局负责各段的 VA 和 FOA。先在 __text 后发射所选 ISA 的 stub，
// 再在已声明的区域发射 slot 和 dyld/link-edit 表。
macho_import_emit_stubs_arm64(imports, stubs_vaddr, slots_vaddr);
// 或：macho_import_emit_stubs_x86_64(imports, stubs_vaddr, slots_vaddr);
macho_import_emit_slots64(imports);
macho_import_emit_bind64(imports, data_segment_index);
macho_import_emit_symbols64(imports);
macho_import_emit_indirect64(imports);
macho_import_emit_strings64(imports);
```

默认 label 是 `<symbol>_stub` 和 `<symbol>_got`；需要不同本地名称时使用
`macho_import_use64_as`。一个 import list 可以包含多个依赖 dylib，每个 dylib
也可以包含多个函数。库 ordinal 按首次出现顺序分配（1..15），同时写入 bind
流和 undefined symbol 描述。使用 `macho_import_load_dylibs_size64` 与
`macho_import_emit_load_dylibs64` 可为每个唯一依赖只发射一次 load command。这个范围可满足小型
CLI/FFI 消费端，不实现 lazy binding、stub helper、chained fixups 或通用 linker。
完整布局见 `tests/format/macho64_arm64_exe_import.asm` 和
`tests/format/macho64_x86_64_exe_import.asm`。当前 helper 面向 `MH_EXECUTE`；
dylib 自身导入符号仍应走 linker-backed 路径。导入型可执行文件应让 dylib
command、bind 和 string 尺寸都从同一个 import list 推导，并分别只发射一次；
它包含未定义符号，因此不能设置 `MH_NOUNDEFS`。

## 导出 FFI 函数

导出 helper 与 PE 导出 helper 使用相同的“先收集、后发射”模式。收集阶段
保存目标 label 名称；目标 label 完成布局后才计算和发射 export trie：

```asm
import("format/macho_dylib.inc");

let exports: list = macho_export_new()
exports = macho_export_use64(exports, "add7", "_add7")

// 这里发射 Mach-O 头部、__TEXT 段和 load commands。
// 在计算或发射 trie 之前定义 add7。
add7:
    emit.u32(0xd28000e0)
    emit.u32(0xd65f03c0)

let export_size: u64 = macho_export_trie_size64(exports, 0)
exports_data:
macho_export_trie_emit64(exports, 0);

defer {
    // 将 export_size 写入已经发射的
    // LC_DYLD_EXPORTS_TRIE.datasize 和 __LINKEDIT.filesize 字段。
}
```

这段代码是 direct-layout 结构示意：命令偏移由源代码负责，`defer` 之前必须
先预留固定宽度字段。当前 helper 只支持普通已定义导出；re-export、weak 定义、
stub/resolver、chained fixups 和代码签名属于后续功能。

## 坐标和延迟字段

直接构造 Mach-O 时要区分两套坐标：

- label 和 `here()` 是逻辑地址，用于 `vmaddr` 和符号值；
- `segment_64`、`section_64` 以及 dyld 数据命令中的文件位置是 FOA。

最终 FOA 应来自显式布局计算或 `region_file_offset(label)`。`store.u32`/`store.u64`
的目标是逻辑地址，不是原始 FOA。依赖后续区域的头部字段应先按最终宽度发射，
再在普通源码或 `late_layout` 中生成区域，最后只在 `defer` 中回填数值。
`defer` 不能创建字节、label、region 或对齐。

## 与链接器的边界

多目标文件程序应使用目标文件形式，再交给 `ld64` 或 `ld64.lld`。直接生成的
可执行文件或 dylib 适合小型镜像，但不替代 Apple linker 或代码签名。直接导入
helper 会为其受限的 non-lazy 函数导入模型生成 dyld 元数据。发布前应使用 LLVM
Mach-O 工具和独立 AArch64 反汇编器验证。

当前 direct 层不承诺 universal binary、arm64e、chained fixups、lazy binding、
每张表超过 15 个导入库、UUID、代码签名，也不承诺在非 macOS 主机上运行时加载。
dyld 仍在加载时解析声明的依赖和符号。Apple Silicon 可执行文件通常还需要
外部 ad-hoc 或正式签名。

## 验证

在 Windows 或其他非 macOS 主机上，可以使用 LLVM 和 radare2 做结构验证：

```text
llvm-readobj --file-headers --sections --symbols --relocs file.o
llvm-objdump --macho --private-headers --exports-trie file.dylib
llvm-objdump --macho --private-headers --bind --indirect-symbols file
ld64.lld -arch arm64 -platform_version macos 14.0 14.0 ...
radare2 -q -n -a arm -b 64 -c "pd 4 @ <text-address>" file
```

这些检查可以证明 Mach-O 结构、重定位记录、导出名称和 linker 互操作性；
真正运行 arm64 镜像以及测试 `dlopen`/`dlsym`，仍需要 Apple Silicon macOS
主机或 arm64 macOS CI runner。

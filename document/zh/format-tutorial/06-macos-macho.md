# 6. macOS Mach-O

macOS 上的可执行程序、共享库和供链接器使用的目标文件都用 Mach-O 格式。它和 PE、ELF 的组织方式都不同：内容按**段（segment）**分组，每个段下面再放**节（section）**，段和节的名字各占 16 字节，而且名字有固定含义——`__TEXT` 放代码，`__DATA` 放可写数据，加载器和系统工具按这些名字定位内容。

`format.inc` 这一层负责**结构**：头部、段命令、节表、符号表、重定位表，以及它们之间的偏移关系。它不参与指令编码，也不解析 ARM 汇编文本——写进节里的字节由源文件给出。

## 先选产物

Mach-O 的三类产物用三个不同的构造函数建立，选择依据是「谁来收尾」：

```asm id=macho64-exe target=x86-64
import("format/format.inc")

// macOS 14 作为最低版本和 SDK 版本。
const version: u64 = macho_exe_macos_version(14, 0, 0)

// 可执行文件：首段必须是 __TEXT，且必须含一个代码节。
let image: map = format_macho64_exe(
    format_macho64_target_x86_64(version, version),
    list.of(format_macho64_segment(
        "__TEXT",
        format_load | format_readable | format_executable,
        list.of(format_section("__text", format_code | format_readable | format_executable))
    ))
)

format_begin(image)
format_section_begin(image, "__text")
entry:
    // 机器码由你给出：xor eax, eax; ret 的 x86-64 编码。
    db(0x31, 0xc0, 0xc3)
format_section_end(image, "__text")
format_entry_mut(image, entry)
format_finish(image)
```

生成的映像为 4096 字节，头字段为 `Magic64 (0xFEEDFACF)`、`CpuType X86-64`、`FileType Executable`，共 6 条 load command。页大小按 CPU 决定：x86-64 取 4 KiB，arm64 取 16 KiB，和 ELF 那章 AArch64 的取值一致。

## 公共入口

只导入 `format/format.inc` 就能拿到上面这些构造函数。需要直接写段命令、节表、符号表时，才改用更底层的那几个文件：

| 产物 | 底层文件 | 收尾工具 |
| --- | --- | --- |
| 可重定位目标文件 | `macho_obj.inc` | `ld64` 或 `ld64.lld` |
| 可执行文件 | `macho_exe.inc` | macOS 加载器；签名由外部工具完成 |
| 共享库 | `macho_dylib.inc` | dyld；导入与签名由外部工具完成 |
| dyld 函数导入 | `macho_import.inc` | 用于直接生成的可执行文件 |

## 三种产物

`format_macho64_object`、`format_macho64_exe`、`format_macho64_dylib` 共用同一套节生命周期，差别只在头部和段命令。

段和节的名字都是 ≤ 16 字节，而且**段名必须是 `__TEXT`、`__DATA` 这类系统认识的名字**（两个下划线开头）。`__PAGEZERO` 和 `__LINKEDIT` 由 `format.inc` 自己生成，不要声明。

节的身份是「段名 + 节名」，因为不同段可以放同名节：

```text
// 两个段共用一个节名时，两个名字都要给出。
format_macho64_section_begin(image, "__DATA", "__data")

// 关闭时同样给出两个名字。
format_macho64_section_end(image, "__DATA", "__data")
```

只有一个段时，`format_section_begin` 和 `format_section_end` 只收节名就够了，和 PE、ELF 的用法一致。

可执行文件和共享库的约束比目标文件多，违反时报错：

| 约束 | 诊断 |
| --- | --- |
| 首段必须是 `__TEXT` | `Mach-O first segment must be __TEXT` |
| 至少有一个代码节 | `Mach-O executable or dylib requires a code section` |
| 代码节必须落在可执行段里 | `Mach-O code section requires an executable segment` |
| 节的权限不能超过所在段 | `Mach-O section permissions exceed its segment permissions` |
| 零填充节必须排在段内最后 | `Mach-O zerofill sections must be last in their segment` |
| 节名、段名不能重复 | `Mach-O section name is duplicated` / `Mach-O segment name is duplicated` |
| 可执行文件的入口必须落在代码节内 | `Mach-O executable entry is outside its code sections` |
| 共享库至少要有一个导出 | `Mach-O dylib facade requires at least one export` |
| 最后一个节必须已经关闭 | `Mach-O final section is still open` |

可执行文件的入口落在数据节里会被拒绝，因此 `format_entry_mut` 要传代码节内的标签。共享库的导出不是可选项——`format_macho64_dylib` 要求至少声明一个导出，否则 `format_finish` 直接报错。

节名可以用到 16 字节，比 PE 的 8 字节宽；但节的用途只支持三种：`format_code`、`format_data`、`format_uninitialized_data`。Mach-O 没有「可丢弃」这个概念，`format_discardable` 会报 `Mach-O sections do not support the discardable attribute`。

## 目标文件符号与重定位

目标文件里供链接器使用的两项内容是符号表和重定位表。`format_macho64_object` 在写头部时预留 `LC_SYMTAB` 命令，`format_finish` 回填其中的偏移，因此不用自己计算符号下标或字符串表偏移：

```asm id=macho64-object target=aarch64
import("format/format.inc")

const version: u64 = macho_exe_macos_version(14, 0, 0)
let object: map = format_macho64_object(
    format_macho64_target_arm64(version, version),
    list.of(
        format_section("__text", format_code | format_readable | format_executable),
        format_section("__data", format_data | format_readable | format_writeable)
    )
)

format_begin(object)

// 三处占位指令字，立即数字段留给链接器。
format_section_begin(object, "__text")
text_start:
call_site:
    emit.u32(0x94000000)
page_site:
    emit.u32(0x90000000)
lo12_site:
    emit.u32(0x91000000)
format_section_end(object, "__text")

format_section_begin(object, "__data")
data_start:
answer:
    emit.u64(42)
pointer_slot:
    emit.u64(0)
format_section_end(object, "__data")

const symbols: list = list.of(
    format_macho64_public("_entry", "__text", text_start, call_site, macho_n_sect | macho_n_ext),
    format_macho64_public("_answer", "__data", data_start, answer, macho_n_sect | macho_n_ext),
    format_macho64_extern("_printf")
)
const relocs: list = list.of(
    format_macho64_arm64_reloc("__text", text_start, call_site, "_printf", macho_arm64_reloc_branch26),
    format_macho64_arm64_reloc("__text", text_start, page_site, "_answer", macho_arm64_reloc_page21),
    format_macho64_arm64_reloc("__text", text_start, lo12_site, "_answer", macho_arm64_reloc_pageoff12),
    format_macho64_arm64_reloc("__data", data_start, pointer_slot, "_printf", macho_arm64_reloc_unsigned)
)
format_macho64_tables_mut(object, symbols, relocs)
format_finish(object)
```

生成的映像为 448 字节，`FileType` 为 `Relocatable`，带 `MH_SUBSECTIONS_VIA_SYMBOLS` 标志。符号表里有三个符号：`_entry` 落在 `__text`、`_answer` 落在 `__data`，两者类型都是 `Section`；`_printf` 类型是 `Undef`，落在段 0，等待链接器解析。

符号和重定位的对应关系：

| 项目 | 取值方式 |
| --- | --- |
| 符号值 | 地址减去所在节的起始地址；节号是 1 起算的 `n_sect` |
| 已定义的全局符号 | 类型写成 `macho_n_sect \| macho_n_ext` |
| 未定义的外部符号 | 由 `format_macho64_extern` 生成，类型是 `macho_n_undf \| macho_n_ext`，值为 0 |
| 符号名 | 写进字符串表，`n_strx` 由 `format.inc` 计算 |
| 重定位地址 | 同样是节内偏移，对应 Mach-O 的 `r_address` |
| 重定位目标 | 按名字在挂载的符号表里查，`r_extern` 恒为 1 |
| 重定位的 pcrel 与长度 | `format_macho64_arm64_reloc` 从 AArch64 类型推出；用 `format_macho64_reloc` 时要自己给出 |

`format_macho64_arm64_reloc` 推出的两个位域，按 AArch64 重定位类型固定取值：

| 重定位类型 | pcrel | length |
| --- | --- | --- |
| `macho_arm64_reloc_branch26` | 1 | 2（4 字节） |
| `macho_arm64_reloc_page21` | 1 | 2（4 字节） |
| `macho_arm64_reloc_pageoff12` | 0 | 2（4 字节） |
| `macho_arm64_reloc_unsigned` | 0 | 3（8 字节） |

pcrel 为 1 表示这个字段是相对寻址，加载器不需要修正；为 0 表示字段里是绝对地址，必须修正。长度是幂次：2 表示 4 字节，3 表示 8 字节。

`format_macho64_tables_mut` 会检查两张表：符号名必须唯一，重定位引用的节和符号必须已经声明。不挂表的目标文件也合法，只是符号表为空。

## 能力矩阵

| 能力 | arm64 | x86_64 | 所属层 |
| --- | --- | --- | --- |
| Mach-O 64 头部 / 段 / 节 | 支持 | 支持 | `format.inc` |
| 目标文件的符号、重定位、`LC_SYMTAB` | 支持 | 支持 | `format.inc` |
| 直接生成 `MH_EXECUTE` | 支持 | 支持 | `format.inc` |
| `LC_LOAD_DYLINKER` | 支持 | 支持 | 可执行文件的底层构造函数 |
| `MH_DYLIB` install name | 支持 | 支持 | `format.inc` |
| 普通函数 export trie | 支持 | 支持 | `macho_export.inc` |
| 目标文件重定位 | `BRANCH26`、`PAGE21`、`PAGEOFF12` | `BRANCH`、`UNSIGNED` | ISA 专用包装函数 |
| 直接可执行文件的函数导入 | 支持 | 支持 | `macho_import.inc` |

## 在直接可执行文件中导入函数

直接生成的可执行文件要让 dyld 在加载时解析外部函数，就得自己写绑定信息。`macho_import.inc` 提供这条路径，生成的是传统的 non-lazy 绑定，不是 chained fixups：

```text
import("format/macho_import.inc")

let imports: list = macho_import_new()
imports = macho_import_use64(imports, "@executable_path/libmath.dylib", "_add7")

// 各段的地址和文件偏移由外部布局给出，这里只按顺序写出各段信息。
macho_import_emit_stubs_arm64(imports, stubs_vaddr, slots_vaddr)
macho_import_emit_slots64(imports)
macho_import_emit_bind64(imports, data_segment_index)
macho_import_emit_symbols64(imports)
macho_import_emit_indirect64(imports)
macho_import_emit_strings64(imports)
```

导入槽的默认标签是 `<symbol>_stub` 和 `<symbol>_got`，需要别的名字时用 `macho_import_use64_as`。一个导入列表可以放多个依赖库，库序号按首次出现的顺序分配（1 到 15），同时写进绑定流和未定义符号描述。每个依赖库的 `LC_LOAD_DYLIB` 只用 `macho_import_emit_load_dylibs64` 写一次。

这一层不实现 lazy binding、stub helper、chained fixups，也不是通用链接器，够小型命令行工具和 FFI 调用方使用。导入型可执行文件含有未定义符号，因此不能设置 `MH_NOUNDEFS`。完整布局见 `tests/format/macho64_arm64_exe_import.asm` 和 `tests/format/macho64_x86_64_exe_import.asm`；共享库自己导入符号仍要走链接器。

## 导出 FFI 函数

导出和 PE 一样分两步：先收集，目标标签完成布局后再生成 export trie。

```text
import("format/macho_dylib.inc")

let exports: list = macho_export_new()
exports = macho_export_use64(exports, "add7", "_add7")

// 这里写出 Mach-O 头部、__TEXT 段和 load command，并定义 add7。
add7:
    emit.u32(0xd28000e0)
    emit.u32(0xd65f03c0)

let export_size: u64 = macho_export_trie_size64(exports, 0)
exports_data:
macho_export_trie_emit64(exports, 0)

defer {
    // 把 export_size 写进已经写出的
    // LC_DYLD_EXPORTS_TRIE.datasize 和 __LINKEDIT.filesize 字段。
}
```

这段代码是布局示意：命令偏移由源文件负责，`defer` 之前必须先把固定宽度字段写出来。当前只支持普通的已定义导出，re-export、weak 定义、stub/resolver、chained fixups 和代码签名不在此列。

## 坐标与延迟字段

自己排布 Mach-O 时要分清两套坐标：

- 标签和 `here()` 是**逻辑地址**，用于 `vmaddr` 和符号值；
- `segment_64`、`section_64` 以及 dyld 数据命令里的文件位置是**文件偏移（FOA）**。

最终的文件偏移来自显式布局计算，或者由 `region_file_offset(label)` 给出。`store.u32`、`store.u64` 的目标是逻辑地址，不是原始文件偏移。某个头部字段依赖后面的区域时，先把该字段按最终宽度写出来，在普通源码或 `late_layout` 中生成该区域，最后在 `defer` 里回填数值。`defer` 不能创建字节、标签、区域或对齐。

## 与链接器的边界

由多个目标文件组成的程序用目标文件形式，交由 `ld64` 或 `ld64.lld` 链接。直接生成的可执行文件和共享库适合小型镜像，但不替代 Apple 的链接器和代码签名。

这一层不提供 universal binary、arm64e、chained fixups、lazy binding、每张表超过 15 个导入库、UUID 和代码签名，也不保证在非 macOS 主机上运行。dyld 在加载时解析声明的依赖和符号；Apple Silicon 的可执行文件通常还需要外部的 ad-hoc 或正式签名。

## 验证方法

在没有 macOS 主机的环境里，用 LLVM 工具核对结构：

```text
llvm-readobj --file-headers --sections --symbols --relocs file.o
llvm-objdump -d --macho file.o
llvm-objdump --macho --private-headers --exports-trie file.dylib
llvm-objdump --macho --private-headers --bind --indirect-symbols file
ld64.lld -arch arm64 -platform_version macos 14.0 14.0 ...
radare2 -q -n -a arm -b 64 -c "pd 4 @ <text-address>" file
```

`llvm-objdump -d` 最有价值：它按重定位和符号表把指令反汇编出来，是唯一能同时验证机器码、符号值和重定位记录三者对得上的一步。上面那份目标文件反汇编后得到：

```text
_entry:
       0:  bl      _answer
       4:  ret
_answer:
       8:  mov     w0, #0x2a
       c:  ret
```

`bl _answer` 说明相对分支的重定位被正确解析，`mov w0, #0x2a` 说明写进节里的指令字是有效的 A64 编码。如果重定位位域或符号下标写错，这一步会显示错误的符号名或直接拒绝反汇编。

`llvm-readobj --relocs` 用来核对重定位记录本身，会列出每条记录所在节、偏移、pcrel、length、extern 和类型。

这些命令能核对 Mach-O 结构、重定位记录、导出名称和链接器互操作性。真正运行 arm64 镜像、测试 `dlopen` 或 `dlsym` 仍然需要 Apple Silicon 的 macOS 主机或对应的 CI runner。

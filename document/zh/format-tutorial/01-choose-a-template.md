# 1. 选择模板

先确定输出文件类型，再选择构造函数。普通用户不需要从文件头字段开始设计。

## 统一入口

```asm
import("format/format.inc");
```

只有在标准模板无法表达目标文件时，才直接导入 `pe.inc`、`elfexe.inc` 或 `elfobj.inc`。

## 构造函数

| 输出文件 | 构造函数 | 内容描述 |
| --- | --- | --- |
| PE32 可执行文件或 DLL | `format_pe32(options, sections)` | `format_section(...)` |
| PE64 可执行文件或 DLL | `format_pe64(options, sections)` | `format_section(...)` |
| COFF32 目标文件 | `format_coff32(sections)` | `format_section(...)` |
| COFF64 目标文件 | `format_coff64(sections)` | `format_section(...)` |
| ELF32 可执行文件 | `format_elf32(options, segments)` | `format_segment(...)` |
| ELF64 可执行文件或 PIE | `format_elf64(options, segments)` | `format_segment(...)` |
| ELF32 目标文件 | `format_elfobj32(sections)` | `format_section(...)` |
| ELF64 目标文件 | `format_elfobj64(sections)` | `format_section(...)` |
| ELF64 共享库 | `format_elf64_so(soname, segments)` | `format_segment(...)` |

PE、COFF 和 ELF 目标文件使用节。ELF 可执行文件和共享库使用加载段。

## 节属性

`format_section(name, attributes)` 接收节名和属性。属性必须包含一个用途，可以再组合权限。

| 用途 | 内容 |
| --- | --- |
| `format_code` | 指令 |
| `format_data` | 已初始化数据或只读数据 |
| `format_uninitialized_data` | 只占内存的未初始化空间 |
| `format_imports` | PE 导入表 |
| `format_exports` | PE 导出表 |
| `format_resources` | PE 资源 |
| `format_fixups` | PE 基址重定位表 |

| 权限 | 含义 |
| --- | --- |
| `format_readable` | 可读 |
| `format_writeable` | 可写 |
| `format_executable` | 可执行 |
| `format_discardable` | 加载器处理后可以丢弃 |

常用组合：

| 内容 | 属性 |
| --- | --- |
| 代码 | `format_code \| format_readable \| format_executable` |
| 只读数据 | `format_data \| format_readable` |
| 可写数据 | `format_data \| format_readable \| format_writeable` |
| BSS | `format_uninitialized_data \| format_readable \| format_writeable` |
| PE 导入 | `format_imports \| format_readable \| format_writeable` |
| PE 导出 | `format_exports \| format_readable` |
| PE 资源 | `format_resources \| format_readable` |
| PE 重定位 | `format_fixups \| format_readable \| format_discardable` |

## 段属性

`format_segment(name, attributes)` 用于 ELF 加载段。属性使用 `format_load` 加权限：

| 内容 | 属性 |
| --- | --- |
| 代码 | `format_load \| format_readable \| format_executable` |
| 只读数据 | `format_load \| format_readable` |
| 可写数据或 BSS | `format_load \| format_readable \| format_writeable` |

## 完整流程

```asm
import("format/format.inc");

let image: map = format_pe64(
    format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_auto,
    list.of(
        format_section(".text", format_code | format_readable | format_executable),
        format_section(".bss", format_uninitialized_data | format_readable | format_writeable)
    )
)
format_begin(image);

format_section_begin(image, ".text");
start:
    xor eax, eax
    ret
format_section_end(image, ".text");

format_section_begin(image, ".bss");
    rb(64);
format_section_end(image, ".bss");

format_entry_mut(image, start)
format_finish(image);
```

格式封装会根据命名节推导头部、表项、文件位置、RVA、对齐和 BSS 大小。

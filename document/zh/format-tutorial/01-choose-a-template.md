# 1. 选择模板

写格式文件时，先从“最终想得到什么输出”开始，不要从 PE 或 ELF 的头字段开始。`format.inc` 的高层封装已经把常见输出整理成几组模板。

## 统一入口

```asm
import("format/format.inc");
```

直接导入 `pe.inc`、`elfexe.inc`、`elfobj.inc` 之类文件，会进入更底层的字段和表项构造层。普通教程不需要它们；只有当高层配置无法表达目标文件时，才改用高级格式构造。

## 配置函数

| 输出 | 配置函数 | 内容描述 |
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

PE、COFF 和 ELF 目标文件按“节”组织内容；ELF 可执行文件和 ELF 共享库按“装载段”组织运行时映射。

## 节描述

`format_section(name, attributes)` 用来声明 PE、COFF 和 ELF 目标文件里的节。

| 参数 | 写什么 |
| --- | --- |
| `name` | 节名，例如 `".text"`、`".data"`、`".bss"`、`".idata"` |
| `attributes` | 一个用途标志，加上需要的权限标志 |

每个节只能选一个用途：

| 用途 | 适合内容 |
| --- | --- |
| `format_code` | 指令 |
| `format_data` | 已初始化数据或只读常量 |
| `format_uninitialized_data` | 零初始化内存，也就是 BSS |
| `format_imports` | PE 导入表 |
| `format_exports` | PE 导出表 |
| `format_resources` | PE 资源 |
| `format_fixups` | PE 基址重定位表 |

再叠加权限：

| 权限 | 含义 |
| --- | --- |
| `format_readable` | 运行时可读 |
| `format_writeable` | 运行时可写 |
| `format_executable` | 运行时可执行 |
| `format_discardable` | 加载后可丢弃的元数据 |

常用组合：

| 内容 | 推荐属性 |
| --- | --- |
| 代码 | `format_code \| format_readable \| format_executable` |
| 只读数据 | `format_data \| format_readable` |
| 可写数据 | `format_data \| format_readable \| format_writeable` |
| BSS | `format_uninitialized_data \| format_readable \| format_writeable` |
| PE 导入表 | `format_imports \| format_readable \| format_writeable` |
| PE 导出表 | `format_exports \| format_readable` |
| PE 资源 | `format_resources \| format_readable` |
| PE 重定位表 | `format_fixups \| format_readable \| format_discardable` |

节名必须唯一。PE 和 COFF 的普通封装要求节名不超过 8 字节。`format_imports`、`format_exports`、`format_resources`、`format_fixups` 这类特殊用途在同一个配置里也只能出现一次。

## 装载段描述

`format_segment(name, attributes)` 用于 ELF 可执行文件和 ELF 共享库。

| 参数 | 写什么 |
| --- | --- |
| `name` | 装载段名，例如 `".text"`、`".rodata"`、`".data"`、`".bss"` |
| `attributes` | `format_load` 加权限标志 |

常用 ELF 装载段组合：

| 内容 | 推荐属性 |
| --- | --- |
| 代码 | `format_load \| format_readable \| format_executable` |
| 只读数据 | `format_load \| format_readable` |
| 可写数据 | `format_load \| format_readable \| format_writeable` |
| BSS | `format_load \| format_readable \| format_writeable` |

装载段名必须唯一。普通层目前只暴露 `format_load` 这种可装载段；需要其他程序头类型时，属于高级格式构造范围。

## 完整流程

下面是一个最小 PE64 控制台程序。它声明 `.text` 和 `.bss`，由格式层生成 PE 头、节表、入口字段和 BSS 的文件/内存大小差异。

```asm
import("format/format.inc");

let image: map = format_pe64(
    format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_disabled,
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
scratch:
    rb(64);
format_section_end(image, ".bss");

format_entry_mut(image, start)
format_finish(image);
```

关键顺序是：

1. 先创建 `let image: map = ...`；
2. 再 `format_begin(image)` 预留头部和表项；
3. 内容必须写在已经声明过的节或装载段里；
4. 可执行文件用 `format_entry_mut(image, start)` 设置入口；
5. 最后调用 `format_finish(image)` 完成所有回填。

目标文件和 ELF 共享库没有普通可执行文件入口，不要对它们调用 `format_entry_mut`。

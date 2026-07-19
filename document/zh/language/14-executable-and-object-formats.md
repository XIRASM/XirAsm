# 第 14 章：可执行文件与目标文件格式

PE、COFF、ELF 不止是数据加指令。它们还包含文件头、节区段/段表、权限、入口点、导入导出表、符号表、重定位表，由链接器和加载器按规则解析。

XIRASM 用格式库处理这些：

```asm
// 导入用于构造标准文件格式的统一接口。
import("format/format.inc");
```

格式接口让源码描述目标映像，而不是手写表计数、表行位置、文件偏移、虚拟地址和文件头字段。

本章只介绍语言层面的通用模式。完整的格式选项、导入、导出、重定位、共享库、目标文件和高级辅助函数，请看[《格式教程》](../format-tutorial.md)。需要直接控制格式字段和表项时，再阅读[《高级格式构造指南》](../../advanced-formats.md)。

## 先声明映像再写内容

使用格式接口的程序，第一步是声明映像包含哪些 section 或 segment。每个描述符给出名称、用途和权限。

描述符列表是结构性的：
- 长度决定所需表的数量
- 顺序决定格式表的顺序
- 名称标识后续写入的内容块
- 用途选择格式特定的行为
- 权限成为 section/segment 属性

源文件不需要另外传入表计数或行号。增删描述符时，生成的格式结构会随之更新。

## 完整示例：ELF64 程序

以下示例创建 x86-64 ELF 可执行文件，含一个可加载、可读、可执行的 segment：

```asm
// 导入格式接口，并选择 64 位 x86 指令编码。
import("format/format.inc");
x86.use64();

// 声明 ELF64 可执行映像及其唯一的可装载代码段。
let image: map = format_elf64(
    format_elf_exec,
    list.of(
        format_segment(
            ".text",
            format_load | format_readable | format_executable
        )
    )
)
format_begin(image);

// 在声明的 .text 段中写入程序入口代码。
format_segment_begin(image, ".text");
start:
    // 调用 Linux 退出系统调用，并把退出状态设为零。
    mov eax, 60
    xor edi, edi
    syscall
format_segment_end(image, ".text");

// 绑定入口标号，随后完成映像中的文件头和表项。
format_entry_mut(image, start)
format_finish(image);
```

在 x86-64 Linux 下，这个程序以状态码 0 退出。

五步走：
1. `format_elf64` 创建声明式 ELF64 计划。
2. `format_segment` 声明一个 segment 及其权限。
3. `format_begin` 写出计划决定的格式结构。
4. `format_segment_begin` 和 `format_segment_end` 包住这个 segment 的实际指令和数据。
5. `format_entry_mut` 绑定入口标号，`format_finish` 完成映像。

源文件从不提供程序头计数、表行、文件偏移、加载地址或入口点字段偏移。格式接口会从计划和已完成的 segment 布局推导这些值。

## Sections 与 Segments

普通生命周期沿用所选格式的术语：
- PE 映像和目标文件用 section
- ELF 可执行文件和共享库用 segment
- ELF 目标文件用 section，不涉及运行时装载

对应的生命周期调用：

```text
format_section_begin(image, name)
format_section_end(image, name)

format_segment_begin(image, name)
format_segment_end(image, name)
```

只打开计划中声明过的描述符，并按声明时的用途使用每个名称。这样格式接口才能把已写出的字节、逻辑大小、权限和生成的表关联到正确的格式条目。

## 格式族

格式库支持以下映像类：

| 映像类 | 常规构造函数 |
| --- | --- |
| PE32 / PE64 映像 | `format_pe32`、`format_pe64` |
| COFF32 / COFF64 目标文件 | `format_coff32`、`format_coff64` |
| ELF32 / ELF64 可执行文件 | `format_elf32`、`format_elf64` |
| ELF32 / ELF64 目标文件 | `format_elfobj32`、`format_elfobj64` |
| ELF64 共享库 | `format_elf64_so` |

构造函数选项区分可执行文件与 DLL、控制台/GUI 子系统、位置无关执行、NX 策略、地址随机化等映像属性。Section/segment 描述符携带内容用途，以及读、写、执行或可丢弃等权限。

完整的选项和描述符列表属于参考材料，本语言指南不重复列出。

## 入口点绑定

可执行文件应在源码定义完入口代码后绑定入口标号：

```text
format_entry_mut(image, start)
format_finish(image);
```

`format_entry_mut` 会直接更新第一个参数传入的 `let` 绑定；这里不需要维护多个不可变中间副本。`format_finish` 随后验证可执行文件具备所需入口信息。

目标文件和部分库形式不需要入口点。按所选格式的生命周期来，不要加无意义的入口标签。

## 生成的格式内容

部分格式内容来自更高层的声明，不是作为普通 payload 字节手写出来的：
- 导入导出表
- 符号表和字符串表
- 重定位记录
- 基址重定位段
- 动态元数据
- 资源目录

这些功能的格式接口 API 接受名称、标号、权限和重定位类型。section 编号、符号索引、表偏移、行号和计数由接口内部推导。

不要用硬编码的表位置替代这些声明。格式接口的价值正在于让格式簿记与实际布局保持一致。

## 常规接口与高级接口

普通程序应从 `format/format.inc` 开始。它是稳定的用户层，负责协调格式属性、描述符、命名内容块、入口和生成表。

各格式特有的 include 文件提供更低层次的构建块。有些暴露特定位宽的便捷封装，有些暴露直接的文件头、section、segment 或表辅助函数。它们适合实现新的格式接口，或表达普通层无法覆盖的专用布局。

只是生成常见的多 section 可执行文件、DLL、目标文件、共享库、导入表、导出表或重定位表时，不需要切到底层 include。普通接口支持目标映像时，应优先使用普通接口。

不要随意混用抽象层次。底层辅助函数可能要求调用者自己管理计数、行号、偏移或格式不变式，而这些通常由普通接口维护。

第 11 到 13 章的 `region.begin`、虚拟区域、`late_layout` 和 `defer` 是底层布局工具。它们能表达“字节在文件哪里、逻辑地址是多少、最终字段何时回填”，但不会自动生成 PE/COFF/ELF 的 section、segment、符号表或重定位表记录。需要这些格式记录时，用 `format_section_begin`、`format_segment_begin` 和对应格式 API；只有在实现新格式接口或普通接口覆盖不了的专用布局时，才直接组合底层区域和收尾阶段。

## 后续阅读

[《格式教程》](../format-tutorial.md)提供可直接使用的模板、参数说明和 API 摘要：
- PE32/PE64 可执行文件和 DLL
- COFF32/COFF64 目标文件
- ELF32/ELF64 可执行文件和位置无关可执行文件
- ELF32/ELF64 目标文件
- ELF64 共享库
- 多 section 和多 segment
- 已初始化和未初始化数据
- 导入、导出、符号、重定位
- 普通格式接口与高级底层辅助函数的界限

已知所需格式系列时直接查 API Reference。

下一章讲诊断和源文件组织惯例。

[返回目录](../language.md)

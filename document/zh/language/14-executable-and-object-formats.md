# 第 14 章：可执行文件与目标文件格式

PE、COFF、ELF 不是“把指令和数据拼在一起”就够了。它们还要有文件头、section 或 segment 表、权限、入口点、导入导出表、符号表和重定位表；链接器和加载器会按这些结构解释文件。

XIRASM 用格式库生成这些结构：

```asm
// 导入常用的 PE/COFF/ELF 格式接口。
import("format/format.inc");
```

使用 `format.inc` 时，源码描述“文件里有哪些 section 或 segment、入口在哪里、需要哪些表”。表计数、表项顺序、文件偏移、虚拟地址和文件头字段由格式库推导。

本章只讲通用工作顺序。完整的格式选项、导入、导出、重定位、共享库和目标文件示例，请看[《格式教程》](../format-tutorial.md)。如果你确实要自己安排文件头和表项，再看[《高级格式构造指南》](../../advanced-formats.md)。

## 先声明映像再写内容

使用格式库的程序，第一步是声明输出文件包含哪些 section 或 segment。每个描述符给出名称、用途和权限。

描述符列表直接决定后面的格式结构：
- 列表长度决定表项数量；
- 列表顺序决定表项顺序；
- 名称用于后续打开对应内容块；
- 用途决定这块内容是代码、数据、BSS、导入表、导出表还是重定位表；
- 权限会写入 section 或 segment 属性。

源文件不用再手填表计数或行号。增删描述符时，生成的格式结构会跟着变化。

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

// 绑定入口标号，随后完成文件头和表项。
format_entry_mut(image, start)
format_finish(image);
```

在 x86-64 Linux 下，这个程序以状态码 0 退出。

基本顺序是：
1. `format_elf64` 创建 ELF64 文件配置。
2. `format_segment` 声明一个 segment 及其权限。
3. `format_begin` 写出这份配置需要的格式结构。
4. `format_segment_begin` 和 `format_segment_end` 包住这个 segment 的实际指令和数据。
5. `format_entry_mut` 绑定入口标号，`format_finish` 完成文件。

源文件不需要提供程序头计数、表行号、文件偏移、加载地址或入口点字段偏移。格式库会根据配置和已经完成的 segment 布局推导这些值。

## section 和 segment 怎么选

调用名称沿用文件格式自己的术语：
- PE 映像和目标文件用 section；
- ELF 可执行文件和共享库用 segment；
- ELF 目标文件用 section，不涉及运行时装载。

对应的生命周期调用：

```text
format_section_begin(image, name)
format_section_end(image, name)

format_segment_begin(image, name)
format_segment_end(image, name)
```

只能打开配置里声明过的名称，并按声明时的用途使用它。这样格式库才能把已写出的字节、逻辑大小、权限和生成的表关联到正确的格式条目。

## 格式族

格式库支持以下映像类：

| 映像类 | 常规构造函数 |
| --- | --- |
| PE32 / PE64 映像 | `format_pe32`、`format_pe64` |
| COFF32 / COFF64 目标文件 | `format_coff32`、`format_coff64` |
| ELF32 / ELF64 可执行文件 | `format_elf32`、`format_elf64` |
| ELF32 / ELF64 目标文件 | `format_elfobj32`、`format_elfobj64` |
| ELF64 共享库 | `format_elf64_so` |

构造函数选项区分可执行文件与 DLL、控制台/GUI 子系统、位置无关执行、NX 策略、地址随机化等文件属性。Section/segment 描述符携带内容用途，以及读、写、执行或可丢弃等权限。

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

有些格式内容不应该当成普通字节手写。它们来自专门的声明：
- 导入导出表
- 符号表和字符串表
- 重定位记录
- 基址重定位段
- 动态元数据
- 资源目录

这些 API 接受名称、标号、权限和重定位类型。section 编号、符号索引、表偏移、行号和计数由格式库推导。

不要用硬编码的表位置替代这些声明。格式库的价值正在于让表项和实际布局保持一致。

## 从 `format.inc` 开始

写常见 PE、COFF、ELF 文件时，先从 `format/format.inc` 开始。它负责协调格式属性、描述符、命名内容块、入口和生成表。

各格式特有的 include 文件会暴露更细的构造函数，例如文件头、section、segment、目录项或动态表。只有在 `format.inc` 无法表达目标布局时，才直接使用这些函数。

只是生成常见的多 section 可执行文件、DLL、目标文件、共享库、导入表、导出表或重定位表时，不需要绕过 `format.inc`。

不要混用两套写法。更细的构造函数通常要求调用者自己管理计数、行号、偏移和格式不变式；这些正是 `format.inc` 会替你维护的内容。

第 11 到 13 章的 `region.begin`、虚拟区域、`late_layout` 和 `defer` 只负责布局：字节放在文件哪里、逻辑地址是多少、最终字段何时回填。它们不会自动生成 PE/COFF/ELF 的 section、segment、符号表或重定位表记录。需要这些格式记录时，用 `format_section_begin`、`format_segment_begin` 和对应的格式 API。只有在实现新格式接口，或 `format.inc` 表达不了的专用布局时，才直接组合区域和收尾阶段。

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
- 什么时候用 `format.inc`，什么时候直接构造格式字段

已知所需格式系列时直接查 API Reference。

下一章讲诊断和源文件组织惯例。

[返回目录](../language.md)

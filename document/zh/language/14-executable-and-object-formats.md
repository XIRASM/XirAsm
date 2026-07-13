# 第 14 章：可执行文件与目标文件格式

PE、COFF、ELF 不止是数据加指令。它们还包含文件头、节区段/段表、权限、入口点、导入导出表、符号表、重定位表，由链接器和加载器按规则解析。

XIRASM 用格式库处理这些：

```asm
// 导入用于构造标准文件格式的统一接口。
import("format/format.inc");
```

格式库让源码描述目标映像，不需要手写表的计数、行位置、文件偏移、虚拟地址和文件头字段。

本章只介绍基本用法。完整的选项、导入导出、重定位、共享库、目标文件和底层辅助函数详见《可执行文件格式指南》。

## 声明段和权限

格式库程序的第一步：声明映像包含哪些 segment 或 section。每个描述符给出名称、用途和权限。

描述符列表是结构性的：
- 长度决定所需表的数量
- 顺序决定格式表的顺序
- 名称标识后续写入的内容块
- 用途选择格式特定的行为
- 权限成为 section/segment 属性

源文件不需要传表的计数或行号。增删描述符，格式结构自动更新。

## 完整示例：ELF64 程序

以下示例创建 x86-64 ELF 可执行文件，含一个可加载、可读、可执行的 segment：

```asm
// 导入格式接口，并选择 64 位 x86 指令编码。
import("format/format.inc");
x86.use64();

// 声明 ELF64 可执行映像及其唯一的可装载代码段。
const image0: map = format_elf64(
    format_elf_exec,
    list.of(
        format_segment(
            ".text",
            format_load | format_readable | format_executable
        )
    )
)
format_begin(image0);

// 在声明的 .text 段中写入程序入口代码。
format_segment_begin(image0, ".text");
start:
    // 调用 Linux 退出系统调用，并把退出状态设为零。
    mov eax, 60
    xor edi, edi
    syscall
format_segment_end(image0, ".text");

// 绑定入口标号，随后完成映像中的文件头和表项。
const image: map = format_entry(image0, start)
format_finish(image);
```

在 x86-64 Linux 下，这个程序以状态码 0 退出。

五步走：
1. `format_elf64` 创建 ELF64 计划。
2. `format_segment` 声明一个 segment 及其权限。
3. `format_begin` 写出计划决定的头部结构。
4. `format_segment_begin` 和 `format_segment_end` 包裹 segment 的实际指令和数据。
5. `format_entry` 绑定入口标签，`format_finish` 完成映像。

源文件不提供程序头计数、表行、文件偏移、加载地址或入口点字段偏移。格式库从计划表和已完成布局推导这些值。

## Section vs Segment

不同格式用不同的术语：
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

只打开计划中声明过的描述符，每个名称的用途与声明时一致。格式库由此把已写出的字节、逻辑大小、权限和生成的表关联到正确的格式条目。

## 构造函数系列

格式库支持以下映像类：

| 映像类 | 构造函数 |
| --- | --- |
| PE32 / PE64 映像 | `format_pe32`、`format_pe64` |
| COFF32 / COFF64 目标文件 | `format_coff32`、`format_coff64` |
| ELF32 / ELF64 可执行文件 | `format_elf32`、`format_elf64` |
| ELF32 / ELF64 目标文件 | `format_elfobj32`、`format_elfobj64` |
| ELF64 共享库 | `format_elf64_so` |

构造函数选项区分可执行文件与 DLL、控制台/GUI 子系统、位置无关、NX 策略、地址随机化等。Section/segment 描述符携带用途和读写执行权限。

完整的选项和描述符列表见《可执行文件格式指南》。

## 入口点绑定

可执行文件在源码定义入口代码后绑定标签：

```text
const image: map = format_entry(image0, start)
format_finish(image);
```

`format_entry` 返回更新后的计划。显式保持返回值让状态变化可见，也让 `format_finish` 能验证入口信息是否完整。

目标文件和部分库形式不需要入口点。按所选格式的生命周期来，不要加无意义的入口标签。

## 表自动生成

部分格式内容由高级声明生成，不作为普通数据字节写入：
- 导入导出表
- 符号表和字符串表
- 重定位记录
- 基址重定位段
- 动态元数据
- 资源目录

这些功能的格式库 API 接受名称、标签、权限和重定位类型。节区段编号、符号索引、表偏移、行号和计数由库内部推导。

不要用硬编码的表位置替代这些声明。格式库的作用就是让格式的簿记与实际布局保持一致。

## 普通库就够了

`format/format.inc` 是稳定的用户层，负责协调格式属性、描述符、命名内容块、入口和生成表。

各格式特有的 include 文件提供更低层次的构建块。某些暴露特定宽度的便捷封装，某些暴露直接的文件头、section、segment 或表辅助函数。这些适用于实现新的格式库布局，或普通库无法表达的专用布局。

仅仅为了生成常见的多 section 可执行文件、DLL、目标文件或共享库，不需要用底层 include。普通库支持目标映像时就优先用普通库。

不要随意混用抽象层次。底层辅助函数可能要求调用者管理计数、行号、偏移或格式不变式——这些在普通层由库维护。

## 后续阅读

《可执行文件格式指南》涵盖完整示例：
- PE32/PE64 可执行文件和 DLL
- COFF32/COFF64 目标文件
- ELF32/ELF64 可执行文件和位置无关可执行文件
- ELF32/ELF64 目标文件
- ELF64 共享库
- 多 section 和多 segment
- 已初始化和未初始化数据
- 导入、导出、符号、重定位
- 普通库与底层辅助函数的界限

已知所需格式系列时直接查 API Reference。

下一章讲诊断和源文件组织惯例。

[返回目录](../language.md)

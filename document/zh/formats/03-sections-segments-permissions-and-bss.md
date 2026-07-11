# 第 3 章：节、段、权限与未初始化数据区

可执行文件格式既要描述文件中保存的字节，也要描述加载这些字节后形成的内存映像。节、段、权限和未初始化数据区共同连接这两种视图。

常用格式接口会在内部处理各种文件格式的计算规则。源代码只需声明命名内容及其用途，格式接口会据此推导表项、文件位置、虚拟地址、大小和对齐方式。

本章把只在加载后占用内存、在文件中没有对应初始字节的空间称为未初始化数据区。这类区域通常使用 `.bss` 作为名称。

## 节和段回答不同的问题

**节**描述文件中一个有名称的组成部分。**段**描述 ELF 加载器映射到内存中的一段范围。

常用格式接口按以下方式使用它们：

| 文件格式系列 | 描述项 | 主要用途 |
| --- | --- | --- |
| PE 可执行文件或动态链接库 | 节 | 组织文件内容并描述映像映射 |
| COFF 目标文件 | 节 | 保存链接器输入、符号和重定位信息 |
| ELF 目标文件 | 节 | 保存链接器输入和节元数据 |
| ELF 可执行文件或位置无关可执行文件 | 段 | 描述运行时的 `LOAD` 映射 |
| ELF 共享对象 | 段 | 描述运行时的 `LOAD` 映射 |

PE 的节同时携带文件布局和内存权限信息。ELF 程序则把运行时内容放入可加载段。ELF 目标文件仍然使用节，因为它们是链接器的输入，而不是完整的运行时映像。

这一区别会影响描述项的构造方式：

```text
format_section(name, purpose | permissions)
format_segment(name, format_load | permissions)
```

不要把 `format_data` 等节用途传给 `format_segment`。普通 ELF 程序的段使用 `format_load`，再由权限和实际内容区分代码、只读数据、可写数据与未初始化数据区。

## 每个节只能有一种用途

一个节描述项必须且只能包含一种用途。常用格式接口定义了以下节用途：

| 用途 | 适合保存的内容 |
| --- | --- |
| `format_code` | 指令和可执行数据 |
| `format_data` | 已初始化数据 |
| `format_uninitialized_data` | 未初始化数据区使用的空间 |
| `format_imports` | 自动生成的 PE 导入数据 |
| `format_exports` | 自动生成的 PE 导出数据 |
| `format_resources` | PE 资源 |
| `format_fixups` | PE 基址重定位信息 |

前三种用途可以用于 PE、COFF 和 ELF 目标文件方案。其余用途描述自动生成的 PE 节，将在 Windows 文件格式相关章节中介绍。

不能在一个节描述项中合并两种用途：

```text
format_section(
    ".bad",
    format_code | format_data | format_readable
)
```

格式接口无法从这种描述项推导出一致的节属性，因此会在开始输出前拒绝该格式方案。

## 权限描述加载后的内存

权限是独立的标志，可以与一种用途组合：

| 权限 | 含义 |
| --- | --- |
| `format_readable` | 映射后的内存范围可以读取 |
| `format_writeable` | 映射后的内存范围可以写入 |
| `format_executable` | 处理器可以执行该内存范围中的指令 |
| `format_discardable` | PE 可以在使用后丢弃该节 |

`format_discardable` 只适用于普通 PE 节方案。COFF 目标文件和 ELF 目标文件不接受该标志，ELF 程序段也不接受该标志。

常见的组合如下：

```text
format_code | format_readable | format_executable
format_data | format_readable
format_data | format_readable | format_writeable
format_uninitialized_data | format_readable | format_writeable
format_load | format_readable | format_executable
format_load | format_readable | format_writeable
```

汇编器不会阻止一个内存映射同时具有可写和可执行权限，但大多数程序都应把代码与可变数据分开。可以采用以下清晰的默认规则：

- 代码可读、可执行；
- 常量只读；
- 已初始化的可变数据可读、可写；
- 未初始化数据区可读、可写。

这些权限描述的是生成后的文件格式，不会限制汇编器在构造文件时能够读取或写入什么内容。

## 命名内容必须匹配描述项种类

节使用节的构建流程：

```text
format_section_begin(plan, ".text")
    ...
format_section_end(plan, ".text")
```

段使用段的构建流程：

```text
format_segment_begin(plan, ".text")
    ...
format_segment_end(plan, ".text")
```

名称用于查找已经保存在格式方案中的描述项，并不会声明一个新的节或段。开始调用会确定内容的逻辑起点和实际文件起点，结束调用会关闭这段范围，使格式接口能够确定最终大小。

应使用与格式方案匹配的构建流程：

- PE、COFF 和 ELF 目标文件方案使用节相关调用；
- ELF 可执行文件、位置无关可执行文件和共享对象方案使用段相关调用。

把段方案传给 `format_section_begin`，或者把节方案传给 `format_segment_begin`，都会产生错误，不会自动转换。

## 文件中的实际字节与仅存在于内存的空间

指令和数据会在文件中写出真实字节。预留空间会增加逻辑大小，但不一定增加最终文件的字节数。

当预留空间位于节或段的末尾时，常用格式接口可以把它表示为仅存在于内存的空间：

```text
bss_start:
    rb(64)
```

这正是未初始化数据区的核心关系：

```text
逻辑大小 > 文件中有实际字节的大小
```

对于完全由 64 字节预留空间组成的未初始化数据区：

```text
文件中有实际字节的大小 = 0
逻辑大小                 = 64
```

对于一个 ELF 可加载段，如果开头有 4 个已初始化字节，后面有 64 个预留字节：

```text
文件中有实际字节的大小 = 4
逻辑大小                 = 68
```

加载器从文件中取得已初始化的开头部分，并为剩余范围提供已经清零的内存。

预留空间必须留在末尾，才能不占用文件字节。如果在同一输出区域的预留间隙之后继续写出字节，这段间隙就会成为文件布局的一部分。如果一段空间必须完全不出现在文件中，应为它使用单独的未初始化数据区描述项。

底层的逻辑位置和实际文件位置模型见[输出区域与虚拟数据](../language/11-output-regions-and-virtual-data.md)。使用常用格式接口的源代码通常不需要直接调用区域相关接口。

## 节和段中的未初始化数据区

不同文件格式系列使用不同方式表达未初始化数据区。

对于 PE、COFF 和 ELF 目标文件，应声明一个未初始化数据节：

```text
format_section(
    ".bss",
    format_uninitialized_data
        | format_readable
        | format_writeable
)
```

最终含义取决于具体文件格式：

- PE 记录节的虚拟大小，但不保存该节的原始字节；
- COFF 把该节标记为未初始化数据；
- ELF 目标文件使用一种不在文件中保存数据的节类型。

对于 ELF 可执行文件、位置无关可执行文件和共享对象，应声明一个可写的加载段，并且只在其中预留空间：

```text
format_segment(
    ".bss",
    format_load | format_readable | format_writeable
)
```

程序头随后会记录文件大小为零、内存大小不为零。段没有单独的 `format_bss` 用途。

## 包含四种节角色的 PE64 映像

下面的示例把代码、常量、可变数据和未初始化数据区分别放入不同的节：

```asm
// 导入常用格式接口，并选择 64 位 x86 指令模式。
import("format/format.inc");
x86.use64();

// 按代码、只读数据、可写数据和未初始化数据声明四个节。
const image0: map = format_pe64(
    format_pe_exe
        | format_pe_console
        | format_pe_nx
        | format_pe_aslr_auto,
    list.of(
        format_section(
            ".text",
            format_code | format_readable | format_executable
        ),
        format_section(
            ".rdata",
            format_data | format_readable
        ),
        format_section(
            ".data",
            format_data | format_readable | format_writeable
        ),
        format_section(
            ".bss",
            format_uninitialized_data
                | format_readable
                | format_writeable
        )
    )
)
format_begin(image0);

// 在可读、可执行的代码节中写入程序入口。
format_section_begin(image0, ".text");
start:
    xor eax, eax
    ret
format_section_end(image0, ".text");

// 只读数据节保存以零结尾的常量字符串。
format_section_begin(image0, ".rdata");
message:
    db("ready", 0);
format_section_end(image0, ".rdata");

// 可写数据节保存具有初始值的计数器。
format_section_begin(image0, ".data");
counter:
    dq(1);
format_section_end(image0, ".data");

// 未初始化数据节只预留空间，不向文件写入原始字节。
format_section_begin(image0, ".bss");
workspace:
    rb(64);
format_section_end(image0, ".bss");

// 绑定入口标号，并根据最终布局完成 PE64 文件映像。
const image: map = format_entry(image0, start)
format_finish(image);
```

节表会按照声明顺序记录四个表项。`.text`、`.rdata` 和 `.data` 占用文件空间；`.bss` 的逻辑大小为 64 字节，原始数据大小为零。

PE 的文件对齐与映像对齐是两项不同的规则。文件中有实际字节的节数据使用 PE 文件对齐，节的虚拟地址则按照 PE 节对齐向前排列。常用格式接口会同时应用这两项规则。

## 在文件数据段之间放置未初始化数据区的 ELF64 映像

下面的示例特意把一个纯未初始化数据段放在最后一个只读段之前：

```asm
// 导入常用格式接口，并选择 64 位 x86 指令模式。
import("format/format.inc");
x86.use64();

// 声明代码、可写数据、未初始化数据和只读数据四个加载段。
const image0: map = format_elf64(
    format_elf_exec,
    list.of(
        format_segment(
            ".text",
            format_load | format_readable | format_executable
        ),
        format_segment(
            ".data",
            format_load | format_readable | format_writeable
        ),
        format_segment(
            ".bss",
            format_load | format_readable | format_writeable
        ),
        format_segment(
            ".rodata",
            format_load | format_readable
        )
    )
)
format_begin(image0);

// 代码段通过系统调用以状态码零退出。
format_segment_begin(image0, ".text");
start:
    mov eax, 60
    xor edi, edi
    syscall
format_segment_end(image0, ".text");

// 可写数据段保存一个已经初始化的计数器。
format_segment_begin(image0, ".data");
counter:
    dq(1);
format_segment_end(image0, ".data");

// 该段只预留 128 字节内存，不在文件中写出数据。
format_segment_begin(image0, ".bss");
workspace:
    rb(128);
format_segment_end(image0, ".bss");

// 后续只读段仍会写入文件，但虚拟地址位于未初始化数据区之后。
format_segment_begin(image0, ".rodata");
message:
    db("ready", 0);
format_segment_end(image0, ".rodata");

// 绑定入口标号，并根据最终布局完成 ELF64 文件映像。
const image: map = format_entry(image0, start)
format_finish(image);
```

未初始化数据段会占用 128 字节内存，但在文件中不占用任何字节。因此，后面的 `.rodata` 段可以从未初始化数据段起点所在的同一文件偏移开始；它的虚拟地址仍然会越过未初始化数据段占用的内存范围。

ELF 加载对齐不要求在文件中留下整页大小的空洞。格式接口会紧凑排列文件偏移，同时选择满足以下关系的虚拟地址：

```text
虚拟地址除以对齐值的余数 = 文件偏移除以对齐值的余数
```

这样既能满足加载器的对齐要求，也不必在文件中写入无用的整页填充。

## 对齐由格式接口推导

使用常用格式接口的源代码不应手工对齐节表项、程序头表项、原始数据指针、相对虚拟地址或加载地址。

格式接口会应用对应文件格式的规则：

- PE 分别处理文件对齐和节的虚拟地址对齐；
- COFF 与 ELF 目标文件根据用途和位数选择节对齐；
- ELF 加载段保持所需的页对齐；
- 不占用文件字节的未初始化数据区只增加逻辑内存大小，不会在文件中产生整页空洞；
- 后续文件数据从已经确定的实际文件位置继续写入。

显式的输出区域对齐适合高级的自定义布局。把它混入常用格式方案，可能会重复应用或违背格式接口的布局规则。

## 无效的属性组合会被尽早拒绝

描述项会拒绝不适用于自身种类的属性：

```text
format_section(
    ".text",
    format_code | format_load | format_readable
)
```

`format_load` 是段的用途，因此上面的节声明无效。

其他限制包括：

- 节描述项拒绝未知标志；
- 段描述项拒绝节用途标志；
- ELF 目标文件的节拒绝 PE 专用的可丢弃属性；
- COFF 目标文件的节只接受代码、数据和未初始化数据三种用途；
- 每个描述项必须且只能包含一种用途；
- 同一格式方案中的名称必须唯一。

这些错误可以防止源代码悄悄请求一种最终文件格式会忽略的属性。

## 实用布局规则

规划普通内容时，可以采用以下默认规则：

1. 不同的权限或存储角色分别使用独立的描述项。
2. 代码设为可读、可执行，但不可写。
3. 常量设为可读、不可写。
4. 可变数据和未初始化数据区设为可读、可写。
5. PE、COFF 和 ELF 目标文件的未初始化数据区使用 `format_uninitialized_data`。
6. ELF 运行时未初始化数据区使用只预留空间、可写的 `format_load` 段。
7. 不占用文件字节的预留空间必须位于节或段的末尾。
8. 按照格式方案中的顺序写入描述项，并关闭每个已经开始的内容块。
9. 让格式接口推导数量、地址、偏移、大小和对齐。

第 4 章将在这些布局规则的基础上介绍地址、符号、地址回填项和重定位。

[返回可执行文件格式指南](../formats.md)

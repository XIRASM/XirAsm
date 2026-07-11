# 第 4 章：地址、符号与重定位

标号为源代码中的逻辑地址提供稳定名称。可执行文件格式和目标文件格式再把这个地址转换成文件头、符号表、重定位记录、指令字段或加载器所需的坐标。

最重要的原则是保留每种坐标的含义。虚拟地址、相对虚拟地址、节内偏移和文件偏移可以从不同角度描述同一个字节，但它们不能相互替代。

## 明确所需的地址坐标

常用格式接口会处理以下几种地址形式：

| 地址坐标 | 含义 |
| --- | --- |
| 逻辑地址 | 标号在当前输出区域中的值 |
| 虚拟地址 | 文件映像加载到内存后使用的地址 |
| 相对虚拟地址 | PE 中相对于映像基址的虚拟地址 |
| 节内偏移 | 相对于目标文件中某个节起点的位置 |
| 文件偏移 | 生成文件中的实际字节位置 |

例如，PE 入口标号具有逻辑地址，而 PE 文件头保存的是它的相对虚拟地址。目标文件中的符号保存相对于所属节起点的值，节表项则保存该节字节在文件中的偏移。

普通源代码应把标号和节起始标号交给格式接口，不应自行计算这些派生值：

```text
format_entry(image0, start)
format_coff_public("caller", ".text", text_start, caller, ...)
format_coff_reloc(".text", text_start, patch_field, "callee", ...)
```

格式接口会根据所选文件格式推导入口的相对虚拟地址、符号值、重定位偏移、表项索引和文件位置。

不要把文件偏移当作指针。文件偏移标识文件中保存的字节，虚拟地址和逻辑地址标识加载后的内存位置。

## 指令内部引用使用汇编器地址回填项

指令引用源代码中的标号时，通常不需要显式声明格式重定位：

```text
start:
    jmp finished
    nop

finished:
    ret
```

汇编器会记录指令中的符号操作数，确定最终的指令布局，再把编码后的位移写入指令字段。这项记录称为**汇编器地址回填项**。

如果目标标号在汇编期间已经确定，而且所选文件格式不需要其他程序再次调整这个字段，地址回填就会在生成文件时完全解决。

只要条件允许，就应直接在指令操作数中使用标号，不要改写为手工计算的位移。

## 入口地址属于最终文件映像

PE 可执行文件和动态链接库，以及 ELF 可执行文件和可在任意地址加载的位置无关可执行文件，都需要入口地址：

```text
const image: map = format_entry(image0, start)
format_finish(image)
```

`format_entry` 把入口标号的逻辑地址保存到一个新的格式方案中。完成格式时，收尾处理会写入相应文件映像要求的地址形式：

- PE 保存相对于映像基址的相对虚拟地址；
- ELF 保存可执行代码的虚拟地址。

必须先定义入口标号，再绑定入口地址，并把更新后的格式方案传给 `format_finish`。

目标文件和 ELF 共享对象不使用这个构建步骤。目标文件通过符号向链接器公布名称；共享对象公布导出符号和动态元数据。把这两类格式方案传给 `format_entry` 会产生错误。

## 地址回填与重定位是不同操作

“重定位”有时会泛指几种相近的机制。使用时必须区分由谁处理以及解决什么问题：

| 机制 | 处理者 | 用途 |
| --- | --- | --- |
| 汇编器地址回填项 | 汇编器 | 解析已知符号，并写入对应的指令字段 |
| 目标文件重定位 | 链接器 | 在最终链接时解析符号或调整符号位置 |
| PE 基址重定位 | 加载器 | 文件映像更换加载基址后，调整其中的绝对地址 |
| 动态重定位 | 动态加载器 | 在运行时解析导入项或调整可移动数据 |

同一文件内的分支可能只需要汇编器地址回填项。调用外部目标文件符号时，需要目标文件重定位。可重定位 PE 文件映像中的绝对指针即使指向同一份源代码中定义的标号，也需要 PE 基址重定位。

ELF 动态导入和位置无关数据将在 ELF 相关章节中介绍。本章先建立这些格式共用的地址模型。

## 稳定的绝对值应在布局完成后写入

指令操作数可以保持符号形式，直到汇编器解析地址回填项。普通整数表达式则不会自动保留这种符号关系。

如果数据中需要保存绝对指针，应先预留字段，再在 `defer` 收尾块中写入最终地址：

```text
entry_pointer:
    dq(0)

defer {
    store.u64(entry_pointer, start);
}
```

收尾处理会在指令长度、输出区域、标号和整体布局全部稳定后运行，因此写入的是真正的逻辑地址，而不是布局过程中的临时值。

这次回填解决的是字段当前应保存什么值，但它不会自动通知操作系统加载器：当文件映像换到另一个基址时还要修改该字段。PE 文件映像需要通过基址重定位描述第二项操作。

## PE 基址重定位标识绝对地址字段

PE 基址重定位描述的是一个字段的位置，该字段保存与首选映像基址相关的绝对虚拟地址。加载器更改文件映像的加载基址时，会把映像基址的变化量加到这个字段中。

常用格式接口把整个过程分成四步：

1. 写出一个绝对地址字段；
2. 把该字段的逻辑地址加入重定位列表；
3. 写出自动生成的重定位节；
4. 回填最终的绝对指针值。

`format_pe_reloc_add` 会根据 PE 格式方案选择重定位宽度：

- PE32 使用 32 位高低位重定位；
- PE64 使用 64 位重定位。

调用者提供绝对地址字段的逻辑地址。格式接口会推导其相对虚拟地址，按页对重定位项分组并排序，然后写出重定位目录。

## 包含可重定位指针的 PE64 可执行文件

下面的文件映像要求支持地址空间布局随机化，并包含一个绝对指针：

```asm
// 创建要求支持地址空间布局随机化的 PE64 控制台文件映像。
import("format/format.inc");
x86.use64();

const image0: map = format_pe64(
    format_pe_exe
        | format_pe_console
        | format_pe_nx
        | format_pe_aslr_required,
    list.of(
        format_section(
            ".text",
            format_code | format_readable | format_executable
        ),
        format_section(
            ".reloc",
            format_fixups | format_readable | format_discardable
        )
    )
)
format_begin(image0);

// 在代码节中写入入口代码，并预留一个保存绝对虚拟地址的字段。
format_section_begin(image0, ".text");
start:
    xor eax, eax
    ret

entry_pointer:
    dq(0);
format_section_end(image0, ".text");

// 登记绝对地址字段，由格式接口生成 PE 基址重定位节。
const relocs0: list = pe_reloc_new()
const relocs: list = format_pe_reloc_add(
    image0,
    relocs0,
    entry_pointer
)
format_pe_reloc_section(image0, ".reloc", relocs);

// 绑定入口标号并完成文件映像。
const image: map = format_entry(image0, start)
format_finish(image);

defer {
    // 布局稳定后，把入口的最终逻辑地址写入绝对地址字段。
    store.u64(entry_pointer, start);
}
```

指针字段最终保存 `start` 的地址，重定位目录则把 `entry_pointer` 标记为加载器更改映像基址时必须调整的字段。

`format_pe_aslr_required` 明确要求文件映像能够重定位。如果缺少重定位目录，汇编会失败，而不会在实际上无法重定位时仍然声称支持地址空间布局随机化。

## 目标文件符号描述链接器可见的名称

目标文件还没有最终运行时地址。它通过符号和重定位信息，让链接器随后放置各个节并解析相互引用。

常用目标文件接口使用两类符号：

- **公开符号**由当前目标文件定义；
- **外部符号**由其他目标文件或库提供。

声明公开符号时需要提供：

```text
名称
节名称
节起始标号
符号地址
符号类型
```

ELF 目标文件还会记录符号大小。格式接口根据下面的关系推导相对于节起点的符号值：

```text
符号值 = 符号地址 - 节起始地址
```

外部符号没有当前文件中的节或地址，它的名称会成为重定位目标。

## 目标文件重定位标识待修改字段

一项目标文件重定位会关联四项信息：

```text
包含待修改字段的节
字段在该节中的偏移
目标符号名称
重定位类型
```

源代码传入节起始标号和待修改字段的标号，格式接口据此推导相对于节起点的重定位偏移：

```text
重定位偏移 = 待修改字段地址 - 节起始地址
```

符号索引由符号声明列表的内容决定，调用者不需要自行计算。

COFF 的重定位加数保存在待修改字段的字节中。ELF 的某些重定位形式可以另外携带显式加数。目标文件相关章节会分别说明不同字段宽度使用的重定位类型和加数约定。

## 调用外部函数的 COFF64 目标文件

外部符号不是当前源代码中的标号，因此示例先写入调用位移的占位值，再为该字段声明重定位：

```asm
// 创建只包含一个代码节的 COFF64 目标文件。
import("format/format.inc");
x86.use64();

const object0: map = format_coff64(
    list.of(
        format_section(
            ".text",
            format_code | format_readable | format_executable
        )
    )
)
format_begin(object0);

// 写入 call 操作码，并为尚未解析的相对位移保留四个字节。
format_section_begin(object0, ".text");
text_start:
caller:
    db(0xe8);
call_displacement:
    dd(0);
    ret
format_section_end(object0, ".text");

// 公布当前目标文件定义的 caller，并声明外部函数 callee。
const symbols: list = list.of(
    format_coff_public(
        "caller",
        ".text",
        text_start,
        caller,
        coff_sym_type_function
    ),
    format_coff_extern(
        "callee",
        coff_sym_type_function
    )
)
// 将调用位移字段连接到 callee 的相对地址重定位。
const relocs: list = list.of(
    format_coff_reloc(
        ".text",
        text_start,
        call_displacement,
        "callee",
        coff_rel_amd64_rel32
    )
)
const object: map = format_coff_tables(object0, symbols, relocs)
format_finish(object);
```

生成的目标文件包含：

- `.text` 节中的一个公开符号 `caller`；
- 一个尚未定义的外部符号 `callee`；
- `call_displacement` 位置的一项相对重定位；
- 一个通过符号名称解析的重定位目标。

符号表和重定位表会在 `format_finish` 阶段写出。表项索引、文件偏移和表项数量均由格式方案推导。

## ELF 目标文件使用相同的声明模型

ELF 目标文件也通过相同的源代码关系声明符号和重定位：

```text
format_elfobj_public(
    name,
    section_name,
    section_start,
    address,
    size,
    symbol_type
)

format_elfobj_extern(name, symbol_type)

format_elfobj_reloc(
    section_name,
    section_start,
    patch_address,
    symbol_name,
    relocation_type,
    addend
)
```

格式接口会创建 ELF 目标文件所需的符号表、字符串表、重定位节和节表项链接。调用者只需提供名称、标号、符号含义、重定位类型和加数。

ELF32 和 ELF64 的具体重定位形式留到 ELF 目标文件章节说明，以便本章始终使用同一套地址坐标模型。

## 格式接口会检查重定位声明

构建目标文件数据表时，会拒绝以下相互矛盾的声明：

- 公开符号指定的节必须已经声明；
- 用户符号列表中的符号名称不能重复；
- 重定位字段不能位于所属节起始地址之前；
- 格式方案中必须存在用于保存重定位记录的节；
- 每个重定位目标名称都必须对应一个已声明符号。

PE 重定位节还必须至少包含一项重定位，并且对应的节必须以 `format_fixups` 用途声明。

这些检查可以防止无效符号索引或属于其他节的地址坐标进入生成文件。

## 不要混淆指针值与重定位记录

字段中保存的值和重定位记录解决的是两个不同问题：

```text
保存的指针值 = 字段当前写入的地址
重定位记录   = 以后如何修改该字段的说明
```

在目标文件中，占位值为零的字段加上一项重定位记录已经足够，因为最终值由链接器填写。完整的 PE 文件映像还必须先在字段中保存当前绝对地址，加载器才能在此基础上加上基址变化量。

同样，如果相对分支的位移已经在汇编期间完全确定，就不需要格式重定位记录。

## 地址与重定位的实用规则

1. 使用标号表示逻辑地址和指令目标。
2. 让汇编器地址回填项解析指令内部的符号字段。
3. `format_entry` 只用于 PE 或 ELF 可执行文件格式方案。
4. 把绑定入口后的新格式方案传给 `format_finish`。
5. 始终区分文件偏移、虚拟地址和相对虚拟地址。
6. 原始数据字段需要稳定的绝对地址时，在收尾处理中回填。
7. 绝对地址字段需要随 PE 映像基址变化时，为每个字段添加 PE 基址重定位。
8. 通过名称声明目标文件中的公开符号和外部符号。
9. 使用节起始标号和待修改字段标号声明目标文件重定位。
10. 让格式接口分配符号索引、重定位表项和文件位置。

第二部分将把这些基础规则应用到 Windows 文件格式，首先介绍 PE32 和 PE64 可执行文件的构造方法。

[返回可执行文件格式指南](../formats.md)

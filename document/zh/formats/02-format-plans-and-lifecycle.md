# 第 2 章：格式方案与构建流程

## 格式方案是编译期值

常用格式构造函数会返回一个 `map`：

```text
const image0: map = format_pe64(
    format_pe_exe
        | format_pe_console
        | format_pe_nx
        | format_pe_aslr_auto,
    list.of(
        format_section(
            ".text",
            format_code | format_readable | format_executable
        )
    )
)
```

这个映射是对要生成文件的编译期描述。它不是已经完成的文件字节映像，创建格式方案也不会写入节的内容。

格式方案会记录对应文件格式所需的信息：

| 方案类别 | 核心信息 |
| --- | --- |
| PE 映像 | 位数、映像选项、节、入口，以及可选的自动生成数据 |
| COFF 目标文件 | 位数、节、公开或外部符号，以及重定位 |
| ELF 可执行文件 | 位数、文件模式、可加载段、入口，以及可选的导入 |
| ELF 目标文件 | 位数、节、公开或外部符号，以及重定位 |
| ELF 共享对象 | 共享对象名称（`SONAME`）、可加载段、导出和导入 |

后续辅助函数可能返回一份加入了更多信息的新方案。每次都用新的绑定保存返回值，可以让整个构建流程清楚可见。

## 描述项定义预定布局

节和段必须在 `format_begin` 之前声明：

```text
const sections: list = list.of(
    format_section(
        ".text",
        format_code | format_readable | format_executable
    ),
    format_section(
        ".rdata",
        format_data | format_readable
    )
)
```

每个描述项包含：

- 供后续构建流程调用使用的名称；
- 一种内容用途；
- 一组访问权限；
- 根据这些值推导出的格式专用属性。

描述项列表本身具有结构含义：

| 列表属性 | 作用 |
| --- | --- |
| 长度 | 决定预定的节表项或段表项数量 |
| 顺序 | 决定表项顺序和运行时映射顺序 |
| 名称 | 将后续内容块连接到对应的描述项 |
| 用途 | 选择代码、数据、未初始化数据区（BSS）、导入、导出或其他行为 |
| 权限 | 选择可读、可写、可执行或可丢弃属性 |

命名内容应当按照描述项的声明顺序写入。PE 和目标文件中的表会按照描述项顺序排列各个表项；ELF 可加载段在分配逻辑映射时也使用这一顺序。

## 格式方案在创建时验证

如果一组参数无法描述结构一致的文件格式，构造函数会直接拒绝这份方案。

描述项通常遵循以下规则：

- 节或段列表不能为空；
- 名称不能为空，也不能重复；
- 每个描述项必须恰好具有一种用途；
- 互斥选项不能组合使用；
- PE 中用于导入或导出等特殊用途的节不能重复；
- 段属性必须符合 ELF 常用接口的要求。

PE 和当前的 COFF 常用接口要求节名称能够放入八字节的节名称字段。ELF 目标文件通过 `.shstrtab` 保存名称，因此可以使用更长的名称：

```text
.text
.data
.rodata.long
```

这些检查会在写出文件头或实际内容之前完成。因此，格式错误的方案会在构造时失败，而不会生成一个只有部分结构有效的文件。

## 格式构建流程的五个阶段

使用常用格式接口的源代码遵循五个阶段。

### 1. 创建格式方案

选择文件格式、选项和完整的描述项列表：

```text
const plan0 = format_*(options, descriptors)
```

目标文件和共享库的构造函数可能使用不同的参数，但它们同样会返回一份格式方案。

### 2. 开始构造格式

开始构造所选文件格式：

```text
format_begin(plan0);
```

`format_begin` 会根据方案类别写出或预留该格式所需的初始结构，例如可执行文件头、程序头表项、目标文件头，以及只能在布局确定后补全的字段。

完整的描述项列表准备好之后、开始写入预定内容之前，只调用一次 `format_begin`。

### 3. 写入命名内容

依次打开每个已经声明的节或段，写入其中的指令或数据，然后将其关闭：

```text
format_section_begin(plan0, ".text");
start:
    xor eax, eax
    ret
format_section_end(plan0, ".text");
```

名称必须已经存在于格式方案中。开始调用会把当前输出位置与对应的描述项表项关联起来；结束调用会关闭实际文件范围，并记录该格式所需的最终逻辑大小和文件中有实际字节的数据大小。

ELF 可执行文件和共享对象的可加载段使用 `format_segment_begin` 与 `format_segment_end`。PE、COFF 和 ELF 目标文件使用节相关调用。

### 4. 附加最终信息

有些信息只有在相应标号或声明出现之后才能取得。可执行文件的入口是最简单的例子：

```text
const image: map = format_entry(image0, start)
```

`format_entry` 会返回一份新方案，而不会修改名为 `image0` 的绑定。下一项构建操作必须接收这个返回值。

附加目标文件符号、重定位、可执行文件导入或共享对象数据表的辅助函数，也遵循同样的值传递方式：

```text
const plan1 = attach_one_group(plan0, declarations)
const plan2 = attach_another_group(plan1, more_declarations)
format_finish(plan2)
```

这些辅助函数的准确名称将在对应的格式章节和独立的格式接口参考中介绍。

### 5. 完成格式

完成所选文件：

```text
format_finish(image);
```

不同文件格式在完成阶段承担不同工作：

- PE 映像会确定入口，并补全由方案管理的目录信息；
- ELF 可执行文件会确定入口，并补全可选的动态元数据；
- COFF 和 ELF 目标文件会写出符号表、字符串表和重定位表；
- ELF 共享对象会写出动态元数据、符号表、字符串表、导出和导入信息。

`format_finish` 还会拒绝缺少必要构建信息的方案。PE 映像和 ELF 可执行文件要求入口地址非零；目标文件和共享对象会完成各自的数据表，但不会凭空添加可执行入口。

## 完整的双节格式方案

下面的可执行文件会先声明两个节，再写入其中任何一个节的内容：

```asm
// 导入常用格式接口，并选择 64 位 x86 指令模式。
import("format/format.inc");
x86.use64();

// 提前声明代码节和只读数据节，顺序同时决定节表项顺序。
const sections: list = list.of(
    format_section(
        ".text",
        format_code | format_readable | format_executable
    ),
    format_section(
        ".rdata",
        format_data | format_readable
    )
)

// 使用完整的描述项列表创建并开始 PE64 格式方案。
const image0: map = format_pe64(
    format_pe_exe
        | format_pe_console
        | format_pe_nx
        | format_pe_aslr_auto,
    sections
)
format_begin(image0);

// 写入 .text 节，并记录程序入口标号。
format_section_begin(image0, ".text");
start:
    xor eax, eax
    ret
format_section_end(image0, ".text");

// 按声明顺序写入 .rdata 节中的零结尾文本。
format_section_begin(image0, ".rdata");
message:
    db("hello", 0);
format_section_end(image0, ".rdata");

// 保存附加入口后的新方案，再完成整个文件映像。
const image: map = format_entry(image0, start)
format_finish(image);
```

格式方案把 `.text` 确定为第 0 个表项，把 `.rdata` 确定为第 1 个表项。后续开始调用使用这些名称，不需要调用者自行提供表项编号。

增加第三个描述项时，只需增加一个新的命名内容块，不需要手工修改节数量、文件头大小、表项偏移、原始数据指针或相对虚拟地址。

## 必须保留更新后的格式方案

下面的写法正确：

```text
const image: map = format_entry(image0, start)
format_finish(image)
```

下面的写法完成的是旧方案，因此会失败：

```text
const image: map = format_entry(image0, start)
format_finish(image0)
```

返回的 `image` 包含入口地址，`image0` 中的入口仍然是原来的零值。

可以使用 `image0`、`image1` 和 `image` 等不同名称，也可以根据附加的数据命名。关键规则是始终把最新的格式方案传递给下一项操作。

## 构建流程错误会被明确拒绝

常用格式接口不会暗中猜测用户意图，而是直接拒绝无效的构建操作。

| 错误 | 结果 |
| --- | --- |
| 描述项列表为空 | 构造函数拒绝格式方案 |
| 描述项名称重复 | 构造函数拒绝格式方案 |
| 一个描述项具有多种用途 | 创建描述项失败 |
| 节或段名称未知 | 开始调用或相关声明失败 |
| 缺少可执行入口 | `format_finish` 失败 |
| 构建调用与方案类别不匹配 | 调用拒绝该方案类别 |

例如，下面两个描述项不能同时存在：

```text
format_section(".text", format_code | format_readable)
format_section(".text", format_data | format_readable)
```

重复名称会让后续的 `format_section_begin(plan, ".text")` 等调用无法确定对应的描述项，因此格式方案会在开始输出之前被拒绝。

## 自动生成的内容仍由格式方案管理

并非每一种格式数据表都会由用户作为节或段手工写出。导入、导出、动态元数据、符号表、字符串表和重定位表，都可能根据附加到格式方案的声明自动生成。

这些自动生成的内容仍然遵循同一构建流程：

1. 描述项预留用户可见的结构；
2. 命名内容块确定实际布局信息；
3. 声明辅助函数附加名称、标号和重定位信息；
4. `format_finish` 写出或补全由格式方案管理的元数据。

因此，当常用格式接口已经支持导入或重定位时，不应绕过格式方案，另行手工写入相关数据表字节。手工数据表会绕过负责管理数量、索引和最终位置的格式方案。

## 格式方案的实用规则

使用常用格式接口编写源代码时，可以按照下面的清单检查：

1. 首先声明完整的节或段列表。
2. 为每个描述项使用唯一且含义明确的名称。
3. 为每个描述项指定恰好一种用途和所需权限。
4. 只调用一次 `format_begin`。
5. 按照声明顺序写入各个描述项。
6. 使用正确类别的构建调用打开和关闭每个命名内容块。
7. 保留入口或数据表辅助函数返回的每一份更新方案。
8. 把最新的格式方案传给 `format_finish`。
9. 让格式接口推导数量、表项、偏移、大小和自动生成的数据表。

第 3 章将说明这些描述项在运行时的含义，包括节、可加载段、权限、文件中有实际字节的数据、未初始化数据区、逻辑大小、实际文件大小和对齐。

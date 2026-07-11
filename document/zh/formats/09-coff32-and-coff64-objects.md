# 第 9 章：COFF32 与 COFF64 目标文件

COFF 目标文件不是操作系统可以直接加载的程序。它由节、符号和交给链接器处理的重定位请求组成。

因此，目标文件的格式构建流程与可执行文件不同：

- 没有 PE 可选文件头；
- 没有子系统或映像基址；
- 没有可执行入口；
- 公开符号表示本目标文件提供的定义；
- 外部符号表示需要由其他目标文件或库提供的定义；
- 重定位告诉链接器，哪些已编码字段依赖这些符号。

常用格式接口会在内部管理节编号、符号索引、重定位表项和各数据表的文件偏移。

## 创建目标文件方案

32 位 x86 目标文件使用 `format_coff32`，64 位 x86 目标文件使用 `format_coff64`：

```text
const object0: map = format_coff64(
    list.of(
        format_section(
            ".text",
            format_code | format_readable | format_executable
        ),
        format_section(
            ".data",
            format_data | format_readable | format_writeable
        ),
        format_section(
            ".bss",
            format_uninitialized_data | format_readable | format_writeable
        )
    )
)
```

描述项的顺序就是 COFF 节的顺序。格式接口会推导节数量，并为每个描述项写入一个节表项。

目标文件中的节采用与 PE 节相同的常用构建流程：

```text
format_begin(object0)
format_section_begin(object0, ".text")
...
format_section_end(object0, ".text")
```

不要调用 `format_entry`。目标文件通过符号公开定义；当多个目标文件被链接成最终映像时，才会选择可执行文件的入口。

## 公开符号描述本文件提供的定义

`format_coff_public` 声明一个由目标文件内某个节定义的符号：

```text
format_coff_public(
    "main",
    ".text",
    text_start,
    main,
    coff_sym_type_function
)
```

各参数依次表示：

1. 链接器可见的符号名称；
2. 声明该符号所属的节名称；
3. 该节起始位置的标号；
4. 符号自身的标号；
5. COFF 符号类型。

格式接口会计算符号所属的节编号，以及符号相对于该节起点的值。源代码不需要传入这两个数值字段。

可调用的代码使用 `coff_sym_type_function`，普通数据使用 `coff_sym_type_null`。

## 外部符号描述本文件所需的定义

`format_coff_extern` 声明一个必须由其他位置提供的符号：

```text
format_coff_extern("helper", coff_sym_type_function)
```

生成的符号没有定义它的节。链接器随后会在参与链接的其他目标文件和库中查找名称匹配的定义。

当前常用 COFF 构建流程使用能够放入八字节 COFF 名称字段的名称。节名称、公开符号名称、外部符号名称和重定位目标名称都应限制在这个范围内。

## 重定位标记编码中的待修改字段

调用外部函数时，指令中有一个四字节位移字段。链接器知道目标地址后才能确定该字段的最终值，因此需要先写入占位值，并在字段本身的位置定义标号：

```text
db(0xe8)
helper_disp:
dd(0)
```

重定位应引用位移字段的标号，而不是调用指令的操作码：

```text
format_coff_reloc(
    ".text",
    text_start,
    helper_disp,
    "helper",
    coff_rel_amd64_rel32
)
```

格式接口会推导：

- 根据 `.text` 确定重定位所属的节编号；
- 根据 `helper_disp - text_start` 确定重定位在节内的偏移；
- 通过查找 `helper` 确定符号表索引；
- 在完成格式时确定重定位表的文件位置。

重定位类型必须与处理器架构和已编码字段相匹配。相对调用使用：

| 目标文件种类 | 相对调用的重定位 |
| --- | --- |
| COFF32 | `coff_rel_i386_rel32` |
| COFF64 | `coff_rel_amd64_rel32` |

## 把符号和重定位附加到方案

符号声明和重定位声明都是普通的编译期列表：

```text
const symbols: list = list.of(...)
const relocs: list = list.of(...)
```

使用 `format_coff_tables` 把它们附加到格式方案：

```text
const object: map = format_coff_tables(object0, symbols, relocs)
format_finish(object)
```

这个函数会返回一份新的方案。必须保留返回值，并把它传给 `format_finish`。

完成格式时，格式接口会：

1. 按照声明的节对重定位进行分组；
2. 根据符号名称解析每个重定位目标；
3. 写入重定位表项；
4. 按照声明顺序写入符号表；
5. 写入最小的 COFF 字符串表结束项；
6. 回填文件头以及各节表项中的重定位字段。

## 一个可以参与链接的 COFF64 目标文件

下面的目标文件定义了 `main`、已初始化数据和通常称为 BSS 的未初始化数据区。它通过 64 位 x86 相对重定位调用名为 `helper` 的外部函数：

```asm
// 导入常用格式接口，并声明代码、已初始化数据和未初始化数据三个节。
import("format/format.inc");

const object0: map = format_coff64(
    list.of(
        format_section(
            ".text",
            format_code | format_readable | format_executable
        ),
        format_section(
            ".data",
            format_data | format_readable | format_writeable
        ),
        format_section(
            ".bss",
            format_uninitialized_data | format_readable | format_writeable
        )
    )
)

format_begin(object0);

// 写入 main，并为链接器稍后处理的 helper 相对调用保留四字节位移字段。
format_section_begin(object0, ".text");
text_start:
main:
    sub rsp, 40
    db(0xe8);
helper_disp:
    dd(0);
    add rsp, 40
    ret
format_section_end(object0, ".text");

// 写入一个具有初始值的公开数据对象。
format_section_begin(object0, ".data");
data_start:
answer:
    dd(42);
format_section_end(object0, ".data");

// 只预留 64 字节逻辑空间，不向目标文件写入对应载荷。
format_section_begin(object0, ".bss");
bss_start:
scratch:
    rb(64);
format_section_end(object0, ".bss");

// 声明本文件提供的符号，以及需要由其他目标文件提供的 helper。
const symbols: list = list.of(
    format_coff_public(
        "main",
        ".text",
        text_start,
        main,
        coff_sym_type_function
    ),
    format_coff_public(
        "answer",
        ".data",
        data_start,
        answer,
        coff_sym_type_null
    ),
    format_coff_public(
        "scratch",
        ".bss",
        bss_start,
        scratch,
        coff_sym_type_null
    ),
    format_coff_extern("helper", coff_sym_type_function)
)

// 把 helper 的相对调用位移交给本机链接器完成重定位。
const relocs: list = list.of(
    format_coff_reloc(
        ".text",
        text_start,
        helper_disp,
        "helper",
        coff_rel_amd64_rel32
    )
)

// 使用包含符号表和重定位表的新方案完成 COFF64 目标文件。
const object: map = format_coff_tables(object0, symbols, relocs)
format_finish(object);
```

栈指针调整会为 64 位 Windows 调用保留影子空间，并使外部调用时的栈满足对齐要求。目标文件本身没有定义 `helper`。

可以使用一份 `C` 源代码提供缺失的定义：

```c
// 引用 XIRASM 目标文件公开的 64 字节未初始化数组。
extern unsigned char scratch[64];

// 提供 helper，并确认链接后分配的数组最后一个字节可以写入。
int helper(void) {
    scratch[63] = 7;
    return scratch[63] == 7 ? 0 : 1;
}
```

将 `C` 源代码编译成 COFF64 目标文件，再使用本机链接器把它与 XIRASM 目标文件链接。链接器会解析尚未定义的 `helper` 符号，应用 `REL32` 重定位，并生成最终的可执行文件。

`.bss` 节表项报告的大小为 64，原始数据指针为零。目标文件不会保存 64 字节载荷；链接器会在最终映像中分配这段空间，`C` 函数则确认最后一个字节可以写入。

## COFF32 使用相同的方案模型

32 位构建流程需要改变目标文件种类、所选应用二进制接口要求的符号写法，以及重定位类型：

```asm
// 导入常用格式接口，并创建一个只包含代码节的 COFF32 目标文件。
import("format/format.inc");

const object0: map = format_coff32(
    list.of(
        format_section(
            ".text",
            format_code | format_readable | format_executable
        )
    )
)

format_begin(object0);

// 写入 _main，并为尚未解析的 _helper 相对调用保留位移字段。
format_section_begin(object0, ".text");
text_start:
_main:
    db(0xe8);
helper_disp:
    dd(0);
    ret
format_section_end(object0, ".text");

// 公开 _main，并声明由其他目标文件提供的 _helper。
const symbols: list = list.of(
    format_coff_public(
        "_main",
        ".text",
        text_start,
        _main,
        coff_sym_type_function
    ),
    format_coff_extern("_helper", coff_sym_type_function)
)

// COFF32 相对调用使用 i386 的 REL32 重定位类型。
const relocs: list = list.of(
    format_coff_reloc(
        ".text",
        text_start,
        helper_disp,
        "_helper",
        coff_rel_i386_rel32
    )
)

// 附加符号和重定位信息，然后完成目标文件。
const object: map = format_coff_tables(object0, symbols, relocs)
format_finish(object);
```

本例中的前导下划线遵循一种常见的 32 位 `C` 应用二进制接口命名约定。它们是源代码明确声明的符号名称，并不是 COFF 格式接口自动进行的转换。符号名称必须与项目使用的编译器和链接器保持一致。

## BSS 必须保持文件中无载荷

未初始化数据描述项会为节设置 COFF 未初始化数据属性。只包含预留操作的节会增加逻辑大小，但不会写入载荷字节。节表项记录这个逻辑大小，而原始数据指针保持为零。

常用格式接口会同时维护两个位置：

- 潜在文件位置保留预留空间的逻辑范围；
- 实际文件位置标记下一个真正写入文件的位置。

重定位表和符号表从实际文件位置开始写入。这样可以保持目标文件紧凑，也能防止元数据被错误地计入 BSS 原始数据。

## 常见的 COFF 目标文件错误

### 调用 `format_entry`

COFF 目标文件不包含可执行入口。应当公开一个函数符号，并让最终的链接过程选择入口。

### 丢弃更新后的方案

`format_coff_tables` 返回的方案拥有符号列表和重定位列表。如果把较早的方案传给 `format_finish`，生成的目标文件就会遗漏这些表。

### 把重定位放在操作码上

对于相对调用，重定位属于操作码之后的四字节位移字段。

### 使用了错误架构的重定位

`format_coff32` 应使用 32 位 x86 重定位常量，`format_coff64` 应使用 64 位 x86 重定位常量。

### 遗漏外部符号

重定位目标必须出现在符号列表中。使用 `format_coff_extern` 声明尚未解析的目标。

### 重复使用符号名称

常用格式接口会拒绝名称重复的公开符号或外部符号，否则按名称查找重定位目标时会产生歧义。

### 向 BSS 写入字节

未初始化数据应使用预留操作。具有初始值的字节应放在 `format_data` 节中。

### 假定调用约定

符号表只描述名称和位置，不描述参数如何传递。汇编代码、编译生成的目标文件和最终的链接命令必须使用一致的应用二进制接口。

## COFF 目标文件的实用规则

1. 根据目标链接器接受的输入，选择 `format_coff32` 或 `format_coff64`。
2. 分别声明代码、已初始化数据和 BSS 节。
3. 每个被符号或重定位引用的节都应定义稳定的起始标号。
4. 使用 `format_coff_public` 声明每个需要让链接器看到的定义。
5. 使用 `format_coff_extern` 声明每个尚未解析的外部需求。
6. 把重定位标号放在编码中的待修改字段上，而不是放在周围的指令上。
7. 选择同时匹配处理器架构和字段编码方式的重定位类型。
8. 使用 `format_coff_tables` 附加最终的符号列表和重定位列表。
9. 不要添加可执行入口，并使用更新后的方案完成格式。
10. 使用本机链接器，把目标文件与真正引用它或提供外部定义的其他目标文件链接，以确认生成结果。

第 10 章将重新介绍可加载映像，并说明 ELF32 与 ELF64 可执行文件如何采用紧凑的文件布局，以及如何让各个 `LOAD` 段分别对齐。

# 第 12 章：ELF32 与 ELF64 目标文件

ELF 目标文件是交给链接器处理的可重定位输入文件，不能直接作为进程映像加载。

目标文件记录以下信息：

- 包含代码、初始化数据或预留空间的命名节；
- 由当前目标文件定义的公开符号；
- 需要由其他目标文件或库提供的外部符号；
- 最终值尚未确定的编码字段所需的重定位请求。

链接器会把这些信息组合成可执行文件或共享对象。常用格式接口会自行维护节索引、符号索引、表偏移和节头数量，使用者不需要手工计算这些字段。

## 创建 ELF 目标文件方案

使用 `format_elfobj32` 创建 `i386` 目标文件，使用 `format_elfobj64` 创建 `x86-64` 目标文件：

```text
const object0: map = format_elfobj64(
    list.of(
        format_section(
            ".text",
            format_code | format_readable | format_executable
        ),
        format_section(
            ".bss",
            format_uninitialized_data | format_readable | format_writeable
        ),
        format_section(
            ".data",
            format_data | format_readable | format_writeable
        )
    )
)
```

描述项的顺序就是目标文件中各个用户节的顺序。常用格式接口还会生成普通构建流程所需的重定位节、符号表、字符串表、节名称表和栈权限说明节。

开始构造目标文件后，按照声明顺序写入各个节：

```text
format_begin(object0)
format_section_begin(object0, ".text")
...
format_section_end(object0, ".text")
```

ELF 目标文件没有映像基址、程序头、子系统或可执行文件入口字段。`_start` 之类的符号在目标文件中只是一个公开定义，只有链接器把它选为最终可执行文件的入口时，它才会成为运行起点。

## 节描述链接器的输入内容

常用目标文件格式接口接受以下节用途：

- `format_code` 表示可执行代码；
- `format_data` 表示已经初始化的字节；
- `format_uninitialized_data` 表示未初始化数据区形式的预留空间。

未初始化数据节会生成 `SHT_NOBITS` 节。它的节头记录逻辑大小，但目标文件不会保存这些预留字节。

因此，未初始化数据节和后面一个在文件中有实际字节的节可以具有相同的文件偏移。两者仍然是不同的节：前者占用内存空间，后者占用文件字节。

应为每个节保留起始标号。公开符号和重定位会利用该标号计算相对于节起点的值：

```text
format_section_begin(object0, ".bss")
bss_start:
scratch:
    reserve(64)
format_section_end(object0, ".bss")
```

## 公开符号描述当前文件中的定义

使用 `format_elfobj_public` 声明一个定义：

```text
format_elfobj_public(
    "scratch",
    ".bss",
    bss_start,
    scratch,
    64,
    elfobj_stt_object
)
```

各个参数依次表示：

1. 链接器可见的符号名称；
2. 定义所在的节；
3. 该节起点处的标号；
4. 符号自身的标号；
5. 符号大小；
6. ELF 符号类型。

格式接口会计算节索引和符号相对于节起点的值。

符号类型可以选择：

- 可调用代码使用 `elfobj_stt_func`；
- 数据或预留空间使用 `elfobj_stt_object`；
- 没有更具体类型时使用 `elfobj_stt_notype`。

## 外部符号描述尚未满足的需求

使用 `format_elfobj_extern` 声明一个未定义符号：

```text
format_elfobj_extern("helper", elfobj_stt_func)
```

生成的符号使用 `SHN_UNDEF` 作为节索引。链接器必须从其他输入文件或库中找到名称匹配的定义。

符号名称按照字符串精确匹配。名称必须采用目标平台应用二进制接口以及参与链接的其他目标文件所要求的拼写。

## 重定位描述需要修补的编码字段

对外部符号的相对调用包含一个四字节位移，而它的最终值取决于链接后目标符号的地址。

先写出操作码，为位移写入占位值，并在位移字段本身定义标号：

```text
db(0xe8)
helper_disp:
dd(0)
```

然后声明重定位：

```text
format_elfobj_reloc(
    ".text",
    text_start,
    helper_disp,
    "helper",
    elf_r_x86_64_plt32,
    0xfffffffffffffffc
)
```

各个参数依次表示：

1. 编码字段所在的节；
2. 该节的起点；
3. 编码字段的地址；
4. 目标符号名称；
5. 与处理器架构对应的重定位类型；
6. 重定位加数。

格式接口会计算重定位字段相对于节起点的偏移，并按名称解析目标符号的索引。

加数 `-4` 用于计入四字节位移字段本身：

| 目标文件类别 | 相对调用重定位类型 | 加数的编码值 |
| --- | --- | --- |
| ELF32 | `elf_r_386_pc32` | `0xfffffffc` |
| ELF64 | `elf_r_x86_64_plt32` | `0xfffffffffffffffc` |

重定位类型必须按照目标处理器架构的应用二进制接口选择。即使两个字段宽度相同，它们的重定位类型也不一定可以互换。

## `REL` 与 `RELA` 使用不同方式保存加数

常用 ELF32 构建流程会生成 `SHT_REL` 重定位节。`REL` 把加数保存在编码字段中，因此格式接口会在收尾处理阶段把声明的加数写入四字节占位字段。

常用 ELF64 构建流程会生成 `SHT_RELA` 重定位节。`RELA` 把加数保存在重定位表项中，编码字段则继续保留为供链接器处理的占位值。

这种差异由生成的表在内部处理。两种构建流程都使用相同形式的 `format_elfobj_reloc` 声明。

## 关联符号与重定位

把各项声明收集到列表中：

```text
const symbols: list = list.of(...)
const relocs: list = list.of(...)
```

再把列表关联到格式方案：

```text
const object: map = format_elfobj_tables(object0, symbols, relocs)
format_finish(object)
```

`format_elfobj_tables` 会返回更新后的格式方案。调用 `format_finish` 时必须传入这个返回值。

完成目标文件时，格式接口会：

1. 按照被重定位的节对重定位项分组；
2. 按照符号名称解析重定位目标；
3. 生成 `REL` 或 `RELA` 节；
4. 生成各个节对应的局部符号；
5. 生成已经声明的公开符号和外部符号；
6. 生成 `.symtab`、`.strtab` 和 `.shstrtab`；
7. 生成大小为零且不要求可执行栈的说明节；
8. 写入最终节头表以及 ELF 文件头中的数量字段。

## 可由本机链接器处理的 ELF64 目标文件

下面的目标文件定义 `_start`、初始化数据和 64 字节未初始化数据空间，并调用名为 `helper` 的外部函数：

```asm
// 导入常用格式接口。
import("format/format.inc");

// 创建 ELF64 目标文件方案，并声明代码、未初始化数据和初始化数据节。
const object0: map = format_elfobj64(
    list.of(
        format_section(
            ".text",
            format_code | format_readable | format_executable
        ),
        format_section(
            ".bss",
            format_uninitialized_data | format_readable | format_writeable
        ),
        format_section(
            ".data",
            format_data | format_readable | format_writeable
        )
    )
)

// 开始构造目标文件。
format_begin(object0);

// 写出入口代码，并为外部函数调用保留四字节相对位移。
format_section_begin(object0, ".text");
text_start:
_start:
    db(0xe8);
helper_disp:
    dd(0);
    mov edi, eax
    mov eax, 60
    syscall
_start_end:
format_section_end(object0, ".text");

// 预留 64 字节未初始化数据，不向目标文件写入对应载荷。
format_section_begin(object0, ".bss");
bss_start:
scratch:
    reserve(64);
format_section_end(object0, ".bss");

// 写出一个八字节初始化数据对象。
format_section_begin(object0, ".data");
data_start:
marker:
    dq(0x1122334455667788);
format_section_end(object0, ".data");

// 声明当前目标文件提供的三个公开符号和一个外部函数符号。
const symbols: list = list.of(
    format_elfobj_public(
        "_start",
        ".text",
        text_start,
        _start,
        _start_end - _start,
        elfobj_stt_func
    ),
    format_elfobj_public(
        "marker",
        ".data",
        data_start,
        marker,
        8,
        elfobj_stt_object
    ),
    format_elfobj_public(
        "scratch",
        ".bss",
        bss_start,
        scratch,
        64,
        elfobj_stt_object
    ),
    format_elfobj_extern("helper", elfobj_stt_func)
)

// 让链接器在 .text 节中修补 helper 调用的相对位移字段。
const relocs: list = list.of(
    format_elfobj_reloc(
        ".text",
        text_start,
        helper_disp,
        "helper",
        elf_r_x86_64_plt32,
        0xfffffffffffffffc
    )
)

// 关联符号与重定位表，并使用更新后的方案完成目标文件。
const object: map = format_elfobj_tables(object0, symbols, relocs)
format_finish(object);
```

另一个目标文件可以提供 `helper`，并使用当前文件公开的未初始化数据符号：

```c
// 引用另一个目标文件中定义的 64 字节未初始化数据对象。
extern volatile unsigned char scratch[64];

// 写入并读回最后一个字节，确认链接器为完整对象分配了空间。
int helper(void) {
    scratch[63] = 0x5a;
    return scratch[63] == 0x5a ? 0 : 1;
}
```

完成本机链接后，`_start` 会调用 `helper`，并使用它的返回值作为退出状态。提供方会写入并读回 `scratch` 的最后一个字节，从而证明链接器为这个定义分配了完整的 64 字节未初始化数据空间。

目标文件本身不保存 64 字节的未初始化数据载荷。它的 `.bss` 节类型为 `SHT_NOBITS`，大小为 64，并带有可写和运行时分配标志。

## ELF32 使用相同的格式方案模型

32 位源代码需要更换格式方案构造函数、指令序列和重定位类型：

```asm
// 导入常用格式接口。
import("format/format.inc");

// 创建 ELF32 目标文件方案，并声明代码、初始化数据和未初始化数据节。
const object0: map = format_elfobj32(
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

// 开始构造目标文件。
format_begin(object0);

// 写出 32 位入口代码，并为外部函数调用保留相对位移。
format_section_begin(object0, ".text");
text_start:
_start:
    db(0xe8);
helper_disp:
    dd(0);
    mov ebx, eax
    mov eax, 1
    db(0xcd, 0x80);
_start_end:
format_section_end(object0, ".text");

// 写出一个四字节初始化数据对象。
format_section_begin(object0, ".data");
data_start:
marker:
    dd(0x11223344);
format_section_end(object0, ".data");

// 预留 64 字节未初始化数据空间。
format_section_begin(object0, ".bss");
bss_start:
scratch:
    reserve(64);
format_section_end(object0, ".bss");

// 声明公开符号和需要在链接时解析的外部函数。
const symbols: list = list.of(
    format_elfobj_public(
        "_start",
        ".text",
        text_start,
        _start,
        _start_end - _start,
        elfobj_stt_func
    ),
    format_elfobj_public(
        "marker",
        ".data",
        data_start,
        marker,
        4,
        elfobj_stt_object
    ),
    format_elfobj_public(
        "scratch",
        ".bss",
        bss_start,
        scratch,
        64,
        elfobj_stt_object
    ),
    format_elfobj_extern("helper", elfobj_stt_func)
)

// 让链接器使用 32 位相对调用重定位修补位移字段。
const relocs: list = list.of(
    format_elfobj_reloc(
        ".text",
        text_start,
        helper_disp,
        "helper",
        elf_r_386_pc32,
        0xfffffffc
    )
)

// 关联表并完成 ELF32 目标文件。
const object: map = format_elfobj_tables(object0, symbols, relocs)
format_finish(object);
```

把同一份 `C` 定义编译为匹配的 32 位目标平台后，也可以由它提供 `helper`。

ELF32 的重定位节是 `.rel.text`，ELF64 的重定位节是 `.rela.text`。符号名称以及符号与节之间的关系保持不变。

## 自动生成的栈权限

常用格式接口会添加一个大小为零、没有可执行标志的 `.note.GNU-stack` 节。

它会告诉兼容的链接器，当前目标文件不要求进程栈具有执行权限。这是自动生成的元数据，不是用户声明的节描述项，也不会增加载荷字节。

需要可执行栈的代码不属于常用格式接口的安全模型，应改用高级目标文件构建流程。

## ELF 目标文件常见错误

### 调用 `format_entry`

目标文件通过公开符号提供定义，不包含可执行文件入口字段。

### 传入节索引

应传入已经声明的节名称及其起始标号，由格式接口计算数值形式的节索引。

### 传入符号索引

应传入目标符号名称，由格式接口解析生成后的符号表索引。

### 重定位操作码而不是编码字段

相对调用应在操作码之后的四字节位移字段上定义标号。

### 使用错误的重定位类型

重定位类型与处理器架构和字段用途有关，必须与已经编码的指令以及目标平台应用二进制接口相匹配。

### 省略相对程序计数器加数

本章的普通相对调用示例使用 `-4`，因为位移是从四字节字段的末尾开始计算的。

### 把未初始化数据区当作文件数据

应在 `format_uninitialized_data` 节中预留空间，不要向其中写出初始化字节。

### 继续使用原始格式方案

调用 `format_finish` 时，应使用 `format_elfobj_tables` 返回的格式方案。

### 期待汇编器选择运行时入口

最终可执行文件的入口符号由链接器或链接驱动程序选择。

### 混用 ELF32 与 ELF64 输入文件

同一次链接中的所有目标文件必须使用彼此兼容的机器类型、文件类别、应用二进制接口和函数调用约定。

## ELF 目标文件实用规则

1. 根据目标文件类别选择 `format_elfobj32` 或 `format_elfobj64`。
2. 在调用 `format_begin` 前声明所有用户节。
3. 为符号或重定位会引用的每个节保留起始标号。
4. 使用 `format_uninitialized_data` 和 `reserve` 建立未初始化数据区。
5. 使用 `format_elfobj_public` 描述当前文件提供的定义。
6. 使用 `format_elfobj_extern` 描述尚未解析的外部需求。
7. 在链接器需要修补的准确编码字段上定义标号。
8. 按照目标平台的应用二进制接口选择重定位类型。
9. 对本章所示的相对调用传入用补码表示的 `-4` 加数。
10. 使用 `format_elfobj_tables` 关联符号与重定位。
11. 使用返回的格式方案完成目标文件。
12. 让格式接口生成节索引、符号索引、各类表和不可执行栈说明节。
13. 只链接使用兼容处理器架构和应用二进制接口的目标文件。

第 13 章将构建 ELF64 共享对象。共享对象中的动态导出符号和导入符号由运行时加载器解析，不只依赖静态链接。

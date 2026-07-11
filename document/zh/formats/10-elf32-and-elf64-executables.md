# 第 10 章：ELF32 与 ELF64 可执行文件

ELF（可执行与可链接格式）可执行文件是一种可加载映像，适用于采用 ELF 进程模型的系统。ELF 文件头记录处理器架构和入口地址，程序头则描述加载器需要映射到进程中的文件字节范围与内存范围。

本章构造固定地址可执行文件：

- `format_elf32(format_elf_exec, ...)` 创建 `i386` `ET_EXEC` 映像；
- `format_elf64(format_elf_exec, ...)` 创建 `AMD64` `ET_EXEC` 映像；
- 每个普通描述项生成一个 `PT_LOAD` 程序头；
- `format_entry` 绑定开始执行的地址；
- 格式接口推导程序头的数量、文件偏移、地址、大小、标志和对齐字段。

位置无关映像和动态导入将在第 11 章介绍。

## 选择 ELF 类别和执行模式

ELF 格式方案接收执行模式和一个有序的段列表：

```text
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
        )
    )
)
```

32 位 x86 代码使用 `format_elf32`，64 位 x86 代码使用 `format_elf64`。所选格式决定 ELF 类别、机器类型、文件头字段宽度和默认加载基址。

普通固定地址模式的默认值如下：

| 格式方案 | ELF 类别 | 机器类型 | 默认映像基址 |
| --- | --- | --- | --- |
| `format_elf32` | ELF32 | `i386` | `0x08048000` |
| `format_elf64` | ELF64 | `AMD64` | `0x00400000` |

`format_elf32` 目前只接受 `format_elf_exec`。`format_elf64` 还支持位置无关模式，但该模式会改变加载和动态链接方式，因此放在下一章单独介绍。

## ELF 可执行文件使用可加载段

加载器不会按照源代码中的节名称组织可执行文件，而是映射程序头描述的范围。

因此，普通可执行文件格式接口使用段描述项：

```text
format_segment(
    ".text",
    format_load | format_readable | format_executable
)
```

每个普通可执行文件段都必须包含 `format_load` 用途标志。权限用于描述加载后的内存映射：

| 内容 | 建议权限 |
| --- | --- |
| 指令 | 可读、可执行 |
| 可修改的初始化数据 | 可读、可写 |
| 未初始化数据区（BSS） | 可读、可写 |
| 常量 | 可读 |

描述项的顺序就是程序头的顺序。使用以下接口打开和关闭段内容：

```text
format_segment_begin(image0, ".text")
...
format_segment_end(image0, ".text")
```

ELF 可执行文件方案不能使用 `format_section_begin`。节是目标文件提供给链接器的组织单位，本章使用的可加载段则是运行时映射单位。

## 固定地址 ELF64 可执行文件

下面的程序会检查初始化数据，写入未初始化数据区的最后一个字节，读取位于该区域之后的常量，最后通过 Linux x86-64 系统调用接口退出：

```asm
// 导入常用格式接口。
import("format/format.inc");

// 创建固定地址 ELF64 格式方案，并按顺序声明代码、数据、
// 未初始化数据和只读数据四个可加载段。
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

// 开始构造文件映像。
format_begin(image0);

// 写入可执行代码，并通过相对指令指针寻址访问其他可加载段。
format_segment_begin(image0, ".text");
start:
    mov eax, [rel answer]
    cmp eax, 42
    jne failed

    // 验证未初始化数据区的最后一个字节已经映射为可写内存。
    lea rbx, [rel scratch]
    mov byte [rbx + 127], 7
    cmp byte [rbx + 127], 7
    jne failed

    // 验证未初始化数据区之后的只读常量仍可正常访问。
    mov eax, [rel marker]
    cmp eax, 0x11223344
    jne failed

    // 将退出状态设为 0，并调用 Linux x86-64 的 exit 系统调用。
    xor edi, edi
exit:
    mov eax, 60
    syscall
failed:
    mov edi, 1
    jmp exit
format_segment_end(image0, ".text");

// 写入占用文件空间的可修改初始化数据。
format_segment_begin(image0, ".data");
answer:
    dd(42);
format_segment_end(image0, ".data");

// 只预留运行时内存，不向文件写入初始化字节。
format_segment_begin(image0, ".bss");
scratch:
    rb(128);
format_segment_end(image0, ".bss");

// 写入只读常量。
format_segment_begin(image0, ".rodata");
marker:
    dd(0x11223344);
format_segment_end(image0, ".rodata");

// 绑定入口标号，并使用更新后的格式方案完成文件映像。
const image: map = format_entry(image0, start)
format_finish(image);
```

程序使用相对指令指针的内存引用访问其他可加载段中的标号，也就是 x86-64 的 `RIP` 相对寻址。`jne failed` 等向前条件分支由汇编器解析，不需要手工添加 `near` 限定符。

`exit` 系统调用要求：

- `eax` 保存系统调用号 `60`；
- `edi` 保存进程退出状态。

程序直接使用内核接口，因此不需要运行库，也不需要动态加载所需的元数据。

## 文件布局与内存布局不同

上面的 ELF64 示例生成四个可加载映射。具体大小取决于指令编码，但各段的文件内容与内存空间始终保持以下关系：

| 段 | 文件字节 | 内存字节 | 权限 |
| --- | --- | --- | --- |
| `.text` | 指令 | 指令 | 读、执行 |
| `.data` | 初始化数据 | 初始化数据 | 读、写 |
| `.bss` | 无 | 预留空间 | 读、写 |
| `.rodata` | 常量 | 常量 | 读 |

对于这份源代码，输出文件为 368 字节，可加载段的布局如下：

| 段 | 文件偏移 | 虚拟地址 | 文件大小 | 内存大小 |
| --- | --- | --- | --- | --- |
| `.text` | `0x120` | `0x400120` | `0x48` | `0x48` |
| `.data` | `0x168` | `0x401168` | `0x04` | `0x04` |
| `.bss` | `0x16C` | `0x40216C` | `0x00` | `0x80` |
| `.rodata` | `0x16C` | `0x40316C` | `0x04` | `0x04` |

未初始化数据区没有文件字节，因此 `.bss` 和后面的只读段可以使用相同的文件偏移，但它们的虚拟地址不同。

每个可加载段都保持页内偏移同余：

```text
p_vaddr % p_align == p_offset % p_align
```

格式接口会把逻辑地址推进到合适的内存页，同时让文件内容紧接在前一段实际字节的末尾。它不会在两个可加载段之间写入整页零字节。

因此，每增加一个段不会让文件额外膨胀数千字节，整个文件仍然只有数百字节。

## BSS 只占用内存，不包含文件内容

只包含预留空间的可加载段会记录：

```text
p_filesz = 0
p_memsz  = 预留空间的逻辑大小
```

加载器会为这个范围建立可写且初始值为零的内存。示例对 `scratch` 最后一个预留字节的访问，证明整个范围都已经映射并且允许写入。

在 BSS 段中应使用 `rb` 等预留操作。已经初始化的字节应放入文件中有实际字节的数据段。

BSS 后面可以继续放置另一个有文件内容的段。格式接口会让下一个段从当前实际文件末尾继续紧凑排列，同时为它分配后面的虚拟内存页，避免新映射与 BSS 的内存范围重叠。

## 在入口标号定义后绑定入口

入口标号属于代码段：

```text
start:
    ...

const image: map = format_entry(image0, start)
format_finish(image)
```

`format_entry` 会返回更新后的格式方案。调用 `format_finish` 时必须传入这个返回值。

对于 ELF 可执行文件，入口字段保存最终虚拟地址，不是文件偏移，也不是相对于映像基址的数值。

完成 ELF32 或 ELF64 可执行文件之前，格式接口要求入口地址不能为零。

## ELF32 使用相同的段模型

ELF32 会改变文件头字段宽度、机器类型、地址宽度以及系统调用所用的应用二进制接口，但格式方案的构建流程保持不变。

源代码必须选择 32 位 x86 指令模式：

```asm
// 导入常用格式接口，并选择 32 位 x86 指令模式。
import("format/format.inc");

x86.use32();

// 创建固定地址 ELF32 格式方案，段的用途和权限与 ELF64 示例一致。
const image0: map = format_elf32(
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

// 开始构造文件映像。
format_begin(image0);

// 使用 32 位绝对地址访问数据，并验证各个可加载段。
format_segment_begin(image0, ".text");
start:
    mov eax, [answer]
    cmp eax, 42
    jne failed

    // 验证 BSS 段的最后一个预留字节可以读写。
    mov byte [scratch + 63], 7
    cmp byte [scratch + 63], 7
    jne failed

    // 验证 BSS 之后的只读常量可以访问。
    mov eax, [marker]
    cmp eax, 0x11223344
    jne failed

    // 将退出状态设为 0，并调用 32 位 Linux 的 exit 系统调用。
    xor ebx, ebx
exit:
    mov eax, 1
    int 0x80
failed:
    mov ebx, 1
    jmp exit
format_segment_end(image0, ".text");

// 写入可修改的初始化数据。
format_segment_begin(image0, ".data");
answer:
    dd(42);
format_segment_end(image0, ".data");

// 为未初始化数据预留 64 字节运行时内存。
format_segment_begin(image0, ".bss");
scratch:
    rb(64);
format_segment_end(image0, ".bss");

// 写入只读常量。
format_segment_begin(image0, ".rodata");
marker:
    dd(0x11223344);
format_segment_end(image0, ".rodata");

// 绑定入口标号，并完成 ELF32 文件映像。
const image: map = format_entry(image0, start)
format_finish(image);
```

32 位 Linux 退出接口要求 `eax` 保存系统调用号 `1`，`ebx` 保存退出状态。

这个示例生成 269 字节的 ELF32 可执行文件。它的 BSS 可加载段文件大小为零，内存大小为 64 字节。BSS 后面的只读可加载段继续使用相同的实际文件偏移，但位于后面的虚拟内存页。

64 位 Linux 系统可能需要启用 `IA32` 执行支持才能运行 32 位可执行文件。这属于操作系统配置问题，不会改变 ELF 布局。

## 程序头是运行时约定

本章的固定地址可执行文件不需要节头表。加载器使用以下信息：

- ELF 文件头；
- 入口虚拟地址；
- 有序的程序头表；
- 可加载段的文件偏移、地址、大小、权限和对齐。

`.text` 和 `.bss` 等描述项名称只存在于源代码的格式方案中。源代码通过这些名称打开对应的段，诊断信息也可以用它们指出错误。这些紧凑映像不会把它们写成运行时节名称。

如果链接器需要命名节、符号表和重定位节，应使用 ELF 目标文件。第 12 章将介绍这种构建流程。

## 固定地址可执行文件不提供动态导入

直接进行系统调用不需要导入符号。调用 `C` 运行库或其他共享库时，则需要更多 ELF 元数据：

- 指定动态加载器的解释器记录；
- 动态字符串表和动态符号表；
- 过程链接表（`PLT`）与全局偏移表（`GOT`）所需的数据；
- 动态重定位；
- 依赖库记录。

不要在本章所示的固定地址可执行文件中调用尚未解析的库符号。第 11 章将介绍 ELF64 动态导入的常用构建流程。

## ELF 可执行文件常见错误

### 省略 `format_elf_exec`

常用构造函数要求显式提供一种执行模式。本章使用 `format_elf_exec`。

### 使用节而不是可加载段

ELF 可执行文件方案使用 `format_segment_begin` 打开段，使用 `format_segment_end` 关闭段。

### 省略 `format_load`

每个普通可执行文件段除了权限标志，还必须包含 `format_load` 用途标志。

### 让数据段具有执行权限

只有可修改的数据和 BSS 需要写权限。常量应保持只读，可写数据也不应具有执行权限。

### 向 BSS 写入初始化字节

使用 `rb` 或其他预留操作建立 BSS 空间。已经初始化的值应移动到文件中有实际字节的数据段。

### 手工添加内存页填充

不要在段之间写入整页零字节。格式接口会推导满足页内偏移同余关系的虚拟地址，同时保持实际文件字节紧凑排列。

### 丢弃更新后的入口格式方案

完成格式时应传入 `format_entry` 返回的值，而不是较早绑定的格式方案。

### 认为段名称会写入文件

这种紧凑可执行文件由程序头驱动。源代码中的段名称不会形成节头字符串表。

### 在没有动态元数据时调用库

直接调用内核和动态导入库函数是两种不同的构建流程。如果符号需要由运行时链接器解析，应使用第 11 章介绍的动态导入格式接口。

## ELF 可执行文件实用规则

1. 根据指令位数选择 `format_elf32` 或 `format_elf64`。
2. 使用本章的固定地址流程时传入 `format_elf_exec`。
3. 把代码、可修改数据、BSS 和常量分别描述为不同的可加载段。
4. 每个可加载段只设置其内容确实需要的权限。
5. 按照描述项顺序调用 `format_segment_begin` 和 `format_segment_end`。
6. 为 BSS 预留空间，但不要写出初始化字节。
7. 让格式接口推导文件偏移、虚拟地址和页内偏移同余关系。
8. 在可执行代码中定义入口标号。
9. 使用 `format_entry` 返回的更新后格式方案完成文件。
10. 仅在不需要动态运行时依赖时使用直接系统调用。

第 11 章将介绍 ELF64 位置无关可执行文件和动态导入，包括动态加载器、过程链接表、全局偏移表和运行时重定位模型。

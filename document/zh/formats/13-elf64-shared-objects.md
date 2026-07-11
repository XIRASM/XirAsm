# 第 13 章：ELF64 共享对象

ELF 共享对象是一种 `ET_DYN` 映像，用于加载到另一个进程中。它通常没有自己的进程入口，而是发布动态符号，供程序或其他共享对象在运行时解析。

常用的 ELF64 共享对象格式接口可以：

- 通过动态符号表发布函数或数据；
- 通过自动生成的过程链接表和全局偏移表状态，从指定共享库导入过程；
- 描述多个权限彼此独立的用户可加载段；
- 表示只预留空间的 BSS，而不在文件中保存填零内容；
- 生成运行时加载器需要的库标识名、动态数据表、散列表、重定位、节头和程序头。

本章将构造一个共享对象：它导入 `puts`，导出一个可调用函数，使用 BSS 保存状态，并且可以通过 `dlopen` 加载。

## 创建共享对象格式方案

使用下面的接口创建常用的 ELF64 共享对象格式方案：

```text
format_elf64_so(soname, segments)
```

库标识名会记录在动态数据表中，用来标识这个共享库：

```asm
// 导入常用格式接口，使本示例可以单独汇编。
import("format/format.inc");

// 创建 ELF64 共享对象，并按代码、BSS、只读数据和可写数据的顺序声明段。
const image0: map = format_elf64_so(
    "libxirasm_ch13.so",
    list.of(
        format_segment(".text", format_load | format_readable | format_executable),
        format_segment(".bss", format_load | format_readable | format_writeable),
        format_segment(".rodata", format_load | format_readable),
        format_segment(".data", format_load | format_readable | format_writeable)
    )
)
```

描述项的顺序决定用户 `LOAD` 项和用户节头的顺序。权限模型与可执行文件相同：

- 代码可读、可执行；
- BSS 和已经初始化的可修改数据可读、可写；
- 常量只需可读；
- 用户段不应同时具有写入和执行权限。

当前常用共享对象构建流程只支持 ELF64。

## 声明导出符号

使用下面的接口声明导出符号：

```text
format_elfso_export(target_label, export_name, segment_name, symbol_size)
```

四个参数依次表示：

1. 源代码定义的目标标号；
2. 动态符号表中发布的名称；
3. 包含该符号的已声明用户段；
4. 记录给运行时工具和使用方的符号大小。

例如：

```asm
// 导入常用格式接口，使本示例可以单独汇编。
import("format/format.inc");

// 发布代码段中的函数，并记录它在动态符号表中的名称和大小。
const exports: list = list.of(
    format_elfso_export(
        "xirasm_call_puts",
        "xirasm_call_puts",
        ".text",
        46
    )
)
```

目标标号和发布名称可以不同。段名称必须与格式方案中的描述项一致，符号大小必须大于零。

当前常用格式接口要求至少声明一个导出项。它会在收尾处理阶段解析目标标号和自动生成的节索引，用户不需要计算动态符号表项或节索引。

## 声明过程链接表导入项

使用下面的接口声明导入过程：

```text
format_elfso_import_plt(library, name, slot_label, plt_label)
```

例如：

```asm
// 导入常用格式接口，使本示例可以单独汇编。
import("format/format.inc");

// 从 libc.so.6 导入 puts，并为全局偏移表槽位和过程链接表入口指定本地标号。
const imports: list = list.of(
    format_elfso_import_plt(
        "libc.so.6",
        "puts",
        "puts_gotplt",
        "puts_plt"
    )
)
```

共享库名称会形成一项 `DT_NEEDED` 记录。外部符号名称会形成一个未定义的动态符号。两个本地标号分别表示自动生成的全局偏移表和过程链接表槽位，以及过程链接表入口。

普通调用应使用过程链接表标号：

```text
call puts_plt
```

运行时加载器会解析 `puts`，并把函数地址写入自动生成的全局偏移表和过程链接表槽位。

## 开始映像前附加动态数据表

使用下面的接口附加导出列表和导入列表：

```text
format_elfso_tables(plan, exports, imports)
```

后续完整构建流程都应使用返回的新格式方案：

```asm
// 导入常用格式接口，并补齐本示例依赖的格式方案与声明。
import("format/format.inc");

const image0: map = format_elf64_so(
    "libxirasm_ch13.so",
    list.of(
        format_segment(".text", format_load | format_readable | format_executable),
        format_segment(".bss", format_load | format_readable | format_writeable),
        format_segment(".rodata", format_load | format_readable),
        format_segment(".data", format_load | format_readable | format_writeable)
    )
)
const exports: list = list.of(
    format_elfso_export(
        "xirasm_call_puts",
        "xirasm_call_puts",
        ".text",
        46
    )
)
const imports: list = list.of(
    format_elfso_import_plt(
        "libc.so.6",
        "puts",
        "puts_gotplt",
        "puts_plt"
    )
)

// 把导出和导入声明附加到格式方案，再开始构造共享对象映像。
const image: map = format_elfso_tables(image0, exports, imports)
format_begin(image);
```

必须在 `format_begin` 之前附加这些列表。导入项会影响自动生成的程序头数量，还需要分别建立可执行的过程链接表映射和可写的元数据映射。

只导出、不导入的共享对象应传入空导入列表：

```text
format_elfso_tables(image0, exports, list.new())
```

## 构造多段共享对象

下面的源代码从 `libc.so.6` 导入 `puts`，导出 `xirasm_call_puts`，在 BSS 中保存调用次数，并把代码、常量、BSS、初始化数据、自动生成的过程链接表和动态元数据放入权限合适的映射中：

```asm
// 导入常用格式接口。
import("format/format.inc");

// 创建共享对象格式方案，并为不同用途的内容声明独立段。
const image0: map = format_elf64_so(
    "libxirasm_ch13.so",
    list.of(
        format_segment(".text", format_load | format_readable | format_executable),
        format_segment(".bss", format_load | format_readable | format_writeable),
        format_segment(".rodata", format_load | format_readable),
        format_segment(".data", format_load | format_readable | format_writeable)
    )
)
// 发布可供加载方解析和调用的函数。
const exports: list = list.of(
    format_elfso_export(
        "xirasm_call_puts",
        "xirasm_call_puts",
        ".text",
        46
    )
)
// 声明外部过程，并指定本地全局偏移表槽位和过程链接表入口标号。
const imports: list = list.of(
    format_elfso_import_plt("libc.so.6", "puts", "puts_gotplt", "puts_plt")
)
// 导入和导出会改变自动生成的运行时元数据，因此先附加数据表再开始映像。
const image: map = format_elfso_tables(image0, exports, imports)
format_begin(image);

// 导出函数更新 BSS 中的调用次数，通过过程链接表调用 puts，并返回最新计数。
format_segment_begin(image, ".text");
xirasm_call_puts:
    mov rax, [rel call_count]
    add rax, 1
    mov [rel call_count], rax
    lea rdi, [rel message_text]
    sub rsp, 8
    call puts_plt
    add rsp, 8
    mov rax, [rel call_count]
    ret
format_segment_end(image, ".text");

// 只预留运行时内存，用于保存跨调用持续存在的计数。
format_segment_begin(image, ".bss");
call_count:
    reserve(64);
format_segment_end(image, ".bss");

// 保存传给 puts 的零结尾只读文本。
format_segment_begin(image, ".rodata");
message_text:
    db("XIRASM shared object", 0);
format_segment_end(image, ".rodata");

// 写入共享对象自带的可修改初始化数据。
format_segment_begin(image, ".data");
library_state:
    dq(0x1122334455667788);
format_segment_end(image, ".data");

// 生成动态数据表、程序头、节头及其最终地址和大小。
format_finish(image);
```

这个函数遵守 x86-64 的 `System V` 调用约定。它在调用 `puts` 前保持所需的栈对齐，通过相对于指令指针的寻址访问内部数据，并在 `rax` 中返回更新后的调用次数。

共享对象没有可执行文件入口。`format_finish` 会在用户段之后写出运行时元数据，并确定所有自动生成内容的地址、大小、索引和数量。

## 加载并调用导出函数

使用 `C` 编写的加载程序可以打开文件并解析导出的函数：

```c
#include <dlfcn.h>

// 导出函数没有参数，并以 long 返回当前调用次数。
typedef long (*entry_fn)(void);

int main(void) {
    // 立即解析共享对象需要的动态符号。
    void *handle = dlopen("./libxirasm_ch13.so", RTLD_NOW);
    if (handle == 0) {
        return 1;
    }

    // 按发布名称查找导出函数，而不是使用源代码标号或符号索引。
    entry_fn entry = (entry_fn)dlsym(handle, "xirasm_call_puts");
    if (entry == 0) {
        dlclose(handle);
        return 2;
    }

    // 连续调用两次，验证 BSS 状态在已加载映像中持续存在。
    const long first = entry();
    const long second = entry();
    dlclose(handle);
    return first == 1 && second == 2 ? 0 : 3;
}
```

第一次调用会输出消息并返回 1。第二次调用会返回 2，证明 BSS 状态在已加载映像中持续存在。

`dlsym` 使用发布的导出名称查找函数，不使用源代码标号、节名称或数字符号索引。

## BSS 只占用内存，不包含文件内容

`.bss` 段只包含：

```asm
// 为调用计数预留 64 字节运行时空间，不在文件中写入初始字节。
reserve(64);
```

它的程序头中文件大小为零，内存大小为 64。对应节头使用 `SHT_NOBITS`，大小同样为 64。后面的 `.rodata` 段可以从相同的紧凑文件偏移开始，因为 BSS 占用的是虚拟内存，而不是文件字节。

加载器会把 BSS 映射到独立的可写虚拟内存页，并把这段内存初始化为零。

常用 BSS 段应只包含预留空间。如果初始化字节和预留空间必须共用一个逻辑区域，应使用不同的常用段，或者使用专门的高级布局。

## 自动生成的运行时元数据

对于同时包含导入和导出的构建流程，格式接口会生成：

- 保存导入和导出名称的 `.dynsym` 与 `.dynstr`；
- `System V` ELF 散列表；
- 用于导入过程的 `.plt` 节及全局偏移表和过程链接表状态；
- `R_X86_64_JUMP_SLOT` 重定位记录；
- 包含 `DT_SONAME`、`DT_NEEDED` 和各数据表连接信息的 `.dynamic` 节；
- 节名称字符串表和最终节头表；
- `LOAD` 与 `DYNAMIC` 程序头。

用户只需提供名称、权限、标号和符号大小。格式接口会推导程序头表项、节索引、符号索引、字符串偏移、重定位表项、文件偏移、虚拟地址和数据表大小。

## 可执行内容与可写状态保持分离

存在导入项时，自动生成的内容会放入另外两个 `LOAD` 项：

- 过程链接表可读、可执行；
- 全局偏移表、符号、字符串、重定位、动态数据和节元数据可读、可写。

任何 `LOAD` 都不会同时具有写入和执行权限。

实际文件仍然保持紧凑。不同虚拟内存页可以分别实施权限，而不必在文件中填充整页零字节；每个 `LOAD` 的文件偏移和虚拟地址都保持 ELF 要求的页内偏移同余关系。

## 共享对象必须遵守使用方的应用二进制接口

动态符号解析不会定义函数的调用约定。每个导出过程和导入过程都必须遵守调用方或被调用方要求的应用二进制接口。

对于 x86-64 的 `System V` 函数：

- 从规定的寄存器接收参数；
- 保留应用二进制接口要求被调用方保留的寄存器；
- 在调用其他函数前保持要求的栈对齐；
- 在规定的寄存器中返回结果；
- 使用兼容的数据大小和结构布局。

导入函数也必须遵守同一规则。即使过程链接表重定位完全正确，也无法修复错误的调用指令序列。

## 当前常用接口边界

当前常用共享对象格式接口提供：

- ELF64 共享对象；
- 至少一个导出的动态符号；
- 可选的过程链接表函数导入；
- 多个用户 `LOAD` 段；
- 只包含预留空间的 BSS；
- 自动生成的库标识名、散列表、符号、字符串、重定位、过程链接表、全局偏移表、动态数据和节头状态。

它目前不提供常用的 ELF32 共享对象构造函数，也不提供符号版本表、线程局部存储、构造函数数组、`GNU` 散列表或任意自定义动态标签。

不要把按位宽划分的兼容接口或按表项逐行操作的辅助接口混入常用格式方案，以此绕过这些边界。特殊布局应使用单独的高级格式指南。

## 共享对象常见错误

### 调用 `format_entry`

共享对象发布动态符号。常用构建流程不使用可执行文件入口。

### 没有声明任何导出项

当前常用格式接口要求至少声明一个导出项。

### 在 `format_begin` 之后附加数据表

导入项会改变自动生成的程序头布局。开始映像之前必须附加导出列表和导入列表。

### 直接调用外部名称

应调用 `format_elfso_import_plt` 提供的本地过程链接表标号。

### 为导出项声明错误的段

导出项中声明的段必须是实际包含目标标号的用户段。

### 记录错误的符号大小

导出大小应与实际写出的函数或对象保持一致。

### 向 BSS 写入字节

只包含预留空间的 BSS 段会使用 `SHT_NOBITS`。初始化字节应放入文件中有实际字节的数据段。

### 让一个段同时具有写入和执行权限

代码与可修改状态应保持分离。常用格式接口已经把自动生成的过程链接表字节和可写元数据分开。

### 忽略平台应用二进制接口

动态调用的两端必须对寄存器用法、栈对齐、数据布局和返回值保持一致。

### 认为库标识名可以找到文件

库标识名只在文件已经找到后标识这个共享库。搜索路径、加载器配置和调用程序仍然决定如何定位文件。

## ELF64 共享对象实用规则

1. 使用 `format_elf64_so` 创建格式方案。
2. 为文件提供非空的库标识名。
3. 使用满足实际需求的最小权限声明用户段。
4. 把只包含预留空间的 BSS 放入独立的可写段。
5. 使用 `format_elfso_export` 声明每个发布符号。
6. 使用 `format_elfso_import_plt` 声明导入过程。
7. 在 `format_begin` 之前使用 `format_elfso_tables` 附加导出列表和导入列表。
8. 后续每个构建流程调用都使用返回的新格式方案。
9. 通过自动生成的本地过程链接表标号调用导入过程。
10. 每个导入过程和导出过程都应遵守平台应用二进制接口。
11. 让格式接口推导动态数据表、索引、偏移和程序头。
12. 让可执行映射与可写映射保持分离。
13. 通过目标平台的动态加载接口加载共享对象并解析导出名称。

至此，常用可执行文件格式指南已经介绍完毕：用户可以通过 `format.inc` 格式接口构造 PE 可执行文件和动态链接库、COFF 目标文件、ELF 可执行文件和位置无关可执行文件、ELF 目标文件，以及 ELF64 共享对象。

直接导入格式专用包含文件、使用兼容接口、显式构造数据表项和生成特殊元数据，都属于高级接口。这些内容会在单独的高级格式指南中介绍，不与常用构建流程混在一起。

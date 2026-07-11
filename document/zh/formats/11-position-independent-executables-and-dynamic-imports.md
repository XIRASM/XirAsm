# 第 11 章：位置无关可执行文件与动态导入

ELF64 的常用格式接口还支持两种可执行文件构建流程：

- 使用相对寻址和直接系统调用的位置无关可执行文件；
- 通过自动生成的过程链接表和全局偏移表导入函数的固定地址可执行文件。

这两种流程彼此独立。选择位置无关可执行文件会改变加载器放置映像的方式，但不会自动加入运行时解释器或导入符号。添加动态导入表会生成解释器记录、动态符号数据、过程链接表、全局偏移表和重定位记录，但当前常用导入流程要求使用固定地址的 `EXEC` 模式。

本章分别说明这两种模型，以及它们之间的使用边界。

## 显式选择 ELF64 位置无关模式

使用下面的调用创建位置无关格式方案：

```text
format_elf64(format_elf_pie, segments)
```

生成的 ELF 文件头使用 `ET_DYN`，映像基址为零。各个 `LOAD` 项中的虚拟地址表示映像内部的偏移，不再从第 10 章使用的固定 ELF64 基址推导。

操作系统会选择运行时加载地址。映射可执行文件时，它会把这个地址加到入口值和各个 `LOAD` 虚拟地址上。

常用的位置无关构建流程目前只支持 ELF64。把 `format_elf_pie` 传给 `format_elf32` 会被拒绝。

## 位置无关性取决于源代码

仅仅使用 `ET_DYN` 文件头，并不能让源代码中的绝对值自动变成位置无关形式。

代码应通过相对于当前指令位置的寻址访问内部标号：

```text
lea rsi, [rel message]
mov eax, [rel value]
call helper
```

整个映像移动后，直接相对跳转或相对调用仍然有效，因为指令和目标会移动相同的距离。

绝对数据字段则不同。例如，直接写出 `dq(start)` 会保存 `start` 在链接阶段确定的值。本章的最小位置无关流程不会为这个字段生成动态重定位，因此运行时加载器不知道需要把实际加载地址加到该值上。

如果位置无关可执行文件没有动态重定位，应使用相对代码引用、相对偏移，或者在运行时计算所需地址。

## 多段 ELF64 位置无关可执行文件

下面的示例包含可执行代码、未初始化数据区和只读数据。代码通过相对于指令指针的寻址访问两个数据段，因此映像加载到任何地址时都能正常工作。

```asm
// 导入常用格式接口，并创建可在任意地址加载的 ELF64 映像。
import("format/format.inc");

const image0: map = format_elf64(
    format_elf_pie,
    list.of(
        format_segment(".text", format_load | format_readable | format_executable),
        format_segment(".bss", format_load | format_readable | format_writeable),
        format_segment(".rodata", format_load | format_readable)
    )
)
format_begin(image0);

// 代码通过相对地址访问内部的预留空间和只读消息。
format_segment_begin(image0, ".text");
start:
    lea rbx, [rel scratch]
    mov dword [rbx], 0x5a
    cmp dword [rbx], 0x5a
    jne failed

    // 直接调用内核，把只读消息写到标准输出。
    mov eax, 1
    mov edi, 1
    lea rsi, [rel message]
    mov edx, message_end - message
    syscall

    xor edi, edi
    jmp finish

failed:
    mov edi, 1

finish:
    // 使用成功或失败状态结束进程。
    mov eax, 60
    syscall
format_segment_end(image0, ".text");

// 未初始化数据区只预留运行时内存，不在文件中写出初始字节。
format_segment_begin(image0, ".bss");
scratch:
    rb(64);
format_segment_end(image0, ".bss");

// 只读段保存程序需要输出的消息。
format_segment_begin(image0, ".rodata");
message:
    db("XIRASM PIE", 10);
message_end:
format_segment_end(image0, ".rodata");

// 绑定入口标号，并完成文件映像。
const image: map = format_entry(image0, start)
format_finish(image);
```

生成的文件大小为 316 字节，包含 3 个 `LOAD` 项：

- 代码使用可读、可执行的 `RX` 映射；
- 未初始化数据区使用可读、可写的 `RW` 映射，文件大小为零，内存大小为 64；
- 消息使用只读的 `R` 映射。

未初始化数据区不占用文件字节，因此它和只读 `LOAD` 在紧凑文件布局中使用同一个后续物理位置，但分别占用不同的虚拟页。每个 `LOAD` 仍满足 ELF 的要求：虚拟地址和文件偏移对页对齐值取模后结果相同。

程序先向未初始化数据区写入数值，再通过相对地址读取消息并输出。作为 `ET_DYN` 可执行文件加载后，它会正常结束。

## 位置无关可执行文件不一定需要动态链接器

上一个示例直接进行 Linux 系统调用，没有导入任何库符号，因此不需要：

- `PT_INTERP`；
- `PT_DYNAMIC`；
- 动态符号表或动态字符串表；
- 过程链接表（`PLT`）或全局偏移表（`GOT`）；
- 动态重定位表。

它是位置无关可执行文件，但不是动态链接的可执行文件。

必须区分这两个概念：位置无关模式描述映像可以放在什么地址，动态链接描述如何在运行时解析符号。一个文件可能只需要其中一种能力，也可能两种都需要，或者两种都不需要。当前常用格式接口分别实现本章介绍的两种组合，而不是把它们当作同一个选项。

## 声明过程链接表导入项

常用动态导入流程从固定地址的 ELF64 可执行文件方案开始：

```text
format_elf64(format_elf_exec, segments)
```

为每个导入过程创建一项声明：

```text
format_elfexe_import_plt(library, name, slot_label, plt_label)
```

各个参数分别表示：

- 由 `DT_NEEDED` 记录的共享库名称；
- 运行时链接器需要查找的外部符号名称；
- 本地全局偏移表槽位及对应过程链接表入口的标号；
- 调用指令使用的本地过程链接表入口标号。

把这些声明收集到列表中，再附加到格式方案：

```text
const image1: map = format_elfexe_tables(image0, imports)
```

后续的 `format_begin`、段构建调用、`format_entry` 和 `format_finish` 都应使用 `image1`。导入声明属于这个更新后的格式方案。

## 调用 `libc` 的固定 ELF64 可执行文件

下面的可执行文件从 `libc.so.6` 导入 `getpid`。这个函数没有参数，因此示例可以集中展示 ELF 导入模型。

```asm
// 导入常用格式接口，并创建固定地址的 ELF64 可执行文件。
import("format/format.inc");

const image0: map = format_elf64(
    format_elf_exec,
    list.of(
        format_segment(".text", format_load | format_readable | format_executable)
    )
)
// 声明共享库、外部函数以及本地 GOT/PLT 槽位和调用入口。
const imports: list = list.of(
    format_elfexe_import_plt(
        "libc.so.6",
        "getpid",
        "getpid_gotplt",
        "getpid_plt"
    )
)
// 导入表属于返回的新格式方案，后续构建流程都使用该方案。
const image1: map = format_elfexe_tables(image0, imports)
format_begin(image1);

format_segment_begin(image1, ".text");
start:
    // 通过本地过程链接表入口调用运行时解析的 getpid。
    call getpid_plt
    test eax, eax
    jle failed

    xor edi, edi
    jmp finish

failed:
    mov edi, 1

finish:
    // 根据 getpid 的返回值，以成功或失败状态结束进程。
    mov eax, 60
    syscall
format_segment_end(image1, ".text");

// 绑定入口并完成包含动态导入元数据的映像。
const image: map = format_entry(image1, start)
format_finish(image);
```

这个示例会生成 768 字节的 ELF64 可执行文件。程序启动时，动态链接器会解析 `getpid`，更新过程链接表使用的全局偏移表槽位，再通过 `getpid_plt` 转移控制。程序把大于零的进程标识符视为成功，并以状态 0 退出。

## 导入格式接口会生成什么

只要提供导入声明，常用格式接口就会生成：

- 指向 ELF64 运行时解释器的 `PT_INTERP` 项；
- `PT_DYNAMIC` 项；
- 动态符号表和动态字符串表；
- 每个不同共享库对应的一项依赖记录；
- 每个导入过程对应的过程链接表入口；
- 运行时解析器使用的全局偏移表和过程链接表状态；
- `R_X86_64_JUMP_SLOT` 重定位记录；
- 连接这些表的动态标签。

用户不需要计算符号索引、表地址、重定位表项或程序头位置。

生成的 `LOAD` 权限会把可执行内容与可写状态分开：

- 用户代码使用 `RX` 权限；
- 自动生成的过程链接表使用 `RX` 权限；
- 全局偏移表和动态元数据使用 `RW` 权限；
- 不会生成同时可写和可执行的 `LOAD`。

过程链接表与动态元数据在紧凑文件中物理相邻，但它们的虚拟地址会放在分别满足页内偏移关系的 `LOAD` 映射中。

## 调用过程链接表标号

调用 `format_elfexe_import_plt` 提供的本地过程链接表标号：

```text
call getpid_plt
```

不要直接调用未定义的外部名称。XIRASM 需要这个本地过程链接表标号，才能让常用格式接口把调用指令连接到自动生成的运行时解析入口。

槽位标号表示过程链接表使用的全局偏移表项。当代码需要取得已经解析的函数指针时，可以使用它；普通的过程调用通常使用过程链接表标号。

## 导入过程仍需遵守平台应用二进制接口

格式接口负责构造 ELF 元数据，不会改变被导入函数的调用约定。

调用库过程之前，应当：

- 按照平台应用二进制接口的要求，把参数放入指定寄存器或栈位置；
- 保留该接口要求调用方保留的寄存器；
- 维持要求的栈对齐；
- 按照函数约定解释返回值。

即使加载器正确解析了符号，调用方使用错误的应用二进制接口仍会导致调用失败。

## 解释器路径属于文件内容

当前 ELF64 可执行文件导入流程会记录：

```text
/lib64/ld-linux-x86-64.so.2
```

目标系统必须在这个路径提供兼容的运行时解释器。运行时目录布局不同的系统可能会在程序入口执行之前拒绝该文件。

解释器路径与 `DT_NEEDED` 中的共享库名称不是一回事。解释器负责读取可执行文件的动态元数据，再查找 `libc.so.6` 等依赖库。

## 当前常用接口的边界

当前常用格式接口支持：

- 不生成动态导入的 ELF64 位置无关可执行文件；
- 通过过程链接表进行动态导入的固定地址 ELF64 `EXEC` 文件。

它目前不允许把 `format_elfexe_tables` 附加到：

- ELF64 位置无关格式方案；
- ELF32 可执行文件；
- ELF32 位置无关格式方案。

这些组合会被拒绝，避免生成不完整的动态元数据。

不要把常用格式方案与按位宽划分或按表项逐行操作的辅助接口混合起来，以此绕过上述边界。需要直接控制格式细节时，应使用单独的高级格式指南所介绍的流程。

## 位置无关模式与动态导入的常见错误

### 在位置无关数据中保存绝对内部地址

在最小位置无关流程中，`dq(start)` 这样的原始指针不会自动根据加载地址调整。应使用相对访问，或者通过合适的高级流程生成所需的动态重定位。

### 在位置无关代码中使用绝对寻址

代码需要访问同一映像中的其他内容时，应使用 `[rel label]` 等相对寻址形式。

### 认为位置无关模式会添加库导入

`format_elf_pie` 只选择位置无关的映像放置方式，不会添加解释器、导入符号或过程链接表。

### 把导入表附加到位置无关方案

当前常用的可执行文件导入辅助接口要求使用 `format_elf_exec`。

### 继续使用原始格式方案

调用 `format_elfexe_tables` 后，后续构建流程必须使用它返回的新格式方案。

### 直接调用外部名称

应调用导入声明中指定的本地过程链接表标号。

### 为自动生成的元数据设置可写且可执行权限

常用格式接口会把可执行的过程链接表字节与可写的全局偏移表及动态状态分开。不要把它们合并到手工创建的可写且可执行段中。

### 忽略导入函数的应用二进制接口

ELF 符号解析不会检查参数、寄存器保留规则或栈对齐。

### 认为每个 Linux 系统都使用同一解释器

应确认目标系统提供生成文件中记录的解释器路径。

## 位置无关模式与动态导入实用规则

1. 使用 `format_elf64(format_elf_pie, segments)` 构造直接进行系统调用的位置无关可执行文件。
2. 位置无关代码及其内部数据引用应使用相对于当前指令位置的形式。
3. 除非运行时重定位会修正绝对标号值，否则不要把它写入数据字段。
4. 当前动态导入流程应使用 `format_elf64(format_elf_exec, segments)`。
5. 使用 `format_elfexe_import_plt` 声明导入过程。
6. 使用 `format_elfexe_tables` 把导入列表附加到格式方案。
7. 后续构建流程应继续使用更新后的格式方案。
8. 调用自动生成的本地过程链接表标号。
9. 遵守被导入函数的平台应用二进制接口。
10. 让格式接口生成并分隔过程链接表、全局偏移表、解释器记录和动态数据。
11. 现阶段应把位置无关模式和动态导入视为两种独立的受支持流程。

第 12 章将从运行时加载的映像转向 ELF32 和 ELF64 目标文件。链接器会使用这些目标文件中的命名节、符号，以及 `REL` 或 `RELA` 重定位记录。

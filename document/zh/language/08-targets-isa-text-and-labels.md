# 第 8 章：目标、指令与标号

编译期语言决定生成什么；汇编器模型决定生成的指令和数据放在哪里、由哪个指令集编码，以及符号引用如何变成具体值。

本章先讲三件事：

- 当前目标决定使用哪套指令集和位宽；
- 指令行会按当前目标编码；
- 标号给地址位置取名字，供指令和数据引用。

手写汇编时，直接选择目标、写指令、定义标号。只有确实需要在汇编期间拼出指令或标号名时，才使用 `isa(...)` 和 `label.define(...)`。

## 当前目标

每条指令都会按当前目标编码。目标包含指令集系列，以及该指令集需要的位宽等信息。

命令行选项设置初始目标：

```text
xirasm program.xir -o program.bin --target x86-64
xirasm program.xir -o program.bin --target x86
xirasm program.xir -o program.bin --target rv64
xirasm program.xir -o program.bin --target rv32
xirasm module.spvasm -o module.spv --target spv
```

没有显式选择时，XIRASM 默认使用 64 位 x86。源码仍然可以写明指令模式；示例、可复用 include 和依赖特定位宽的代码都建议显式声明：

```asm
// 明确选择后续指令使用的 64 位 x86 编码。
x86.use64();

entry:
    // 生成一个返回零的最小指令序列。
    xor eax, eax
    ret
```

模式调用只影响它之后出现的指令，不会改写前面已经写出的指令。

## 选择 x86、RISC-V 和 SPIR-V

源文件内用这些接口切换模式：

| 接口              | 后续指令按什么模式编码 |
| ----------------- | ------------ |
| `x86.use16()`   | 16 位 x86    |
| `x86.use32()`   | 32 位 x86    |
| `x86.use64()`   | 64 位 x86    |
| `riscv.use32()` | 32 位 RISC-V |
| `riscv.use64()` | 64 位 RISC-V |
| `spv.use()`    | SPIR-V 1.6 模块 |

同一源文件可以切换模式：

```asm
// 第一条指令使用 16 位 x86 编码。
x86.use16();
mov ax, 1

// 第二条指令使用 32 位 x86 编码。
x86.use32();
mov eax, 2

// 第三条指令使用 64 位 x86 编码。
x86.use64();
mov rax, 3
```

这三条指令分别按 16 位、32 位和 64 位 x86 编码。模式调用不会回头修改前面的指令。

选择编码模式不等于让生成的程序在运行时切换处理器模式。引导映像、内核、固件组件或混合模式程序仍然需要自己安排运行时模式转换。RISC-V 宽度选择也遵循同样的源码顺序规则：

```asm
// 选择 XLEN 为 64 位的 RISC-V 模式。
riscv.use64();

// 两条指令都会按照当前 64 位 RISC-V 目标编码。
addi x1, x0, 1
addi x0, x0, 0
```

不要把 x86 的模式概念套到 RISC-V 或 SPIR-V 上。XIRASM 会分别保存各 ISA 的目标设置，而不是把所有 ISA 都压成一个通用的 `mode_bits` 值。

SPIR-V 不是逐条独立编码的机器指令流，而是一个完整的逻辑模块。用 `spv.use()` 选择 SPIR-V 1.6，然后直接书写标准 `Op*` 指令和数字结果 ID：

```asm
spv.use();

OpCapability Shader
OpMemoryModel Logical GLSL450
%1 = OpTypeVoid
```

命令行可用 `--target spv` 或 `--target spirv`，两者都选择 SPIR-V 1.6。同一个 SPIR-V 输出只能包含同一个 section、同一个模块版本的 SPIR-V 指令行，不能混入 x86/RISC-V 指令，也不能混入数据写出、预留或对齐片段。结果 ID 目前必须写成 `%1` 这类数字形式，不接受符号 ID。

## 查询目标

编译期控制流可以检查当前目标：

```asm
// 选择 x86 后端和 64 位模式。
x86.use64();

// 这个条件在汇编期间判断，不会生成运行时分支。
if target.isa == .x86_64 {
    assert(target.bits == 64);
    mov eax, 1
}
```

可查询的目标系列值：

| 值           | 目标系列                 |
| ------------ | ------------------------ |
| `.x86_64`  | x86（use16/use32/use64） |
| `.riscv64` | RISC-V（xlen 32/64）     |
| `.spirv`   | SPIR-V                   |

这些公开的目标系列名称标识后端系列，不报告当前指令宽度。例如 `x86.use32()` 之后，`target.isa == .x86_64` 仍然成立，但 `target.bits == 32`。

需要判定位宽时用 `target.bits`；RISC-V 条件也可以使用 `target.xlen`：

```asm
// 选择 XLEN 为 32 位的 RISC-V 模式。
riscv.use32();

// 同时检查后端系列与 XLEN。
if target.isa == .riscv64 {
    assert(target.xlen == 32);
    addi x1, x0, 1
}
```

## 直接书写指令

指令使用所选指令集的常规汇编语法：

```asm
// 选择 64 位 x86，然后直接编写指令。
x86.use64();

entry:
    mov rax, 1
    add rax, 2
    ret
```

指令行由助记符和操作数组成。空格用于提高可读性；方括号、圆括号或花括号中的逗号属于嵌套操作数的一部分，不会把指令错误拆开。

指令行末尾不写分号。结构化的编译期调用需要分号：

```asm
// 这两行是编译期接口调用，因此以分号结束。
x86.use64();
emit.u8(0x90);

// 这一行是处理器指令，因此不写分号。
nop
```

`x86.use64();` 和 `emit.u8(0x90);` 是编译期 API 调用，`nop` 是处理器指令。

XIRASM 会把指令内容和当前目标一起交给对应后端编码。标号、布局、输出区域和地址回填仍由前端负责。

SPIR-V 是例外：汇编器会按源码顺序收集整个模块的指令，再一次性交给后端，使模块头、ID 上界、类型上下文和扩展指令集保持一致。

## 在指令中使用编译期值

编译期常量可以直接出现在指令操作数中：

```asm
// 在汇编期间计算立即数。
x86.use64();
const initial_value: u32 = 40 + 2

entry:
    // 编译期常量会直接成为指令操作数。
    mov eax, initial_value
    ret
```

标号也可以在指令中参与运算：

```asm
// 把逻辑起始地址设置为 0x1000。
x86.use64();
origin(0x1000);

target:
    // 操作数表示标号地址再加四。
    mov rax, target + 4
    ret
```

汇编器会以符号形式保留表达式，等地址确定后再求值。

只有确实需要动态生成指令时，才拼接指令字符串。

## 静态标号

标号写在名字后加冒号：

```asm
// 使用普通标号表达控制流。
x86.use64();

entry:
    mov eax, 1
    jmp done

done:
    ret
```

标号不产生任何字节，只把名字绑定到当前位置。

标号可以先使用后定义：

```asm
// finished 在跳转指令之后定义，仍然可以提前引用。
x86.use64();

entry:
    jmp short finished
    mov eax, 1

finished:
    ret
```

前向引用的长度选择属于指令编码约束。源码可以显式写出 `short` 或 `near`，也可以让布局和后端在约束允许时处理符号位移；不要在源码中手算跳转偏移。

## 符号引用与地址回填

引用标号的指令，有时要等布局确定后才能知道最终位移。

XIRASM 的处理顺序：

1. 源文件定义标号并生成指令片段。
2. 后端先编码指令，把依赖标号的字段暂时留下。
3. 布局器给标号和片段分配最终地址。
4. 地址确定后计算标号表达式，并把结果写回指令字段。

前向引用不需要手动计算地址：

```asm
// 跳转目标稍后定义，位移由汇编器计算。
x86.use64();

entry:
    jmp target
    nop

target:
    ret
```

只要源文件描述指令及其标号表达式，而非手动填偏移，前面的指令改变长度也不会失效。

## 动态指令文本与动态标号

编译期需要计算名字时使用动态指令和标号：

```asm
// 根据多个固定部分组成动态标号名称。
const done: string = sym.join("generated_", "done")

// 动态指令和动态标号仍然进入正常的汇编流程。
isa(sym.join("jmp ", done));
label.define(done);
isa("ret");
```

```asm
// 这是上一个动态示例所对应的普通静态写法。
jmp generated_done
generated_done:
ret
```

`isa(text)` 把指令文本交给当前目标编码，`label.define(name)` 在当前位置创建标号。命名用 `sym.join`，需要唯一名称时用 `sym.unique`。

只在确实需要时用动态标号。不要替代 `loop:`、`done:` 等静态写法。

## 读取标号地址

`label_addr(label_or_name)` 返回标号的逻辑地址：

```asm
// 定义一个标号，并把它的逻辑地址写入输出。
x86.use64();

entry:
    ret

dq(label_addr(entry));
```

指令内的标号引用通过地址计算完成，不需要手动查询。`label_addr()` 用于数据段写入标号地址这类求值场景。

布局未稳定时，在 `defer`（第 12 章）里延迟查询。需要重定位时用格式接口，不要手动填偏移。

## 实用规则

- 源文件开头明确选择目标模式。
- 指令按对应 ISA 的汇编语法直接写。
- 编译期调用末尾加分号，指令末尾不加。
- 源文件中地址明确时用静态标号。
- 前向引用以符号形式传递地址。
- 只在确实需要时用 `isa` 和 `label.define`。
- 判定位宽用 `target.bits`，判定系列用 `target.isa`。
- 布局未稳定时，推迟绝对地址查询到 `defer`。
- 需要可加载文件中的重定位时，使用格式接口提供的重定位声明。

下一章介绍数据声明和二进制布局。

[返回目录](../language.md)

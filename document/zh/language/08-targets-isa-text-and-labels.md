# 第 8 章：目标平台、处理器指令与标号

本章涵盖三件事：选择目标平台和指令集，用自然 ISA 语法写指令，用标号给输出位置命名(所谓的符号逻辑RV地址)。

## 当前目标平台

每个指令都根据当前目标平台编码。目标平台决定指令集系列，以及编码时用到的目标信息。

命令行选项设置初始目标平台：

```text
xirasm program.xir -o program.bin --target x86-64
xirasm program.xir -o program.bin --target x86
xirasm program.xir -o program.bin --target rv64
xirasm program.xir -o program.bin --target rv32
```

默认使用 64 位 x86。源文件可以随时切换模式。文件头写明模式能帮助编辑器、语法高亮和特定宽度的代码片段正确配置：

```asm
// 明确选择后续指令使用的 64 位 x86 编码。
x86.use64();

entry:
    // 生成一个返回零的最小指令序列。
    xor eax, eax
    ret
```

模式切换只影响之后的指令。每个指令都记住编码时的目标平台。

## 选择 x86 和 RISC-V 模式

源文件内用这些接口切换模式：

| 接口              | 后续指令模式 |
| ----------------- | ------------ |
| `x86.use16()`   | 16 位 x86    |
| `x86.use32()`   | 32 位 x86    |
| `x86.use64()`   | 64 位 x86    |
| `riscv.use32()` | 32 位 RISC-V |
| `riscv.use64()` | 64 位 RISC-V |

同一源文件可以多次切换：

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

每条指令独立记住自己的编码模式。

多模式常见于引导代码、内核、固件。RISC-V 也一样：

```asm
// 选择 XLEN 为 64 位的 RISC-V 模式。
riscv.use64();

// 两条指令都会按照当前的 64 位 RISC-V 目标编码。
addi x1, x0, 1
addi x0, x0, 0
```

x86 和 RISC-V/SPIR-V 的配置互不影响。

## 查询目标平台

编译时控制流可以检查当前目标平台：

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

系列标识不反映当前位宽。`x86.use32()` 之后 `target.isa == .x86_64` 仍然成立，但 `target.bits == 32`。

判定位宽用 `target.bits`，RISC-V 也可以用 `target.xlen`：

```asm
// 选择 XLEN 为 32 位的 RISC-V 模式。
riscv.use32();

// 同时检查后端系列与 XLEN。
if target.isa == .riscv64 {
    assert(target.xlen == 32);
    addi x1, x0, 1
}
```

## 汇编指令写法

指令用所选指令集的常规文本语法写：

```asm
// 选择 64 位 x86，然后直接编写普通指令。
x86.use64();

entry:
    mov rax, 1
    add rax, 2
    ret
```

一行一个指令。空格提高可读性，括号和逗号处理嵌套操作数。

汇编指令末尾不写分号。编译期接口调用需要分号：

```asm
// 这两行是编译期接口调用，因此以分号结束。
x86.use64();
emit.u8(0x90);

// 这一行是处理器指令，因此不写分号。
nop
```

`x86.use64();` 和 `emit.u8(0x90);` 是编译期调用，`nop` 是原生指令。

XIRASM 把指令文本和当前目标平台一起保存，再交给指令集后端编码。标号、数字、表达式和地址计算在前端处理。

## 在指令中使用编译期值

编译期变量可以直接出现在指令操作数中：

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

编译器以符号形式保留表达式，地址确定后再求值。

只在你确实需要动态生成时才拼指令字符串。

## 静态标号

标号写在名字后加冒号：

```asm
// 使用静态标号表达普通控制流。
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

前向引用需要明确写 `short/near`。x86 编码保留长度约束，由布局器处理。

实际上后端能自动处理，但建议X64还是带near，这样后端速度会快一点.

后端默认不是短跳转优先。

## 符号引用与地址回填

包含符号的指令宽度不固定。

XIRASM 的处理顺序：

1. 源文件定义标号并生成指令片段。
2. 后端逐条编码指令，符号字段暂时未知。
3. 布局器给标号和片段分配最终地址。
4. 地址确定后计算每个标号表达式，回填已编码字段。

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

字符串/token拼接。

编译时需要计算名字时使用动态指令和标号：

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

`isa(text)` 编码指令文本，`label.define(name)` 在当前位置创建标号。命名用 `sym.join`，展开用 `sym.unique`。

只在确实需要时用动态标号。不要替代 `loop:`、`done:` 等静态写法。

## 读取标号地址

`label_addr(label_or_name)` 返回标号的逻辑地址：

```asm
// 定义一个普通标号，并把它的逻辑地址写入输出。
x86.use64();

entry:
    ret

dq(label_addr(entry));
```

指令内的标号引用通过地址计算完成，不需要手动查询。`label_addr()` 用于数据段写入标号地址这类求值场景。

布局未稳定时改用 `defer`（第 12 章）延迟查询。需要重定位时用格式接口，不要手动填偏移。

## 实用规则

- 文件头明确选择目标模式。
- 指令用自然 ISA 文本。
- 编译期调用末尾加分号，指令末尾不加。
- 源文件中地址明确时用静态标号。
- 前向引用以符号形式传递地址。
- 只在确实需要时用 `isa` 和 `label.define`。
- 判定位宽用 `target.bits`，判定系列用 `target.isa`。
- 布局未稳定时，推迟绝对地址查询到 `defer`。
- 需要加载重定位地址时用格式重定位接口。

下一章介绍数据声明和二进制布局。

[返回目录](../language.md)

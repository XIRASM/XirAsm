# 第 5 章：函数与作用域

## 函数复用汇编期间的工作

函数用来复用汇编期间的逻辑。它可以计算一个值，也可以写出数据、指令或组合多个输出操作。

XIRASM 有两种函数：

- **过程函数**执行操作，不返回表达式值。
- **返回值函数**计算并返回一个值，用 `->` 声明返回类型。

两种函数都用 `fn`、参数列表和代码块声明。函数在汇编期间执行；声明函数本身不写字节。只有调用过程函数，或把返回值交给输出接口时，输出才会变化。

一个函数最好只做一类事：要么执行输出或布局操作，要么返回一个可用于表达式的值。

## 指令形式的宏

`macro` 让 Meta 编码过程可以用自然指令语法调用：

```asm
macro byte(value) {
    const n: u64 = operand.eval(value)
    emit.u8(n)
}
const LIMIT: u64 = 7
byte LIMIT + 1
byte (LIMIT + 2)
```

输出为 `08 09`。参数是不可变的 `operand`，不会自动变成整数或字符串。
`operand.eval` 用调用处捕获的值绑定求值；宏内同名变量不会改变传入表达式的含义。
类型、整数溢出、变量声明和赋值仍遵循普通 Meta 规则。前向标号应通过
`operand.text` 交给延迟分支辅助函数，不应提前求地址。

`operand.text(op)` 取拼写；`operand.slice(op, start, end)` 取经过边界检查的
左闭右开字节片段；`operand.split(op)` 在顶层逗号处分割，保留引号和配对的
`()[]{}`，返回操作数列表。切片和分割保留原始捕获环境。

```asm
macro twice(dst, src) {
    mov dst, src
    mov dst, src
}
macro bytes(...values) {
    for item in values {
        byte item
    }
}
twice eax, ebx
bytes 1, 2, 3
```

指令操作数中绑定到 `operand` 的标识符会转发原始操作数，包括循环和辅助函数中的
操作数局部变量。普通字符串、引号内文本和助记符不替换，插入的参数也不会再次扫描。
混合模板的每个片段保留各自的值绑定；求值过程中调用的函数，以及 `here()` 等位置
内置函数，使用第一个片段的捕获上下文。每次显式调用 `operand.eval` 都会重新求值。

宏必须在顶层定义，先定义或导入后使用。名称区分大小写，允许点分隔名称。
参数没有类型注解和默认值，末尾可以有一个 `...name`。相同名称允许多个不同精确
参数数目的定义及一个可变参数定义；精确匹配优先，已知名称参数数目不匹配时报错。
调用使用 `name operands`；`name(expression)` 是函数语法，`name (expression)`
中的空白表示首个操作数为括号表达式。宏体使用现有的多行代码块语法。

宏可以使用 Meta 变量、控制流、过程、指令和合法的收尾块注册，但不能返回值。
`break`、`continue` 不能跳出调用者的循环。已保存的 `defer`、`late_layout` 中不能
定义或调用宏，也不能借宏绕过返回值函数的副作用限制。

每个实际到达的宏调用仅在源码 lowering 时执行一次。编码、布局、松弛和收尾不会
重跑宏体。函数和宏共享 128 层调用深度；同一 lowering 上下文累计最多调用宏
100,000 次，每次最多 256 个操作数、64 层操作数括号。这不替代原有 Meta 循环限制。
保存的操作数之间最多有 128 层捕获依赖，超限报告 `MacroCaptureDepthExceeded`。
捕获会复制可见的值绑定；不再需要原始语法时应保存求值结果，避免长期保留较大的环境和集合。
静态标号仍是模块标号；私有标号用 `sym.unique` 配合 `label.define`。
`isa(text)` 可绕过宏查找，直接提交原生指令。

### A64 自然指令

```asm
import("arm/arm64-macros.inc")
const VALUE: u64 = 42
movz x0, #VALUE
add x1, x0, #(VALUE + 1)
ldr x2, [sp, #16]
b.eq done
done:
ret
```

此可选入口包装现有 `arm64/asm.inc` 支持的整数移动、算术、逻辑、条件、分支和
访存/地址形式，不代表全部 A64 或浮点/SIMD API 都有宏。立即数沿用 Meta 表达式，
寄存器、范围、移位、对齐和写回检查由 DSL 编码辅助函数完成。`b.eq` 只有一个目标参数。
导入后，同名助记符在该 lowering 上下文中归宏处理，不自动按原生 target 隔离；
混合 ISA 源码需要 API-only 入口时继续导入 `arm/arm64.inc`。

## 过程函数

过程函数适合组合一组输出操作：

```asm
// 把传入字节及其后继值作为一组连续数据写出。
fn emit_pair(value: u8) {
    db(value);
    db(value + 1);
}

// 两次调用分别生成 02 03 和 08 09。
emit_pair(2);
emit_pair(8);
```

输出：

```text
02 03 08 09
```

没有 `->` 返回类型的函数就是过程函数。过程调用是一条语句，末尾要加分号。

过程函数体可以包含声明、赋值、控制流、数据输出以及其他过程调用。重复的二进制记录、指令序列、表项或格式构建步骤，都适合写成过程函数。

过程函数本身不是值，不能用于初始化绑定：

```text
fn emit_marker() {
    db(0x90);
}

const marker = emit_marker()
```

这会报错，因为 `emit_marker()` 只执行操作，不返回表达式值。

## 参数和实参

参数写在括号里：

```asm
// 连续写出 count 个相同字节。
fn emit_run(value: u8, count: u64) {
    // index 负责控制循环次数，循环体只需要使用 value。
    for index in range(0, count) {
        db(value);
    }
}

// 写出四个 cc 字节。
emit_run(0xcc, 4);
```

输出四个 `cc` 字节。`index` 控制循环次数，即使循环体里未使用它。

参数类型可以省略，但公开辅助函数最好写清楚：

```asm
// 形参类型可以省略，调用时传入的值会绑定到对应形参。
fn add(left, right) -> u64 {
    return left + right;
}

// 计算 20 + 22，并把结果 2a 写成一个字节。
db(add(20, 22));
```

输出 `2a`。实参值按位置绑定到对应参数。公开的辅助函数建议加类型注解，让调用约定更明确，也能更早发现不合适的实参。

实参按位置对应参数。调用时必须为每个参数提供一个实参；没有默认实参机制。同一函数的参数名不能重复。每次调用有独立的参数绑定，互不影响。

## 返回值函数

函数需要返回表达式值时，加上 `-> type`：

```asm
// 把 value 向上对齐到 alignment 的整数倍。
fn align_up(value: u64, alignment: u64) -> u64 {
    return ((value + alignment - 1) / alignment) * alignment;
}

// 0x73 按 0x20 对齐后得到 0x80，再以双字节写出。
const header_size = align_up(0x73, 0x20)
dw(header_size);
```

函数返回 `0x80`，输出：

```text
80 00
```

`return` 末尾加分号。返回表达式必须符合声明的返回类型。返回类型可以是整数、布尔值、字符串、字节序列等：

```asm
// 判断传入值是否等于一个 0x1000 字节的页大小。
fn is_page(value: u64) -> bool {
    return value == 0x1000;
}

// 返回固定的两个签名字节。
fn signature() -> bytes {
    return b"XR";
}

// 先检查计算结果，再写出签名字节。
assert(is_page(0x1000));
db(signature());
```

返回值函数可以放在任何接受其返回类型的位置：声明、实参、条件、函数调用，或更大的表达式里。

## 返回规则

返回值函数必须执行到 `return`。末尾无返回值会报错：

```text
fn incomplete(value: u64) -> u64 {
    const doubled = value * 2
}

const result = incomplete(4)
```

返回值类型必须匹配：

```text
fn enabled() -> bool {
    return 1;
}

const result = enabled()
```

报错，整数不满足 `bool` 约定。

返回值函数只用于计算，不能写出数据，也不能改变布局：

```text
fn bad_counter() -> u64 {
    db(1);
    return 1;
}

const result = bad_counter()
```

需要改变输出或布局时用过程函数；需要计算值时用返回值函数。

过程函数不声明返回类型，也不能返回值：

```text
fn emit_one() {
    return 1;
}

emit_one();
```

过程函数执行到末尾即结束。

## 函数局部作用域

参数和函数内的绑定只属于当前调用：

所有实参先在调用方的作用域中求值，然后才建立新的形参绑定。例如调用 `pair(b, a)` 时，名为 `a` 的形参不会改变第二个实参 `a` 的含义。

```asm
// 加上固定开销，并确保结果不小于 16。
fn adjusted_size(size: u64) -> u64 {
    const overhead = 4
    let result = size + overhead

    if result < 16 {
        result = 16
    }

    return result;
}

// 两次调用各自使用独立的局部绑定。
db(adjusted_size(3));
db(adjusted_size(20));
```

输出 `10 18`。每次调用创建新的 `size`、`overhead`、`result`，调用结束后这些名字不再可用。

函数内的块创建嵌套作用域，可遮蔽外部名字：

```asm
// 使用嵌套作用域中的同名常量参与一次局部计算。
fn combine(value: u64) -> u64 {
    let result = value

    {
        // 此处的 value 只在这个代码块内表示常量 5。
        const value = 5
        result = result + value
    }

    return result;
}

// 参数值 3 与局部常量 5 相加，结果为 08。
db(combine(3));
```

输出 `08`。嵌套块中 `value` 指向局部常量 `5`。块结束后参数 `value` 重新可见。

中间计算放在局部名字里，临时状态不会泄漏到函数外，多次调用也互不干扰。

## 声明顺序

函数必须在调用前声明：

```asm
// 先声明函数，后面的源代码才能引用它。
fn add(left: u64, right: u64) -> u64 {
    return left + right;
}

// 调用已经可见的函数，并写出结果。
const answer = add(20, 22)
db(answer);
```

把调用移至声明前会报错，此时函数名尚未定义。

函数声明只能出现在顶层，不能写在另一个函数、循环、条件块或代码块内。相关函数可以在顶层相邻排列，供后续源码调用。

第 10 章介绍如何通过包含文件将函数声明提供给另一个源文件。

## 递归和调用深度

返回值函数在有终止条件时可以递归调用自身：

```asm
// 递归计算从 value 到 1 的总和。
fn triangular(value: u64) -> u64 {
    // value 为零时停止递归。
    if value == 0 {
        return 0;
    }

    return value + triangular(value - 1);
}

// triangular(4) 计算 4 + 3 + 2 + 1，并写出 0a。
db(triangular(4));
```

输出 `0a`，即 `4 + 3 + 2 + 1` 的结果。

递归在汇编期间执行。递归深度应控制在较小范围内，终止条件必须明确。XIRASM 会拒绝超过 128 层调用的函数链，避免失控递归。

遍历范围或集合时用循环。只有计算本身具有递归结构且终止条件明确时，才用递归。

## 选哪种函数

| 需求             | 使用           |
| ---------------- | -------------- |
| 输出字节或指令   | 过程函数       |
| 组合多个输出调用 | 过程函数       |
| 为表达式计算值   | 返回值函数     |
| 复用纯计算逻辑   | 返回值函数     |
| 临时名字不泄漏   | 两种均可       |
| 遍历范围或集合   | 通常用循环     |
| 递归计算         | 递归返回值函数 |

每个函数尽量专注一件事。小的计算函数容易组合；小的过程函数也更容易从调用处看出会写出什么。

下一章介绍列表、映射、字符串和字节序列，供需要处理集合和文本的函数使用。

[返回语言指南](../language.md)

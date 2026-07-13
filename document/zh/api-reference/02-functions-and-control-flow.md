# 第 2 章：函数与流程控制

函数和流程控制语句在汇编过程中执行。它们用于计算值、选择源码中的操作和重复执行这些操作。除非函数体或语句块写出相应的处理器指令，否则不会生成运行时函数调用、分支或循环。

## 语法摘要

| 形式 | 语法 | 用途 |
| --- | --- | --- |
| 过程函数 | `fn name(parameters) { statements }` | 封装编译期操作。 |
| 过程调用 | `name(arguments)` | 执行过程函数。 |
| 返回值函数 | `fn name(parameters) -> type { statements }` | 计算表达式值。 |
| 返回 | `return expression` | 结束返回值函数并给出结果。 |
| 返回值调用 | `name(arguments)` | 在表达式中使用返回值函数。 |
| 条件分支 | `if condition { statements }` | 布尔条件为真时执行代码块。 |
| 备选分支 | `} else { statements }` | 执行备选代码块。 |
| 条件循环 | `while condition { statements }` | 布尔条件保持为真时重复执行。 |
| 数值范围循环 | `for name in range(start, end) { statements }` | 迭代左闭右开的数值范围。 |
| 列表循环 | `for name in list_value { statements }` | 按顺序迭代列表中的值。 |

## 过程函数

```asm
// 定义一个过程函数，连续写出输入值及其后继值。
fn emit_pair(value: u8) {
    emit.u8(value)
    emit.u8(value + 1)
}

// 分别调用两次，写出两组相邻字节。
emit_pair(2)
emit_pair(8)
```

没有 `-> type` 的函数是过程函数。过程函数执行操作，但不产生表达式值。函数体可以写出数据或指令、改变布局、声明局部值、使用流程控制，以及调用其他过程函数。

参数按位置对应。类型标注可以省略；如果提供了类型标注，调用时会用它检查对应实参。每次调用都必须为每个参数提供且只提供一个实参。

过程调用是一条语句。末尾可以写分号，但不要求写。

## 返回值函数

```asm
// 将 value 向上对齐到 alignment 的整数倍。
fn align_up(value: u64, alignment: u64) -> u64 {
    return ((value + alignment - 1) / alignment) * alignment
}

// 计算对齐后的值，并将 16 位结果写入输出内容。
emit.u16(align_up(0x73, 0x20))
```

带有 `-> type` 的函数是返回值函数。它的调用属于表达式，可以出现在声明、条件、实参、`return` 或更大的表达式中。

`return` 会计算表达式，并把结果转换为声明的返回类型。返回值函数中每条实际执行的路径都必须到达 `return`。

返回值函数用于辅助计算。它可以使用局部绑定、流程控制和其他返回值函数，但不得写出输出内容，也不得执行其他会改变布局的操作。

## 函数声明与调用规则

- 函数必须在顶层声明。
- 函数声明必须出现在首次调用之前。
- 同一声明中的参数名称不得重复。
- 每次调用都有各自的参数和局部绑定。
- 过程调用不能用作表达式值。
- `return` 只能出现在返回值函数中。
- 函数调用链最多允许 128 层。

只要递归返回值函数能在达到调用深度上限前结束，就允许使用递归。如果操作本身适合迭代，应使用循环。

## `if` 与 `else`

```asm
// enabled 为 false，因此只执行备选分支。
const enabled = false

if enabled {
    emit.u8(0x11)
} else {
    emit.u8(0x22)
}
```

条件必须计算为 `bool`。只有选中的分支会执行。每个分支都有自己的词法作用域。

备选分支应写成规范的 `} else if condition {` 和 `} else {` 形式。`else if` 和最后的 `else` 都可以省略。

`if` 语句在汇编期间选择源码操作。要实现运行时条件行为，仍需写出处理器分支指令。

## `while`

```asm
// 每轮写出当前值，再更新控制循环的可变绑定。
let value = 1

while value <= 3 {
    emit.u8(value)
    value = value + 1
}
```

`while` 会在每次迭代前计算布尔条件。如果条件一开始就是假，循环体不会执行。

`break` 会结束最内层的活动 Meta 循环。`continue` 会跳过循环体中剩余的语句并开始下一次迭代。它们也可以用于 `for` 循环和延迟执行的 `while` 代码块。编译期循环最多执行 1,000,000 次。在循环外使用循环控制语句，或试图让它跨越函数调用边界，均属于错误。

## 数值范围迭代

```asm
// 迭代左闭右开的范围 [0, 4)，依次写出四个字节。
for index in range(0, 4) {
    emit.u8(index)
}
```

`range(start, end)` 包含 `start`，不包含 `end`。此示例写出 `00 01 02 03`。

数值范围只能向前移动，也可以为空。降序范围无效：

```text
for value in range(2, 0) {
    emit.u8(value)
}
```

循环绑定是只读的局部值。每次迭代都会获得新的绑定和新的循环体作用域。

## 列表迭代

```asm
// 按列表顺序写出三个预先选定的操作码字节。
const opcodes: list = list.of(0x90, 0x90, 0xc3)

for opcode in opcodes {
    emit.u8(opcode)
}
```

列表循环按列表顺序访问各个值。循环绑定只在本次迭代中有效，不能对它赋值。

这种形式只直接接受列表值。要迭代映射内容，应先用 `map.keys(...)` 或 `map.values(...)` 等映射辅助函数取得列表。

## 无效的函数形式

过程函数不能返回值：

```text
fn invalid() {
    return 1
}

invalid()
```

返回值函数不能在未返回结果的情况下执行到函数末尾：

```text
fn invalid() -> u64 {
    const value = 1
}

const result = invalid()
```

返回值函数不能写出输出内容：

```text
fn invalid() -> u64 {
    emit.u8(1)
    return 1
}

const result = invalid()
```

操作会改变输出内容或布局时，应使用过程函数。调用方需要计算结果时，应使用返回值函数。

## 完整示例

```asm
// 过程函数负责写出一对相邻字节。
fn emit_pair(value: u8) {
    emit.u8(value)
    emit.u8(value + 1)
}

// 返回 value 与 limit 中较小的值。
fn choose(value: u64, limit: u64) -> u64 {
    if value > limit {
        return limit
    } else {
        return value
    }
}

// 写出过程函数结果和返回值函数结果。
emit_pair(1)
emit.u8(choose(9, 5))

// 编译期条件选择第一个源码分支。
const enabled = true

if enabled {
    emit.u8(0xaa)
} else {
    emit.u8(0xff)
}

// 条件循环写出两个连续值。
let counter = 0

while counter < 2 {
    emit.u8(0x10 + counter)
    counter = counter + 1
}

// 数值范围循环写出 0x20 和 0x21。
for index in range(0, 2) {
    emit.u8(0x20 + index)
}

// 列表循环按顺序写出列表中的两个值。
const values: list = list.of(0x30, 0x31)

for value in values {
    emit.u8(value)
}
```

源代码会写出：

```text
01 02 05 aa 10 11 20 21 30 31
```

## 选用指南

| 需求 | 使用形式 |
| --- | --- |
| 封装会改变输出内容或布局的操作 | 过程函数 |
| 计算可复用的表达式值 | 返回值函数 |
| 选择一个代码块 | `if` |
| 在两个代码块中选择一个 | `if` / `else` |
| 在多个代码块中选择一个 | `if` / `else if` / `else` |
| 重复执行，直到可变状态满足条件 | `while` |
| 迭代固定的数值范围 | 搭配 `range` 的 `for` |
| 迭代列表中的已知值 | 搭配列表的 `for` |
| 提前结束最内层循环 | `break` |
| 跳过当前迭代的剩余部分 | `continue` |

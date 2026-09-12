# 第 4 章：控制流

## 控制流在汇编期间执行

XIRASM 的控制流决定构造输出时要执行哪些源码操作。它不会自动生成运行时的分支或循环。

```asm id=if-else target=x86-64 bytes=52454c45415345
const debug_build = false

if debug_build {
    db("DEBUG")
} else {
    db("RELEASE")
}
```

只有选中的分支会写出字节。运行时分支仍然用普通指令写：x86 的 `jmp`、`call` 和条件跳转。

## `if` 与 `else`

`if` 的条件必须产生布尔值。选中的代码块在自己的作用域中执行，未选中的代码块什么都不产生：

```asm id=if-else-if target=x86-64 bytes=02
const payload_size = 32

if payload_size < 16 {
    db(1)
} else if payload_size < 64 {
    db(2)          // 走这个分支
} else {
    db(3)
}
```

`else` 可以省略：

```asm id=if-without-else target=x86-64 bytes=4d41524b
const include_marker = true

if include_marker {
    db("MARK")
}
```

## 条件生成的指令

`if` 代码块里可以放处理器指令，因此同一份源码能为不同配置生成不同指令：

```asm id=instruction-selection target=x86-64 bytes=31c0c3
x86.use64()

const return_zero = true

entry:
    if return_zero {
        xor eax, eax
    } else {
        mov eax, 1
    }
    ret
```

没被选中的 `mov` 不会进入输出。这是编译期选指令，不是运行时分支。

## 目标条件

`target.isa` 是所选指令集族，`target.bits` 是当前位宽。`x86.use32()` 这类模式调用会改变后面的条件看到的值：

```asm id=target-condition target=x86-64 bytes=1000
x86.use32()

if target.isa == .x86_64 {
    db(0x10)          // 指令集族仍是 x86
}

if target.bits == 32 {
    db(0x00)          // 但位宽已经变成 32
}
```

目标查询有专门的条件语法，直接写在 `if` 条件里。

## `for` 与 `range`

迭代次数已知时用 `range(start, end)`。起点包含在内，终点排除在外：

```asm id=range-loop target=x86-64 bytes=00010203
for index in range(0, 4) {
    db(index)
}
```

倒序的范围会被拒绝：

```asm id=descending-range target=x86-64
for index in range(4, 0) {
    db(index)
}
```

```text
bad.xir:1:1: error: lowering failed: InvalidMetaFor
```

循环绑定属于循环体，而且每一轮都重新绑定一次：

```asm id=loop-local-binding target=x86-64 bytes=101112
for index in range(0, 3) {
    const encoded = index + 0x10
    db(encoded)
}
```

## `for` 与列表

`for` 也按列表顺序遍历编译期列表的值：

```asm id=list-loop target=x86-64 bytes=9090c3
const opcodes: list = list.of(0x90, 0x90, 0xc3)

for opcode in opcodes {
    db(opcode)
}
```

列表和映射在第 6 章介绍。

## `while`

终止条件依赖循环自己更新的值时用 `while`：

```asm id=while-loop target=x86-64 bytes=01020304
let value = 1

while value <= 4 {
    db(value)
    value = value + 1
}
```

每轮开始前先判断条件，所以一开始条件就为假的循环体一次也不执行。无法终止的编译期循环会让整个构建停住，因此循环超过 1,000,000 次就直接停止：

```asm id=loop-limit target=x86-64
for index in range(0, 1000001) {
    db(0)
}
```

```text
bad.xir:1:1: error: the loop ran past the supported iteration limit (MetaLoopLimitExceeded)
```

## `break` 与 `continue`

`break` 结束最内层循环，`continue` 跳过本轮剩下的部分。两者在 `for`、`while` 和嵌套的 `if` 里都能用：

```asm id=break-continue target=x86-64 bytes=000204
for value in range(0, 8) {
    if value == 6 {
        break
    }
    if (value & 1) != 0 {
        continue
    }
    db(value)          // 6 以下的偶数
}
```

两者都不会跨过函数调用边界：

```asm id=loop-control-in-function target=x86-64
fn stop() {
    break
}

for index in range(0, 3) {
    stop()
}
```

```text
bad.xir:2:5: error: break used outside of a Meta loop
```

[返回语言指南](../language.md)

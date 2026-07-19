# 第 4 章：控制流

## 控制流只影响汇编过程

XIRASM 的 `if`、`for`、`while` 在汇编期间执行。它们决定哪些源码参与本次输出、哪些源码重复执行；不会自动变成最终程序里的运行时分支或循环。

```asm
// 这个编译期选项决定输出调试标记还是发布标记。
const debug_build = false

if debug_build {
    db("DEBUG");
} else {
    db("RELEASE");
}
```

只有选中的分支会写出字节。`debug_build` 为 false 时，输出包含 `RELEASE`；生成文件里没有运行时条件判断。

编译期控制流用来：

- 按目标选择源码
- 重复生成数据或指令
- 遍历编译期集合
- 计算表格和偏移量
- 包含可选的文件格式记录
- 验证源码配置

运行时控制流仍然要写处理器指令，比如 x86 的 `jmp`、`call` 和条件分支。

## `if` 和 `else`

`if` 条件必须产生布尔值：

```asm
// 根据数据大小选择一个单字节标记。
const payload_size = 32

if payload_size <= 64 {
    db(0x01);
} else {
    db(0xff);
}
```

选中的块在自己的作用域中执行。另一个块不会写出内容，也不会执行其中的编译期操作。

`else` 块可以省略：

```asm
// 只有选项启用时才写出标记文本。
const include_marker = true

if include_marker {
    db("MARK");
}
```

需要多于两个分支时用 `else if`：

```asm
// 通过链式条件把数据大小划分为三个区间。
const payload_size = 32

if payload_size < 16 {
    db(1);
} else if payload_size < 64 {
    db(2);
} else {
    db(3);
}
```

输出 `02`。

## 选择要生成的指令

`if` 块里可以直接写处理器指令：

```asm
// 选择 64 位 x86 指令编码。
x86.use64();

// 编译期常量决定采用哪组返回值指令。
const return_zero = true

entry:
    if return_zero {
        // 清零 eax，令例程返回零。
        xor eax, eax
    } else {
        // 只有条件为假时才把返回值设为一。
        mov eax, 1
    }
    ret
```

因为 `return_zero` 为 true，生成的指令是：

```asm
// 编译期条件只保留清零返回值的路径。
xor eax, eax
// 返回调用者。
ret
```

没选中的 `mov` 指令不会进入输出。这是汇编期间选择指令，不是运行时条件分支。

## 目标条件

`if` 条件里可以直接用目标查询：

```asm
// x86-64 目标使用 64 位指令编码模式。
if target.isa == .x86_64 {
    x86.use64();
}

// 根据当前位宽写出对应的文本标记。
if target.bits == 64 {
    db("wide");
} else {
    db("narrow");
}
```

`target.isa` 标识选择的 ISA 系列，`target.bits` 报告当前位宽。`x86.use32()`、`x86.use64()`、`riscv.use32()`、`riscv.use64()` 等模式调用会更新后续目标条件看到的位宽。

目标查询专门用于这种条件判断。直接写在 `if` 条件里即可，不必先复制到另一个绑定。

## 遍历范围

已知迭代次数时，用 `for` 配合 `range(start, end)`：

```asm
// 依次写出从起始值零到结束值四之前的每个索引。
for index in range(0, 4) {
    db(index);
}
```

输出：

```text
00 01 02 03
```

起始值包含，结束值不包含。范围必须递增或为空，递减范围如 `range(4, 0)` 会报错。

循环绑定属于循环体：

```asm
// 每次迭代都在索引上加 0x10，再写出编码后的值。
for index in range(0, 3) {
    const encoded = index + 0x10
    db(encoded);
}
```

输出 `10 11 12`。`index` 和 `encoded` 都是每次循环的局部变量。

## 遍历列表

`for` 循环可以遍历编译期列表的值：

```asm
// 列表按输出顺序保存三个待写出的字节值。
const opcodes: list = list.of(0x90, 0x90, 0xc3)

for opcode in opcodes {
    db(opcode);
}
```

按列表顺序遍历。适用于字节表、导入描述、生成的名字等集合数据。

映射不能直接遍历。用 `map.keys(...)` 或 `map.values(...)` 取得列表后再遍历。集合在第 6 章介绍。

## while

当循环何时结束取决于循环体里的更新时，用 `while`：

```asm
// 每次写出当前值，然后推进到下一个值。
let value = 1

while value <= 4 {
    db(value);
    value = value + 1
}
```

输出：

```text
01 02 03 04
```

每次迭代前判断条件。初始为 false 则不执行循环体。

终止条件应靠近更新逻辑，并且一眼能看明白。编译期循环如果停不下来，汇编就无法完成；XIRASM 最多允许 1,000,000 次迭代，超限会报错。

## break 和 continue

`break` 结束当前最内层的编译期循环。`continue` 跳过本次迭代剩下的语句，直接开始下一次迭代。两者可以用在 `for`、`while` 中，也可以用在收尾处理里的 `while` 中；循环体里嵌套 `if` 时同样可用。

例如：

```asm
for value in range(0, 8) {
    if (value == 6) {
        break;
    }
    if (value & 1) != 0 {
        continue;
    }
    db(value);
}
```

输出 `00 02 04`。循环控制语句不能跨函数调用边界，在循环外使用会报错。

## 选择控制流形式

| 需求                   | 使用                            |
| ---------------------- | ------------------------------- |
| 两个源码块二选一       | `if` / `else`               |
| 多个源码块选一个       | `if` / `else if` / `else` |
| 按指令集或位宽选源码   | 目标条件                        |
| 重复固定次数           | `for` + `range`             |
| 遍历编译期集合         | `for` + 列表                  |
| 重复到条件满足为止     | `while`                       |
| 选择生成的指令         | `if` 块中直接写指令           |
| 提前结束最内层循环     | `break`                       |
| 跳过当前迭代的剩余部分 | `continue`                    |

迭代次数已知时优先用 `for`，比 `while` 更容易看出输出规律，也不需要手动维护循环变量。

下一章把重复的计算和输出操作打包成函数，带参数、返回值和局部作用域。

[返回语言指南](../language.md)

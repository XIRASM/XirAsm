# 第 3 章：表达式

## 表达式在汇编期间求值

表达式在 XIRASM 汇编源码时计算出值。声明、赋值、函数参数、`return` 语句、条件、断言、指令操作数和数据调用里都可以写表达式。

```asm id=table-size target=x86-64 bytes=18000000
const entry_count = 3
const bytes_per_entry = 8
const table_size = entry_count * bytes_per_entry

dd(table_size)          // 24 = 0x18
```

## 算术运算

| 运算符 | 含义 |
| --- | --- |
| `+` | 加法 |
| `-` | 减法 |
| `*` | 乘法 |
| `/` | 整数除法 |
| `%` | 取余 |

```asm id=arithmetic target=x86-64 bytes=0e000000140000000300000002000000
const total = 2 + 3 * 4       // 14
const grouped = (2 + 3) * 4   // 20
const quotient = 17 / 5       // 3
const remainder = 17 % 5      // 2

dd(total, grouped, quotient, remainder)
```

加、减、乘都做检查：结果超出整数范围就报错，不会静默改变布局。

```asm id=arithmetic-overflow target=x86-64
dq(0xffffffffffffffff + 1)
```

```text
bad.xir:1:1: error: an expression in this statement is not valid (InvalidExpression)
```

```asm id=division-by-zero target=x86-64
dd(1 / 0)
```

```text
bad.xir:1:1: error: the expression divides by zero (DivisionByZero)
```

一元 `+` 不改变值；一元 `-` 产生 64 位补码值，负数就是靠它写出去的：

```asm id=unary-minus target=x86-64 bytes=ffffffffffffffff
const all_bits = -1

dq(all_bits)            // 八个 `ff` 字节
```

## 位运算与移位

位运算用于描述权限、掩码、指令字段和文件格式标志：

| 运算符 | 含义 |
| --- | --- |
| `&` | 按位与 |
| `\|` | 按位或 |
| `^` | 按位异或 |
| `~` | 按位取反 |
| `<<` | 左移 |
| `>>` | 右移 |

```asm id=bitwise-mask target=x86-64 bytes=05
const readable = 1 << 0
const writeable = 1 << 1
const executable = 1 << 2

const permissions = readable | executable

assert((permissions & executable) != 0)
assert((permissions & writeable) == 0)
db(permissions)         // 1 | 4 = 5
```

移位量达到或超过值的宽度时结果是零，不是错误：

```asm id=shift-past-width target=x86-64 bytes=00000000000000800000000000000000
dq(1 << 63)             // 00 00 00 00 00 00 00 80
dq(1 << 64)             // 已经没有位可以移进来
```

## 比较与相等

| 运算符 | 含义 |
| --- | --- |
| `==` | 等于 |
| `!=` | 不等于 |
| `<` | 小于 |
| `<=` | 小于等于 |
| `>` | 大于 |
| `>=` | 大于等于 |

大小比较用于整数；相等判断还能用于兼容的非整数类型：

```asm id=comparison target=x86-64
const payload_size = 96
const maximum_size = 128

assert(payload_size > 0 && payload_size <= maximum_size)

const format_name = "raw"
const signature = b"OK"

assert(format_name == "raw")
assert(signature == b"OK")
```

不属于同一类的值会被拒绝，而不是被转换：

```asm id=mixed-category-operands target=x86-64
const total = "x" + 1
```

```text
bad.xir:1:1: error: an expression in this statement is not valid (InvalidExpression)
```

## 布尔逻辑与短路

| 运算符 | 含义 |
| --- | --- |
| `!` | 逻辑非 |
| `&&` | 逻辑与 |
| `\|\|` | 逻辑或 |

`&&` 和 `||` 在结果已经确定时立即停止。`left && right` 在 `left` 为假时不计算 `right`；`left || right` 在 `left` 为真时不计算 `right`：

```asm id=short-circuit target=x86-64
const enabled = true
const safe = enabled || (1 / 0 == 0)   // 右边的除法根本不会执行

assert(safe)
```

只有当前面的条件成立、后面的操作数才合法时，短路正是让这种写法成立的原因。

## 表达式中的函数调用

有返回值的调用可以出现在任何接受其结果类型的位置：

```asm id=calls-in-expressions target=x86-64 bytes=0630000000
const name_length = lengthof("XIRASM")        // 6
const aligned_size = ((37 + 15) / 16) * 16    // 48 = 0x30

db(name_length)
dd(aligned_size)
```

调用可以嵌套，内层先计算完再交给外层：

```asm id=nested-calls target=x86-64
const normalized = upper(trim("  kernel  "))

assert(normalized == "KERNEL")
```

只写出内容或执行汇编动作的过程按语句调用，不产生值。两类函数都在第 5 章介绍。

## 字段访问

`.` 选择一个命名字段。`target.bits` 和 `target.isa` 读取当前生效的指令集，第 4 章和第 8 章的条件里会用到；结构体字段在第 9 章介绍。

```asm id=target-bits target=x86-64 bytes=4020
const before = target.bits   // 64：此刻读到的值

x86.use32()

db(before)                   // 40：绑定保留了读到的那个值
db(target.bits)              // 20：再读一次看到的是当前目标
```

## 运算符优先级

同一行的运算符优先级相同；越靠上的行绑定越紧，同优先级从左到右结合。

| 优先级 | 运算符 |
| --- | --- |
| 最高 | 函数调用、括号表达式、字段访问 |
| 一元 | `+`、`-`、`~`、`!` |
| 乘法 | `*`、`/`、`%` |
| 移位 | `<<`、`>>` |
| 加法 | `+`、`-` |
| 按位与 | `&` |
| 按位异或 | `^` |
| 按位或 | `\|` |
| 大小比较 | `<`、`<=`、`>`、`>=` |
| 相等判断 | `==`、`!=` |
| 逻辑与 | `&&` |
| 最低 | `\|\|` |

这不是 C 的那张表。移位比加减法绑定更紧：

```asm id=shift-precedence target=x86-64 bytes=1100000018000000
const shift_first = 1 + 2 << 3        // 1 + (2 << 3) = 17
const grouped_shift = (1 + 2) << 3    // 24 = 0x18

dd(shift_first, grouped_shift)
```

表达式同时混用移位、算术、掩码或比较时，加上括号。括号把计算顺序直接写出来，读者就不必回头查上面这张表。

## 表达式错误

计算不出明确的编译期值时，XIRASM 停止汇编而不是给出零——一个静默的零会破坏指令操作数或二进制布局。上面已经出现除零、溢出和类型不匹配；名字未定义同样失败：

```asm id=undefined-name target=x86-64
dd(missing + 1)
```

```text
bad.xir:1:1: error: the name is not defined where it is used (UndefinedSymbol)
```

[返回语言指南](../language.md)

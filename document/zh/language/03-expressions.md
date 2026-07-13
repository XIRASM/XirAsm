# 第3章：表达式

## 表达式产生编译时值

表达式在 XIRASM 汇编时计算值。表达式可以用在声明、赋值、函数参数、return 语句、条件、断言、指令操作数和数据调用中。

```asm
// 根据表项数量和单项大小，在汇编期间计算整张表的字节数。
const entry_count = 3
const bytes_per_entry = 8
const table_size = entry_count * bytes_per_entry

dd(table_size);
```

输出 32 位值 `24`。乘法在汇编时执行，输出只有计算结果。

## 算术运算

整数表达式支持：

| 运算符 | 含义     |
| ------ | -------- |
| `+`  | 加法     |
| `-`  | 减法     |
| `*`  | 乘法     |
| `/`  | 整数除法 |
| `%`  | 取余     |

```asm
// 同时演示默认优先级、括号分组、整数除法和取余。
const total = 2 + 3 * 4
const grouped = (2 + 3) * 4
const quotient = 17 / 5
const remainder = 17 % 5

dd(total, grouped, quotient, remainder);
```

输出值分别是 `14`、`20`、`3`、`2`。

加、减、乘会检查溢出。结果超出支持的整数范围时报错，不会静默截断。除数为零会报错。

一元 `+` 保持值不变。一元 `-` 产生 64 位补码值：

```asm
// -1 的 64 位二进制补码中，每一位都为 1。
const all_bits = -1
dq(all_bits);
```

输出八个 `ff` 字节。

## 位运算和移位

位运算用于权限、掩码、指令字段和文件格式标志：



| 运算符     | 含义     |
| ---------- | -------- |
| `&`      | 按位与   |
| `\|`        | 按位或   |
| `^`      | 按位异或 |
| `~`      | 按位取反 |
| `<<`     | 左移     |
| `>>`     | 右移     |

```asm
// 每一位分别表示一种权限。
const readable = 1 << 0
const writeable = 1 << 1
const executable = 1 << 2

// 组合读取与执行权限，再分别检查两个权限位。
const permissions = readable | executable
const can_execute = (permissions & executable) != 0
const can_write = (permissions & writeable) != 0

assert(can_execute);
assert(!can_write);
db(permissions);
```

输出字节是 `05`。

掩码测试用括号包起来，这样意图更清楚，也不依赖位运算和比较运算的优先级。

## 比较和相等判断

表达式可以比较值：

| 运算符 | 含义     |
| ------ | -------- |
| `==` | 等于     |
| `!=` | 不等于   |
| `<`  | 小于     |
| `<=` | 小于等于 |
| `>`  | 大于     |
| `>=` | 大于等于 |

大小比较作用于整数：

```asm
// 数据必须大于零，并且不能超过允许的最大大小。
const payload_size = 96
const maximum_size = 128
const fits = payload_size > 0 && payload_size <= maximum_size

assert(fits);
```

相等和不相等也可以用于兼容的非整数类型：

```asm
// 分别核对字符串名称和精确的字节签名。
const format_name = "raw"
const signature = b"OK"

assert(format_name == "raw");
assert(signature == b"OK");
```

不相关的值类别之间比较会报错，不会隐式转换。

## 布尔逻辑和短路求值

布尔表达式：

| 运算符           | 含义   |
| ---------------- | ------ |
| `!`            | 逻辑非 |
| `&&`           | 逻辑与 |
| `\|\|`          |   逻辑或 |

`&&` 和 `||` 会短路：

- `left && right` 当 `left` 为 false 时不计算 `right`。
- `left || right` 当 `left` 为 true 时不计算 `right`。

```asm
// 左侧已经为真，因此右侧包含除零的表达式不会被计算。
const enabled = true
const safe = enabled || (1 / 0 == 0)

assert(safe);
```

除法不会被执行，因为 `enabled` 是 true。

短路求值在后面的表达式需要前面的条件成立时很有用。

## 表达式中的函数调用

返回值函数或内置函数可以出现在任何能接受其结果类型的地方：

```asm
// 计算名称长度，并把 37 向上调整到 16 的整数倍。
const name_length = lengthof("XIRASM")
const aligned_size = ((37 + 15) / 16) * 16

db(name_length);
dd(aligned_size);
```

调用可以嵌套：

```asm
// 先去掉两端空格，再把结果转换为大写。
const normalized = upper(trim("  kernel  "))
assert(normalized == "KERNEL");
```

只做输出或汇编动作的过程函数以语句方式调用，不产生表达式值。返回值函数在第5章介绍。

## 字段访问

有命名字段的值用 `.` 选择一个字段：

```text
header.magic
header.entry_offset
```

结构体和联合体值在第9章介绍。`target.bits` 和 `target.isa` 这类目标查询属于目标条件，不能复制到绑定中。

## 运算符优先级

同一行的运算符优先级相同。越靠上的行绑定越紧密：

| 优先级   | 运算符                         |
| -------- | ------------------------------ |
| 最高     | 函数调用、括号表达式、字段访问 |
| 一元     | `+`、`-`、`~`、`!`     |
| 乘法     | `*`、`/`、`%`            |
| 移位     | `<<`、`>>`                 |
| 加法     | `+`、`-`                   |
| 按位与   | `&`                          |
| 按位异或 | `^`                          |
| 按位或   | `\|`                     |
| 大小比较 | `<`、`<=`、`>`、`>=`   |
| 相等判断 | `==`、`!=`                 |
| 逻辑与   | `&&`                         |
| 最低     | `\|\|`               |

同优先级从左到右计算。

XIRASM 的优先级表可能和其他语言不一样。特别注意移位比加减法绑定更紧密：

```asm
// 第一项先执行移位；第二项用括号明确要求先做加法。
const shift_first = 1 + 2 << 3
const grouped_shift = (1 + 2) << 3

dd(shift_first, grouped_shift);
```

第一个值是 `17`，因为计算方式是 `1 + (2 << 3)`。第二个值是 `24`。

在混合移位、算术、掩码或比较的表达式中用括号。括号能说明意图，也让后续修改更安全。

## 表达式错误

表达式无法产生明确的编译时值时，XIRASM 会报错。常见原因：

- 名字未定义
- 操作数值类别不对
- 除数为零
- 整数溢出或下溢
- 字段不存在
- 函数参数无效

这些错误会终止汇编。不会用零代替或忽略，否则可能静默破坏指令操作数或二进制布局。

下一章讲 `if`、`while` 和 `for` 中的表达式如何选择和重复源码。

[返回语言指南](../language.md)

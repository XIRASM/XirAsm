# 第 10 章：文本、转换与标号名称

## 语法摘要

| 函数 | 结果 | 说明 |
| --- | --- | --- |
| `lengthof(value)` | `u64` | 返回字节长度，或整数的十进制位数。 |
| `len(value)` | `u64` | 返回字节数、列表项数或映射条目数。 |
| `to_string(value)` | `string` | 把整数、布尔值、字符串或字节序列转换为文本。 |
| `trim(text)` | `string` | 删除文本两端的 ASCII 空格、制表符、回车符和换行符。 |
| `lower(text)` | `string` | 把 ASCII 字母转换为小写。 |
| `upper(text)` | `string` | 把 ASCII 字母转换为大写。 |
| `starts_with(text, prefix)` | `bool` | 检查字符串是否以指定前缀开头。 |
| `ends_with(text, suffix)` | `bool` | 检查字符串是否以指定后缀结尾。 |
| `contains(value, needle)` | `bool` | 在字符串或字节序列中查找内容。 |
| `replace(text, needle, replacement)` | `string` | 替换字符串中所有互不重叠的匹配项。 |
| `split(text, separator)` | `list` | 按分隔符把字符串拆分为字符串列表。 |
| `join(parts, separator)` | `string` | 使用分隔符连接字符串列表。 |
| `sym.join(parts...)` | `string` | 转换并直接拼接多个值，不插入分隔符。 |
| `sym.unique(prefix)` | `string` | 返回本次汇编中不会重复的生成名称。 |

本章函数都是普通的编译期表达式。它们会创建新值，不会修改传入的值。

## 长度查询

`lengthof` 和 `len` 回答的问题不同：

| 输入 | `lengthof` | `len` |
| --- | --- | --- |
| `string` | 字节长度 | 字节长度 |
| `bytes` | 字节长度 | 字节长度 |
| 无符号整数 | 十进制位数 | 不接受 |
| `list` | 不接受 | 列表项数 |
| `map` | 不接受 | 映射条目数 |

字符串长度按字节计算，而不是按书写字符的数量计算。对于整数，`lengthof(0)` 的结果是 `1`，因为它的十进制文本是 `"0"`。

```asm
// 查询整数与字符串的长度，并把 4096 的十进制位数写成文本。
assert(lengthof(4096) == 4)
assert(lengthof("XIRASM") == 6)
assert(len(split("code::data::", "::")) == 3)

db(to_string(lengthof(4096)))
```

输出是 ASCII 字节 `0x34`，表示文本 `"4"`。

## 转换为文本

`to_string(value)` 使用以下转换规则：

| 输入 | 文本形式 |
| --- | --- |
| 整数 | 无符号十进制 |
| 布尔值 | `"true"` 或 `"false"` |
| 字符串 | 内容不变的副本 |
| 字节序列 | 小写十六进制，每个字节使用两位数字 |

```asm
// 检查整数、布尔值、字符串和字节序列的文本转换结果。
assert(to_string(42) == "42")
assert(to_string(true) == "true")
assert(to_string("ready") == "ready")
assert(to_string(b"AZ") == "415a")
```

结构体、列表和映射不会自动转换。需要文本时，应分别转换其中的字段或元素。

## 文本变换与查找

`trim`、`lower` 和 `upper` 处理 ASCII 文本。`trim` 只把空格、水平制表符、回车符和换行符视为两端空白。大小写转换不会改变非 ASCII 字节。

`starts_with` 和 `ends_with` 接受字符串。`contains` 可以接受两个字符串，也可以接受两个字节序列；两个参数必须是同一种值。

```asm
// 清理并统一库名称的大小写，再检查其中的各个文本片段。
const name: string = lower(trim("  Kernel32.DLL  "))

assert(name == "kernel32.dll")
assert(starts_with(name, "kernel"))
assert(ends_with(name, ".dll"))
assert(contains(name, "32"))

db(name)
```

## 替换、拆分与连接

`replace` 会替换 `needle` 的每个互不重叠的匹配项。`needle` 不能为空。

`split` 会在非空分隔符的每个匹配位置拆分字符串。空字段会被保留，包括相邻分隔符或末尾分隔符产生的字段。因此，空输入字符串会得到只包含一个空字符串的列表。

`join` 要求列表中的每一项都是字符串。空列表会得到空字符串。

```asm
// 拆分包含末尾分隔符的文本，再连接字段并执行全部匹配项替换。
const fields: list = split("red::green::", "::")

assert(len(fields) == 3)
assert(join(fields, "|") == "red|green|")
assert(replace("one fish, one fish", "one", "two") == "two fish, two fish")

db(join(fields, "|"))
```

## 构造标号名称

`sym.join(parts...)` 会按照与 `to_string` 相同的规则转换整数、布尔值、字符串和字节序列参数，然后直接拼接结果，不自动插入分隔符：

```asm
// 拼接固定文本、整数和布尔值，得到可直接定义的标号名称。
const slot: string = sym.join("_slot_", 12, "_", true)

assert(slot == "_slot_12_true")
label.define(slot)
emit.u8(0xaa)
```

需要分隔符时，应把所需标点明确写在参数中。

`sym.unique(prefix)` 每调用一次，都会返回本次汇编中不同的生成字符串。生成顺序是确定的，但后缀格式不是源码可以依赖的约定。应保存返回的字符串并始终使用该值，不要自行重新构造名称。

```asm
// 使用相同前缀生成两个不同名称，并分别定义标号和写出数据。
const first: string = sym.unique("_temporary")
const second: string = sym.unique("_temporary")

assert(first != second)

label.define(first)
emit.u8(0x11)

label.define(second)
emit.u8(0x22)
```

`sym.unique` 只保证名称不重复，不保证名称符合标号语法。把结果传给 `label.define` 时，应选择能使完整结果成为有效标号名称的前缀。

## 错误条件

以下输入会被拒绝：

- 向 `lengthof` 传入字符串、字节序列和无符号整数以外的值；
- 向 `len` 传入字符串、字节序列、列表和映射以外的值；
- 向 `to_string` 或 `sym.join` 传入聚合值；
- 向 `contains` 同时传入字符串和字节序列；
- 向 `replace` 传入空的 `needle`，或向 `split` 传入空分隔符；
- 向 `join` 传入包含非字符串项的列表；
- 把生成名称用于 `label.define` 时，该名称不符合标号语法。

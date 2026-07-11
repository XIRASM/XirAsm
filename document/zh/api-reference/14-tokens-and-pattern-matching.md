# 第 14 章：词法单元与模式匹配

## 语法摘要

| 功能 | 调用形式 | 结果 |
| --- | --- | --- |
| 对源代码形式的文本进行词法分析 | `tokens.of(source)` | 由词法单元字符串组成的 `list` |
| 呈现词法单元字符串 | `tokens.join(tokens)` | 规范形式的 `string` |
| 匹配词法单元结构 | `match.tokens(pattern, input)` | 结果 `map` |

`tokens.of` 接受字符串或已有的字符串列表。传入字符串时会进行词法分析；传入列表时会验证每一项并复制该列表。

`tokens.join` 接受所有元素都是字符串的列表。

`match.tokens` 的模式和输入都可以是字符串或字符串列表。模式为列表时，每一项必须是一个完整的模式片段。输入为列表时，其中的词法单元会直接参与匹配，不会再次进行词法分析。

## 词法分析

`tokens.of` 用于处理具有源代码结构的文本。它会分离名称、字面量、标点、括号和运算符，并丢弃不影响结构的空白。

```asm
// 把一条具有地址表达式的文本拆成词法单元列表。
const input: list = tokens.of("load rax, [rbx + 4]")

// 空白不会成为词法单元，标点和括号会被单独保留。
assert(len(input) == 8);
assert(list.get(input, 0) == "load");
assert(list.get(input, 2) == ",");
assert(list.get(input, 3) == "[");
assert(tokens.join(input) == "load rax, [rbx+4]");

// 写出词法单元数量和规范形式文本。
emit.u8(len(input));
emit.bytes(tokens.join(input));
```

示例会写出：

```text
08 6c 6f 61 64 20 72 61 78 2c 20 5b 72 62 78 2b 34 5d
```

带引号的文本会保留为一个词法单元，其中包括引号字符。没有结束引号的词法单元无效。

以下双字符运算符会分别形成一个词法单元：

```text
==  !=  <=  >=  &&  ||  <<  >>  ->  =>  ::
```

以下单字符也会分别形成一个词法单元：

```text
, ( ) [ ] { } < > : = + - * / % & | ^ ~ . ! ? ;
```

其他相邻的非空白字符会留在同一个词法单元中，直到遇到引号或能够识别的运算符。

## 规范形式呈现

`tokens.join` 会生成规范形式的源代码文本。它会在普通相邻词法单元之间插入空格，并删除括号、标点和紧密运算符周围不需要的空格。

规范形式呈现不会逐字节还原原始字符串：

```asm
// 原始文本中的多余空格不会保留在规范形式结果中。
const input: list = tokens.of("left  && middle ||  right")
assert(tokens.join(input) == "left&&middle||right");
```

如果空白的精确形式本身有意义，应保留原始字符串。

## 模式片段

词法单元模式由若干使用空白分隔的片段组成。每个片段必须是精确字面量或命名捕获。

| 片段 | 含义 |
| --- | --- |
| `=token` | 精确匹配一个词法单元 |
| `name:token` | 捕获任意一个词法单元，并返回字符串 |
| `name:name` | 捕获一个名称形式的词法单元，并返回字符串 |
| `name:int` | 捕获一个整数词法单元，并返回整数 |
| `name:quoted` | 捕获一个带引号的词法单元，并返回去除引号后的字符串 |
| `name:tokens` | 捕获一段保持括号平衡的词法单元，并返回列表 |

开头的 `=` 是字面量标记。例如：

```text
=load  匹配 load 词法单元
=,     匹配逗号词法单元
===    匹配 == 词法单元
```

捕获名称使用标识符语法，并且在同一个模式中不能重复。

## 匹配结果

`match.tokens` 返回包含两个条目的映射：

| 键 | 值 |
| --- | --- |
| `"ok"` | 表示整个输入是否匹配的布尔值 |
| `"captures"` | 从捕获名称到捕获值的映射 |

只有完整模式和完整输入都被使用后，匹配才算成功。

```asm
// 匹配 load 形式，并分别捕获目标名称和完整地址表达式。
const result: map = match.tokens(
    "=load destination:name =, address:tokens",
    "load rax, [rbx+(rcx*4)]"
)

assert(map.get(result, "ok"));

// 匹配成功后，从 captures 映射中读取命名捕获。
const captures: map = map.get(result, "captures")
const destination: string = map.get(captures, "destination")
const address: list = map.get(captures, "address")

assert(destination == "rax");
assert(tokens.join(address) == "[rbx+(rcx*4)]");

// 写出捕获到的目标名称和规范形式地址文本。
emit.bytes(destination);
emit.bytes(tokens.join(address));
```

示例会写出：

```text
72 61 78 5b 72 62 78 2b 28 72 63 78 2a 34 29 5d
```

读取命名捕获之前必须先检查 `"ok"`。匹配失败时，结果中的 `"ok"` 为 `false`，捕获映射为空。

## 捕获值

`token` 和 `name` 捕获都返回字符串。`token` 接受任意一个词法单元；`name` 要求标识符以 ASCII 字母或下划线开头，后续字符只能是 ASCII 字母、数字或下划线。

`int` 会使用通常的数值前缀，把一个词法单元解析为无符号整数：

```asm
// 捕获目标名称和带十六进制前缀的整数。
const result: map = match.tokens(
    "=set target:name =, value:int",
    "set count, 0x2a"
)
const captures: map = map.get(result, "captures")

// 整数捕获会返回数值，而不是原始词法单元字符串。
assert(map.get(result, "ok"));
assert(map.get(captures, "target") == "count");
assert(map.get(captures, "value") == 42);
```

`quoted` 接受单引号或双引号，去除两端引号，并处理 `\n`、`\r`、`\t`、转义引号和转义反斜杠。其他转义形式会保留反斜杠后的字符。

`tokens` 返回由词法单元字符串组成的列表，可以捕获零个或多个词法单元。捕获范围内的圆括号、方括号和花括号必须保持平衡。

## 从最短范围开始匹配与回溯

`tokens` 捕获最初只使用最短的平衡范围。如果后续模式片段无法匹配，它会扩大捕获范围并重新尝试：

```asm
// prefix 先尝试空范围；整数捕获失败后，它会扩大到包含 name。
const result: map = match.tokens(
    "prefix:tokens value:int",
    "name 42"
)
const captures: map = map.get(result, "captures")

// 回溯后，prefix 捕获名称词法单元，value 捕获整数 42。
assert(map.get(result, "ok"));
assert(tokens.join(map.get(captures, "prefix")) == "name");
assert(map.get(captures, "value") == 42);
```

比较运算符 `<` 和 `>` 只是普通词法单元，不是分组边界。只有 `()`、`[]` 和 `{}` 参与平衡检查。

模式不提供表示多个选择的运算符。如果输入可能具有多种有效形式，应在普通 `if`/`else` 流程控制中依次尝试完整模式。

## 普通匹配失败与无效模式

以下情况属于普通匹配失败，返回 `"ok" == false`：

- 精确字面量不同；
- 带类型的捕获遇到不符合要求的词法单元；
- `tokens` 捕获无法形成平衡范围；
- 模式先于输入结束；
- 输入先于模式结束。

以下情况会把调用作为无效表达式拒绝：

- 模式片段既不是字面量，也不是捕获；
- 字面量标记后没有词法单元；
- 捕获名称无效或重复；
- 捕获种类未知；
- 输入中的带引号词法单元没有结束引号；
- 参数不是字符串或字符串列表；
- `tokens.join` 收到包含非字符串值的列表；
- 实参数量不正确。

## 限制

词法单元匹配使用固定限制，使编译期解析的工作量保持可控：

| 限制项 | 最大值 |
| --- | --- |
| 模式片段 | 64 |
| 输入词法单元 | 256 |
| 匹配尝试次数 | 4096 |
| 嵌套括号深度 | 64 |

超过限制时，匹配调用会被拒绝，而不是作为普通匹配失败返回。

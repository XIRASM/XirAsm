# 第 7 章：词法单元与模式匹配

本章讨论在编译期检查“类似源码的文本”。字符串 API 适合处理普通文本；当你关心名称、标点、运算符、字面量和括号分组这些源代码结构时，应先把文本拆成词法单元，再进行模式匹配。

不要为了汇编普通 ISA 指令而手动分词。自然 ISA 文本已经是 XIRASM 源语言的一部分，可以直接写在源码里。词法单元匹配主要用于小型用户 DSL、生成的源码片段、小型命令记录和可复用的编译期辅助函数。

## 词法单元表示源代码结构

字符串辅助接口把文本视为字符序列。对于名称、路径、分隔字段和简单替换，这种模型已经够用。类似源码的文本通常需要另一种模型。

请看下面这段文本：

```text
load rax, [rbx+(rcx*4)]
```

其中的逗号、方括号、圆括号、名称、运算符和整数字面量都具有结构意义。如果只按空格拆分，不仅会丢失这些结构，还会对仅有空格差异的等价写法产生不一致的处理结果。

XIRASM 可以把类似源代码的文本转换为词法单元列表：

```asm
// 把表达式拆成词法单元，并验证空白不会进入结果列表。
const source: string = "count + 0x2a"
const source_tokens: list = tokens.of(source)

assert(len(source_tokens) == 3);
assert(list.get(source_tokens, 0) == "count");
assert(list.get(source_tokens, 1) == "+");
assert(list.get(source_tokens, 2) == "0x2a");

// 按规范形式重新连接词法单元，并把结果写入输出内容。
emit.bytes(tokens.join(source_tokens));
```

这段代码会写出规范化后的文本：

```text
count+0x2a
```

`tokens.of` 会丢弃无意义的空白，同时保留词法单元的顺序。`tokens.join` 使用规范间距重新呈现这个序列，并不会逐字节还原原始字符串。

当字符排列本身很重要时，应使用字符串。当名称、标点、运算符、字面量和平衡分组的结构很重要时，应使用词法单元。

## 匹配词法单元结构

`match.tokens(pattern, input)` 会把类似源代码的输入与词法单元模式比较：

```asm
// 匹配 load 形式，并分别捕获目标名称和完整的源操作数。
const line: string = "load rax, [rbx+(rcx*4)]"
const result: map = match.tokens(
    "=load destination:name =, source:tokens",
    line
)

// 完整匹配成功后，再读取命名捕获得到的值。
assert(map.get(result, "ok"));

const captures: map = map.get(result, "captures")
assert(map.get(captures, "destination") == "rax");
assert(tokens.join(map.get(captures, "source")) == "[rbx+(rcx*4)]");
```

结果是一个包含两个字段的映射：

- `"ok"` 是布尔值，表示完整输入是否匹配成功；
- `"captures"` 是一个映射，保存各个命名捕获所提取的值。

只有检查 `"ok"` 后，才能读取捕获结果。

## 字面量模式词法单元

以 `=` 开头的模式片段会匹配一个完全相同的词法单元：

```asm
// `=&&` 要求输入中必须出现精确的逻辑与词法单元。
const result: map = match.tokens(
    "left:name =&& right:name",
    "ready && enabled"
)

assert(map.get(result, "ok"));
```

`=&&` 要求输入中出现逻辑与词法单元。同一规则也适用于名称和标点：

```text
=load      精确匹配名称词法单元
=,         精确匹配逗号词法单元
=[         精确匹配左方括号词法单元
===        精确匹配相等运算符词法单元
```

第一个 `=` 是模式标记；`===` 表示“匹配 `==` 词法单元”，而不是匹配一个由三个字符组成的相等运算符。

模式片段之间使用空白分隔。模式中的空白只用于提高可读性；实际匹配依据的是词法单元，而不是输入中原有的间距。

## 捕获种类

捕获的形式为 `name:kind`。捕获名称会成为结果中 `"captures"` 映射的键。

| 种类       | 匹配内容                   | 捕获的值                       |
| ---------- | -------------------------- | ------------------------------ |
| `token`  | 任意种类的一个词法单元     | `string`                     |
| `name`   | 一个类似标识符的名称       | `string`                     |
| `int`    | 一个整数字面量             | 整数值                         |
| `quoted` | 一个带引号的词法单元       | 去除引号后的 `string`        |
| `tokens` | 一段保持分组平衡的词法单元 | 由词法单元字符串组成的 `list` |

同一个模式中的捕获名称必须唯一。

单词法单元捕获可以精确描述小型命令语法：

```asm
// 从 set 形式中提取目标名称，并把整数字面量转换为整数值。
const assignment: map = match.tokens(
    "=set target:name =, value:int",
    "set count, 0x2a"
)
const assignment_captures: map = map.get(assignment, "captures")

// 保留中间运算符的原始词法单元文本。
const operation: map = match.tokens(
    "left:name operator:token right:name",
    "count + step"
)
const operation_captures: map = map.get(operation, "captures")

// 去除外层引号后捕获消息文本。
const message: map = match.tokens("=db text:quoted", "db 'READY'")
const message_captures: map = map.get(message, "captures")

// 验证每种捕获都生成了预期类型和值。
assert(map.get(assignment, "ok"));
assert(map.get(assignment_captures, "target") == "count");
assert(map.get(assignment_captures, "value") == 42);
assert(map.get(operation_captures, "operator") == "+");
assert(map.get(message_captures, "text") == "READY");
```

`int` 捕获会把字面量转换为整数值。`quoted` 捕获会移除外层引号，并解码受支持的转义序列。`token` 捕获只返回词法单元文本，不会要求它属于更具体的类型。

## 平衡的词法单元范围

`tokens` 捕获可以使用多个词法单元，同时保持圆括号、方括号和花括号的平衡：

```asm
// 把方括号内的嵌套地址表达式作为一个平衡范围捕获。
const result: map = match.tokens(
    "=load destination:name =, address:tokens",
    "load rax, [rbx+(rcx*4)]"
)
const captures: map = map.get(result, "captures")
const address: list = map.get(captures, "address")

assert(map.get(result, "ok"));
assert(tokens.join(address) == "[rbx+(rcx*4)]");
```

捕获的值是词法单元列表，而不是字符串。继续保留词法单元形式，其他匹配器就能直接检查这段内容，无须再次对文本词法分析。

平衡捕获适用于 `()`、`[]` 和 `{}`。`<`、`>` 等比较运算符仍然只是普通的运算符词法单元：

```asm
// 比较运算符不会被当作分组边界，整个表达式仍可被捕获。
const result: map = match.tokens("expression:tokens", "left < right")
const captures: map = map.get(result, "captures")

assert(map.get(result, "ok"));
assert(tokens.join(map.get(captures, "expression")) == "left<right");
```

## 最小匹配与回溯

当 `tokens` 捕获后面还有其他模式片段时，它最初会尽可能少地使用词法单元。如果剩余模式无法匹配，捕获范围就会扩展，然后重新尝试匹配：

```asm
// prefix 会先尝试空范围，再扩展到足以让整数捕获成功的位置。
const result: map = match.tokens(
    "prefix:tokens value:int",
    "name 42"
)
const captures: map = map.get(result, "captures")

assert(map.get(result, "ok"));
assert(tokens.join(map.get(captures, "prefix")) == "name");
assert(map.get(captures, "value") == 42);
```

第一次尝试会给 `prefix` 分配一个空范围，但 `value:int` 无法匹配 `name`。匹配器随后扩展 `prefix`，使其包含 `name`，这样整数捕获就能匹配 `42`。

带类型的捕获遇到错误种类的词法单元时，只是一次普通的匹配失败。一个有效模式不会产生汇编错误：

```asm
// name 不是整数字面量，模式有效，但本次输入不匹配。
const result: map = match.tokens("value:int", "name")
assert(!map.get(result, "ok"));
```

这种行为便于依次尝试多个有效模式。

## 空词法单元范围

`tokens` 捕获可以为空：

```asm
// call 后没有参数， arguments 捕获得到一个空列表。
const result: map = match.tokens("=call arguments:tokens", "call")
const captures: map = map.get(result, "captures")

assert(map.get(result, "ok"));
assert(len(map.get(captures, "arguments")) == 0);
```

如果词法单元范围必须非空，可以在匹配成功后检查其长度，也可以在模式中加入另一个必需的捕获。

## 匹配已有词法单元列表

传给 `match.tokens` 的输入也可以是已经生成的词法单元字符串列表：

```asm
// 先一次词法分析，再把同一列表直接交给模式匹配器。
const input: list = tokens.of("load r1, 42")
const result: map = match.tokens(
    "=load destination:name =, value:int",
    input
)
const captures: map = map.get(result, "captures")

assert(map.get(result, "ok"));
assert(map.get(captures, "destination") == "r1");
assert(map.get(captures, "value") == 42);
```

当多个处理步骤需要检查同一段源代码时，可以在辅助接口之间直接传递词法单元列表。只有在确实需要文本值时，才使用 `tokens.join` 转回文本。

## 尝试不同结构

模式本身不包含“或者”运算符。应在编译期控制流中依次尝试每一种完整结构：

```asm
// 先尝试 load 结构；当前输入不匹配时，再尝试 store 结构。
const line: string = "store r1, r2"
const load: map = match.tokens(
    "=load destination:name =, source:name",
    line
)

if map.get(load, "ok") {
    // load 分支只写出目标名称。
    const captures: map = map.get(load, "captures")
    emit.bytes(map.get(captures, "destination"));
} else {
    const store: map = match.tokens(
        "=store destination:name =, source:name",
        line
    )

    // store 分支写出目标名称和源名称。
    assert(map.get(store, "ok"));
    const captures: map = map.get(store, "captures")
    emit.bytes(map.get(captures, "destination"));
    emit.bytes(map.get(captures, "source"));
}
```

这段代码会写出 `r1r2`。每个模式只描述一种有效形式，普通的 `if`/`else` 逻辑负责判断输入采用了哪一种形式。

对于更大的语法，可以把每种结构放进一个返回值小函数中，并让调用位置清楚地显示分派顺序。

## 匹配失败与无效模式

普通的结构或类型不匹配会返回 `"ok" == false` 的结果。比如：

- 精确字面量不同；
- `name` 捕获收到标点；
- `int` 捕获收到名称；
- `tokens` 捕获中的括号不平衡；
- 模式已经结束，但输入仍有剩余。

格式错误的模式则不同。它会作为汇编错误被拒绝，而不是被报告为匹配失败。未知的捕获种类、空字面量或重复的捕获名称都会造成模式错误：

```text
const invalid = match.tokens(
    "value:name value:int",
    "left 42"
)
```

两个捕获都使用了键 `"value"`，这个模式无效。

请记住两者的区别：

- **模式有效，但输入不适用**，表示 `"ok" == false`；
- **模式定义无效**，表示源代码有错误，应当修正模式。

## 字符串还是词法单元

| 需求                         | 使用方式                             |
| ---------------------------- | ------------------------------------ |
| 搜索子字符串                 | `contains`                         |
| 检查文本前缀或后缀           | `starts_with` / `ends_with`      |
| 解析使用简单分隔符分开的文本 | `split`                            |
| 保留名称、标点和分组结构     | `tokens.of`                        |
| 匹配精确的源代码结构         | `match.tokens`                     |
| 提取带类型的字段             | `name`、`int` 或 `quoted` 捕获 |
| 捕获嵌套表达式或操作数       | `tokens` 捕获                      |
| 尝试多种命令形式             | 配合 `if` / `else` 使用多个模式 |

不要仅仅为了汇编普通 ISA 指令，就先把指令行转换为词法单元。自然 ISA 文本本来就是源语言的一部分，可以直接书写。词法单元匹配最适合用于紧凑的用户自定义 DSL、生成的源代码片段、小型命令记录，以及可复用的编译期辅助函数。

至此，本指南的语言基础部分全部结束。下一章将从目标、自然 ISA 文本、标号和引用开始介绍汇编器模型。

[返回语言指南](../language.md)

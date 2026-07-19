# 第 7 章：词法单元与模式匹配

本章讲如何在汇编期间检查一段“像源码一样的文本”。普通字符串 API 适合处理名称、路径和简单替换；如果你关心标点、运算符、字面量、括号分组这些源码结构，就先把文本拆成词法单元，再做模式匹配。

不要为了汇编普通指令而手动分词。x86、RISC-V 和 SPIR-V 指令本来就能直接写在 XIRASM 源码里。词法单元匹配主要用于小型 DSL、生成的源码片段、命令记录和可复用的编译期辅助函数。

## 词法单元保留源码结构

字符串接口把文本看成字符序列。处理名称、路径、分隔字段和简单替换时，这已经够用。要处理像源码一样的文本时，通常需要保留更细的结构。

请看下面这段文本：

```text
load rax, [rbx+(rcx*4)]
```

其中的逗号、方括号、圆括号、名称、运算符和整数字面量都有结构意义。如果只按空格拆分，不仅会丢掉这些结构，还会让只差空格的等价写法得到不同结果。

XIRASM 可以把这类文本转换为词法单元列表：

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

`tokens.of` 会丢弃无意义的空白，同时保留词法单元顺序。`tokens.join` 会用规范间距重新拼回文本，但不会逐字节还原原始字符串。

如果字符排列本身重要，用字符串。如果名称、标点、运算符、字面量和括号分组重要，用词法单元。

## 匹配词法单元结构

`match.tokens(pattern, input)` 会把输入和词法单元模式比较：

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

结果是一个包含两个字段的 map：

- `"ok"` 是布尔值，表示完整输入是否匹配成功；
- `"captures"` 是一个 map，保存各个命名捕获提取出的值。

先确认 `"ok"` 为 true，再读取捕获结果。

## 字面量模式词法单元

模式片段以 `=` 开头时，表示精确匹配一个词法单元：

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

模式片段之间用空白分隔。模式里的空白只用于可读性；真正匹配的是词法单元，不是输入原来的空格数量。

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

单个词法单元捕获适合描述小型命令语法：

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

捕获结果是词法单元列表，不是字符串。继续保留词法单元形式，后续匹配器就能直接检查这段内容，不必再次分词。

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

带类型的捕获遇到不合适的词法单元时，只是匹配失败。只要模式本身有效，就不会产生汇编错误：

```asm
// name 不是整数字面量，模式有效，但本次输入不匹配。
const result: map = match.tokens("value:int", "name")
assert(!map.get(result, "ok"));
```

这让你可以按顺序尝试多个有效模式。

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

模式本身没有“或者”运算符。需要支持多种形式时，用编译期控制流依次尝试：

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

这段代码会写出 `r1r2`。每个模式只描述一种形式，`if`/`else` 负责判断当前输入属于哪一种。

语法更大时，可以把每种形式放进一个小的返回值函数，让调用处清楚显示尝试顺序。

## 匹配失败与无效模式

输入结构或捕获类型不匹配时，结果是 `"ok" == false`。比如：

- 精确字面量不同；
- `name` 捕获收到标点；
- `int` 捕获收到名称；
- `tokens` 捕获中的括号不平衡；
- 模式已经结束，但输入仍有剩余。

模式本身写错时则不同。XIRASM 会把它当成源码错误拒绝，而不是返回“匹配失败”。未知捕获种类、空字面量或重复捕获名称都会造成模式错误：

```text
const invalid = match.tokens(
    "value:name value:int",
    "left 42"
)
```

两个捕获都使用了键 `"value"`，这个模式无效。

请记住两者的区别：

- **模式有效，但输入不匹配**，表示 `"ok" == false`；
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

不要为了汇编普通指令而把指令行转换成词法单元。普通指令直接写；词法单元匹配留给用户自定义 DSL、生成的源码片段、小型命令记录，以及可复用的编译期辅助函数。

至此，本指南的语言基础部分全部结束。下一章介绍目标选择、指令、标号和地址引用。

[返回语言指南](../language.md)

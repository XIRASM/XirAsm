# 第 7 章：词法单元与模式匹配

普通字符串 API 适合处理名称、路径和简单替换；如果你关心标点、运算符、字面量、括号分组这些源码结构，就先把文本拆成词法单元，再做模式匹配。

不要为了汇编普通指令而手动分词。x86、RISC-V 和 SPIR-V 指令本来就能直接写在 XIRASM 源码里。词法单元匹配主要用于小型 DSL、生成的源码片段、命令记录和可复用的编译期辅助函数。

## 词法单元保留源码结构

字符串辅助函数把文本当成一串字符处理，这对名称、路径、分隔字段和简单替换够用。类源码的文本带的结构比这更多：

```text
load rax, [rbx+(rcx*4)]
```

这里的逗号、方括号、圆括号、名字、运算符和字面量各自都有含义。按空格切分就会丢掉这层含义：`[rbx+(rcx*4)]` 被切成三块，中间的运算关系看不出来了。反过来，两个只差空格、意思完全一样的写法，切出来的结果又不一样。`tokens.of` 把这类文本转成词法单元列表：

```asm id=07-of
const source: string = "count + 0x2a"
const source_tokens: list = tokens.of(source)

assert(len(source_tokens) == 3)
assert(list.get(source_tokens, 0) == "count")
assert(list.get(source_tokens, 1) == "+")
assert(list.get(source_tokens, 2) == "0x2a")

emit.bytes(tokens.join(source_tokens))   // 规范化空格，不是原样输出
```

`tokens.of` 只保留词法单元本身，空白一律丢掉。`tokens.join` 再用统一的空格把它们拼回一段文本。所以 `tokens.join(tokens.of(x))` 和 `x` 不一定逐字节相同：上例里 `"count + 0x2a"` 拼回来是 `count+0x2a`。

## 匹配词法单元结构

```asm id=07-tokens
// 拿这一行源码当输入：要求它以 load 开头，逗号后跟一段配平的词法单元。
const line: string = "load rax, [rbx+(rcx*4)]"
const result: map = match.tokens(
    "=load destination:name =, source:tokens",
    line
)

// 整条输入都匹配上了，才有捕获可读。
assert(map.get(result, "ok"))

const captures: map = map.get(result, "captures")
assert(map.get(captures, "destination") == "rax")
// source 是 tokens 捕获，拿到的是词法单元列表，拼回来仍是原文那一段。
assert(tokens.join(map.get(captures, "source")) == "[rbx+(rcx*4)]")
```

结果是带两个字段的映射：`"ok"` 是布尔值，表示整条输入是否匹配；`"captures"` 是各命名捕获取出的值。只有在 `"ok"` 为真之后才去读捕获。

## 字面量模式词法单元

以 `=` 开头的模式片段匹配一个确切的词法单元：

```asm id=07-tokens-2
// `=&&` 要求这里出现的就是逻辑与这个词法单元本身。
const result: map = match.tokens(
    "left:name =&& right:name",
    "ready && enabled"
)

assert(map.get(result, "ok"))
```

| 片段      | 匹配                 |
| --------- | -------------------- |
| `=load` | 名字词法单元`load` |
| `=,`    | 逗号词法单元         |
| `=[`    | 左方括号词法单元     |
| `===`   | `==` 词法单元      |

第一个 `=` 是模式标记，所以 `===` 的意思是"匹配 `==` 这个词法单元"，不是三字符的相等运算符。模式片段之间用空白分隔。匹配比较的是词法单元，输入里用多少空格都不影响结果。

## 捕获种类

捕获写成 `name:kind`，名字会成为 `"captures"` 里的键；同一个模式里捕获名必须唯一。

| 种类       | 匹配                   | 捕获到的值               |
| ---------- | ---------------------- | ------------------------ |
| `token`  | 任意一个词法单元       | `string`               |
| `name`   | 一个类标识符的名字     | `string`               |
| `int`    | 一个整数字面量         | 整数值                   |
| `quoted` | 一个引号词法单元       | 去掉引号的`string`     |
| `tokens` | 一段配平的词法单元范围 | 词法单元字符串的`list` |

```asm id=07-tokens-3
const assignment: map = match.tokens("=set target:name =, value:int", "set count, 0x2a")
const operation: map = match.tokens("left:name operator:token right:name", "count + step")
const message: map = match.tokens("=db text:quoted", "db 'READY'")

assert(map.get(assignment, "ok"))

const assignment_captures: map = map.get(assignment, "captures")
const operation_captures: map = map.get(operation, "captures")
const message_captures: map = map.get(message, "captures")

assert(map.get(assignment_captures, "target") == "count")
assert(map.get(assignment_captures, "value") == 42)        // `int` 变成了数
assert(map.get(operation_captures, "operator") == "+")     // `token` 是文本
assert(map.get(message_captures, "text") == "READY")       // `quoted` 去掉了引号
```

## 配平的词法单元范围(类似括号平衡)

一个 `tokens` 捕获可以连续吃下多个词法单元，条件是里面的圆括号、方括号和花括号必须成对：

```asm id=07-tokens-4
// address 要吃掉一个整体：从 [ 开始，到配平的 ] 结束。
const result: map = match.tokens(
    "=load destination:name =, address:tokens",
    "load rax, [rbx+(rcx*4)]"
)
const captures: map = map.get(result, "captures")
const address: list = map.get(captures, "address")

assert(map.get(result, "ok"))
assert(tokens.join(address) == "[rbx+(rcx*4)]")
```

它捕到的是词法单元列表，不是字符串。所以下一层匹配器可以直接拿它继续匹配，不用再分一次词。

配平只认 `()`、`[]` 和 `{}`。`<` 和 `>` 是普通的运算符词法单元，不参与配平：

```asm id=07-tokens-5
// < 不是配平字符，所以整条输入都能被 expression 吃掉。
const result: map = match.tokens("expression:tokens", "left < right")
const captures: map = map.get(result, "captures")

assert(map.get(result, "ok"))
// 拼回来时空格按规范重建，left<right 之间不再有空格。
assert(tokens.join(map.get(captures, "expression")) == "left<right")
```

## 最小匹配与回溯

`tokens` 捕获后面还跟着模式片段时，它先尽量少吃，只有剩下的模式匹配不上才扩张：

```asm id=07-tokens-6
// prefix 先试空；空的时候 value:int 匹配不上 name，于是 prefix 扩张到 name 再试。
const result: map = match.tokens(
    "prefix:tokens value:int",
    "name 42"
)
const captures: map = map.get(result, "captures")

assert(map.get(result, "ok"))
assert(tokens.join(map.get(captures, "prefix")) == "name")
assert(map.get(captures, "value") == 42)
```

带类型的捕获遇到不对的词法单元只是一次普通失配，不是模式本身出错：

```asm id=07-tokens-7
// int 捕获碰上名字，只是一次没匹配上：ok 为假，不报错。
const result: map = match.tokens("value:int", "name")

assert(!map.get(result, "ok"))
```

正因如此，依次尝试多个合法模式是可行的。

## 空词法单元范围

`tokens` 捕获可以是空的：

```asm id=07-tokens-8
// arguments 一个词法单元都没吃到，也是合法的捕获。
const result: map = match.tokens("=call arguments:tokens", "call")
const captures: map = map.get(result, "captures")

assert(map.get(result, "ok"))
assert(len(map.get(captures, "arguments")) == 0)
```

要求范围非空时，在匹配成功后检查它的长度，或者在模式里再放一个必需捕获。

## 匹配已有词法单元列表

`match.tokens` 的输入也可以已经是词法单元列表：

```asm id=07-of-2
// 先自己分好词，再把列表交给 match.tokens，省掉重复分词。
const input: list = tokens.of("load r1, 42")
const result: map = match.tokens(
    "=load destination:name =, value:int",
    input
)
const captures: map = map.get(result, "captures")

assert(map.get(result, "ok"))
assert(map.get(captures, "destination") == "r1")
assert(map.get(captures, "value") == 42)
```

`match.tokens` 也可以直接匹配一段已经分好词的输入。多步处理同一段源码时，把词法单元列表传给下一个辅助函数，比每次都重新分词省事；只有确实需要文本时才用 `tokens.join` 转回去。

## 尝试不同结构

模式里没有"或"运算符，所以每种完整结构都放在编译期控制流里依次尝试：

```asm id=07-tokens-9
// 两种结构各试一次：load 先试，不中再试 store。
const line: string = "store r1, r2"
const load: map = match.tokens(
    "=load destination:name =, source:name",
    line
)

if map.get(load, "ok") {
    const captures: map = map.get(load, "captures")
    emit.bytes(map.get(captures, "destination"))
} else {
    const store: map = match.tokens(
        "=store destination:name =, source:name",
        line
    )

    assert(map.get(store, "ok"))

    const captures: map = map.get(store, "captures")
    emit.bytes(map.get(captures, "destination"))
    emit.bytes(map.get(captures, "source"))
}
```

结构再多就不好这样堆 `if` 了。每种结构写成一个返回 `map` 的函数，然后按顺序试，成功就停：

```asm id=07-try-load
// 每种结构一个函数，函数名就是它的模式。
fn try_load(line: string) -> map {
    return match.tokens("=load destination:name =, source:name", line)
}

fn try_store(line: string) -> map {
    return match.tokens("=store destination:name =, source:name", line)
}

const line: string = "store r1, r2"

// 从上往下试；先命中的那个返回搜索结果，后面的不再试。
if map.get(try_load(line), "ok") {
    emit.bytes("load")
} else if map.get(try_store(line), "ok") {
    const captures: map = map.get(try_store(line), "captures")
    emit.bytes(map.get(captures, "destination"))   // 这里写出：72 31 72 32
    emit.bytes(map.get(captures, "source"))
} else {
    err("unknown instruction shape", line)
}
```

写成函数有两个好处：模式本身集中在函数体里，调用处一眼就能看出先试哪种、后试哪种；要加新结构，就再加一个函数、在链尾加一个分支。

## 失配与无效模式

普通的形状或类型不符返回 `"ok" == false`：字面量对不上、`name` 捕获碰到标点、`int` 捕获碰到名字、`tokens` 捕获里括号不配平、模式匹配完了输入还有剩余，都是这一类。下面的例子里右方括号没配平，`tokens` 捕获吃不下，于是 `"ok"` 为假：

```asm id=07-tokens-10
// 右方括号没配平，tokens 捕获吃不下 → ok 为假。
const result: map = match.tokens("=load dest:name =, rest:tokens", "load rax, [rbx")

assert(!map.get(result, "ok"))
```

**模式写错了**是另一回事：它作为源码错误被拒绝，而不是报成失配。未知的捕获种类、空字面量、重复的捕获名都会让汇编停下来：

```asm id=07-tokens-11 error=an expression in this statement is not valid (InvalidExpression)
// 两个捕获都叫 value：模式本身写错了，不是输入不匹配。
const invalid: map = match.tokens(
    "value:name value:int",
    "left 42"
)
```

```text
bad.xir:1:1: error: an expression in this statement is not valid (InvalidExpression)
```

上面的例子属于无效模式：两个捕获都叫 `"value"`。

捕获名必须符合标识符写法（字母或下划线开头，后面是字母、数字或下划线）。`v:` 这种空种类、`=` 这种空字面量、未知的种类名，都会按无效模式拒绝。

匹配也有上限：输入最多 256 个词法单元，模式最多 64 个片段，回溯尝试最多 4096 次，这三项超出都报 `InvalidArgument`。

[返回语言指南](../language.md)

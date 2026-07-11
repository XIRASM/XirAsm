# 第 6 章：集合与文本

## 集合是编译期值

汇编程序往往不只描述一个个整数。源文件可能需要一组有序字段、一张带名称的属性表、动态生成的符号名称，或者一段必须逐字节保持不变的数据。

XIRASM 为这些用途提供了四种常见值类型：

| 类型 | 表示的内容 | 常见用途 |
| --- | --- | --- |
| `string` | 源代码层面的文本 | 名称、路径、诊断信息、解析出的字段 |
| `bytes` | 精确的二进制数据 | 签名、编码后的整数、二进制记录 |
| `list` | 有序值 | 表格、重复项、有序描述信息 |
| `map` | 以字符串为键的值 | 命名选项、记录、查找表 |

这些类型都属于编译期值。创建字符串、字节序列、列表或映射并不会写出任何内容。只有把值传给输出接口，它的内容才会成为生成文件的一部分。

字符串、字节序列、列表和映射通过会产生新值的辅助接口进行操作。`list.push` 或 `map.set` 之类的操作会返回一个新值，而不是就地修改原值。这样既能明确表示每个中间状态，也能安全地重复使用已有值。

## 用字符串表示源文本

字符串保存汇编过程中使用的文本：

```asm
// 先清除名称两端的空白，再把 ASCII 字母统一转换为小写。
const raw_name: string = "  Kernel64  "
const name: string = lower(trim(raw_name))

// 检查规范化后的名称及其组成部分。
assert(name == "kernel64");
assert(starts_with(name, "kernel"));
assert(ends_with(name, "64"));
assert(contains(name, "nel"));

// 把最终文本作为字节写入输出内容。
emit.bytes(name);
```

这段代码会写出 `kernel64` 的八个文本字节。

最常用的字符串辅助接口包括：

- `trim(text)` 删除文本两端的空白；
- `lower(text)` 和 `upper(text)` 分别把 ASCII 字母转换为小写和大写；
- `starts_with`、`ends_with` 和 `contains` 检查文本；
- `replace(text, needle, replacement)` 替换匹配的文本；
- `to_string(value)` 生成某个值的文本表示。

字符串的大小写转换面向 ASCII 字符。名称、配置文本、路径、诊断信息和其他供人阅读的值适合使用字符串；如果必须逐字节精确保留二进制数据，则应使用 `bytes`。

## 拆分与连接文本

`split` 把带分隔符的文本拆成字符串列表，`join` 则把字符串列表连接起来：

```asm
// 把逗号分隔的节名称拆成列表，再按路径形式重新连接。
const sections: list = split("text,data,bss", ",")
const path: string = join(sections, "/")

// 列表索引从零开始，因此索引 0 和 2 分别对应首尾元素。
assert(len(sections) == 3);
assert(list.get(sections, 0) == "text");
assert(list.get(sections, 2) == "bss");
assert(path == "text/data/bss");

// 写出重新组合后的路径文本。
emit.bytes(path);
```

索引从零开始。`list.get(sections, 0)` 返回第一个元素。

拆分操作适合处理源代码层面的小型格式、类似命令行的文本和动态生成的名称。结构更复杂的外部数据将在第 10 章介绍，其中包括文件、JSON 和 TOML。

## 用字节序列表示二进制值

`bytes` 值是一段精确的字节序列：

```asm
// 从十六进制文本构造文件标记，并把版本号编码为两个小端字节。
const magic: bytes = bytes.from_hex("58495200")
const version: bytes = bytes.le(3, 2)
const header: bytes = bytes.concat(magic, version)

// 检查原始标记和版本字段的编码结果。
assert(bytes.eq(magic, bytes.from_hex("58495200")));
assert(bytes.hex(version) == "0300");

// 按连接后的顺序写出完整文件头。
emit.bytes(header);
```

输出内容为：

```text
58 49 52 00 03 00
```

`bytes.from_hex` 把十六进制文本转换为二进制数据。`bytes.le(value, width)` 使用指定字节数，按小端顺序编码一个整数。`bytes.concat` 把两段字节序列连接起来。

需要明确比较两段字节序列是否相等时，使用 `bytes.eq`；需要把二进制值显示为小写十六进制文本时，使用 `bytes.hex`。

## 构造字节序列

字节辅助接口会返回新值，因此可以用清晰的步骤逐步构造二进制记录：

```asm
// 从 ABC 的字节表示开始，在索引 1 处插入连字符。
const base: bytes = bytes.from_hex("414243")
const marked: bytes = bytes.insert(base, 1, b"-")

// 从索引 2 开始替换一个字节，并追加两个 0xff 字节。
const patched: bytes = bytes.replace(marked, 2, 1, b"Z")
const trailer: bytes = bytes.repeat(2, 0xff)
const result: bytes = bytes.concat(patched, trailer)

// 只写出最终结果，各个中间值仍可继续复用。
emit.bytes(result);
```

这段代码会写出：

```text
41 2d 5a 43 ff ff
```

这些操作包括：

- `bytes.new()` 创建空字节序列；
- `bytes.push(value, byte)` 在末尾追加一个字节；
- `bytes.repeat(count, byte)` 创建重复字节；
- `bytes.insert(value, index, addition)` 在从零开始的索引处插入字节；
- `bytes.replace(value, index, count, replacement)` 替换一段字节范围；
- `bytes.concat(left, right)` 连接两段字节序列。

原始 `base` 值仍然是 `41 42 43`。每次操作都会产生一个新值，既可以保留或重复使用，也可以继续传给下一个操作。

## 列表保留顺序

列表保存一组有序的编译期值：

```asm
// 先追加一个元素，再替换索引 1 处的值。
const base: list = list.of(1, 2, 3)
const extended: list = list.push(base, 4)
const patched: list = list.set(extended, 1, 0xaa)

// 从索引 1 开始截取两个元素，原列表不会被修改。
const middle: list = list.slice(patched, 1, 2)

assert(list.eq(base, list.of(1, 2, 3)));
assert(list.eq(patched, list.of(1, 0xaa, 3, 4)));
assert(list.eq(middle, list.of(0xaa, 3)));

// 按列表中的固定顺序逐项写出字节。
for value in patched {
    db(value);
}
```

这段代码会写出：

```text
01 aa 03 04
```

`list.set` 返回一个替换了指定元素的新列表。`list.slice` 接收起始索引和元素数量。这两个操作都不会修改输入列表。

其他常用列表操作包括：

- `list.new()` 创建空列表；
- `list.get(value, index)` 读取一个元素；
- `list.concat(left, right)` 连接两个列表；
- `list.eq(left, right)` 比较列表内容；
- `len(value)` 返回元素数量。

列表自身包含元素顺序，因此可以自然地配合 `for` 使用。节描述、表格行、字节块以及其他必须按确定顺序处理的数据都适合使用列表。

## 列表可以保存更复杂的值

列表元素并不局限于单个整数。列表还可以组织字符串、字节序列、映射或其他编译期值：

```asm
// 把文本标记和一个双字节小端整数组织成有序字节块。
const chunks: list = list.concat(
    list.of(b"XR"),
    list.of(bytes.le(0x1234, 2))
)

// 列表决定写出顺序，每个元素保留各自精确的字节表示。
for chunk in chunks {
    emit.bytes(chunk);
}
```

这段代码会写出：

```text
58 52 34 12
```

当一条记录更适合表示为若干有序片段时，这种写法很有用。列表控制片段顺序，每段字节序列则控制自身精确的二进制表示。

## 映射保存命名值

映射把字符串键与编译期值关联起来：

```asm
// 逐步加入命名属性，并用新值替换已有的 arch 属性。
const base: map = map.set(map.new(), "arch", "x64")
const configured: map = map.set(base, "mode", "release")
const changed: map = map.set(configured, "arch", "rv64")

// 映射中的值也可以是列表等更大的编译期值。
const complete: map = map.set(changed, "tags", list.of("asm", "dsl"))

// 检查键是否存在，并读取必需或带默认值的属性。
assert(len(complete) == 3);
assert(map.has(complete, "arch"));
assert(!map.has(complete, "missing"));
assert(map.get(base, "arch") == "x64");
assert(map.get(changed, "arch") == "rv64");
assert(map.get_or(complete, "missing", "default") == "default");
assert(list.eq(map.get(complete, "tags"), list.of("asm", "dsl")));
```

`map.set` 会添加一个键；如果键已经存在，则返回一个替换了该键对应值的新映射。较早的映射值不会改变，因此在 `changed` 保存 `"rv64"` 之后，`base` 中仍然保存着 `"x64"`。

可以使用：

- `map.has(value, key)` 检查键是否存在；
- `map.get(value, key)` 读取必需键对应的值；
- `map.get_or(value, key, fallback)` 读取可选键对应的值，键不存在时返回后备值；
- `map.eq(left, right)` 比较映射内容。

`map.eq` 比较键和值的内容，而不比较插入顺序。

## 遍历映射内容

映射主要用于按键查找。遍历之前，应先把它的键或值转换成列表：

```asm
// 用映射保存两个带名称的二进制字段。
const fields: map = map.set(
    map.set(map.new(), "magic", b"XR"),
    "version",
    bytes.le(3, 2)
)

// 键和值分别转换为列表，便于检查数量或逐项处理。
const keys: list = map.keys(fields)
const values: list = map.values(fields)

assert(len(keys) == 2);
assert(len(values) == 2);

// 逐项写出映射中保存的字节序列。
for value in values {
    emit.bytes(value);
}
```

处理名称时使用 `map.keys`，处理已保存的值时使用 `map.values`。如果文件格式规定了明确的处理顺序，应把顺序保存在列表中，而只把映射用于查找。

## 在函数中组合集合

当函数需要把一份描述转换成二进制数据时，集合尤其有用：

```asm
// 把列表中的每个数值编码为两个小端字节。
fn encode_u16(values: list) -> bytes {
    let result: bytes = bytes.new()

    // 每次连接都会产生新的字节序列，并更新可变绑定 result。
    for value in values {
        result = bytes.concat(result, bytes.le(value, 2))
    }

    return result;
}

// 调用者决定何时把函数生成的字节序列写入输出内容。
const words: list = list.of(0x1234, 0xabcd)
emit.bytes(encode_u16(words));
```

这段代码会写出：

```text
34 12 cd ab
```

函数接收一份有序描述，逐步构造不可变的字节值，最后返回完整的编码结果。调用者负责决定在何时、何处写出该结果。

这种职责划分可以很好地扩展：

- 字符串描述名称和源代码层面的文本；
- 映射描述带名称的属性；
- 列表保留输出顺序；
- 字节序列保存最终的二进制表示；
- 过程函数决定在何处写出这种表示。

## 选择集合类型

| 需求 | 使用方式 |
| --- | --- |
| 供人阅读的源文本 | `string` |
| 精确的二进制表示 | `bytes` |
| 有序值序列 | `list` |
| 按字符串键查找 | `map` |
| 解析带简单分隔符的文本 | 使用 `split` 转换为 `list` |
| 重新构造带分隔符的文本 | `join` |
| 在内存中构造二进制记录 | `bytes` 辅助接口 |
| 既保留顺序又支持查找 | 同时使用 `list` 和 `map` |

应选择与数据含义一致的类型。不要把字符串当作二进制缓冲区，也不要在格式本身包含顺序要求时使用映射代替有序结构。

下一章将介绍词法单元和模式匹配，用于处理那些必须按照语言语法理解、而不能只视为普通字符串的源文本。

[返回语言指南](../language.md)

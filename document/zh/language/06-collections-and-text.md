# 第6章：集合和文本

## 集合是编译时值

XIRASM 有四种编译时值类型：

| 类型       | 表示什么         | 常见用途                       |
| ---------- | ---------------- | ------------------------------ |
| `string` | 源文件中的文本   | 名字、路径、错误信息、文本字段 |
| `bytes`  | 确切的二进制数据 | 签名、魔数、编码指令、打包记录 |
| `list`   | 有序的值序列     | 重复表项、参数列表、配置条目   |
| `map`    | 字符串到值的映射 | 配置选项、记录字段、查找表     |

这些类型不写数据。只有传给输出接口，数据才会写入输出文件。

字符串、字节序列、列表、映射都提供产生新值的 API。`list.push`、`map.set` 等操作返回新值，不修改原值。列表和映射还有可变接口，给 `let` 绑定的集合逐步添加内容。值在传递时复制，不共享内存。

## 字符串表示源文本

字符串存放编译时用的文本：

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

输出 `kernel64` 的八个文本字节。

常用字符串 API：

- `trim(text)` 去掉两端空白
- `lower(text)`、`upper(text)` 转 ASCII 字母大小写
- `starts_with`、`ends_with`、`contains` 检测文本
- `replace(text, needle, replacement)` 替换匹配文本
- `to_string(value)` 把值转成文本

大小写转换只处理 ASCII。名字、路径、错误消息、配置键适合字符串。二进制数据用 `bytes`。

## 分割和连接文本

`split` 按分隔符拆成字符串列表，`join` 把列表连成文本：

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

索引从零开始。用于处理小配置列表、格式选项中的文本、动态生成的名字。

## 用字节序列表示二进制值

`bytes` 是一段确切的字节序列：

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

输出 `58 49 52 00 03 00`。

`bytes.from_hex` 把十六进制文本转二进制。`bytes.le(value, width)` 用指定位数小端序编码整数。`bytes.concat` 拼接字节序列。`bytes.eq` 比较两个序列。`bytes.hex` 把二进制显示为小写十六进制文本。

## 构建字节序列

字节操作 API 都返回新值，可以链式调用：

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

输出 `41 2d 5a 43 ff ff`。

操作包括：

- `bytes.new()` 空序列
- `bytes.push(value, byte)` 末尾追加
- `bytes.repeat(count, byte)` 重复字节
- `bytes.insert(value, index, addition)` 在零开始索引处插入
- `bytes.replace(value, index, count, replacement)` 替换范围
- `bytes.concat(left, right)` 拼接

原始 `base` 仍然是 `41 42 43`。每次操作产生新值，旧值不受影响。

## 列表保持顺序

列表存放有序值：

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

for value in patched { db(value); }
```

输出 `01 aa 03 04`。

`list.set` 返回替换元素后的新列表。`list.slice` 返回从起始索引开始的指定个元素。都不改原列表。

其他：`list.new()`、`list.get()`、`list.concat()`、`list.eq()`、`len()`。

## 用可变绑定的API版本的集合

局部算法需要逐步构建列表或映射时用可变接口：

```asm
let items: list = list.of(1, 2)
list.push_mut(items, 3);
list.set_mut(items, 0, 4);

let options: map = map.new()
map.set_mut(options, "arch", "x64");
map.set_mut(options, "items", items);
```

第一个参数必须是 `let` 绑定的标识符。传 `const` 会报错。类型不匹配也会报错。`defer` 块只能更新它内部的局部 `let`。

值复制有明确边界：

```asm
let items: list = list.of(1)
const snapshot: list = items
list.push_mut(items, 2);

assert(list.eq(snapshot, list.of(1)));
assert(list.eq(items, list.of(1, 2)));
```

## 列表可以放各种值

列表元素不限整数，可以放字符串、字节序列、映射等：

```asm
// 把文本标记和一个双字节小端整数组织成有序字节块。
const chunks: list = list.concat(
    list.of(b"XR"),
    list.of(bytes.le(0x1234, 2))
)

for chunk in chunks { emit.bytes(chunk); }
```

输出 `58 52 34 12`。

## 映射保存键值对

映射把字符串键关联到值：

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

`map.set` 返回新映射。键已存在则替换值。改 `changed` 不影响 `base`。

## 遍历映射要先把键或值转列表

映射用于按键查找。需要遍历时先用 `map.keys` 或 `map.values` 转列表：

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

文件格式规定了确切顺序的，用列表存。映射只负责查找。

## 在函数中组合集合

集合转换用函数封装：

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

输出 `34 12 cd ab`。函数逐步构建不可变字节值，调用者控制何时写输出。

职责划分：字符串存名字和文本，映射存命名配置，列表存有序值，字节序列存最终二进制表示，过程函数控制何时写输出。

## 选哪种集合

| 需求                   | 用这个                |
| ---------------------- | --------------------- |
| 面向人的源文本         | `string`            |
| 确切的二进制表示       | `bytes`             |
| 有序值序列             | `list`              |
| 按字符串键查找         | `map`               |
| 处理按分隔符拆分的文本 | `split` 转 `list` |
| 重新组合分隔文本       | `join`              |
| 逐字节构建二进制记录   | `bytes` API         |
| 既要顺序又要查找       | `list` + `map`    |

下一章讲词法元素和模式匹配，用于需要按语法解析的源文本。

[返回语言指南](../language.md)

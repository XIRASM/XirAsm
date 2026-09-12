# 第 6 章：集合与文本

## 四种集合类型

一个字节不够用时，编译期需要更大的容器。XIRASM 有四种：

| 类型     | 表示             | 典型用途                             |
| -------- | ---------------- | ------------------------------------ |
| `string` | 源码级文本       | 名称、路径、诊断信息、解析出的字段   |
| `bytes`  | 精确二进制数据   | 签名、编码后的整数、二进制记录       |
| `list`   | 有序的值序列     | 表格、重复项、有序描述符             |
| `map`    | 以字符串为键的值 | 命名选项、记录、查找表               |

四种都是编译期值，可以存在绑定里、当实参传递，也可以直接交给写输出的接口：

```asm id=06-of
const name: string = "kernel"
const magic: bytes = b"XR"
const sizes: list = list.of(1, 2, 3)

let options: map = map.new()
map.set_mut(options, "arch", "x64")

emit.bytes(name)          // 这里写出：6b 65 72 6e 65 6c
emit.bytes(magic)         // 这里写出：58 52
emit.u8(len(sizes))       // 这里写出：03
```

写输出之前，它们不占文件里任何位置。上面四条声明本身不产生字节。

改集合有两种写法。一种是返回值形式，它不动传进来的那个集合，另计算出一个新集合返回：

```asm id=06-of-2
const base: list = list.of(1, 2)
const grown: list = list.push(base, 3)

emit.u8(len(base))        // 这里写出：02
emit.u8(len(grown))       // 这里写出：03
```

另一种是语句形式，名字以 `_mut` 结尾，它直接改掉传进来的那个 `let` 绑定。第一个实参必须是 `let` 声明的标识符，`const` 和临时值都会被拒绝（见本章《改写 `let` 绑定的集合》）。

```asm id=06-of-3
let items: list = list.of(1, 2)
list.push_mut(items, 3)

emit.u8(len(items))       // 这里写出：03
```

把集合交给另一个绑定时会复制一份，两个绑定互不影响：

```asm id=06-of-4
let items: list = list.of(1)
const snapshot: list = items
list.push_mut(items, 2)

emit.u8(len(snapshot))    // 这里写出：01
emit.u8(len(items))       // 这里写出：02
```

## 字符串

```asm id=06-lower
const raw_name: string = "  Kernel64  "
const name: string = lower(trim(raw_name))

assert(name == "kernel64")
assert(starts_with(name, "kernel"))
assert(ends_with(name, "64"))
assert(contains(name, "nel"))

emit.bytes(name)        // 这里写出：6b 65 72 6e 65 6c 36 34
```

字符串接口：

| 调用                                       | 作用                                                  |
| ------------------------------------------ | ----------------------------------------------------- |
| `trim(text)`                               | 去掉两端的空白                                        |
| `lower(text)` 、 `upper(text)`             | 规范化 ASCII 字母的大小写                             |
| `starts_with` 、 `ends_with` 、 `contains` | 判断一段文本                                          |
| `replace(text, needle, replacement)`       | 替换匹配到的文本                                      |
| `to_string(value)`                         | 把值转成十进制文本：`to_string(0x1234)` 得到 `"4660"` |
| `len(text)`                                | 长度                                                  |

大小写转换按 ASCII 处理。名称、配置文本、路径和诊断信息用字符串；要求每个字节都原样保留时用 `bytes`。

## 分割与连接

```asm id=06-split
const sections: list = split("text,data,bss", ",")
const path: string = join(sections, "/")

assert(len(sections) == 3)
assert(list.get(sections, 0) == "text")
assert(list.get(sections, 2) == "bss")
assert(path == "text/data/bss")

emit.bytes(path)        // 这里写出：74 65 78 74 2f 64 61 74 61 2f 62 73 73
```

`split` 按分隔符把文本拆成字符串列表，`join` 把列表连回一段文本。下标从 0 开始。结构化的外部数据——文件、JSON、TOML——在第 10 章。

## 字节序列

```asm id=06-from-hex
const magic: bytes = bytes.from_hex("58495200")
const version: bytes = bytes.le(3, 2)
const header: bytes = bytes.concat(magic, version)

assert(bytes.eq(magic, bytes.from_hex("58495200")))
assert(bytes.hex(version) == "0300")

emit.bytes(header)      // 这里写出：58 49 52 00 03 00
```

`bytes.from_hex` 读十六进制文本，`bytes.le(value, width)` 按指定字节数把小端整数编码出来，`bytes.concat` 连接两段序列，`bytes.eq` 比较两段序列，`bytes.hex` 渲染成小写十六进制文本。

## 拼接字节序列

```asm id=06-from-hex-2
const base: bytes = bytes.from_hex("414243")
const marked: bytes = bytes.insert(base, 1, b"-")     // 41 2d 42 43
const patched: bytes = bytes.replace(marked, 2, 1, b"Z")
const trailer: bytes = bytes.repeat(2, 0xff)
const result: bytes = bytes.concat(patched, trailer)

emit.bytes(result)      // 这里写出：41 2d 5a 43 ff ff
```

| 调用                                              | 作用                       |
| ------------------------------------------------- | -------------------------- |
| `bytes.new()`                                     | 空序列                     |
| `bytes.push(value, byte)`                         | 追加一个字节，返回新序列   |
| `bytes.repeat(count, byte)`                       | 重复同一个字节             |
| `bytes.insert(value, index, addition)`            | 在下标处放进一段字节       |
| `bytes.replace(value, index, count, replacement)` | 换掉一段字节               |
| `bytes.concat(left, right)`                       | 连接两段序列               |

走完上面这些步骤，`base` 仍然是 `41 42 43`：每一步都产出一个新值，交给下一步。

## 列表

```asm id=06-of-5
let items: list = list.of(1, 2, 3)
list.push_mut(items, 4)
list.set_mut(items, 1, 0xaa)
const middle: list = list.slice(items, 1, 2)

assert(list.eq(items, list.of(1, 0xaa, 3, 4)))
assert(list.eq(middle, list.of(0xaa, 3)))

for value in items {
    db(value)              // 这里写出：01 aa 03 04
}
```

| 调用                                  | 作用                 |
| ------------------------------------- | -------------------- |
| `list.new()`                          | 空列表               |
| `list.of(...)`                        | 用给出的值建一个列表 |
| `list.get(value, index)`              | 读一个元素           |
| `list.slice(value, index, count)`     | 复制一段元素         |
| `list.concat(left, right)`            | 连接两个列表         |
| `list.eq(left, right)`                | 比较内容             |
| `len(value)`                          | 元素个数             |

顺序是列表的一部分，`for` 遍历列表才有意义。节描述、表格行和字节分块都依赖确定的次序。

## 改写 `let` 绑定的集合

语句形式的接口改写的是一个 `let` 绑定本身，不返回新值：

```asm id=06-of-6
// 三个 _mut 调用改的都是左边的绑定本身。
let items: list = list.of(1, 2)
list.push_mut(items, 3)          // 末尾变 1, 2, 3
list.set_mut(items, 0, 4)        // 下标 0 换成 4 → 4, 2, 3

let options: map = map.new()
map.set_mut(options, "arch", "x64")
map.set_mut(options, "items", items)   // 值可以是别的集合
```

第一个实参必须是 `let` 绑定的标识符，`const` 会被拒绝：

```asm id=06-of-7 error=cannot mutate a const collection binding
// items 是 const，没有可改写的绑定。
const items: list = list.of(1)
list.push_mut(items, 2)
```

```text
bad.xir:2:1: error: cannot mutate a const collection binding
```

临时值同样会被拒绝：

```asm id=06-of-8 error=collection mutation target must be a direct let binding
// 前两行没问题，第三行的目标是临时值 list.of(1)。
let items: list = list.of(1)
list.push_mut(items, 2)
list.push_mut(list.of(1), 3)
```

```text
bad.xir:3:1: error: collection mutation target must be a direct let binding
```

查找名字时用最近的那个绑定，所以块里重新 `let` 一个同名变量，会遮住外层的那个；块里改的是块自己的集合，退出块后外层不受影响。顶层的 `let` 在普通 lowering 期间可以改；返回值函数只能改自己的局部绑定。

三种改写各自做的事：

| 调用                            | 做的事                                       |
| ------------------------------- | -------------------------------------------- |
| `list.push_mut(value, item)`    | 在末尾追加一个元素                           |
| `list.set_mut(value, index, v)` | 换掉已存在下标处的元素                       |
| `map.set_mut(value, key, v)`    | 写入一个字符串键；键已存在时改值，键的位置不变 |

这三种都是语句，不返回值，也不能写进表达式。它们还受块的性质限制：

```asm id=06-of-9 error=lowering failed: FinalizerCannotChangeLayout
// defer 在布局定下来之后运行，那时不能再长出新内容。
let items: list = list.of(1)
defer {
    list.push_mut(items, 2)
}
```

```text
error: lowering failed: FinalizerCannotChangeLayout
```

`late_layout` 里同样不行（报 `InvalidLateLayout`），因为这两个块运行在布局定下来之后，不能再长出内容。

一个绑定被改写，另一个绑定不受影响：

```asm id=06-of-10
// snapshot 拿到的是当时的副本，之后改 items 不影响它。
let items: list = list.of(1)
const snapshot: list = items
list.push_mut(items, 2)

assert(list.eq(snapshot, list.of(1)))
assert(list.eq(items, list.of(1, 2)))
```

## 元素不限于整数

```asm id=06-concat
const chunks: list = list.concat(
    list.of(b"XR"),
    list.of(bytes.le(0x1234, 2))
)

for chunk in chunks {
    emit.bytes(chunk)      // 先 58 52，再 34 12
}
```

列表负责顺序，每个元素负责自己的二进制表示。记录的各段宽度不同时，这样最好写。

## 映射

```asm id=06-new
// "arch" 写两次：第二次是改已有键的值，不是新增。
let options: map = map.new()
map.set_mut(options, "arch", "x64")
map.set_mut(options, "mode", "release")
map.set_mut(options, "arch", "rv64")
map.set_mut(options, "tags", list.of("asm", "dsl"))

// 三个不同的键：arch / mode / tags。
assert(len(options) == 3)
assert(map.has(options, "arch"))
assert(!map.has(options, "missing"))
assert(map.get(options, "arch") == "rv64")
// 键不在时用兜底值，而不是报错。
assert(map.get_or(options, "missing", "default") == "default")
assert(list.eq(map.get(options, "tags"), list.of("asm", "dsl")))
```

| 调用                                  | 作用                     |
| ------------------------------------- | ------------------------ |
| `map.new()`                           | 空映射                   |
| `map.has(value, key)`                 | 键是否存在               |
| `map.get(value, key)`                 | 读一个必须存在的键       |
| `map.get_or(value, key, fallback)`    | 读一个可以不存在的键     |
| `map.eq(left, right)`                 | 比较内容，不比较插入顺序 |

上面 `"arch"` 写了两次，长度仍然是 3：第二次是替换而不是新增，键的位置也不变。

## 遍历映射

映射是查找结构，遍历要先取出它的键列表或值列表：

```asm id=06-new-2
let fields: map = map.new()
map.set_mut(fields, "magic", b"XR")
map.set_mut(fields, "version", bytes.le(3, 2))

const keys: list = map.keys(fields)
const values: list = map.values(fields)

assert(len(keys) == 2)
assert(len(values) == 2)

for value in values {
    emit.bytes(value)      // 先 58 52，再 03 00
}
```

查名字用 `map.keys`，查存下来的值用 `map.values`。当处理顺序是文件格式的一部分时，把顺序放进列表，映射只负责查找。

## 在函数中组合集合

```asm id=06-encode-u16
fn encode_u16(values: list) -> bytes {
    let result: bytes = bytes.new()

    for value in values {
        result = bytes.concat(result, bytes.le(value, 2))
    }

    return result
}

const words: list = list.of(0x1234, 0xabcd)
emit.bytes(encode_u16(words))   // 这里写出：34 12 cd ab
```

函数接收一份有序描述，计算出编码结果返回；结果放进输出的哪一段由调用者决定。四种类型在这里各司其职：字符串和映射负责描述，列表决定次序，字节序列承载表示，过程决定它落在哪里。

[返回语言指南](../language.md)

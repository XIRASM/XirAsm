# 第 12 章：列表与映射

列表和映射都是编译期值集合。表达式接口在添加、替换或组合值时返回新集合，所有输入集合保持不变。当算法需要逐步构造集合时，也可以使用仅作用于直接 `let` 绑定的显式可变语句。

## 列表函数

| 函数 | 结果 | 说明 |
| --- | --- | --- |
| `list.new()` | `list` | 创建空列表。 |
| `list.of(values...)` | `list` | 使用零个或多个值创建列表。 |
| `list.push(value, item)` | `list` | 在列表末尾追加一个元素。 |
| `list.concat(left, right)` | `list` | 连接两个列表。 |
| `list.get(value, index)` | 值 | 返回从零开始的索引所指向的元素。 |
| `list.set(value, index, item)` | `list` | 返回替换了一个元素的新列表。 |
| `list.slice(value, start, count)` | `list` | 返回一段连续范围组成的新列表。 |
| `list.eq(left, right)` | `bool` | 按顺序递归比较两个列表是否相等。 |

以下语句直接更新 `let` 绑定，不返回值：

| 语句 | 说明 |
| --- | --- |
| `list.push_mut(target, item);` | 把深拷贝后的元素追加到 `target`。 |
| `list.set_mut(target, index, item);` | 使用深拷贝后的值替换已有元素。 |

`list.get` 和 `list.set` 要求索引小于列表长度。`list.slice` 的起始索引可以从零取到列表长度，但所选范围不能超出列表。允许在列表末尾取得长度为零的切片。

```asm
// 每次列表操作都返回新列表，base 和 extended 不会被后续操作修改。
const base: list = list.of(1, 2, 3)
const extended: list = list.push(base, 4)
const patched: list = list.set(extended, 1, 0xaa)
const middle: list = list.slice(patched, 1, 2)
const combined: list = list.concat(list.of(0x10, 0x11), middle)

// 索引从零开始；列表相等比较同时检查元素顺序和内容。
assert(list.get(base, 1) == 2)
assert(list.eq(base, list.of(1, 2, 3)))
assert(list.eq(patched, list.of(1, 0xaa, 3, 4)))
assert(list.eq(middle, list.of(0xaa, 3)))

// 按 combined 中的顺序逐项写出字节。
for value in combined {
    emit.u8(value)
}
```

这段代码会写出 `10 11 aa 03`。列表相等比较与元素顺序有关，并会递归比较嵌套的列表、映射、结构体、字符串和字节序列。

## 映射函数

| 函数 | 结果 | 说明 |
| --- | --- | --- |
| `map.new()` | `map` | 创建空映射。 |
| `map.set(value, key, item)` | `map` | 添加字符串键，或替换已有键对应的值，并返回新映射。 |
| `map.has(value, key)` | `bool` | 检查指定字符串键是否存在。 |
| `map.get(value, key)` | 值 | 返回必需键对应的值。 |
| `map.get_or(value, key, fallback)` | 值 | 键存在时返回对应值，否则返回给定的后备值。 |
| `map.keys(value)` | `list` | 按插入顺序返回键列表。 |
| `map.values(value)` | `list` | 按与键相同的插入顺序返回值列表。 |
| `map.eq(left, right)` | `bool` | 递归比较两个映射是否相等，不考虑键的顺序。 |

`map.set_mut(target, key, item);` 会在由直接 `let` 绑定的映射中添加或替换深拷贝后的值。键必须是字符串；替换已有键时，该键的插入位置保持不变。

映射的键必须是字符串。添加新键时，该项会追加到插入顺序末尾；替换已有键时，该键原有的位置保持不变。因此，`map.keys` 和 `map.values` 返回的两个列表一一对应，相同索引表示同一个映射项。

```asm
// map.set 返回新映射；empty、first 和 configured 都保持原值。
const empty: map = map.new()
const first: map = map.set(empty, "arch", "x64")
const configured: map = map.set(first, "mode", 64)
const updated: map = map.set(configured, "arch", "rv64")
const complete: map = map.set(updated, "tags", list.of("asm", "dsl"))

// 检查键、后备值和插入顺序，并确认替换不会改变旧映射。
assert(len(empty) == 0)
assert(map.has(complete, "arch"))
assert(!map.has(complete, "missing"))
assert(map.get(first, "arch") == "x64")
assert(map.get(updated, "arch") == "rv64")
assert(map.get_or(complete, "missing", "default") == "default")
assert(list.eq(map.keys(complete), list.of("arch", "mode", "tags")))
assert(list.eq(map.get(complete, "tags"), list.of("asm", "dsl")))

// 以不同顺序插入相同的键和值。
const reordered: map = map.set(
    map.set(
        map.set(map.new(), "tags", list.of("asm", "dsl")),
        "mode",
        64
    ),
    "arch",
    "rv64"
)

// map.eq 不要求插入顺序相同，最后写出 mode 对应的字节。
assert(map.eq(complete, reordered))
emit.u8(map.get(complete, "mode"))
```

这段代码会写出 `40`。`map.eq` 会比较键和嵌套值，但不要求两个映射具有相同的插入顺序。

## 可变集合绑定规则

`list.push_mut`、`list.set_mut` 和 `map.set_mut` 的目标必须是直接标识符，并解析到词法作用域中最近的 `let` 绑定。目标不能是 `const`、临时表达式、调用结果、字段访问或类型不匹配的值。普通 lowering 阶段允许更新顶层 `let`；值函数中只能更新本次调用内部的局部绑定。这些接口是语句，不能作为表达式使用，也不能出现在 `defer` 或 `late_layout` 块中。

插入的值会在提交修改之前完成深拷贝，因此目标之前的副本以及插入到其他集合中的值都保持独立。分配失败时，目标集合保持原样。

## 错误条件

集合辅助接口会拒绝以下情况：

- 向 `list.*` 操作传入非列表参数；
- 向 `map.*` 操作传入非映射参数；
- 函数参数数量错误；
- 列表索引超出可用元素范围；
- 列表切片超出列表范围；
- 映射键不是字符串；
- 向 `map.get` 传入不存在的键。

如果键不存在属于预期情况，应使用 `map.has` 或 `map.get_or`。

# 第 8 章：主输出区域、输出区与文件游标

## 语法摘要

| 形式 | 语法 | 结果 |
| --- | --- | --- |
| 明确主输出区域 | `region.begin(name, origin, file_offset)` | 在明确的逻辑地址和文件位置开始一个主输出区域。 |
| 文件大小对齐 | `region.file_align(boundary)` | 对齐主输出区域的实际文件大小，并结束该区域。 |
| 潜在位置续接 | `output.org(name, origin)` | 从前一个潜在文件游标开始新的主输出区。 |
| 实际位置续接 | `output.section(name, origin)` | 从前一个实际文件游标开始新的主输出区。 |
| 虚拟输出区 | `virtual.begin([origin])` | 开始一个具有逻辑地址但不产生文件字节的嵌套输出区。 |
| 结束虚拟输出区 | `virtual.end()` | 返回 `virtual.begin` 之前处于活动状态的输出区。 |
| 区域逻辑原点 | `region_base()` | 返回当前主输出区域的逻辑基地址。 |
| 当前文件位置 | `file_offset()` | 返回当前主输出区域的绝对实际文件游标。 |
| 实际文件游标 | `file_cursor_real()` | 返回当前实际文件字节之后的下一个绝对位置。 |
| 潜在文件游标 | `file_cursor_potential()` | 返回由逻辑游标推导出的绝对文件位置。 |
| 尾部预留空间 | `tail_reserve_size()` | 返回当前主输出区域尾部尚未写入文件的逻辑字节数。 |

## 坐标模型

主输出区域分别维护逻辑坐标和文件坐标：

| 坐标 | 含义 |
| --- | --- |
| 逻辑地址 | 标号、`here()`、指令和地址回填项使用的地址。 |
| 实际文件游标 | 当前输出内容中已经存在的字节之后的绝对文件位置。 |
| 潜在文件游标 | 全部逻辑输出内容所推导出的绝对文件位置，其中包括尾部预留空间。 |

对于当前主输出区域：

```text
here()                  = region_base() + logical offset
file_cursor_real()      = region file offset + real relative cursor
file_cursor_potential() = region file offset + logical offset
tail_reserve_size()     = logical bytes beyond the real relative cursor
```

`file_offset()` 是查询当前实际文件游标的常用名称，返回值与
`file_cursor_real()` 相同。

实际写出的字节会同时推进两个文件游标。尾部预留空间只推进逻辑游标和潜在文件游标：

```asm
// 在逻辑地址 0x4000、文件偏移 0x20 处开始载荷区域。
region.begin("payload", 0x4000, 0x20)

// 写出一个实际文件字节，再增加三个尾部预留字节。
emit.u8(0x11)
reserve(3)

// 逻辑位置包含预留空间，实际文件游标只越过已写入的字节。
assert(region_base() == 0x4000)
assert(here() == 0x4004)
assert(file_offset() == 0x21)
assert(file_cursor_real() == 0x21)
assert(file_cursor_potential() == 0x24)
assert(tail_reserve_size() == 3)
```

如果同一主输出区域在预留空间之后继续写出已经初始化的内容，中间的间隔就会成为输出文件的一部分。实际文件游标会先追上潜在位置，再越过新写出的字节。

## 开始明确的主输出区域

`region.begin(name, origin, file_offset)` 开始一个新的主输出区域：

- `name` 用于在诊断信息和布局信息中标识该区域；
- `origin` 是该区域的逻辑基地址；
- `file_offset` 是该区域在输出文件中的绝对起始位置。

新区域的相对逻辑游标和相对文件游标都从零开始。各参数彼此独立，因此一种格式可以把紧凑的文件范围映射到不同的逻辑地址。

`region.begin` 不会根据前一个区域推断连续位置。如果新区域必须续接已有布局，应当在调用之前查询相应的文件游标。

## 实际位置与潜在位置续接

`output.section(name, origin)` 和 `output.org(name, origin)` 都会开始新的主输出区，并为它设置新的逻辑原点。两者的区别在于从前一个输出区选择哪个文件位置：

| 过程 | 新文件位置 | 对尾部预留空间的影响 |
| --- | --- | --- |
| `output.section` | 前一个实际文件游标 | 不把尚未写入文件的尾部预留空间计入后续文件布局。 |
| `output.org` | 前一个潜在文件游标 | 后续写出字节时，将尾部预留空间保留为文件间隔。 |

```asm
// 头部写出一个字节，并留下三个尾部预留字节。
region.begin("header", 0x4000, 0x20)
emit.u8(0x11)
reserve(3)

// 从实际文件游标续接，因此去除前面的尾部预留空间。
output.section("trimmed", 0x5000)
assert(file_offset() == 0x21)
emit.u8(0x22)
reserve(2)

// 从潜在文件游标续接，因此保留两个预留字节形成文件间隔。
output.org("preserved", 0x6000)
assert(file_offset() == 0x24)
emit.u8(0x33)
```

第一次切换会把 `trimmed` 放在字节 `0x11` 之后，三个尾部预留字节不会写入文件。第二次切换从潜在位置开始，因此 `0x22` 与 `0x33` 之间的两个预留字节会成为文件中间的间隔。

这两个过程都要求当前存在尚未结束的主输出区域。在虚拟输出区内调用它们属于无效操作。

## 结束并对齐文件区域

`region.file_align(boundary)` 会把当前主输出区域的实际文件大小向上取整到非零的 2 的幂边界，并结束该区域，禁止继续写出内容：

```asm
// 写出一个字节后，把主输出区域的实际文件大小对齐到八字节。
region.begin("record", 0x8000, 0)
emit.u8(0x7f)
region.file_align(8)

// 文件对齐只扩展实际文件范围，不会推进潜在文件游标。
assert(file_cursor_real() == 8)
assert(file_cursor_potential() == 1)
```

对齐产生的文件尾部属于输出文件，并使用零填充。因此，实际文件游标可以越过潜在文件游标。调用成功后，不能在该区域中继续写出、预留或对齐数据；必须开始另一个主输出区域或输出区才能继续。

## 虚拟输出区

`virtual.begin()` 会在当前逻辑地址开始一个嵌套的虚拟输出区。
`virtual.begin(origin)` 则使用明确的逻辑原点。虚拟输出区可以定义标号、预留空间并保存临时字节，但不会向最终文件贡献任何字节。

```asm
// 主输出区域先写出一个字节，虚拟输出区从下一逻辑地址开始。
region.begin("main", 0x7000, 0)
emit.u8(0xaa)

// 虚拟输出区可以推进自身逻辑位置，但不会推进主输出区域。
virtual.begin()
assert(region_base() == 0x7001)
emit.u16(0x1234)
reserve(2)
assert(here() == 0x7005)
virtual.end()

// 返回后恢复主输出区域的逻辑原点和当前位置。
assert(region_base() == 0x7000)
assert(here() == 0x7001)
emit.u8(0xbb)
```

最终文件只包含 `aa bb`。`virtual.end()` 会恢复先前的输出区及其游标。虚拟输出区可以嵌套，但每个 `virtual.begin` 都必须有一个对应的 `virtual.end`。

文件游标查询描述的是主输出文件，不能用来推断虚拟输出区的存储范围。虚拟输出区处于活动状态时，应当使用逻辑地址和标号。

## 错误条件

区域 API 会拒绝以下情况：

- `region.file_align` 的边界为零或不是 2 的幂；
- `region.file_align` 已经结束当前主输出区域后，仍尝试继续写出内容；
- 虚拟输出区处于活动状态时调用 `output.section` 或 `output.org`；
- 在没有对应开始操作时调用 `virtual.end`；
- 源文件结束时仍有尚未关闭的虚拟输出区。

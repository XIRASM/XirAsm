# 第 4 章：收尾处理语法形式

XIRASM 提供两个有意分开的后期处理阶段：

- `late_layout` 在最终输出内容确定之前执行受限的布局变更；
- `defer` 在布局确定后读取并回填最终字节映像，但不会改变布局。

不要把这两种形式互换使用。

## 阶段顺序

| 阶段 | 允许承担的职责 |
| --- | --- |
| 普通源码 | 声明标号、写出内容、预留空间并登记后期代码块。 |
| 指令编码 | 编码普通处理器指令片段。 |
| `late_layout` | 一次性追加或重新组织受限的布局内容。 |
| 地址回填与布局 | 解析引用，并计算最终的逻辑位置和物理位置。 |
| 生成最终字节映像 | 创建最终字节映像，并应用已经解析的地址回填项。 |
| `defer` | 读取、验证和回填已经生成的现有字节。 |

每一种代码块都按照登记顺序执行。

## `late_layout`

```asm
// 普通源码先写出第一个字节。
emit.u8(0x10)

late_layout {
    // 第一个后期布局块追加第二个字节。
    emit.u8(0x20)
}

late_layout {
    // 第二个后期布局块继续按登记顺序追加字节。
    emit.u8(0x30)
}
```

这个示例会写出 `10 20 30`。

后期布局块在普通源码写出和指令编码结束后执行一次，但早于地址回填项解析和最终布局。它写出的数据会参与最终偏移和大小的计算。

`late_layout` 接受：

- 输出与布局 API 调用；
- 整数、字节和复合值写出；
- 预留、补齐和对齐调用；
- 输出区域与虚拟区域调用；
- 向模块中已有内容执行写入；
- 诊断与断言；
- `if` 和 `else`。

它不接受局部声明、赋值、循环、标号、处理器指令、函数声明、源码加载、`defer` 或另一个 `late_layout`。

后期布局是一次性阶段，不是隐式的多轮处理机制。

## 预留尾部与后期布局

在同一个区域的预留尾部之后追加已初始化数据，会使预留空隙成为文件中的实际字节：

```asm
// 先写出一个字节，再预留两个只占逻辑空间的字节。
emit.u8(0xaa)
reserve(2)

late_layout {
    // 在预留尾部之后追加数据，使中间空隙进入实际输出。
    emit.u8(0xbb)
}
```

输出为 `aa 00 00 bb`。如果预留尾部必须只保留逻辑空间，请改用另一个输出区域。

## `defer`

```asm
// 让当前输出区域从逻辑地址 0 开始。
origin(0)

// 为最终文件大小预留一个 16 位字段。
size_field:
emit.u16(0)

// 写出两字节正文。
payload:
emit.bytes(b"AB")

defer {
    // 布局稳定后回填区域文件大小，并读取结果进行验证。
    store.u16(size_field, region_file_size(size_field))
    assert(load.u16(size_field) == 4)
}
```

输出为 `04 00 41 42`。

收尾块在最终布局、最终字节映像生成和地址回填项写入完成后执行。它看到的正是即将写入文件的准确字节映像。

收尾块可以包含：

- `const` 和 `let` 声明；
- 对局部 `let` 值赋值；
- `if`、`else` 和 `while`；
- `store.u8`、`store.u16`、`store.u32`、`store.u64` 和 `store.bytes`；
- `assert`、`print`、`warn` 和 `err`。

表达式可以使用纯计算运算符、返回值函数、标号、`load.*` 和稳定的区域信息。

每个收尾块都有自己的局部作用域。循环最多执行 1,000,000 次。

## 收尾块内的局部计算

```asm
// 使用固定逻辑起点，并为校验和预留两个字节。
origin(0)

checksum_field:
emit.u16(0)

// 写出需要参与校验和计算的数据。
payload:
emit.bytes(b"ABCD")

defer {
    // 使用局部可变值逐字节扫描最终映像。
    let cursor = payload
    let checksum = 0
    const end = region_base() + region_file_size(payload)

    while cursor < end {
        checksum = checksum + load.u8(cursor)
        cursor = cursor + 1
    }

    // 把累加结果回填到已有字段。
    store.u16(checksum_field, checksum)
}
```

`let` 会建立可变的收尾块局部状态。赋值用于更新这些状态，`while` 则可以对已经完成的映像执行有界扫描和汇总计算。

## 从过程函数登记收尾块

```asm
// 定义一个登记 16 位回填操作的过程函数。
fn patch_u16(address: u64, value: u64) {
    defer {
        // 收尾块保存调用时传入的地址和值。
        store.u16(address, value)
    }
}

// 先写出占位字段，再登记稍后执行的回填。
field:
emit.u16(0)

patch_u16(field, 0x1234)
```

输出为 `34 12`。

过程函数调用发生在普通源码处理期间。从过程函数作用域捕获的值会为收尾块固定下来。过程函数不会从 `defer` 内部调用。

## 收尾块执行顺序

```asm
// 先写出一个会被两个收尾块连续修改的字节。
origin(0)
emit.u8(0)

defer {
    // 第一个收尾块把初始值改为 1。
    store.u8(0, 1)
}

defer {
    // 第二个收尾块读取前一次修改，再把数值增加 1。
    store.u8(0, load.u8(0) + 1)
}
```

输出为 `02`。后登记的收尾块可以观察到先登记代码块完成的回填。

## 收尾处理限制

`defer` 不能创建字节、标号、区域、对齐或预留空间：

```text
defer {
    emit.u8(0x22)
}
```

在一个后期处理阶段中再嵌套另一个后期处理阶段同样无效：

```text
defer {
    late_layout {
        emit.u8(0x22)
    }
}
```

每个回填目标都必须在收尾阶段之前写出或预留。写入操作只能访问已经生成的实际字节。经过裁剪的预留尾部虽然具有逻辑范围，但没有可以回填的实际字节：

```text
origin(0)
emit.u8(0x11)
reserve(1)

defer {
    store.u8(1, 0x22)
}
```

这个写入操作会被拒绝，不会越过实际生成的字节范围写入数据。

## 完整示例

```asm
// 为大小和校验和分别预留两个 16 位字段。
origin(0)

size_field:
emit.u16(0)

checksum_field:
emit.u16(0)

// 普通源码先写出正文的前两个字节。
payload:
emit.bytes(b"AB")

late_layout {
    // 后期布局追加会参与最终大小和校验和计算的字节。
    emit.bytes(b"CD")
}

defer {
    // 扫描完整正文并计算校验和。
    let cursor = payload
    let checksum = 0
    const end = region_base() + region_file_size(payload)

    while cursor < end {
        checksum = checksum + load.u8(cursor)
        cursor = cursor + 1
    }

    // 回填两个文件头字段，并验证最终字节映像。
    store.u16(size_field, region_file_size(size_field))
    store.u16(checksum_field, checksum)

    assert(load.u16(size_field) == 8)
    assert(load.u16(checksum_field) == 0x010a)
    assert(load.bytes(payload, 4) == b"ABCD")
}
```

源代码会写出：

```text
08 00 0a 01 41 42 43 44
```

`late_layout` 会添加正文最后两个字节。随后，`defer` 看到完整的八字节映像，计算校验和，并回填两个已经存在的文件头字段。

## 选用指南

| 需求 | 使用形式 |
| --- | --- |
| 写出普通源码内容 | 普通源码 |
| 在偏移和大小确定之前追加实际字节 | `late_layout` |
| 在布局完成后回填宽度固定的占位字段 | `defer` |
| 根据最终字节计算校验和 | 使用 `load.*` 和局部状态的 `defer` |
| 验证最终偏移、大小或内容 | 使用 `assert` 的 `defer` |

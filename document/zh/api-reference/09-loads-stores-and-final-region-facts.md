# 第 9 章：读取、写入与最终区域信息

## 语法摘要

| 形式 | 语法 | 结果 |
| --- | --- | --- |
| 读取整数 | `load.u8(address)` | 读取一个字节。 |
| 读取整数 | `load.u16(address)` | 读取一个小端顺序的 16 位整数。 |
| 读取整数 | `load.u32(address)` | 读取一个小端顺序的 32 位整数。 |
| 读取整数 | `load.u64(address)` | 读取一个小端顺序的 64 位整数。 |
| 读取字节 | `load.bytes(address, count)` | 返回 `count` 个字节。 |
| 写入整数 | `store.u8(address, value)` | 写入一个字节。 |
| 写入整数 | `store.u16(address, value)` | 写入一个小端顺序的 16 位整数。 |
| 写入整数 | `store.u32(address, value)` | 写入一个小端顺序的 32 位整数。 |
| 写入整数 | `store.u64(address, value)` | 写入一个小端顺序的 64 位整数。 |
| 写入字节 | `store.bytes(address, value)` | 写入字符串或字节序列。 |
| 区域文件偏移 | `region_file_offset(address)` | 返回区域的最终文件偏移。 |
| 区域文件大小 | `region_file_size(address)` | 返回区域最终存在于文件中的字节数。 |
| 区域逻辑大小 | `region_logical_size(address)` | 返回区域的最终逻辑大小。 |

## 常规访问与收尾阶段访问

读取和写入操作在两个阶段访问不同的数据状态：

| 阶段 | 访问的数据 |
| --- | --- |
| 常规求值阶段 | 当前模块布局中已经存在的字节。 |
| `defer` 收尾阶段 | 稳定的最终输出内容中的字节。 |

常规写入可以在目标字节已经生成后初始化或替换这些字节。收尾阶段写入适合处理依赖最终布局的字段，例如大小、偏移、校验和以及目录项。

```asm
// 创建逻辑地址从 0x3000、文件偏移从 0 开始的数据区域。
region.begin("data", 0x3000, 0)

// 先写出不同宽度整数和字节序列所需的存储位置。
byte_slot:
emit.u8(0)

word_slot:
emit.u16(0)

dword_slot:
emit.u32(0)

qword_slot:
emit.u64(0)

bytes_slot:
db(0, 0, 0)

// 常规求值阶段可以修改已经写出的字节。
store.u8(byte_slot, 0xaa)
store.u16(word_slot, 0x2233)

// 立即读取刚才写入的值，确认小端整数访问正确。
assert(load.u8(byte_slot) == 0xaa)
assert(load.u16(word_slot) == 0x2233)

defer {
    // 布局稳定后，回填其余整数和三字节标记。
    store.u32(dword_slot, 0x44556677)
    store.u64(qword_slot, 0x0102030405060708)
    store.bytes(bytes_slot, b"XYZ")

    // 收尾块能同时看到常规阶段和本收尾块完成的写入。
    assert(load.u8(byte_slot) == 0xaa)
    assert(load.u16(word_slot) == 0x2233)
    assert(load.u32(dword_slot) == 0x44556677)
    assert(load.u64(qword_slot) == 0x0102030405060708)
    assert(load.bytes(bytes_slot, 3) == b"XYZ")
}
```

整数形式只接受其指定宽度能够表示的值。读取和写入必须完全落在最终文件中实际存在的字节范围内。这些操作不会分配存储空间、扩大区域或改变布局。

## 标号与输出区身份

仅有逻辑地址不一定足以确定文件中的字节。两个输出区可以使用相互重叠的逻辑地址范围，同时占用不同的文件范围。

当读取、写入或最终区域信息表达式直接包含标号时，XIRASM 会保留该标号的输出区身份，并把它与逻辑地址结合起来。即使另一个输出区使用相同地址，也能据此选择正确的文件范围。

```asm
// 外层区域从逻辑地址 0x1000 和文件偏移 0 开始。
region.begin("outer", 0x1000, 0)

outer:
emit.u32(0x44332211)
// 尾部预留空间扩大逻辑大小，但不会立即形成文件字节。
reserve(4)

// 新输出区从实际文件游标继续，因此紧接 outer 已写出的四个字节。
output.section("inner", 0x1002)

inner:
emit.u16(0x6655)

defer {
    // 两个标号分别查询各自输出区的最终文件偏移和大小。
    assert(region_file_offset(outer) == 0)
    assert(region_file_size(outer) == 4)
    assert(region_logical_size(outer) == 8)

    assert(region_file_offset(inner) == 4)
    assert(region_file_size(inner) == 2)
    assert(region_logical_size(inner) == 2)

    // inner 与 outer + 2 地址相同，但输出区身份让它们访问不同字节。
    assert(load.u16(inner) == 0x6655)
    store.u16(inner, 0x8877)
    assert(load.u16(inner) == 0x8877)
    assert(load.u16(outer + 2) == 0x4433)
}
```

这里的 `outer + 2` 与 `inner` 具有相同逻辑地址。两个标号保留了不同的输出区身份，因此引用的是不同字节。

普通整数不带输出区身份。如果逻辑地址范围可能重叠，应当在访问表达式中保留标号，不要先把它转换成数值变量或函数参数。

## 最终区域信息

只有布局和最终输出都稳定后，才能使用以下三种最终区域信息；通常应当在 `defer` 中查询：

| 表达式 | 含义 |
| --- | --- |
| `region_file_offset(label)` | 区域在文件中的绝对起始位置，也就是最终文件偏移。 |
| `region_file_size(label)` | 区域最终存在于文件中的字节数，包括文件对齐产生的字节。 |
| `region_logical_size(label)` | 区域占用的逻辑地址范围，包括尾部预留空间。 |

未初始化的预留空间使这一区别十分重要。在前一个示例中，`outer` 的逻辑大小为八字节，文件大小只有四字节。`output.section` 从实际文件游标开始 `inner`，因此四字节尾部预留空间不会写入文件。

这些预留地址仍属于逻辑范围，但不是可以读取或写入的最终输出字节。收尾处理不能通过读取或写入，把已经裁剪的尾部预留空间变成实际输出。

## 地址与范围错误

以下情况会被这些 API 拒绝：

- 整数写入值超出所选宽度能够表示的范围；
- 读取或写入超出实际写入的文件字节范围；
- 访问已经从文件布局中裁剪的尾部预留空间；
- 在最终输出稳定之前查询最终区域信息；
- 最终区域信息查询的地址不属于任何最终逻辑区域；
- 一个标号表达式组合了来自不同输出区的标号。

使用数据写出、预留和区域操作定义布局。读取、写入和最终区域信息只应用于检查或回填布局已经建立的存储空间。

# 第 13 章：Flat 二进制与自定义文件格式

XIRASM 默认输出 flat binary：文件只有指令和数据落盘后的字节，没有操作系统文件头。

flat binary 的用途：

- 引导扇区、固件映像
- ROM 表、嵌入式资源
- 协议消息、测试数据
- 紧凑的资源容器
- 私有二进制格式
- 被其他程序加载的小段可执行代码

flat binary 内部可以有结构。标签标位置，结构体描述记录，区域分开逻辑地址和物理位置，收尾处理根据完整映像推导字段值。

## 原始机器码

ISA 指令就是 flat 文件的全部内容。

```asm
// 选择 64 位 x86 指令编码，输出文件只包含下面两条指令的机器码。
x86.use64();

entry:
    // 把数值 42 写入 eax，然后返回给调用者。
    mov eax, 42
    ret
```

输出：

```text
b8 2a 00 00 00 c3
```

没有文件头、没有入口点字段、没有加载器元数据。`entry` 只是汇编标签。加载这些字节的程序必须知道目标 ISA、指令模式、加载地址和调用约定。

## 用 API 搭文件头

```asm
// 先写出四字节文件标识，再写出两个小端顺序的 16 位头字段。
emit.bytes(b"RAW1");
emit.u16(1);
emit.u16(0);

payload:
// 标号记录数据的逻辑起点，随后写出三个数据字节。
emit.bytes(b"ABC");
```

输出：

```text
52 41 57 31 01 00 00 00 41 42 43
```

前四字节是文件签名，接着两个 `u16` 分别是版本号和保留字段，之后是数据。源文件顺序就是输出顺序，不需要声明格式。

## packed struct 对应记录

二进制记录有命名字段、字段间无对齐间隙时用 `packed struct`。

```asm
// 紧凑结构体按声明顺序连续存放两个 16 位字段。
packed struct ChunkHeader {
    kind: u16
    size: u16
}

// 写出记录头，随后紧接着写出三个字节的记录内容。
emit.struct(ChunkHeader {
    kind: 1,
    size: 3,
});
emit.bytes(b"ABC");
```

输出：

```text
01 00 03 00 41 42 43
```

字段类型和宽度在源码里一目了然。`emit.struct` 按 packed 布局写。文件格式本身要求相同对齐和尾部填充时才用普通 struct。

重复的写出逻辑封装成函数：

```asm
// 每次调用都按“一个字节的标签、四个字节的数值”写出一条记录。
fn emit_record(tag: u8, value: u32) {
    emit.u8(tag);
    emit.u32(value);
}

// 两条记录按照调用顺序连续写入文件。
emit_record(1, 0x11223344);
emit_record(2, 0xaabbccdd);
```

输出：

```text
01 44 33 22 11 02 dd cc bb aa
```

函数保证写出格式一致，输出顺序仍由源文件顺序决定。

## 文件头字段 defer 回填

文件头有些字段（大小、偏移、校验和）要等写完才知道。先占位，defer 里回填。

```asm
// 让本区域的逻辑地址从零开始，便于用标号差表示文件内距离。
origin(0);

magic:
emit.bytes(b"XIF1");
// 先为总大小、数据偏移和校验和各写出一个四字节占位字段。
size_field:
emit.u32(0);
payload_offset_field:
emit.u32(0);
checksum_field:
emit.u32(0);

payload:
emit.bytes(b"OK!!");
payload_end:

defer {
    // 布局稳定后，根据标号回填大小、偏移和前两个数据字节的校验和。
    store.u32(size_field, payload_end - magic);
    store.u32(payload_offset_field, payload - magic);
    store.u32(checksum_field, load.u8(payload) + load.u8(payload + 1));

    // 检查最终文件中的标识和三个回填字段。
    assert(load.bytes(magic, 4) == b"XIF1");
    assert(load.u32(size_field) == 20);
    assert(load.u32(payload_offset_field) == 16);
    assert(load.u32(checksum_field) == 0x9a);
}
```

输出：

```text
58 49 46 31 14 00 00 00 10 00 00 00 9a 00 00 00 4f 4b 21 21
```

回填的值从哪来：

- 两端标签的距离 → 标签相减（如 `payload_end - magic`）
- 当前写出位置 → 写出时 `file_offset()`
- 某段内容在文件中的最终位置 → `defer` 里 `region_file_offset(label)`
- 某段内容的最终大小 → `region_file_size(label)`（文件大小）、`region_logical_size(label)`（逻辑大小）

## 文件偏移≠逻辑地址

文件连续存字节，但可以给它们不同的逻辑地址。

```asm
// 文件头位于文件偏移 0，但它的逻辑地址从 0x1000 开始。
region.begin("header", 0x1000, 0);
emit.bytes(b"HDR0");

// 数据紧接文件头写入文件，但逻辑地址改从 0x2000 开始。
output.section("payload", 0x2000);
payload:
emit.bytes(b"DATA");

defer {
    // payload 正好位于区域起点，因此可用它查询区域的起始文件偏移。
    assert(payload == 0x2000);
    assert(region_file_offset(payload) == 4);
}
```

输出还是 8 字节：

```text
48 44 52 30 44 41 54 41
```

数据区在文件偏移 4，逻辑地址却是 0x2000。这在固件、ROM、内存映像和各种需要描述加载位置的格式里很常见。

不要从逻辑地址推文件偏移，除非格式明确规定了关系。两个值各自独立查询。

## reserve：中间补零，尾部不占空间

`reserve` 在不同位置行为不同：

- 中间间隙（前后都有数据） → 实化为零字节
- 区域尾部 → 只增逻辑大小，不写文件

```asm
// 建立逻辑地址从 0x5000 开始、文件偏移从零开始的映像区域。
region.begin("image", 0x5000, 0);

emit.bytes(b"HDR0");
file_size_field:
emit.u32(0);
logical_size_field:
emit.u32(0);

// 中间三字节空隙会因后续的 0xee 而写入文件，末尾八字节只增加逻辑大小。
emit.u8(0xaa);
reserve(3);
emit.u8(0xee);
reserve(8);

defer {
    // 布局稳定后，分别回填文件大小与逻辑大小。
    store.u32(file_size_field, region_file_size(file_size_field));
    store.u32(logical_size_field, region_logical_size(logical_size_field));

    assert(load.u32(file_size_field) == 17);
    assert(load.u32(logical_size_field) == 25);
}
```

文件只写 17 字节：

```text
48 44 52 30 11 00 00 00 19 00 00 00 aa 00 00 00 ee
```

中间的 3 字节预留因为后续有数据被实化。尾部 8 字节预留只增逻辑大小（25），不占文件空间。

适合 BSS 段等场景：文件只记录已初始化的前缀，剩余空间由加载器提供。

## late_layout 追加尾部

主源码处理完后需要追加字节时用 `late_layout`。

```asm
// 文件开头先为最终大小写出一个四字节占位字段。
total_size:
emit.u32(0);
emit.bytes(b"DATA");

late_layout {
    // 普通源代码处理完成后，把真实尾部加入最终布局。
    emit.bytes(b"END!");
}

defer {
    // 收尾处理能够看到包含尾部在内的最终文件大小。
    store.u32(total_size, region_file_size(total_size));
    assert(load.u32(total_size) == 12);
}
```

输出：

```text
0c 00 00 00 44 41 54 41 45 4e 44 21
```

尾部参与最终布局。`defer` 看到的是完整映像，往已分配的文件头字段写值。

仅在尾部确实需要在主源码之后创建时才用 `late_layout`。普通源文件顺序能表达同样布局时更清晰。

## 断言确认文件正确

自定义写入器应该用断言保证输出可读：

- 签名和版本字段值符合预期
- 偏移指向区域内部
- 计数与写出的记录数一致
- 存的大小与区域最终信息匹配
- 校验和覆盖了正确的字节范围
- 逻辑大小和物理大小符合格式规则

`defer` 里的断言验证实际要写出的字节，包括编码后的指令和已解析的重定位。断言失败停止汇编，不产生文件。

断言紧贴它保护的字段。大小回填和对应的断言通常在同一个 `defer` 块里。

## 自定义格式的组织顺序

小格式的源码组织顺序：

1. 声明记录类型和常量
2. 写出固定头字段（含占位符）
3. 写出数据区
4. 追加真正需要晚出的表或尾部
5. 回填稳定字段并做断言

可重用的 include 封装记录声明和写出函数。格式状态通过参数传递，不在源码里散落硬编码的偏移。

格式变复杂后保持同样分离：

- 源码和函数决定记录内容
- 标签和区域描述布局
- `late_layout` 追加参与最终布局的字节
- `defer` 推导和验证稳定字段

## 标准格式用库

有 flat 输出能力，不等于应该手拼那些标准可执行或目标文件格式。PE、COFF、ELF 还需要文件头、表、权限、导入导出、重定位和加载规则。

XIRASM 提供了 `format/format.inc` 库处理这些。下一章从语言层面介绍用法。完整说明见《可执行文件格式指南》。

[返回目录](../language.md)

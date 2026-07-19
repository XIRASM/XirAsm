# 第 13 章：Flat Binary 与自定义文件格式

XIRASM 默认写出 flat binary。输出文件只包含指令、数据声明、填充和输出区域最终物理化的字节；除非源码显式创建，否则不会自动带上操作系统文件头。

这种直接模型适合：

- 引导扇区、固件映像
- ROM 表、嵌入式资源
- 协议消息、测试数据
- 紧凑的资源容器
- 私有二进制格式
- 被其他程序加载的小段可执行代码

flat binary 仍然可以有丰富的内部结构。标号描述逻辑位置，结构体描述记录，区域分离逻辑坐标和物理坐标，收尾处理根据完整映像推导字段值。

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

这里没有可执行文件头、入口点字段或加载器元数据。`entry` 只是汇编器标号，不是操作系统入口点。加载这些字节的程序必须已经知道目标 ISA、指令模式、加载地址和调用约定。

## 组合文件头与 Payload

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

前四字节是文件签名，第一个 `u16` 存版本号，第二个 `u16` 目前保留，剩下的字节构成 payload。这里不需要特殊的文件格式声明；源文件顺序就是文件顺序。

## 用 Struct 描述记录

当二进制记录需要命名字段、且字段之间没有隐式对齐间隙时，使用 `packed struct`。

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

结构体让字段名和宽度留在源码里，`emit.struct` 会按 packed 表示写出。只有当文件格式本身要求同样的对齐和尾部填充时，才使用普通 struct。

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

过程有助于保持自定义写出逻辑一致，但最终文件仍由普通源码顺序决定。

## 推导文件头字段

不要手工维护偏移、大小和校验和。先写出固定宽度占位字段，给相关数据打上标号，再在 `defer` 中推导最终值：

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

这个示例没有硬编码总大小或 payload 偏移。文件头或 payload 改变时，收尾处理会把新值写回既有字段。由于本例使用一个从 origin 0 开始的紧凑区域，`magic` 起算的逻辑距离同时也是文件内的 payload 相对偏移。

明确区分要存入字段的坐标：

- 格式需要逻辑距离时，使用标号相减；
- 需要当前物理光标时，在写出阶段使用 `file_offset()`；
- 需要某个区域最终物理基址时，在 `defer` 中使用 `region_file_offset(address)`；
- 需要稳定后的最终大小时，使用 `region_file_size(address)` 和 `region_logical_size(address)`。

## 区分逻辑地址与文件偏移

文件可以连续存放字节，同时给这些字节分配完全不同的逻辑地址。

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

物理文件仍然紧凑：

```text
48 44 52 30 44 41 54 41
```

payload 从文件偏移 `4` 开始，但逻辑地址是 `0x2000`。固件、ROM、内存映像以及描述加载位置的格式里经常需要这种区分。

除非格式明确规定二者关系，否则不要从逻辑地址推导文件偏移。应分别查询或记录各自的坐标。

## 表示已初始化间隙和 File-Free 尾部

`reserve` 是否进入文件，取决于后面是否还有已初始化数据：

- 文件中间的间隙会物理化为零字节；
- 连续的预留尾部可以只增加逻辑大小，不出现在文件中。

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

物理文件只有 17 字节：

```text
48 44 52 30 11 00 00 00 19 00 00 00 aa 00 00 00 ee
```

中间的 3 字节预留因为后面还有已初始化数据而物理化。最后 8 字节预留只把逻辑大小增加到 25，不增加文件字节。

这适合零初始化存储等场景：文件记录已初始化前缀，剩余逻辑空间由加载器或消费程序提供。

## Late Layout：追加尾部或放置晚生成表

只有真实尾部必须追加，或表、字符串池、重定位记录这类内容必须等普通源码处理完后才能创建/放置时，才使用 `late_layout`。

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

追加的尾部会参与最终布局。`defer` 看到完整映像，并修补已经分配好的文件头字段。

只有这些追加字节确实必须晚于主源码创建时，才使用 late layout。普通源码顺序能够表达同样布局时，普通顺序更清楚。

如果 `late_layout` 里只调用 `emit.*`，它就是在默认输出尾部继续写；这也是最简单、最常见的尾部追加。若晚生成内容属于某个自定义表区或节数据区，应在块里显式 `region.begin(name, origin, file_offset)`，把后续字节放入那个真实区域。

这解决的是“布局尚未封存前创建真实字节”的问题，不是最终映像里的随机插入。已经物理化且位置固定的字段，用 `defer` 回填；缺少的变长表、字符串池、重定位记录等，必须在普通源码或 `late_layout` 中创建，然后再由 `defer` 回填指针、大小和校验。

构造类似 PE section 的自定义区域时要分清两层：

- `region.begin` 的名称只是 XIRASM 的布局区域名，不会自动生成 PE section 表项；
- 如果只是往当前文件尾部补一张表，直接尾部 `emit.*` 就够；
- 如果要把晚生成表放到数据区或某个中间文件偏移，必须显式切换到那块区域，并确保它不和已有文件范围冲突；
- 如果字段已经在头部预留，只需要最终值，使用 `defer`，不要用 `late_layout` 重新造空间；
- 标准 PE/COFF/ELF 优先使用格式接口，让接口维护 section/segment 表、raw pointer、virtual size 和回填字段。

## 断言确认文件正确

自定义写入器应该用断言保证输出可读：

- 签名和版本字段值符合预期
- 偏移指向区域内部
- 计数与写出的记录数一致
- 存的大小与区域最终信息匹配
- 校验和覆盖了正确的字节范围
- 逻辑大小和物理大小符合格式规则

`defer` 中的断言验证将要写出的精确字节，包括已编码指令和已解析 fixup。断言失败会停止汇编，避免产出看似有效但实际不合法的文件。

断言紧贴它保护的字段。大小回填和对应的断言通常在同一个 `defer` 块里。

## 自定义格式的组织顺序

小格式的源码组织顺序：

1. 声明记录类型和常量
2. 写出固定头字段（含占位符）
3. 写出数据区
4. 追加真正需要晚出的表或尾部
5. 回填稳定字段并做断言

可复用 include 可以封装记录声明和写出过程。格式状态应通过参数和值显式传递，不要把互不相关的硬编码偏移散落在源码里。

格式变复杂后保持同样分离：

- 源码和过程决定有哪些记录
- 标签和区域描述布局
- `late_layout` 创建必须参与最终布局的字节
- `defer` 推导并验证稳定字段

## 何时使用格式接口

不要因为 flat 写出器能够表达字节，就手工拼标准可执行文件或目标文件格式。PE、COFF、ELF 还需要协调文件头、表、权限、导入、导出、重定位和加载器规则。

XIRASM 为这些任务提供面向用户的格式接口。语言指南只介绍它们的角色；普通接口的完整示例见[《格式教程》](../format-tutorial.md)，需要直接构造底层格式结构时再看[《高级格式构造指南》](../../advanced-formats.md)。

[返回目录](../language.md)

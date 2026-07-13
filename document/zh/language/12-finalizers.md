# 第 12 章：收尾处理

二进制文件中的许多字段在首次写入时尚无法获得最终值。例如：

- 稍后才声明的数据区大小；
- 另一区域的文件偏移；
- 预留区域的最终逻辑大小；
- 对编码指令和已修补修正值的校验和；
- 由头文件后方的源码累加得到的计数。

XIRASM 通过显式的收尾处理阶段处理这些情况，而无需反复执行整个源文件。

该阶段提供两种工具：

- `late_layout` 在映像封存前执行受限的布局变更操作；
- `defer` 在不改变布局的前提下读取并修补已稳定的最终映像。

用户编写的回填操作应位于 `defer` 中。

## 为回填预留字段

标准流程如下：

1. 写入固定宽度的占位值；
2. 正常写入数据；
3. 在 `defer` 中修补占位字段。

```asm
// 先用两个字节为数据大小预留位置。
size_field:
emit.u16(0);

// 写出实际数据，并用前后标号确定它的长度。
payload:
emit.bytes(b"ABC");
payload_end:

defer {
    // 布局稳定后，把数据长度回填到预留字段。
    store.u16(size_field, payload_end - payload);
}
```

最终输出：

```text
03 00 41 42 43
```

占位字段已占据两字节，收尾处理仅修改其值，不插入字节，也不移动数据区。

顶层的收尾处理块可在其引用的标签之前声明：

```asm
defer {
    // 这些标号可以在收尾块之后定义，最终执行时会得到稳定地址。
    store.u16(size_field, payload_end - payload);
}

// 为数据长度预留两个字节。
size_field:
emit.u16(0);

// 随后写出实际数据。
payload:
emit.bytes(b"ABC");
payload_end:
```

当稳定映像可用时，标签已解析完成。

## 读取最终映像

`load.u8`、`load.u16`、`load.u32` 和 `load.u64` 从已落盘的输出字节中读取小端整数。`load.bytes(address, count)` 返回字节范围。

这些读取操作可与存储和断言组合使用：

```asm
// 让本区域的逻辑地址从 0x4000 开始。
origin(0x4000);

// 预留两个 32 位文件头字段。
header:
emit.u32(0);
emit.u32(0);

// 写出正文和一个稍后替换的尾部标记。
body:
emit.bytes(b"ABCD");
tail:
emit.bytes(b"????");
image_end:

defer {
    // 回填正文到输出末尾的长度，以及正文相对区域起点的位置。
    store.u32(header, image_end - body);
    store.u32(header + 4, body - region_base());
    store.bytes(tail, b"OK!!");

    // 读取最终字节，确认回填结果符合预期。
    assert(load.u32(header) == 8);
    assert(load.u32(header + 4) == 8);
    assert(load.bytes(tail, 4) == b"OK!!");
}
```

完成后的字节：

```text
08 00 00 00 08 00 00 00 41 42 43 44 4f 4b 21 21
```

`store.bytes` 接受字符串或 `bytes` 值。整数存储会拒绝超出目标宽度的值。

所有加载和存储均进行范围检查。收尾处理只能访问物理映像中实际存在的字节。位于已裁掉的尾部预留中的逻辑地址不可写，将被拒绝。

## 计算校验和

收尾处理可声明局部值、更新可变值并使用 `while`：

```asm
// 使用固定逻辑起点，便于按标号读取数据。
origin(0x5000);

// 先为 16 位校验和预留位置。
checksum:
emit.u16(0);

// 写出参与校验和计算的数据。
payload:
emit.bytes(b"ABCD");
payload_end:

defer {
    // 逐字节读取最终数据并累加。
    let cursor = payload
    let sum = 0

    while cursor < payload_end {
        sum = sum + load.u8(cursor)
        cursor = cursor + 1
    }

    // 回填校验和，并立即检查写入结果。
    store.u16(checksum, sum);
    assert(load.u16(checksum) == 266);
}
```

校验和为 `266`（即 `0x010a`），输出：

```text
0a 01 41 42 43 44
```

收尾处理中的循环使用与普通 Meta 循环相同的编译期迭代限制。`for` 目前不允许在收尾处理中使用；字节扫描应使用有界的 `while` 循环。

## 使用稳定的区域信息

第 11 章介绍的最终区域查询可在 `defer` 中使用：

```asm
// 创建逻辑起点为 0x5000、文件起点为 0 的输出区域。
region.begin("payload", 0x5000, 0);

// 为区域的文件大小和逻辑大小预留字段。
file_size_field:
emit.u32(0);
logical_size_field:
emit.u32(0);

// 写出一个实际字节，再追加三个只占逻辑空间的预留字节。
body:
emit.u8(0xaa);
reserve(3);

defer {
    // 布局稳定后查询正文所在区域，并回填最终大小。
    store.u32(file_size_field, region_file_size(body));
    store.u32(logical_size_field, region_logical_size(body));

    // 文件大小不包含未实际写出的预留尾部，逻辑大小包含它。
    assert(region_file_offset(body) == 0);
    assert(region_file_size(body) == 9);
    assert(region_logical_size(body) == 12);
}
```

预留尾部计入逻辑大小，但不计入文件大小：

```text
09 00 00 00 0c 00 00 00 aa
```

这些查询返回包含指定逻辑地址的区域信息：

- `region_file_offset(address)` 返回区域的物理基偏移；
- `region_file_size(address)` 返回最终的实体化大小；
- `region_logical_size(address)` 返回完整的地址空间大小。

它们需要稳定的布局，因此在初始写出阶段不充当实时的游标查询。

## 调用值函数

返回值的 Meta 函数可用于纯粹的最终计算：

```asm
// 计算不小于 value 且满足指定对齐要求的数值。
fn align_up(value: u64, alignment: u64) -> u64 {
    return ((value + alignment - 1) / alignment) * alignment;
}

// 为对齐后的数据大小预留字段。
size_field:
emit.u32(0);

payload:
emit.bytes(b"ABC");
payload_end:

defer {
    // 把三字节数据向上对齐到八字节，并回填计算结果。
    store.u32(size_field, align_up(payload_end - payload, 8));
    assert(load.u32(size_field) == 8);
}
```

最终输出：

```text
08 00 00 00 41 42 43
```

该函数仅执行表达式运算，不自行写出或修补字节。

## 可复用的回填过程

过程可以注册收尾处理块并捕获其参数：

```asm
// 登记一个稍后写入 16 位整数的收尾块。
fn patch_u16(address: u64, value: u64) {
    defer {
        // address 和 value 保存的是调用过程函数时传入的值。
        store.u16(address, value);
    }
}

// 先写出占位字段，再登记对应的回填操作。
field:
emit.u16(0);

patch_u16(field, 0x1234);
```

调用在普通源码处理过程中执行。其参数值被冻结在收尾处理块中，后者随后写出：

```text
34 12
```

此模式适用于小型的、带类型的回填辅助函数。作用域内的过程参数按值冻结。顶层的收尾处理表达式可保持符号状态直至最终求值。

过程并不是在 `defer` 内部调用；过程调用在更早的阶段注册了收尾处理块。

## 收尾处理的控制流

`defer` 体内可包含：

- `const` 和 `let` 声明；
- 对局部 `let` 值的赋值；
- `if` 和 `else`；
- `while`；
- `store.u8`、`store.u16`、`store.u32`、`store.u64` 和 `store.bytes`；
- `assert`、`print`、`warn` 和 `err`。

上述语句中的表达式可使用普通的纯运算符和值函数、标签、`load.*` 以及稳定的区域信息。

每个收尾处理块拥有独立的局部作用域。在一个块中声明的局部变量在另一个块中不可见。

以下操作因会改变布局而被拒绝：

```text
defer {
    emit.u8(0x22);
}
```

相同的限制适用于 ISA 指令、标签、区域切换、对齐、预留、嵌套的收尾处理块、函数声明和源文件加载。

## 收尾处理的执行顺序

收尾处理块按注册顺序执行：

```asm
// 先写出一个稍后会被连续修改的字节。
emit.u8(0);

defer {
    // 第一个收尾块把初始值改为 1。
    store.u8(0, 1);
}

defer {
    // 第二个收尾块能看到前一次修改，因此最终写入 2。
    store.u8(0, load.u8(0) + 1);
}
```

第二个块可观察到第一个块的修补结果，输出：

```text
02
```

应审慎利用此顺序。当两个收尾处理块修改相同的字节时，后执行的块可看到前一个块的结果。

收尾处理块在以下步骤之后执行：

1. 普通源码处理；
2. 指令编码；
3. 后期布局工作；
4. 修正值解析；
5. 最终布局和字节落盘；
6. 修正值修补。

因此，它们看到的是将被实际写入的精确映像，包括已编码的指令和已解析的引用。

## 必须延迟执行的布局工作

有时源文件必须在主源码完成内容注册后才追加实际字节。这是 `late_layout` 的职责：

```asm
// 正常源代码先写出第一个字节。
emit.u8(0x10);

late_layout {
    // 后期布局块按照登记顺序追加实际字节。
    emit.u8(0x20);
}

late_layout {
    emit.u8(0x30);
}
```

后期布局块按注册顺序执行一次，从默认输出区域的末尾开始。示例输出：

```text
10 20 30
```

后期布局在修正值解析和最终布局之前完成。其写出的字节参与最终布局和落盘。

## 后期布局可将尾部预留实体化

由于 `late_layout` 仍可改变布局，追加的已初始化字节可将先前的尾部预留转化为中间间隙：

```asm
// 写出一个字节，并在逻辑地址中预留三个字节。
emit.u8(0xaa);
reserve(3);

late_layout {
    // 在预留空间之后追加实际字节，使中间空隙进入输出文件。
    emit.u8(0xbb);
}
```

最终输出：

```text
aa 00 00 00 bb
```

仅在预留范围确实需要变为物理字节时使用此行为。如果尾部应保持无文件状态，应在注册后续已初始化输出之前切换到另一区域。

## 组合后期布局与最终回填

收尾处理块可看到后期布局期间追加的字节：

```asm
// 为整个区域的最终逻辑大小预留字段。
size_field:
emit.u32(0);

// 正常源代码先写出前两个数据字节。
emit.bytes(b"AB");

late_layout {
    // 后期布局再追加两个会参与最终大小计算的字节。
    emit.bytes(b"CD");
}

defer {
    // 根据稳定后的区域大小回填字段，并检查实际文件大小。
    store.u32(size_field, region_logical_size(size_field));
    assert(region_file_size(size_field) == 8);
}
```

稳定后的区域包含四字节字段加四字节数据：

```text
08 00 00 00 41 42 43 44
```

这是预期的职责划分：

- `late_layout` 创建须参与布局的字节；
- `defer` 观察最终的布局并修补现有字段。

## 后期布局的限制

`late_layout` 比普通源码的范围窄。它接受布局和输出 API 调用、诊断和 `if` 选择。它可以：

- 写出整数、字节和结构体；
- 预留、填充和对齐；
- 切换或对齐输出区域；
- 打开和关闭虚拟区域；
- 存储到现有的模块字节中。

它不能声明标签、写出 ISA 指令文本、声明局部值、循环、定义函数、加载源模块，或注册嵌套的后期/收尾处理块。

后期布局仅执行一次。它不是隐式的多遍机制，不应被用于反复收敛不稳定的值。

## 选择正确的pass阶段

字节可在正常源码顺序中写出时，使用普通源码。

使用 `late_layout` 的场景：

- 必须在主源码完成后追加实际字节或区域；
- 这些字节必须影响最终的偏移和大小；
- 受限的一次性后期布局步骤已足够。

使用 `defer` 的场景：

- 固定宽度的占位字段需要最终值；
- 校验和或验证需要完整的字节映像；
- 需要最终的区域大小或偏移；
- 必须修补现有字节且不改布局。

切勿使用 `defer` 创建缺失的空间。在收尾处理之前预留或写出所需的存储，然后仅修补该现有范围。

下一章进入第三部分，介绍 flat 和自定义二进制文件：将标签、结构体、区域、后期布局和收尾处理组合为完整的文件格式。

## 第三部分：构建程序

[返回目录](../language.md)

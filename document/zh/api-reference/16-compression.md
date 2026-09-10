# 压缩

## 语法总览

| 函数 | 结果 | 说明 |
| --- | --- | --- |
| `deflate.compress(input)` | `bytes` | 按默认级别压缩。 |
| `deflate.compress(input, level)` | `bytes` | 按 1（最快）到 9（最小）的级别压缩。 |
| `deflate.decompress(input)` | `bytes` | 解压裸 DEFLATE 流。 |

`input` 接受 `bytes` 值或 `string`，字符串按其字节序列参与压缩。结果是
**裸 DEFLATE** 流：只有压缩块本身，没有 zlib 或 gzip 头，也没有校验尾。ZIP
的 method 8 条目存的就是它，所以归档里记的 CRC-32 是**未压缩**数据的校验值，
两种形态的尺寸也各记一份。

```asm
const text: bytes = b"XIRASM XIRASM XIRASM XIRASM"
const packed: bytes = deflate.compress(text)
const best: bytes = deflate.compress(text, 9)

assert(len(packed) < len(text));
assert(len(best) < len(text));
emit.u16(len(text));
emit.u16(len(packed));
```

压缩是确定性的：同样的输入与级别每次产出相同的流，格式库因此能构造可复现的
归档。小载荷可能略微变大，因为流自带块头；压不小的载荷就按未压缩存。

级别是时间与体积的取舍。默认级别是 6，适合汇编器存放的载荷；级别 1 适合体积
大又压不动的输入，级别 9 适合不在乎汇编时间、只求最小输出的场合。

`deflate.decompress` 是逆操作，用来读回本工程压出的流，或数据文件里带的流：

```asm
const packed: bytes = deflate.compress(text)
const restored: bytes = deflate.decompress(packed)

assert(bytes.eq(restored, text));
```

裸流里没有长度字段，所以解码器一直读到流的最后一个块，返回它解出的全部内容；
提前结束或自相矛盾的流会报"实参非法"，而不是给出半截结果。又因为压缩流能膨胀
得远大于自身体积，解压到 256 MiB 就停止并报"输出过大"，不会把小输入变成吃掉整台
机器的内存。

## 错误条件

- 实参既不是 `bytes` 值也不是 `string`；
- 级别不在 1 到 9 之间；
- 输入不是合法 DEFLATE 流，或解出的内容超过 256 MiB；
- 实参数量不正确。

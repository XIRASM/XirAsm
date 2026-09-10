# 加密校验与摘要

## 语法总览

| 函数 | 结果 | 说明 |
| --- | --- | --- |
| `crypto.crc32(input)` | integer | 计算 CRC-32（IEEE 802.3）校验值。 |
| `crypto.adler32(input)` | integer | 计算 Adler-32 校验值（RFC 1950）。 |
| `crypto.sha1(input)` | `bytes` | 计算 20 字节 SHA-1 摘要。 |
| `crypto.sha256(input)` | `bytes` | 计算 32 字节 SHA-256 摘要。 |

`input` 接受 `bytes` 值或 `string`，字符串按其字节序列参与计算。这些助手
都是纯表达式调用，可出现在任何值表达式位置，包括 defer 终局块内部。

校验类助手返回无符号整数；摘要类助手返回新的字节序列。

```asm
const payload: bytes = b"123456789"
const crc: u64 = crypto.crc32(payload)
const digest: bytes = crypto.sha256(payload)

assert(crc == 0xcbf43926);
assert(len(digest) == 32);

emit.u32(crc);
emit.bytes(digest);
```

计算以原生速度执行。请使用这些助手代替 Meta 编写的校验循环；兆字节级
载荷立即完成，不再把编译时间花在逐字节扫描上。

## 错误条件

- 实参既不是 `bytes` 值也不是 `string`；
- 实参数量不正确。

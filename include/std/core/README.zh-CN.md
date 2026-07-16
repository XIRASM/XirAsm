# XIRASM std/core memory

`std/core` 是 XIRASM 的实验性底层扩展库，用于生成可被更高层标准库复用的
x86-64 运行时原语。当前版本提供 memory 第一批 correctness baseline，API
和实现仍可能在后续版本调整，不代表最终性能最优版本。

## 当前功能

- `std_memory_copy`：复制不重叠内存。
- `std_memory_move`：复制允许重叠的内存。
- `std_memory_fill`：用指定值的低 8 位填充内存。
- `std_memory_compare`：按第一个不同的无符号字节比较两个范围。

所有入口支持 System V AMD64 和 Windows x64。两端生成的运行时标签相同，
参数寄存器遵循各自平台 ABI。

## 生成入口

导入模块不会立即写入运行时代码。请在可执行文本区域中调用一次 emitter：

```asm
import("std/core.inc");
x86.use64();

// 在 ELF64 文本区域中：
std_memory_emit(std_core_abi_sysv64);
```

Windows x64 使用：

```asm
std_memory_emit(std_core_abi_windows64);
```

emitter 会生成四个固定标签。不要在同一个输出中重复调用，否则固定标签会
产生重复定义诊断。

## 参数与返回

System V AMD64：

| 入口 | RDI | RSI | RDX | 返回 |
| --- | --- | --- | --- | --- |
| `std_memory_copy` | dst | src | count | RAX=dst |
| `std_memory_move` | dst | src | count | RAX=dst |
| `std_memory_fill` | dst | value | count | RAX=dst |
| `std_memory_compare` | left | right | count | RAX=-1/0/1 |

Windows x64：

| 入口 | RCX | RDX | R8 | 返回 |
| --- | --- | --- | --- | --- |
| `std_memory_copy` | dst | src | count | RAX=dst |
| `std_memory_move` | dst | src | count | RAX=dst |
| `std_memory_fill` | dst | value | count | RAX=dst |
| `std_memory_compare` | left | right | count | RAX=-1/0/1 |

Windows 调用方仍应按 ABI 为 `call` 提供 shadow space。当前入口是 leaf，不会
使用调用方的 shadow space，也不会调用其他函数。

## 安全契约

- `count=0` 时不读取或写入参数指针。
- `copy` 要求源和目标不重叠；需要重叠语义时使用 `move`。
- 非零长度要求完整输入和输出范围均有效。
- 默认实现不会读取范围末尾之后的字节，也不会跨页探测尾部。
- `compare` 只承诺返回值的正负关系，不承诺返回两个字节的算术差。
- 入口不取得缓冲区所有权，不分配内存，不使用栈或 red zone。

## 实现层级

`std_memory_emit(...)` 当前生成 x86-64 SSE2 baseline。它使用未对齐安全的
16 字节访问和精确 scalar 尾部，不要求缓冲区对齐。

用于验证和测量时，可以显式选择 scalar：

```asm
std_memory_emit_tier(std_core_abi_sysv64, std_core_memory_tier_scalar);
```

当前版本尚未提供：

- x86-32；
- CPU feature/runtime dispatch；
- AVX2；
- AVX-512；
- REP 或 non-temporal 大块策略；
- CPU 型号相关阈值。

这些功能只有在 ABI、安全和真机性能数据稳定后才会逐批加入。

# XIRASM std/core

`std/core` 是 XIRASM 的实验性底层扩展库，用于生成可被更高层标准库复用的
x86-64 运行时原语。当前版本提供 memory correctness baseline，以及实验性的
CPU feature 与 runtime dispatch 基础。API 和实现仍可能在后续版本调整，
不代表最终性能最优版本。

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

调用方能够保证 CPU 与 OS 已启用 AVX2/YMM 状态时，可以固定生成 AVX2：

```asm
std_memory_emit_tier(std_core_abi_sysv64, std_core_memory_tier_avx2);
```

固定 AVX2 不执行运行时能力检查。在通用二进制中应使用 runtime 模式：

```asm
// 在可执行文本区域中各调用一次。
std_cpu_emit(std_core_abi_sysv64);
std_memory_emit_runtime(std_core_abi_sysv64, "memory_runtime_state");

// 在可写数据区域中提供至少 8 字节对齐的全零状态。
memory_runtime_state:
    rq(8);
```

runtime state 共 64 字节，copy、move、fill、compare 依次使用 offset 0、16、32、
48 的四个 16 字节子状态。公开 offset 与 size 常量以
`std_memory_runtime_*_state_offset` 和 `std_memory_runtime_state_size` 命名。
每个入口首次调用时独立选择 SSE2 或 AVX2，之后直接使用缓存目标指针。

AVX2 主循环使用未对齐安全的 32 字节访问，尾部按 16/8/4/2/1 精确处理，
不会读取或写入范围末尾之外。所有 AVX2 返回路径执行 `vzeroupper`；SSE2
baseline 不执行 VEX/YMM 指令。`vzeroupper` 会清空全部 YMM 寄存器的高
128 位；这些高半部在 System V AMD64 和 Windows x64 中均不属于需保留状态。

AVX2 temporal copy 在 4096 字节及以上检查 low-12-bit 地址关系。对于明确
不重叠的 copy，源未按 32 字节对齐且源/目标低 12 位接近下一页时，内核改为
后向复制以降低 4 KiB alias 假依赖风险。普通 temporal 路径仍使用紧凑的
未对齐循环；双端基准没有证明强制目标对齐或循环展开能普遍获益。达到显式
non-temporal 阈值时优先进入 streaming 路径，不再做 temporal alias 逆向选择。
该逆向选择不会用于允许重叠的 move；move 方向始终只由重叠语义决定。

默认不启用 non-temporal store。调用方已经根据目标机器和数据生命周期完成
基准时，可以显式设置阈值：

```asm
// 固定 AVX2；本程序选择 32 MiB 作为显式、保守的示例阈值。
std_memory_emit_tier_tuned(
    std_core_abi_sysv64,
    std_core_memory_tier_avx2,
    32 * 1024 * 1024
);

// runtime dispatch 使用相同阈值；仍需另行生成 std_cpu_emit。
std_memory_emit_runtime_tuned(
    std_core_abi_sysv64,
    "memory_runtime_state",
    32 * 1024 * 1024
);
```

阈值 `0` 表示禁用，其他值必须至少为 4096。non-temporal 路径只作用于 AVX2
copy，目标先对齐到 32 字节，使用 `vmovntdq`，并在 temporal 尾部和返回前执行
`sfence`。它不用于 move/fill/compare。当前双端基准没有证明统一默认阈值，
因此该能力保持显式 opt-in；示例中的 32 MiB 不是跨 CPU 推荐值。将很快重读的
目标数据写入缓存时通常不应启用。

当前 AVX2 仍是实验性 correctness tier。runtime 在支持主机上按 feature 选择
AVX2；大块 copy 有固定 4096 字节 alias 检查边界，但不包含 CPU 型号或自动
缓存容量探测，不能据此认为每个长度都比 SSE2 更快。

当前版本尚未提供：

- x86-32；
- AVX-512；
- REP 自动策略；
- 自动缓存容量探测或默认 non-temporal 阈值；
- CPU 型号相关阈值。

这些进一步优化只有在 ABI、安全和真机性能数据稳定后才会逐批加入。

## CPU feature

在可执行文本区域中调用一次：

```asm
std_cpu_emit(std_core_abi_sysv64);
```

Windows x64 改用 `std_core_abi_windows64`。该 emitter 生成：

| 入口 | 用途 | 返回 |
| --- | --- | --- |
| `std_cpu_query` | 查询原始 CPUID leaf/subleaf | `RAX=16 字节结果记录地址` |
| `std_cpu_classify` | 从 24 字节 snapshot 计算 feature | `RAX=feature mask` |
| `std_cpu_detect` | 检测当前主机 CPU 与 OS 状态 | `RAX=feature mask` |
| `std_cpu_features_cached` | 原子读取或初始化 feature cache | `RAX=feature mask` |

feature mask 使用独立具名位，不使用单调“指令集等级”：

- `std_cpu_feature_sse2`
- `std_cpu_feature_popcnt`
- `std_cpu_feature_avx`
- `std_cpu_feature_osxsave`
- `std_cpu_feature_avx2`
- `std_cpu_feature_erms`

`std_cpu_feature_avx` 只有在 CPU 报告 AVX 与 OSXSAVE，且 XCR0 已启用
XMM/YMM 状态时才置位。`std_cpu_feature_avx2` 还要求 CPUID leaf 7 的 AVX2
能力。仅检查 CPUID.AVX2 不足以安全执行 AVX2 指令。

24 字节 snapshot 依次包含 `max_basic_leaf`、leaf 1 ECX、leaf 1 EDX、
leaf 7 EBX、XCR0 EAX、XCR0 EDX 六个 u32。对应公开 offset 和 size 常量定义在
`std/core/contract.inc`。该布局适合测试注入和离线判定，不替代本机检测入口。

`std_cpu_query` 的参数：

| ABI | leaf | subleaf | 输出记录 |
| --- | --- | --- | --- |
| System V AMD64 | RDI | RSI | RDX |
| Windows x64 | RCX | RDX | R8 |

输出记录依次包含 EAX、EBX、ECX、EDX 四个 u32。调用方负责提供至少 16 字节
可写存储，并保证查询的 leaf/subleaf 符合自身用途。

`std_cpu_features_cached` 接收一个调用方拥有的 8 字节缓存地址：System V
使用 RDI，Windows 使用 RCX。缓存必须至少 8 字节对齐、可写、初始为 0，且
生命周期覆盖所有并发调用。实现使用原子发布，允许真实 feature mask 为 0。

## Runtime dispatch

`std_dispatch_emit_avx2(...)` 为最多三个整数参数的函数族生成一个调度入口：

```asm
std_dispatch_emit_avx2(
    std_core_abi_sysv64,
    std_core_dispatch_runtime,
    "public_entry",
    "dispatch_state",
    "baseline_target",
    "avx2_target"
);
```

模式：

- `std_core_dispatch_baseline`：直接尾跳 baseline 目标。
- `std_core_dispatch_fixed_avx2`：直接尾跳 AVX2 目标，调用方保证运行环境支持。
- `std_core_dispatch_runtime`：首次调用检测 feature，并原子缓存目标函数指针。

runtime 模式下，`dispatch_state` 是调用方提供的 16 字节可写状态，至少 8 字节
对齐并初始化为全 0。偏移 0 保存内部 feature cache，偏移 8 保存目标函数指针。
baseline 和 fixed AVX2 模式不会读取该状态。实现不会修改代码页，也不会根据
CPU 品牌选择正确性路径。

调度器只保证原样转发前三个整数参数：System V 的 RDI/RSI/RDX，Windows 的
RCX/RDX/R8。目标函数必须使用相同 ABI、参数和返回契约。需要更多参数、浮点或
向量参数的函数族应使用专门调度器，不能套用本入口。

AVX2 目标函数负责在返回未知调用方或调用 legacy SSE 代码前执行正确的
`vzeroupper`；调度器本身不执行 YMM 指令，也不能代替目标处理该边界。

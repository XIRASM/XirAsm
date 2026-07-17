# XIRASM std/core Test Suite

本目录验证 `include/std/core/` 的运行时基础原语。测试按正式实现模块分组，
不与编译器、格式、IO 或操作系统声明测试混放。

当前模块：

```text
tests/std/core/memory/
tests/std/core/cpu/
```

每个正式实现必须同时通过 ReleaseFast 汇编、独立反汇编、Windows 原生和
WSL 真机运行。性能候选只有在 correctness、ABI 和页边界测试通过后才可加入。

`cpu/` 额外覆盖人工 feature snapshot、CPUID/XGETBV、三种调度模式以及
Windows CreateThread 与 Linux CLONE_VM 的 8 路并发首次发布。

`memory/` 覆盖 scalar、SSE2、fixed AVX2 与 runtime dispatch。AVX2/runtime
分别在 Windows 与 WSL 运行 functional、guard-page 和长度/模 32 对齐/重叠
sweep；fixed AVX2 不支持时以退出 77 明确报告跳过，而不是伪装成通过。

`memory/*-large-benchmark.asm` 另外动态分配约 72 MiB，先运行 4097 字节的
32x32 源/目标对齐 correctness 矩阵，再比较 SSE2、compact AVX2、large
temporal 和显式 NT-8MiB。计时覆盖 4 KiB、64 KiB、1/8/16/24/32 MiB 与
三种 low-12-bit 地址关系；near-4K case 验证反向 temporal alias 规避，
显式 NT target 达到阈值后优先验证 streaming store；另一个 threshold=4096 的
32x32 correctness 矩阵覆盖全部目标对齐前缀。
每个 case 之后完整逐字节比较并检查范围外哨兵。周期结果用于人工评估，不是
跨机器发布硬门禁。

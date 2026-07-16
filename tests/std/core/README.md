# XIRASM std/core Test Suite

本目录验证 `include/std/core/` 的运行时基础原语。测试按正式实现模块分组，
不与编译器、格式、IO 或操作系统声明测试混放。

当前第一批：

```text
tests/std/core/memory/
```

每个正式实现必须同时通过 ReleaseFast 汇编、独立反汇编、Windows 原生和
WSL 真机运行。性能候选只有在 correctness、ABI 和页边界测试通过后才可加入。

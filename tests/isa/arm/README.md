# tests/isa/arm — A64 DSL 编码层测试

`include/arm/arm64.inc` 的测试。该层用 Meta/DSL 以数据字形式发射 A64 指令
（`emit.u32` 小端词），不经过任何 ISA 后端，因此测试通过 `xir` 直接运行，
不接入 build.zig fixture。

## 运行方式

```sh
xir tests/isa/arm/arm64-m0-basics.asm -o out0.bin
xir tests/isa/arm/arm64-m1-branches.asm -o out1.bin
```

正向测试是自校验的：每条指令发射后，`defer` 内用 `load.u32` + `assert`
对照期望编码字，汇编成功即全部断言通过。

负向测试位于 `negative/`，每个文件断言一种拒绝行为，运行必须报错：

```sh
xir tests/isa/arm/negative/arm64-movz-imm-overflow.asm -o out.bin
# error: move-wide imm16 does not fit its field width
```

注意：需从仓库根目录用相对/绝对路径运行；在 `negative/` 目录内以裸文件名
运行会因项目根定位失败报 `IncludeNotAvailable`。

## 验证方法学

期望编码字有三重来源，出处在测试与 include 注释中逐条引用：

1. LLVM MC fixture 黄金向量（`llvm/test/MC/AArch64/`，如
   `basic-a64-instructions.s`、`arm64-branch-encoding.s`）；
2. 由 ARM ARM 字段布局手工推导的派生形式（位移、寄存器组合）；
3. radare2 独立反汇编抽查（`r2 -q -n -a arm -b 64 -c "pd N" out.bin`）。

## 覆盖状态

实现进度与 ISA 族缺口由实现 agent 的台账维护（里程碑索引：M0 骨架 / M1 分支 /
M2 核心整数 / M3 条件与进位已完成；M4 访存寻址为下一里程碑）：

- 进度台账维护家族清单、MC 向量引用和差集明细；内部规划文件不属于产品发布内容。
- 本目录测试与台账的对应关系：每个 `arm64-m*.asm` 对应一个里程碑，
  `negative/` 按族归档拒绝行为。

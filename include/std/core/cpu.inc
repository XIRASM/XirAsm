// XIRASM std/core x86-64 CPU feature 公共门面。
//
// 导入只声明 Meta/DSL emitter。调用方在可执行文本区域调用 std_cpu_emit(abi)
// 一次，生成 query、classify、detect 和 features_cached 四个固定运行时入口。

import("contract.inc");
import("x86_64/cpu.inc");

// 生成 CPU feature 运行时入口。
// 编译期参数：abi=std_core_abi_sysv64 或 std_core_abi_windows64。
// 运行时输入、返回、错误、所有权、寄存器和栈契约见各入口中文注释。
// 布局：调用位置必须在可执行区域；重复调用会产生固定标签重复定义诊断。
// ISA：生成 baseline x86-64、CPUID、XGETBV 和 LOCK CMPXCHG，不生成 AVX 指令。
fn std_cpu_emit(abi: string) {
    std_core_assert_x86_64();
    std_core_assert_abi(abi);
    std_core_cpu_emit_query(abi);
    std_core_cpu_emit_classify(abi);
    std_core_cpu_emit_detect();
    std_core_cpu_emit_cached(abi);
}

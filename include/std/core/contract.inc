// XIRASM std/core 的公共编译期契约。
//
// ABI 和实现层级使用具名字符串，避免把平台选择或 ISA 等级编码成难以
// 审查的数字。当前第一批只支持 x86-64 scalar 与 SSE2 baseline。

const std_core_abi_sysv64: string = "sysv64"
const std_core_abi_windows64: string = "windows64"

const std_core_memory_tier_scalar: string = "scalar"
const std_core_memory_tier_sse2: string = "sse2"

const std_memory_copy_symbol: string = "std_memory_copy"
const std_memory_move_symbol: string = "std_memory_move"
const std_memory_fill_symbol: string = "std_memory_fill"
const std_memory_compare_symbol: string = "std_memory_compare"

// 拒绝非 64 位目标；不生成运行时代码，不改变寄存器或布局。
fn std_core_assert_x86_64() {
    assert(target.bits == 64, "std/core memory currently supports x86-64 only");
}

// 校验 memory emitter 的编译期 ABI 选择；非法值在汇编期停止。
fn std_core_assert_memory_abi(abi: string) {
    assert(
        abi == std_core_abi_sysv64 || abi == std_core_abi_windows64,
        "std/core memory ABI must be sysv64 or windows64"
    );
}

// 校验第一批实现层级；当前只接受 scalar 和 x86-64 baseline SSE2。
fn std_core_assert_memory_tier(tier: string) {
    assert(
        tier == std_core_memory_tier_scalar || tier == std_core_memory_tier_sse2,
        "std/core memory tier must be scalar or sse2"
    );
}

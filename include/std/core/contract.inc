// XIRASM std/core 的公共编译期契约。
//
// ABI 和实现层级使用具名字符串，避免把平台选择或 ISA 等级编码成难以
// 审查的数字。memory 当前支持 scalar/SSE2/固定 AVX2，CPU/dispatch 本身只生成
// baseline 指令。

const std_core_abi_sysv64: string = "sysv64"
const std_core_abi_windows64: string = "windows64"

const std_core_memory_tier_scalar: string = "scalar"
const std_core_memory_tier_sse2: string = "sse2"
const std_core_memory_tier_avx2: string = "avx2"

// AVX2 copy 的 non-temporal 阈值。0 表示禁用；默认值必须经过双端真机基准。
const std_memory_non_temporal_disabled: u64 = 0
const std_memory_avx2_non_temporal_threshold_default: u64 = std_memory_non_temporal_disabled

// runtime memory state 为四个连续 16 字节 dispatch state。
const std_memory_runtime_copy_state_offset: u64 = 0
const std_memory_runtime_move_state_offset: u64 = 16
const std_memory_runtime_fill_state_offset: u64 = 32
const std_memory_runtime_compare_state_offset: u64 = 48
const std_memory_runtime_state_size: u64 = 64

const std_memory_copy_symbol: string = "std_memory_copy"
const std_memory_move_symbol: string = "std_memory_move"
const std_memory_fill_symbol: string = "std_memory_fill"
const std_memory_compare_symbol: string = "std_memory_compare"

// CPU feature record 的独立位。AVX/AVX2 位表示 CPU 与 OS 状态均可用，
// 不是只复制 CPUID 原始位；调用方应按所需能力逐位判断。
const std_cpu_feature_sse2: u64 = 1
const std_cpu_feature_popcnt: u64 = 2
const std_cpu_feature_avx: u64 = 4
const std_cpu_feature_osxsave: u64 = 8
const std_cpu_feature_avx2: u64 = 16
const std_cpu_feature_erms: u64 = 32

// CPUID/XGETBV snapshot 是六个连续 u32，供纯判定入口和测试注入使用。
const std_cpu_snapshot_max_basic_offset: u64 = 0
const std_cpu_snapshot_leaf1_ecx_offset: u64 = 4
const std_cpu_snapshot_leaf1_edx_offset: u64 = 8
const std_cpu_snapshot_leaf7_ebx_offset: u64 = 12
const std_cpu_snapshot_xcr0_eax_offset: u64 = 16
const std_cpu_snapshot_xcr0_edx_offset: u64 = 20
const std_cpu_snapshot_size: u64 = 24

const std_cpu_query_symbol: string = "std_cpu_query"
const std_cpu_classify_symbol: string = "std_cpu_classify"
const std_cpu_detect_symbol: string = "std_cpu_detect"
const std_cpu_features_cached_symbol: string = "std_cpu_features_cached"

// 调度模式由编译期显式选择；fixed_avx2 不执行运行时能力检查。
const std_core_dispatch_baseline: string = "baseline"
const std_core_dispatch_fixed_avx2: string = "fixed_avx2"
const std_core_dispatch_runtime: string = "runtime"

// 拒绝非 64 位目标；不生成运行时代码，不改变寄存器或布局。
fn std_core_assert_x86_64() {
    assert(target.bits == 64, "std/core currently supports x86-64 only");
}

// 校验 std/core emitter 的编译期 ABI 选择；非法值在汇编期停止。
fn std_core_assert_abi(abi: string) {
    assert(
        abi == std_core_abi_sysv64 || abi == std_core_abi_windows64,
        "std/core ABI must be sysv64 or windows64"
    );
}

// 校验 memory 实现层级；固定 AVX2 由调用者保证 CPU 与 OS 状态可用。
fn std_core_assert_memory_tier(tier: string) {
    assert(
        tier == std_core_memory_tier_scalar ||
            tier == std_core_memory_tier_sse2 ||
            tier == std_core_memory_tier_avx2,
        "std/core memory tier must be scalar, sse2, or avx2"
    );
}

// 校验 AVX2 copy 的编译期 non-temporal 阈值；不生成运行时代码。
fn std_core_assert_non_temporal_threshold(threshold: u64) {
    assert(
        threshold == std_memory_non_temporal_disabled || threshold >= 4096,
        "std/core non-temporal threshold must be 0 or at least 4096"
    );
}

// 校验三参数 std/core 调度器的编译期模式；不生成运行时代码。
fn std_core_assert_dispatch_mode(mode: string) {
    assert(
        mode == std_core_dispatch_baseline ||
            mode == std_core_dispatch_fixed_avx2 ||
            mode == std_core_dispatch_runtime,
        "std/core dispatch mode must be baseline, fixed_avx2, or runtime"
    );
}

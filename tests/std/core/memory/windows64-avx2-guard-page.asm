// Windows x64 fixed AVX2 memory guard-page 真机测试入口。
const test_memory_abi: string = "windows64"
const test_memory_tier: string = "avx2"
include("guard-page.inc");

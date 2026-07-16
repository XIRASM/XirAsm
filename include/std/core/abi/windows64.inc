// Windows x64 memory 入口的参数映射。
//
// 编译期参数：无。
// 运行时输入：RCX=目标/左缓冲区，RDX=源/右缓冲区或填充值，R8=长度。
// 运行时输出：R10=第一个参数，R11=第二个参数，R8 保持长度。
// 返回值：无；本函数只生成入口映射指令。
// 所有权：不访问参数指向的内存。
// 保留：全部 Win64 非易失 GPR、XMM6-XMM15、RSP、DF、flags。
// 破坏：R10、R11；不使用栈和 shadow space，不执行 call。
fn std_core_memory_map_windows64_args() {
    mov r10, rcx
    mov r11, rdx
}

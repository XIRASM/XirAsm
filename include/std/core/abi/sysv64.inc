// System V AMD64 memory 入口的参数映射。
//
// 编译期参数：无。
// 运行时输入：RDI=目标/左缓冲区，RSI=源/右缓冲区或填充值，RDX=长度。
// 运行时输出：R10=第一个参数，R11=第二个参数，R8=长度。
// 返回值：无；本函数只生成入口映射指令。
// 所有权：不访问参数指向的内存。
// 保留：全部 SysV 非易失寄存器、RSP、DF、flags。
// 破坏：R8、R10、R11；不使用栈。
fn std_core_memory_map_sysv64_args() {
    mov r10, rdi
    mov r11, rsi
    mov r8, rdx
}

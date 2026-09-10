// AArch64 label spelling.
//
// A symbol name is case-sensitive, so every reference form has to keep the
// spelling the source used. Two of them used to lowercase the operand text and
// then hand that text on as the label payload, which meant a name containing an
// uppercase letter could never be found:
//
//   * the literal load form, ldr xN, <label>
//   * the :lo12: modifier, in both its add and memory operand shapes
//
// All-lowercase names hid the defect, and the Android platform API is CamelCase,
// so this fixture pins each form with a mixed-case label.
import("arm/a64-macros.inc");

origin(0)

MyData:
    dq(0x1122334455667788)

MyTable:
    dq(0)

EntryPoint:
    ldr x9, MyData
    adr x10, MyTable
    adrp x11, MyTable
    add x11, x11, :lo12:MyTable
    ldr x12, [x11, :lo12:MyTable]
    b Finished
    mov x13, #1
Finished:
    ret

defer {
    assert(load.u64(0) == 0x1122334455667788, "MyData must keep its value");
    assert(load.u64(8) == 0, "MyTable must stay zeroed");
    assert(load.u32(16) != 0, "the literal load must have encoded an instruction");
    assert(load.u32(36) != 0, "the branch slot must have encoded an instruction");
}

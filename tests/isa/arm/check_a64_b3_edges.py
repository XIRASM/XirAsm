"""Independent A64 memory, literal and capture regression cases."""
import argparse
import json
from pathlib import Path
import tempfile
from check_a64_generated import ROOT, run, success, sync

SOURCE = '''import("arm/a64-macros.inc")
fn marked(value: u64) -> u64 {
    const stamp: string = sym.unique("b3eval")
    return value;
}
fn next_stamp() -> string {
    return sym.unique("b3eval");
}
macro forward(dst, address) {
    const ADDEND: u64 = 100
    ldr dst, address
}
const ADDEND: u64 = 4
start:
ldr x0, finish
forward x1, marked(label_addr(finish) + ADDEND)
a64_ldr(list.of(a64_reg("x2"), a64_target("start")))
a64_ldr(list.of(a64_reg("x3"), a64_address(0)))
ldr x4, #marked(8)
ldr x5, [sp, #marked(16)]
ldr x6, [x7, w8, sxtw #marked(3)]
ld2 {v31.s, v0.s}[marked(3)], [sp], x4
ldp x4, x9, [sp, #-16]
ld1 {v15.h}[7], [x15]
prfm pldl1keep, finish
finish:
emit.u64(0)
assert(sym.unique("b3eval") == "b3eval__4", "memory expressions evaluated more than once")
defer {
    assert(next_stamp() == "b3eval__1", "literal expression evaluated more than once")
}
'''
ORACLE = '''start:
ldr x0, finish
ldr x1, finish + 4
ldr x2, start
ldr x3, start
ldr x4, #8
ldr x5, [sp, #16]
ldr x6, [x7, w8, sxtw #3]
ld2 {v31.s, v0.s}[3], [sp], x4
ldp x4, x9, [sp, #-16]
ld1 {v15.h}[7], [x15]
prfm pldl1keep, finish
finish:
.quad 0
'''
NEGATIVES = [
    'ldr x0, [x0, #8]!', 'str w1, [x1], #4',
    'ldp x0, x0, [sp]', 'ldp x0, x1, [x1], #16',
    'stxr w0, x0, [x2]', 'stxr w0, x1, [x0]',
    'stxp w0, x1, x0, [sp]', 'ldxp x0, x0, [sp]',
    'ldr x0, [xzr]', 'ldr x0, [w1]', 'ldr x0, [x1, w2]',
    'ldr x0, [x1, x2, uxtw]', 'ldr x0, [x1, w2, sxtw #2]',
    'ldr x0, [x1, x2, lsl #-1]', 'ldr x0, [x1, x2]!',
    'ld2 {v0.s, v2.s}[0], [sp]', 'ld2 {v0.s, v1.s}[4], [sp]',
    'ld1 {v0.16b}, [sp], #15', 'ld1 {v0.16b}, [sp], xzr',
    'ldr x0, #2', 'ldr x0, #1048576', 'ldr x0, #-1048580',
    'ldr x0, missing_label',
]

def verify(args, out):
    sync(args.xirasm)
    asm, binary = out / 'edges.asm', out / 'edges.bin'
    ref, obj, expected = out / 'edges.s', out / 'edges.o', out / 'edges.expected'
    asm.write_text(SOURCE, encoding='ascii')
    ref.write_text('.text\n' + ORACLE, encoding='ascii')
    success([args.clang, '--target=aarch64-linux-gnu', '-c', ref, '-o', obj], out)
    success([args.objcopy, '-O', 'binary', '--only-section=.text', obj, expected], out)
    success([args.xirasm, asm, '-o', binary], out)
    assert binary.read_bytes() == expected.read_bytes(), 'independent literal/memory byte mismatch'
    for index, source in enumerate(NEGATIVES):
        asm = out / f'negative-{index}.asm'
        binary = out / f'negative-{index}.bin'
        asm.write_text('import("arm/a64-macros.inc")\n' + source + '\n', encoding='ascii')
        result = run([args.xirasm, asm, '-o', binary], out)
        assert result.returncode != 0 and not binary.exists(), f'accepted invalid operands: {source}'
        # Arm LDXP Decode specifies Unpredictable_LDPOVERLAP for Rt == Rt2;
        # Clang 22 accepts that encoding. Undefined symbols may become relocations.
        # Structure post-index Xm excludes XZR: Rm=31 selects immediate mode.
        if source not in {'ldr x0, missing_label', 'ldxp x0, x0, [sp]', 'ld1 {v0.16b}, [sp], xzr'}:
            ref = out / f'negative-{index}.s'
            obj = out / f'negative-{index}.o'
            ref.write_text('.text\n' + source + '\n', encoding='ascii')
            reference = run([args.clang, '--target=aarch64-linux-gnu', '-c', ref, '-o', obj], out)
            assert reference.returncode != 0, f'Clang accepted negative case: {source}'
    for index, instruction in enumerate(('ldr v0.16b, forbidden()', 'ldr v0.16b, [x1, #forbidden()]')):
        asm = out / f'shape-{index}.asm'
        binary = out / f'shape-{index}.bin'
        asm.write_text('import("arm/a64-macros.inc")\nfn forbidden() -> u64 {\n    assert(false, "UNEXPECTED_EVALUATION")\n    return 0;\n}\n' + instruction + '\n', encoding='ascii')
        result = run([args.xirasm, asm, '-o', binary], out)
        assert result.returncode != 0 and not binary.exists()
        assert 'UNEXPECTED_EVALUATION' not in result.stderr and 'invalid operand classes' in result.stderr, result.stderr
    report = {'status': 'passed', 'independent_words': 11, 'negative_cases': len(NEGATIVES), 'clang_rejections': len(NEGATIVES)-3, 'shape_preflight': 2}
    (out / 'report.json').write_text(json.dumps(report, indent=2), encoding='ascii')
    print(report, flush=True)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--xirasm', type=Path, default=ROOT / 'zig-out/bin/xirasm.exe')
    parser.add_argument('--clang', required=True)
    parser.add_argument('--objcopy', required=True)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    args.xirasm = args.xirasm.resolve()
    if args.output:
        args.output = args.output.resolve()
        args.output.mkdir(parents=True, exist_ok=False)
        verify(args, args.output)
    else:
        with tempfile.TemporaryDirectory(prefix='a64-b3-edges-') as directory:
            verify(args, Path(directory))

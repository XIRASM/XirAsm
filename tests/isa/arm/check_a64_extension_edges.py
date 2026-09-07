"""Independent regular A64 extension boundaries and capture regressions."""
import argparse
import json
from pathlib import Path
import tempfile

from check_a64_generated import ROOT, ORACLE_ARCH, run, success, sync

POSITIVE = '''aese v31.16b, v0.16b
aesd v0.16b, v31.16b
sha256h q0, q1, v2.4s
sha512h q31, q0, v1.2d
sm3tt1a v0.4s, v1.4s, v2.s[3]
sm4e v31.4s, v0.4s
xar v0.2d, v31.2d, v1.2d, #63
crc32x w0, w1, x30
cas x0, x0, [x0]
casp x30, xzr, x0, x1, [sp]
caspal w0, w1, w30, wzr, [x0]
ldaddal x0, xzr, [sp]
swpal w30, wzr, [x0]
ldapr x0, [sp]
ldapur x0, [sp, #-256]
stlur w0, [x1, #255]
fadd h0, h1, h31
fmla v0.8h, v1.8h, v2.8h
faddp h0, v31.2h
fmlal v0.2s, v1.2h, v15.h[7]
sdot v0.4s, v1.16b, v31.4b[3]
udot v31.2s, v0.8b, v31.4b[0]
usdot v0.4s, v1.16b, v31.4b[3]
sudot v0.2s, v1.8b, v31.4b[3]
bfdot v0.4s, v1.8h, v31.2h[3]
bfmlalb v0.4s, v1.8h, v15.h[7]
bfmlalt v0.4s, v1.8h, v15.h[7]
bfmlalb v0.4s, v1.8h, v31.8h
bfmlalt v0.4s, v1.8h, v31.8h
bfcvtn v0.4h, v31.4s
bfcvtn2 v0.8h, v31.4s
bfmmla v0.4s, v1.8h, v31.8h
smmla v0.4s, v1.16b, v31.16b
ummla v0.4s, v1.16b, v31.16b
fcmla v0.4h, v1.4h, v31.h[1], #270
fcmla v0.8h, v1.8h, v31.h[3], #180
fcmla v0.4s, v1.4s, v31.s[1], #90
frint32z v0.4s, v31.4s
fjcvtzs w0, d31
pacia x0, sp
autib x30, x0
paciasp
autiasp
braa x0, sp
retaa
bti
bti c
bti j
bti jc
ldraa x0, [sp, #-4096]
ldrab x0, [sp, #4088]!
addg sp, sp, #1008, #15
subg x0, sp, #0, #0
irg sp, sp
gmi x0, sp, xzr
subp x0, sp, sp
cmpp sp, sp
ldg x0, [sp, #-4096]
stg sp, [sp, #4080]
stzg x0, [x0, #16]!
st2g x0, [x0], #-16
stz2g sp, [sp], #32
stgp x0, x0, [x0, #-1024]!
ldgm x0, [sp]
stgm x0, [sp]
stzgm x0, [sp]
rmif x0, #63, #15
setf8 w0
setf16 w30
cfinv
axflag
xaflag
sb
dgh
esb
bfc x0, #63, #1
'''

NEGATIVE = [
    'aese v0.8b, v1.8b', 'crc32x x0, w1, x2', 'xar v0.2d, v1.2d, v2.2d, #64',
    'casp x1, x2, x4, x5, [sp]', 'casp x0, x2, x4, x5, [sp]',
    'casp x0, x1, x3, x4, [sp]', 'casp x0, x1, x30, x0, [sp]',
    'casp x0, x1, w2, w3, [sp]', 'casp xzr, x0, x2, x3, [sp]',
    'cas x0, x1, [sp, #8]', 'ldadd x0, x1, [xzr]',
    'ldapur x0, [sp, #-257]', 'stlur x0, [sp, #256]',
    'sdot v0.4s, v1.16b, v2.b[0]', 'sdot v0.4s, v1.16b, v2.4b[4]',
    'bfdot v0.4s, v1.8h, v2.h[0]', 'bfdot v0.4s, v1.8h, v2.2h[4]',
    'bfmlalb v0.4s, v1.8h, v16.h[0]', 'fcmla v0.4h, v1.4h, v2.h[2], #0',
    'fcmla v0.4s, v1.4s, v2.s[2], #0', 'fcmla v0.8h, v1.8h, v2.h[0], #45',
    'bti k', 'pacia sp, x0', 'braa x0, xzr',
    'ldraa x0, [x0, #8]!', 'ldraa x0, [sp, #4096]', 'ldraa x0, [sp, #1]',
    'addg x0, sp, #1, #0', 'addg x0, sp, #1024, #0', 'addg x0, sp, #0, #16',
    'stg xzr, [sp]', 'stg x0, [sp, #1]', 'stg x0, [sp, #4096]',
    'stgp x0, x1, [sp, #1024]', 'stgp x0, x1, [sp, #-1040]',
    'a64_sdot(list.of(a64_reg("v0.4s"), a64_reg("v1.16b"), list.of(53, 32, 0)))',
    'a64_sdot(list.of(a64_reg("v0.4s"), a64_reg("v1.16b"), list.of(53, 2, 4)))',
]

CAPTURE = '''fn marked(value: u64) -> u64 {
    const unused: string = sym.unique("ext")
    return value;
}
macro forward(dst, src, lane) {
    const INDEX: u64 = 99
    sdot dst, src, lane
}
const INDEX: u64 = 3
forward v0.4s, v1.16b, v2.4b[marked(INDEX)]
bfdot v0.4s, v1.8h, v2.2h[marked(3)]
stg x0, [sp, #marked(16)]
assert(sym.unique("ext") == "ext__3", "extension expression repeated")
'''


def verify(args, out):
    sync(args.xirasm)
    for name, source, oracle in [('edges', POSITIVE, POSITIVE),
                                  ('capture', CAPTURE, 'sdot v0.4s, v1.16b, v2.4b[3]\nbfdot v0.4s, v1.8h, v2.2h[3]\nstg x0, [sp, #16]')]:
        asm, binary, ref, obj, expected = [out / f'{name}.{ext}' for ext in ('asm', 'bin', 's', 'o', 'expected')]
        asm.write_text('import("arm/a64-macros.inc")\n' + source, encoding='ascii')
        ref.write_text('.text\n' + oracle + '\n', encoding='ascii')
        success([args.clang, '--target=aarch64-linux-gnu', '-march=' + ORACLE_ARCH, '-c', ref, '-o', obj], out)
        success([args.objcopy, '-O', 'binary', '--only-section=.text', obj, expected], out)
        success([args.xirasm, asm, '-o', binary], out)
        assert binary.read_bytes() == expected.read_bytes(), f'{name}: bytes differ'
    for index, entry in enumerate(NEGATIVE):
        asm, binary = out / f'negative-{index}.asm', out / f'negative-{index}.bin'
        asm.write_text('import("arm/a64-macros.inc")\n' + entry + '\n', encoding='ascii')
        result = run([args.xirasm, asm, '-o', binary], out)
        assert result.returncode and not binary.exists(), f'accepted: {entry}'
        assert 'panic' not in result.stderr.lower(), result.stderr
    report = {'status': 'passed', 'independent_words': len(POSITIVE.splitlines()),
              'capture_words': 3, 'rejections': len(NEGATIVE)}
    (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n', encoding='ascii')
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
        with tempfile.TemporaryDirectory(prefix='a64-ext-edges-') as directory:
            verify(args, Path(directory))

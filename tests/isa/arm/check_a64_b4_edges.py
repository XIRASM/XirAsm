"""Independent scalar aliases, system registers, branch and page-target checks."""
import argparse
import json
from pathlib import Path
import tempfile

from check_a64_generated import ROOT, ORACLE_ARCH, run, success, sync


PAIRS = [
    ('mov x0, #0', 'mov x0, #0'),
    ('mov w0, #-1', 'mov w0, #-1'),
    ('mov w0, #-4294967296', 'mov w0, #-4294967296'),
    ('mov w0, #0xffffffff00000001', 'mov w0, #0xffffffff00000001'),
    ('mov x1, #-1', 'mov x1, #-1'),
    ('mov w2, #0xffff0000', 'mov w2, #0xffff0000'),
    ('mov x2, #0xffff0000ffff0000', 'mov x2, #0xffff0000ffff0000'),
    ('mov x3, #0x8000000000000000', 'mov x3, #0x8000000000000000'),
    ('mov sp, x0', 'mov sp, x0'), ('mov x0, sp', 'mov x0, sp'),
    ('mov wsp, w1', 'mov wsp, w1'), ('mov w1, wzr', 'mov w1, wzr'),
    ('add sp, sp, x2', 'add sp, sp, x2'),
    ('add x0, sp, w2, sxtw', 'add x0, sp, w2, sxtw'),
    ('add x0, x1, x2, lsl #4', 'add x0, x1, x2, lsl #4'),
    ('and x0, x1, #0x8000000080000000', 'and x0, x1, #0x8000000080000000'),
    ('cset x0, hs', 'cset x0, hs'), ('csetm w1, lo', 'csetm w1, lo'),
    ('cinc x0, x1, le', 'cinc x0, x1, le'),
    ('bfi x0, x1, #63, #1', 'bfi x0, x1, #63, #1'),
    ('bfxil w0, w1, #0, #32', 'bfxil w0, w1, #0, #32'),
    ('lsr x0, x1, #63', 'lsr x0, x1, #63'),
    ('mrs x0, nzcv', 'mrs x0, nzcv'), ('msr nzcv, x1', 'msr nzcv, x1'),
    ('mrs x2, cntvct_el0', 'mrs x2, cntvct_el0'),
    ('mrs x3, S3_3_C4_C2_0', 'mrs x3, S3_3_C4_C2_0'),
    ('msr daifset, #15', 'msr daifset, #15'),
    ('msr spsel, #1', 'msr spsel, #1'),
    ('msr spsel, #15', 'msr spsel, #15'),
    ('sys #7, c15, c15, #7, x30', 'sys #7, c15, c15, #7, x30'),
    ('sysl x30, #7, c15, c15, #7', 'sysl x30, #7, c15, c15, #7'),
    ('dsb sy', 'dsb sy'), ('dsb #0', 'dsb #0'), ('dmb ish', 'dmb ish'),
    ('isb sy', 'isb sy'), ('isb', 'isb'), ('clrex', 'clrex'), ('ret', 'ret'),
    ('tlbi alle1, xzr', 'tlbi alle1'),
    ('tlbi vae1', 'tlbi vae1, xzr'),
    ('ic iallu, xzr', 'ic iallu'), ('ic ialluis, xzr', 'ic ialluis'),
    ('ic ivau', 'ic ivau, xzr'),
    ('a64_mrs(list.of(a64_reg("x4"), a64_sysreg("nzcv")))', 'mrs x4, nzcv'),
    ('a64_msr(list.of(a64_sysreg("nzcv"), a64_reg("x4")))', 'msr nzcv, x4'),
]

TARGETS = '''fn marked(value: u64) -> u64 {
    const stamp: string = sym.unique("b4eval")
    return value;
}
fn stamp() -> string {
    return sym.unique("b4eval");
}
macro forward(target) {
    const ADDEND: u64 = 100
    b target
}
const ADDEND: u64 = 4
start:
b finish
bl finish
b.eq finish
b.hs start
cbz x0, finish
cbnz w1, start
tbz x2, #63, finish
tbnz w3, #31, start
adr x4, finish
forward marked(label_addr(finish) + ADDEND)
a64_b(list.of(a64_target("start")))
a64_bl(list.of(a64_address(0)))
a64_b_cond(list.of(a64_cond("ne"), a64_target("finish")))
b #marked(4)
finish:
emit.u32(0)
assert(sym.unique("b4eval") == "b4eval__1", "eager expression repeated")
defer {
    assert(stamp() == "b4eval__1", "deferred expression repeated")
}
'''
TARGET_ORACLE = '''start:
b finish
bl finish
b.eq finish
b.hs start
cbz x0, finish
cbnz w1, start
tbz x2, #63, finish
tbnz w3, #31, start
adr x4, finish
b finish + 4
b start
bl start
b.ne finish
b #4
finish:
.word 0
'''

PAGES = '''first:
rb(4092)
adrp x0, finish
adrp x1, first
adrp x2, (label_addr(finish) + 4096)
a64_adrp(list.of(a64_reg("x3"), a64_address(4095)))
a64_adrp(list.of(a64_reg("x4"), a64_target("finish")))
rb(4080)
finish:
emit.u32(0)
'''
PAGE_ORACLE = '''.space 4092
adrp x0, #8192
adrp x1, #-4096
adrp x2, #8192
adrp x3, #-4096
adrp x4, #4096
.space 4080
.word 0
'''

LO12 = '''origin(0x400000)
adrp x1, value
add x1, x1, :lo12:value
ldr w0, [x1, #:lo12:value]
value:
emit.u32(7)
'''
LO12_ORACLE = '''adrp x1, #0
add x1, x1, #12
ldr w0, [x1, #12]
.word 7
'''

NEGATIVES = [
    'add x0, xzr, #1', 'add xzr, x0, #1', 'adds sp, x0, #1',
    'mov sp, xzr', 'mov xzr, sp', 'mov x0, #0x123456789abcdef0',
    'mov w0, #0x100000000', 'and x0, x1, #0', 'and x0, x1, #-1',
    'and w0, w1, #0x100000000', 'movz w0, #1, lsl #32',
    'add x0, x1, x2, ror #1', 'add x0, sp, w2, sxtw #5',
    'add x0, x1, x2, lsl #64', 'add x0, x1, #4096',
    'cset x0, al', 'csetm x0, nv', 'cinc x0, x1, al',
    'bfi x0, x1, #63, #2', 'ubfx w0, w1, #1, #32',
    'b #2', 'b #134217728', 'b #-134217732',
    'b.eq #1048576', 'cbz x0, #-1048580', 'tbz w0, #32, #0',
    'tbnz x0, #64, #0', 'tbz x0, #0, #32768',
    'adr x0, #1048576', 'adrp x0, #4095', 'adrp x0, #4294967296',
    'msr cntvct_el0, x0', 'mrs x0, not_a_register', 'msr allint, #2',
    'sys #8, c0, c0, #0', 'sys #0, c16, c0, #0', 'sys #0, c0, c0, #8',
    'dsb #16', 'tlbi alle1, x0', 'ic iallu, x0', 'ic ialluis, x0',
    'a64_msr(list.of(a64_sysreg("cntvct_el0"), a64_reg("x0")))',
    'a64_mrs(list.of(a64_reg("x0"), list.of(52, 32768)))',
    'b missing_label',
]


def verify(args, out):
    sync(args.xirasm)
    names = json.loads((ROOT / 'tools/arm64/rules/b4.json').read_bytes())['system_registers']['names']
    named_source, named_oracle = [], []
    for name, entry in names.items():
        value = entry['value']
        generic = f'S{2+(value >> 14)}_{(value >> 11)&7}_C{(value >> 7)&15}_C{(value >> 3)&15}_{value&7}'
        if entry['access'] & 1:
            named_source += [f'mrs x0, {name}', f'a64_mrs(list.of(a64_reg("x0"), a64_sysreg("{name}")))']
            named_oracle += [f'mrs x0, {generic}'] * 2
        if entry['access'] & 2:
            named_source += [f'msr {name}, x0', f'a64_msr(list.of(a64_sysreg("{name}"), a64_reg("x0")))']
            named_oracle += [f'msr {generic}, x0'] * 2
    for name, source, oracle in (
        ('scalar', '\n'.join(a for a, b in PAIRS), '\n'.join(b for a, b in PAIRS)),
        ('targets', TARGETS, TARGET_ORACLE), ('pages', PAGES, PAGE_ORACLE),
        ('lo12', LO12, LO12_ORACLE),
        ('system-names', '\n'.join(named_source), '\n'.join(named_oracle)),
    ):
        asm, binary, ref, obj, expected = [out / f'{name}.{ext}' for ext in ('asm', 'bin', 's', 'o', 'expected')]
        asm.write_text('import("arm/a64-macros.inc")\n' + source + '\n', encoding='ascii')
        ref.write_text('.text\n' + oracle + '\n', encoding='ascii')
        success([args.clang, '--target=aarch64-linux-gnu', '-march=' + ORACLE_ARCH, '-c', ref, '-o', obj], out)
        success([args.objcopy, '-O', 'binary', '--only-section=.text', obj, expected], out)
        success([args.xirasm, asm, '-o', binary], out)
        actual, reference = binary.read_bytes(), expected.read_bytes()
        assert actual == reference, (name, [(i, actual[i:i+4].hex(), reference[i:i+4].hex())
                                          for i in range(0, len(reference), 4) if actual[i:i+4] != reference[i:i+4]][:8])
    for index, source in enumerate(NEGATIVES):
        asm, binary = out / f'negative-{index}.asm', out / f'negative-{index}.bin'
        asm.write_text('import("arm/a64-macros.inc")\n' + source + '\n', encoding='ascii')
        result = run([args.xirasm, asm, '-o', binary], out)
        assert result.returncode and not binary.exists(), f'accepted invalid input: {source}'
        assert 'panic' not in result.stderr.lower(), result.stderr
    report = {'status': 'passed', 'scalar_words': len(PAIRS), 'target_words': 14,
              'page_words': 5, 'lo12_words': 4, 'negative_cases': len(NEGATIVES),
              'system_names': len(names), 'system_name_words': len(named_source)}
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
        with tempfile.TemporaryDirectory(prefix='a64-b4-edges-') as directory:
            verify(args, Path(directory))

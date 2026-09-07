"""Structured rules for regular A64 extension templates in the pinned Arm XML.

SPDX-License-Identifier: MPL-2.0
"""
from source import require


def rule(matcher, processor, name='arm-extension-template-v1'):
    return {'rule': name, 'matcher': matcher, 'processor': processor}


def alternatives(matchers, processors, **extra):
    require(len(matchers) == len(processors), 'extensions', 'alternative mismatch')
    return {'rule': 'arm-extension-template-v1', 'matchers': matchers, 'processors': processors, **extra}


def extension_rule(row):
    enc, mnemonic, template = row['encoding'], row['mnemonic'], row['template']
    if not template:
        return rule('', '')
    if enc == 'BFCVTN_asimdmisc_4S':
        return rule(f'VStatic(WORD, {8 if row["q"] else 4}), VStatic(DWORD, 4)', 'R(0), R(5)')
    if enc in {'BFDOT_asimdsame2_D', 'USDOT_asimdsame2_D'}:
        size = 'WORD' if mnemonic == 'BFDOT' else 'BYTE'
        return rule(f'V(DWORD), V({size}), V({size})', 'R(0), R(5), R(16), Rwidth(30)')
    if enc in {'BFDOT_asimdelem_E', 'SUDOT_asimdelem_D', 'USDOT_asimdelem_D'}:
        size, count = ('WORD', 2) if mnemonic == 'BFDOT' else ('BYTE', 4)
        return rule(f'V(DWORD), V({size}), VStaticElement({size}, {count})',
                    'R(0), R(5), R(16), Ufields(&[11, 21]), Rwidth(30)')
    if enc in {'BFMLAL_asimdelem_F', 'BFMLAL_asimdsame2_F_'}:
        indexed = '_asimdelem_' in enc
        matcher = 'VStatic(DWORD, 4), VStatic(WORD, 8), ' + ('VElement(WORD)' if indexed else 'VStatic(WORD, 8)')
        processor = 'R(0), R(5), ' + ('R4(16), Ufields(&[11, 21, 20])' if indexed else 'R(16)')
        return alternatives([matcher, matcher], [processor + ', Static(30, 0b0)', processor + ', Static(30, 0b1)'],
                            output_mnemonics=['BFMLALB', 'BFMLALT'])
    if mnemonic in {'FRINT32X', 'FRINT32Z', 'FRINT64X', 'FRINT64Z'} and '_asimdmisc_' in enc:
        return alternatives(['V(DWORD), V(DWORD)', 'VStatic(QWORD, 2), VStatic(QWORD, 2)'],
                            ['R(0), R(5), Rwidth(30), Static(22, 0b0)',
                             'R(0), R(5), Static(30, 0b1), Static(22, 0b1)'])
    if enc == 'FCMLA_advsimd_elt':
        return alternatives([
            'VStatic(WORD, 4), VStatic(WORD, 4), VElement(WORD), Imm',
            'VStatic(WORD, 8), VStatic(WORD, 8), VElement(WORD), Imm',
            'VStatic(DWORD, 4), VStatic(DWORD, 4), VElement(DWORD), Imm',
        ], [
            'R(0), R(5), R(16), Ufields(&[21]), Ulist(13, &[0, 90, 180, 270]), Static(30, 0b0), Static(22, 0b01), Static(11, 0b0)',
            'R(0), R(5), R(16), Ufields(&[11, 21]), Ulist(13, &[0, 90, 180, 270]), Static(30, 0b1), Static(22, 0b01)',
            'R(0), R(5), R(16), Ufields(&[11]), Ulist(13, &[0, 90, 180, 270]), Static(30, 0b1), Static(22, 0b10), Static(21, 0b0)',
        ])
    if enc == 'BTI_HB_hints':
        return alternatives(['', 'Token("c", 10000)', 'Token("j", 10001)', 'Token("jc", 10002)'],
                            ['Static(5, 0b000)', 'Static(5, 0b010)', 'Static(5, 0b100)', 'Static(5, 0b110)'])
    if mnemonic in {'ADDG', 'SUBG'}:
        return rule('XSP, XSP, Imm, Imm', 'R(0), R(5), Uscaled(16, 6, 4), Ubits(10, 4)')
    if mnemonic in {'SUBP', 'SUBPS'}:
        return rule('X, XSP, XSP', 'R(0), R(5), R(16)')
    if mnemonic == 'CMPP':
        return rule('XSP, XSP', 'R(5), R(16)')
    if mnemonic == 'GMI':
        return rule('X, XSP, X', 'R(0), R(5), R(16)')
    if mnemonic == 'IRG':
        return alternatives(['XSP, XSP, X', 'XSP, XSP'],
                            ['R(0), R(5), R(16)', 'R(0), R(5), Static(16, 0b11111)'])
    if '_ldsttags' in enc:
        if 'bulk_' in enc:
            return rule('X, RefBase', 'R(0), R(5)')
        kind = 'X' if mnemonic == 'LDG' else 'XSP'
        if 'post_' in enc:
            return rule(f'{kind}, RefBase, Imm', 'R(0), R(5), Sscaled(12, 9, 4)')
        memory = 'RefPre' if 'pre_' in enc else 'RefOffset'
        return rule(f'{kind}, {memory}', 'R(0), R(5), Sscaled(12, 9, 4)')
    if mnemonic == 'STGP':
        memory = 'RefBase, Imm' if enc.endswith('_post') else 'RefPre' if enc.endswith('_pre') else 'RefOffset'
        return rule(f'X, X, {memory}', 'R(0), R(10), R(5), Sscaled(15, 7, 4)')
    return None

"""Adapt scalar rule families against the pinned Arm templates.

SPDX-License-Identifier: MPL-2.0
"""
import itertools
import re
import xml.etree.ElementTree as ET
import xml.parsers.expat
from source import digest, require

MODIFIERS = {
    "SHIFTS": ("lsl", "lsr", "asr"),
    "ROTATES": ("lsl", "lsr", "asr", "ror"),
    "EXTENDS": ("uxtb", "uxth", "uxtw", "uxtx", "sxtb", "sxth", "sxtw", "sxtx", "lsl"),
    "EXTENDS_W": ("uxtb", "uxth", "uxtw", "sxtb", "sxth", "sxtw"),
    "EXTENDS_X": ("uxtx", "sxtx", "lsl"),
}


def parse_pinned_xml(data):
    """Parse a pinned Arm spec document with entity expansion disabled.

    The spec files are plain data documents. Anything that declares or
    resolves an entity is hostile input (billion-laughs amplification or
    external fetches) and aborts instead of expanding; predefined
    character entities such as &amp; keep parsing normally.
    """
    builder = ET.TreeBuilder()
    parser = xml.parsers.expat.ParserCreate()
    parser.buffer_text = True
    parser.StartElementHandler = lambda name, attrs: builder.start(name, attrs)
    parser.EndElementHandler = lambda name: builder.end(name)
    parser.CharacterDataHandler = builder.data

    def forbid(*_args):
        raise ValueError("entity expansion is forbidden in pinned XML")

    parser.EntityDeclHandler = forbid
    parser.ExternalEntityRefHandler = forbid
    parser.Parse(data, True)
    return builder.close()


def system_tables(xml):
    """Read named system operands from Arm's structured field tables."""
    result = {}
    offsets = {"op1": 16, "op2": 5, "CRn": 12, "CRm": 8}
    for file in ("at_sys.xml", "dc_sys.xml", "ic_sys.xml", "tlbi_sys.xml", "dmb.xml", "dsb.xml", "msr_imm.xml"):
        root = parse_pinned_xml((xml / file).read_bytes())
        entries = []
        explanations = root.findall('.//explanation')
        if file == 'dsb.xml':
            explanations = [e for e in explanations if 'DSB_BO_barriers' in e.get('enclist', '').split(',')]
        for table in (t for e in explanations for t in e.findall('.//table[@class="valuetable"]')):
            header = table.find('.//thead/row')
            if header is None:
                continue
            columns = [(e.get('class'), ''.join(e.itertext()).strip()) for e in header.findall('entry')]
            if not any(k == 'bitfield' for k, n in columns):
                continue
            for row in table.findall('.//tbody/row'):
                cells = row.findall('entry')
                require(len(cells) == len(columns), file, 'table column mismatch')
                name, mask, value, patterns, features = None, 0, 0, {}, []
                for (kind, field), cell in zip(columns, cells):
                    text = ''.join(cell.itertext()).strip()
                    if kind == 'bitfield':
                        require(field in offsets and set(text) <= set('01x') and text, file, 'unsupported field table')
                        patterns[field] = text
                        for bit, char in enumerate(reversed(text)):
                            if char != 'x':
                                mask |= 1 << (offsets[field] + bit)
                                value |= int(char) << (offsets[field] + bit)
                    elif kind == 'symbol' and field.startswith('<'):
                        name = text.lower()
                    if cell.get('class') == 'feature':
                        features.extend(v.attrib for v in cell.iter('arch_variant'))
                if name and name != 'reserved':
                    require(re.fullmatch(r'[a-z][a-z0-9]*', name), file, 'unsupported operand name')
                    entry = {'name': name, 'mask': mask, 'value': value, 'patterns': patterns, 'features': features}
                    if file == 'tlbi_sys.xml':
                        link = row.find('.//register_link')
                        require(link is not None, name, 'missing TLBI register reference')
                        version = xml.name.removeprefix('ISA_A64_xml_')
                        reference_id = link.get('id')
                        require(reference_id is not None and re.fullmatch(r'[A-Za-z0-9_.-]+', reference_id),
                                name, 'unsupported TLBI register reference id')
                        reference = xml.parents[1] / ('SysReg_xml_' + version) / ('SysReg_xml_' + version) / reference_id
                        content = reference.read_bytes()
                        register = parse_pinned_xml(content)
                        permissions = [''.join(p.itertext()) for p in register.findall('.//access_permission_text/para')]
                        rt_fixed = any('The Rt field should be set to' in p and '0b11111' in p for p in permissions)
                        require(rt_fixed or register.find('.//reg_fieldsets//field') is not None,
                                name, 'TLBI register role not established')
                        entry.update(rt_fixed=rt_fixed, register_source=link.get('id'), register_sha256=digest(content))
                    entries.append(entry)
        require(entries, file, 'empty system operand table')
        result[file] = entries
    names = sorted({e['name'] for entries in result.values() for e in entries} | {f'c{i}' for i in range(16)} | {'sy'})
    return result, {name: i for i, name in enumerate(names)}


def named_rule(row, tables, names):
    """Expand literal names into fixed official fields and typed tokens."""
    file = row['file']
    if file not in tables:
        return None
    matchers, processors, provenance = [], [], []
    for entry in tables[file]:
        name, mask, value = entry['name'], entry['mask'], entry['value']
        matcher = f'Token("{name}", {names[name]})'
        processor = f'NamedBits({mask}, {value})'
        if row['mnemonic'] == 'MSR':
            matcher += ', Imm'
            pattern = entry['patterns']['CRm']
            width = len(pattern) - len(pattern.rstrip('x'))
            require(width in {1, 4}, file, 'unsupported PSTATE immediate field')
            processor += f', Ubits(8, {width})'
        elif row['mnemonic'] in {'AT', 'DC', 'IC', 'TLBI'}:
            matcher += ', X'
            processor += ', R(0)'
            if entry.get('rt_fixed') or (row['mnemonic'] == 'IC' and name != 'ivau'):
                processor += ', C, CUrange(31, 31), A'
        matchers.append(matcher)
        processors.append(processor)
        provenance.append(entry)
        if row['mnemonic'] in {'TLBI', 'IC'}:
            matchers.append(matcher.removesuffix(', X'))
            processors.append(f'NamedBits({mask}, {value}), Static(0, 0b11111)')
            provenance.append(entry)
    if row['mnemonic'] in {'DMB', 'DSB'}:
        matchers.append('Imm')
        processors.append('Ubits(8, 4)')
        provenance.append({})
    return {'rule': 'arm-named-system-fields-v1', 'matchers': matchers, 'processors': processors, 'operand_sources': provenance}


def scalar_rule(row, record, rules):
    fixed = record["encoding"]["fixed_mask"] | record["encoding"]["should_be_mask"]
    fields = tuple(f for f in row["fields"] if (((1 << f[1])-1) << f[2]) & ~fixed)
    template = row["template"]
    if row["mnemonic"] in {"DMB", "DSB"}:
        template = template.strip("()")
        return {"rule": "arm-system-names-v1", "matcher": "Ident", "processor": 'LitList(8, "BARRIER_OPS")'}
    if row["encoding"] == "AT_SYS_CR_systeminstrs":
        return {"rule": "arm-system-names-v1", "matcher": "Ident, X", "processor": 'LitList(5, "AT_OPS"), R(0)'}
    if row["encoding"] == "TLBI_SYS_CR_systeminstrs":
        return {"rule": "arm-system-names-v1", "matcher": "Ident, End, X", "processor": 'LitList(5, "TLBI_OPS"), R(0)'}
    if row["encoding"] == "IC_SYS_CR_systeminstrs":
        return {"rule": "arm-system-names-v1", "matcher": "Ident, End, X", "processor": 'LitList(5, "IC_OPS"), R(0)'}
    if row["encoding"] == "DC_SYS_CR_systeminstrs":
        return {"rule": "arm-system-names-v1", "matcher": "Ident, X", "processor": 'LitList(5, "DC_OPS"), R(0)'}
    if "<invcond>" in template:
        kind = "W" if "<Wd>" in template else "X"
        if row["mnemonic"] in {"CSET", "CSETM"}:
            matcher, processor = f"{kind}, Cond", "R(0), InvCond(12)"
        else:
            matcher, processor = f"{kind}, {kind}, Cond", "R(0), R(5), C, R(16), InvCond(12)"
        return {"rule": "arm-inverted-condition-v1", "matcher": matcher, "processor": processor}
    return rules.get((row["mnemonic"], template, fields))


def expand_rule(row, matcher, processor):
    """Finite syntax choices retain distinct SP/ZR and modifier roles."""
    if "_bitfield" in row["encoding"]:
        # Raw immr/imms are independent; the old CUSum constraint is incorrect.
        if row["mnemonic"] in {"BFM", "SBFM", "UBFM"}:
            processor = re.sub(r"CUSum\(\d+\),?\s*", "", processor)
        processor = processor.replace("Usumdec", "Usum")
    if row["mnemonic"] == "MOV":
        matcher = re.sub(r'Dot, Lit\("(?:logical|inverted)"\), ', "", matcher)
    if row['encoding'] == 'B_only_condbranch':
        matcher = matcher.removeprefix('Dot, ')
    if row['mnemonic'] in {'SYS', 'SYSL'}:
        matcher = matcher.replace('Ident', 'Control')
        processor = processor.replace('LitList(12, "CONTROL_REGS")', 'Ubits(12, 4)').replace('LitList(8, "CONTROL_REGS")', 'Ubits(8, 4)')
    if row['encoding'] in {'MRS_RS_systemmove', 'MSR_SR_systemmove'}:
        matcher = matcher.replace('Imm', 'SysReg')
    if row['mnemonic'] == 'ISB' and matcher == 'Lit("sy")':
        # SY is represented by its architectural CRm value, also accepted numerically.
        matcher, processor = 'Imm', 'Ubits(8, 4)'
    mod = re.search(r"\bMod\((\w+)\)", matcher)
    modifiers = MODIFIERS[mod[1]] if mod else (None,)
    roles = list(re.finditer(r"\b[WX]SP\b", matcher))
    for modifier, sp_choices in itertools.product(modifiers, itertools.product((False, True), repeat=len(roles))):
        active = matcher
        for role, sp in reversed(list(zip(roles, sp_choices))):
            kind = role[0][0]
            active = active[:role.start()] + (kind + "Stack" if sp else kind + "Base") + active[role.end():]
        if mod:
            active = re.sub(r"\bMod\(\w+\)", f"Modifier({modifier.upper()})", active)
        yield active, processor

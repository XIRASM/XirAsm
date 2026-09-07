"""Extract fixed A64 register spellings from the pinned open Arm register data."""
import json
import re
from source import digest, require


def read_register_names(path, version):
    content = path.read_bytes()
    registers = json.loads(content)
    names, unresolved = {}, []
    widths = {'op0': 2, 'op1': 3, 'CRn': 4, 'CRm': 4, 'op2': 3}
    for ri, register in enumerate(registers):
        require(register['_meta']['version'] == version, 'Registers.json', 'register version drift')
        for ai, accessor in enumerate(register.get('accessors', [])):
            access = accessor.get('name')
            if access not in {'A64.MRS', 'A64.MSRregister'}:
                continue
            for ei, encoding in enumerate(accessor.get('encoding', [])):
                spelling = encoding.get('asmvalue')
                fields = encoding.get('encodings', {})
                pointer = f'/{ri}/accessors/{ai}/encoding/{ei}'
                if not isinstance(spelling, str) or not re.fullmatch('[A-Za-z][A-Za-z0-9_]*', spelling) or any(
                    key not in fields or not re.fullmatch("'[01]{" + str(width) + "}'", fields[key].get('value', ''))
                    for key, width in widths.items()
                ):
                    unresolved.append({'source_pointer': pointer, 'name': spelling, 'access': access})
                    continue
                values = {key: int(fields[key]['value'][1:-1], 2) for key in widths}
                require(values['op0'] in {2, 3}, pointer, 'unexpected A64 system register op0')
                value = ((values['op0']-2) << 14) | (values['op1'] << 11) | (values['CRn'] << 7) | (values['CRm'] << 3) | values['op2']
                key = spelling.lower()
                entry = names.setdefault(key, {'value': value, 'access': 0, 'sources': []})
                require(entry['value'] == value, pointer, 'ambiguous register spelling')
                entry['access'] |= 1 if access == 'A64.MRS' else 2
                entry['sources'].append({'pointer': pointer, 'condition': accessor.get('condition'), 'register_condition': register.get('condition')})
    require(names, 'Registers.json', 'empty A64 register map')
    return {'sha256': digest(content), 'names': dict(sorted(names.items())), 'unresolved': unresolved}

"""Compile normalized A64 forms into independent XIRASM APIs and statement macros."""

from __future__ import annotations

import argparse
from collections import defaultdict
import json
from pathlib import Path
import struct

from e5_rules import CSSC_SCALAR_CONFLICTS
from source import canonical, digest, require

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
KINDS = ["imm", "cond", "w", "x", "b", "h", "s", "d", "q", "v8b", "v16b", "v4h",
         "v8h", "v2s", "v4s", "v1d", "v2d", "v1q", "lane_b", "lane_h", "lane_s", "lane_d",
         "lsl", "msl", "fp", "mem_base", "mem_off", "mem_pre", "mem_index",
         "idx_uxtw", "idx_lsl", "idx_sxtw", "idx_sxtx", "target", "sp",
         "captured_target", "label_target", "absolute_target", "wsp", "lsr", "asr", "ror",
         "uxtb", "uxth", "uxtw", "uxtx", "sxtb", "sxth", "sxtw", "sxtx", "name", "creg", "sysreg", "lane_4b", "lane_2h", "v2h"]
CONDITIONS = "eq ne cs cc mi pl vs vc hi ls ge lt gt le al nv".split()


def signature(operands):
    key = 1
    for operand in operands:
        key = key * 512 + KINDS.index(operand["kind"]) + operand.get("list_count", 0) * 64
    return key


def validate(data):
    extension_batches = json.loads((HERE / 'extension-batches.json').read_bytes())['batches']
    extension = data['batch'] in extension_batches
    require(data["format_version"] == 1 and data["batch"] in {"B1", "B2", "B3", "B4"} | set(extension_batches), "rules", "unsupported format")
    require(data["source_lock"] == json.loads((HERE / "source-lock.json").read_bytes()),
            "rules", "source lock mismatch")
    expected = len(extension_batches[data['batch']]['planned_records']) if extension else {"B1": 327, "B2": 191, "B3": 369, "B4": 257}[data["batch"]]
    if extension:
        require(data['planned_records'] == extension_batches[data['batch']]['planned_records'], 'extensions', 'planned source set changed')
    require(len(set(data["planned_records"])) == expected and not data.get("blocked_records"),
            "batch", "incomplete source set")
    require({f["record_id"] for f in data["forms"]} == set(data["planned_records"]), "batch", "source record missing")
    if data["batch"] in {"B2", "B3", "B4"} or extension:
        expected_rows = {'E1': 39, 'E2': 257, 'E3': 218, 'E4': 86}[data['batch']] if extension else {"B2": 212, "B3": 369, "B4": 257}[data["batch"]]
        require(data.get('xml_entries') == expected_rows and not data.get("failures"), data["batch"], "XML conversion incomplete")
        require(data.get("alternatives") and all(a["status"] == "converted" for a in data["alternatives"]),
                "B2", "unaccounted translation alternative")
    identities = set()
    for form in data["forms"]:
        require(form["id"] not in identities, "forms", "duplicate form ID")
        identities.add(form["id"])
        word = form["base"]
        require(type(word) is int and 0 <= word <= 0xFFFFFFFF, form["id"], "invalid base word")
        require(word & form["fixed_mask"] == form["fixed_value"], form["id"], "source fixed bits changed")
        require(word & form["should_be_mask"] == form["should_be_value"], form["id"], "noncanonical preferred bits")
        mask = 0
        for operand in form["operands"]:
            require("transform" not in operand and "list" not in operand, form["id"], "obsolete operand mapping")
            require(operand["kind"] in KINDS and 0 <= operand.get("list_count", 0) <= 4,
                    form["id"], "invalid operand kind or list count")
        for field in form["fields"]:
            index, width, offset = field["operand"], field["width"], field["lsb"]
            require(0 <= index < len(form["operands"]) and 0 < width <= 26 and 0 <= offset <= 32-width,
                    form["id"], "invalid dynamic field")
            bits = ((1 << width) - 1) << offset
            require(not bits & (mask | word | form["fixed_mask"] | form["should_be_mask"]),
                    form["id"], "overlapping field")
            mask |= bits
        require(0 <= len(form["operands"]) <= 6, form["id"], "unsupported arity")
        signature(form["operands"])


def register_source():
    lines = ["// Generated register spellings and operand tags.", "let a64_registers: map = map.new()"]
    for kind in KINDS[2:18]:
        for reg in range(32):
            text = f"v{reg}.{kind[1:]}" if kind.startswith("v") else f"{kind}{reg}"
            if kind in {"w", "x"} and reg == 31:
                text = kind + "zr"
            lines.append(f'map.set_mut(a64_registers, "{text}", list.of({KINDS.index(kind)}, {reg}))')
    lines += ["let a64_lanes: map = map.new()"]
    for reg in range(32):
        lines.append(f'map.set_mut(a64_registers, "v{reg}.2h", list.of(55, {reg}))')
    lines.append('map.set_mut(a64_registers, "sp", list.of(34, 31))')
    lines.append('map.set_mut(a64_registers, "wsp", list.of(38, 31))')
    lines.append('map.set_mut(a64_registers, "fp", list.of(3, 29))')
    lines.append('map.set_mut(a64_registers, "lr", list.of(3, 30))')
    for index, size in enumerate("bhsd"):
        for reg in range(32):
            lines.append(f'map.set_mut(a64_lanes, "v{reg}.{size}", list.of({18+index}, {reg}))')
    for size in ('4b', '2h'):
        for reg in range(32):
            lines.append(f'map.set_mut(a64_lanes, "v{reg}.{size}", list.of({KINDS.index("lane_" + size)}, {reg}))')
    values = []
    for immediate in range(128):
        bits = ((0x3e000000 if immediate & 64 else 0x40000000) | ((immediate & 63) << 19))
        values.append(repr(struct.unpack('<f', struct.pack('<I', bits))[0]))
    lines.append("const a64_fp_values: list = list.of(" + ", ".join(values) + ")")
    lines += ["let a64_conditions: map = map.new()"]
    for index, condition in enumerate(CONDITIONS):
        lines.append(f'map.set_mut(a64_conditions, "{condition}", {index})')
    lines += ['map.set_mut(a64_conditions, "hs", 2)', 'map.set_mut(a64_conditions, "lo", 3)', ""]
    return "\n".join(lines)


def render(batches, e5=None):
    for batch in batches:
        validate(batch)
    if e5 is None:
        e5 = json.loads((HERE / "rules/e5.json").read_bytes())
    require(e5.get("batch") == "E5", "E5", "invalid dispatch source")
    e5_dispatch = defaultdict(list)
    for form in e5["forms"]:
        if form["mnemonic"] in CSSC_SCALAR_CONFLICTS:
            e5_dispatch[form["mnemonic"]].append(form)
    records = [r for b in batches for r in b['planned_records']]
    require(len(records) == len(set(records)), 'batches', 'overlapping source sets')
    data = {"format_version": 1, "batch": "+".join(b["batch"] for b in batches), "source_lock": batches[0]["source_lock"],
            "planned_records": [r for b in batches for r in b["planned_records"]],
            "forms": [f for b in batches for f in b["forms"]], "blocked_records": [],
            "inputs": {**{b["batch"]: digest(canonical(b)) for b in batches},
                       "E5-dispatch": digest(canonical({
                           mnemonic: forms for mnemonic, forms in sorted(e5_dispatch.items())
                       }))}}
    groups = defaultdict(list)
    for form in data["forms"]:
        groups[form["mnemonic"]].append(form)
    code = ["// Generated by tools/arm64/generate_a64.py. See manifest.json and NOTICE.",
            "// Source architectural feature expressions and conditions are retained in manifest.json.", ""]
    macros = ["// Generated statement macros; one owner per mnemonic.", ""]
    for mnemonic, forms in sorted(groups.items()):
        # Prefer shifted registers and MOVZ/MOVN before their overlapping aliases.
        def priority(form):
            enc = form["encoding_id"]
            return (2 if "_addsub_ext" in enc or enc.startswith("MOV_ADD_") else
                    1 if enc.startswith("MOV_MOVN_") else
                    3 if enc.startswith("MOV_ORR_") and "_imm" in enc else 0)
        forms = sorted(forms, key=priority)
        code += [f"fn a64_{mnemonic}_word(args: list) -> u64 {{"]
        if mnemonic in {'mrs', 'msr'}:
            code += [f"    a64_check_sysreg(args, {1 if mnemonic == 'mrs' else 0}, {1 if mnemonic == 'mrs' else 2})"]
        code += ["    const flat: list = a64_flatten(args)", "    const key: u64 = a64_signature(flat)"]
        by_key = defaultdict(list)
        for form in forms:
            by_key[signature(form["operands"])].append(form)
        for key, alternatives in sorted(by_key.items()):
            code.append(f"    if key == {key} {{")
            for i in range(len(alternatives[0]["operands"])):
                code.append(f"        const p{i}: integer = list.get(list.get(flat, {i}), 1)")
            seen = set()
            def value_expr(form, field):
                value = f"p{field['operand']}"
                transform = field.get("transform")
                if transform:
                    kind = transform["kind"]
                    if kind == "subone":
                        value = f"({1 << transform['width']} - {value})"
                    elif kind == "slice":
                        value = f"({value} >> {transform['shift']})"
                    elif kind == "lookup":
                        value = f"a64_option_index({value}, list.of({', '.join(map(str, transform['values']))}))"
                    elif kind == "scale_flag":
                        value = f"a64_scale_flag({value}, {transform['scale']})"
                    elif kind == "xor":
                        value = f"({value} ^ {transform['value']})"
                    elif kind == "bias":
                        value = f"({value} - {transform['value']})"
                    elif kind == "negate":
                        value = f"(-{value})"
                    elif kind == "complement":
                        value = f"(~{value})"
                    elif kind == "sum_previous":
                        value = f"(p{transform['operand']} + {value} - 1)"
                    elif kind == "scalar_special":
                        value = f'a64_scalar_special({value}, "{transform["special"]}")'
                    elif kind == "stretched_immediate":
                        value = f"a64_stretched_immediate({value})"
                    elif kind in {"split_float_immediate", "float_immediate"}:
                        pass  # a64_fp has already validated and compressed the real value.
                    else:
                        raise ValueError(f"unknown field transform {kind}")
                    if kind not in {"slice", "subone", "lookup"} and transform.get("shift"):
                        value = f"({value} >> {transform['shift']})"
                return f"({value} & {(1 << field['width'])-1})"
            for form in alternatives:
                conditions = []
                for i, operand in enumerate(form["operands"]):
                    if "literal" in operand:
                        conditions.append(f"p{i} == {operand['literal']}")
                    else:
                        if operand.get("min", 0) < 0 <= operand.get("max", -1):
                            # Meta integers are unsigned two's-complement words, so a
                            # negative lower bound has to be compared in its unsigned
                            # form: the value is either in the negative range, which
                            # appears as a huge unsigned number, or at most max.
                            umin = operand["min"] & 0xFFFFFFFFFFFFFFFF
                            conditions.append(f"(p{i} >= {umin} || p{i} <= {operand['max']})")
                        else:
                            if "min" in operand:
                                conditions.append(f"p{i} >= {operand['min']}")
                            if "max" in operand:
                                conditions.append(f"p{i} <= {operand['max']}")
                        if "allowed" in operand:
                            conditions.append("(" + " || ".join(f"p{i} == {v}" for v in operand["allowed"]) + ")")
                        if operand.get("multiple", 1) != 1:
                            conditions.append(f"(p{i} % {operand['multiple']}) == 0")
                        if operand.get("special", "").startswith(("logical_immediate", "wide_immediate", "inverted_wide_immediate")):
                            conditions.append(f'a64_scalar_special(p{i}, "{operand["special"]}") != 0xffffffffffffffff')
                for constraint in form.get("constraints", []):
                    left, right = f"p{constraint['left']}", f"p{constraint['right']}"
                    conditions.append({"distinct": f"{left} != {right}",
                                       "base_distinct": f"({left} == 31 || {left} != {right})",
                                       "next": f"{left} == {right} + 1",
                                       "sum_max": f"{left} + {right} <= {constraint.get('max', 0)}"}[constraint["kind"]])
                expr = " | ".join([f"0x{form['base']:08x}"] +
                                  [f"({value_expr(form, f)} << {f['lsb']})" for f in form["fields"]])
                selector = " && ".join(conditions) or "true"
                identity = selector, expr
                if identity in seen:
                    continue  # Alias records may describe the same syntax and encoding.
                require(not any(s == selector for s, _ in seen), mnemonic, "ambiguous syntax selector")
                seen.add(identity)
                code += [f"        // {form['id']}: {form['encoding_id']}",
                         f"        if {selector} {{", f"            return {expr};", "        }"]
            # A value that no form accepts is usually out of range, but an operand
            # with a required multiple is a common enough mistake to name on its own.
            multiples = sorted({(i, operand["multiple"]) for form in alternatives
                                for i, operand in enumerate(form["operands"])
                                if operand.get("multiple", 1) != 1})
            for i, multiple in multiples:
                code += [f"        if (p{i} % {multiple}) != 0 {{",
                         f'            assert(false, "a64 {mnemonic}: operand {i} must be a multiple of {multiple}");',
                         "        }"]
            code += [f'        assert(false, "a64 {mnemonic}: operand value out of range")', "        return 0;", "    }"]
        literal = any(o["kind"] == "target" for f in forms for o in f["operands"])
        page = "true" if mnemonic == "adrp" else "false"
        supports_lo12 = mnemonic == "add" or any(
            operand["kind"] == "mem_off" for form in forms for operand in form["operands"]
        )
        if supports_lo12:
            body = ["    if a64_has_lo12(args) {",
                    f"        a64_{mnemonic}_shape(a64_lo12_values(args, false))",
                    "        defer {",
                    f"            store.u32(here(), a64_{mnemonic}_word(a64_lo12_values(args, true)))",
                    "        }", "        emit.u32(0)"]
            if literal:
                body += ["    } else if a64_has_target(args) {",
                         f"        a64_{mnemonic}_shape(a64_literal_values(args, 0, false, {page}))",
                         "        defer {",
                         f"            store.u32(here(), a64_{mnemonic}_word(a64_literal_values(args, here(), true, {page})))",
                         "        }", "        emit.u32(0)"]
            body += ["    } else {", f"        emit.u32(a64_{mnemonic}_word(args))", "    }"]
        elif literal:
            body = ["    if a64_has_target(args) {",
                    f"        a64_{mnemonic}_shape(a64_literal_values(args, 0, false, {page}))",
                    "        defer {",
                    f"            store.u32(here(), a64_{mnemonic}_word(a64_literal_values(args, here(), true, {page})))",
                    "        }", "        emit.u32(0)", "    } else {",
                    f"        emit.u32(a64_{mnemonic}_word(args))", "    }"]
        else:
            body = [f"    emit.u32(a64_{mnemonic}_word(args))"]
        code += [f'    assert(false, "a64 {mnemonic}: invalid operand classes, arrangements or count")',
                 "    return 0;", "}", f"fn a64_{mnemonic}(args: list) {{", *body, "}", ""]
        code += [f"fn a64_{mnemonic}_shape(args: list) {{",
                 "    const key: u64 = a64_signature(a64_flatten(args))",
                 f'    assert({" || ".join(f"key == {key}" for key in sorted(by_key))}, "a64 {mnemonic}: invalid operand classes, arrangements or count")', "}", ""]
        floating = 'true' if mnemonic == 'fmov' else 'false'
        zero_float = 'true' if any(o.get("float") for f in forms for o in f["operands"]) else 'false'
        literal_arg = 'true' if literal else 'false'
        if mnemonic == 'b_cond':
            for condition in CONDITIONS + ['hs', 'lo']:
                macros += [f'macro b.{condition}(target) {{',
                           f'    const parsed: list = a64_operands(list.of(target), false, false, true, true, "b_cond_target")',
                           f'    a64_b_cond(list.of(a64_cond("{condition}"), list.get(parsed, 0)))', '}', '']
        elif mnemonic in e5_dispatch:
            e5_keys = sorted({signature(form["operands"]) for form in e5_dispatch[mnemonic]})
            macros += [f"macro {mnemonic}(...args) {{",
                       f'    const shaped: list = a64_operands(args, {floating}, {zero_float}, false, {literal_arg}, "{mnemonic}")',
                       "    const key: u64 = a64_signature(a64_flatten(shaped))",
                       f'    if {" || ".join(f"key == {key}" for key in e5_keys)} {{',
                       f"        a64_e5_{mnemonic}_shape(shaped)",
                       f'        a64_e5_{mnemonic}(a64_operands(args, {floating}, {zero_float}, true, {literal_arg}, "{mnemonic}"))',
                       "    } else {",
                       f"        a64_{mnemonic}_shape(shaped)",
                       f'        a64_{mnemonic}(a64_operands(args, {floating}, {zero_float}, true, {literal_arg}, "{mnemonic}"))',
                       "    }", "}", ""]
        else:
            macros += [f"macro {mnemonic}(...args) {{",
                       f'    a64_{mnemonic}_shape(a64_operands(args, {floating}, {zero_float}, false, {literal_arg}, "{mnemonic}"))',
                       f'    a64_{mnemonic}(a64_operands(args, {floating}, {zero_float}, true, {literal_arg}, "{mnemonic}"))', "}", ""]
    suffix = "instructions"
    generated = {
        "a64/generated/registers.inc": register_source(),
        f"a64/generated/{suffix}.inc": "\n".join(code),
        f"a64/generated/{suffix}-macros.inc": "\n".join(macros),
    }
    tokens = {}
    for form in data['forms']:
        for op in form['operands']:
            if op['kind'] == 'name':
                require(op['spelling'] not in tokens or tokens[op['spelling']] == op['literal'], 'names', 'token collision')
                tokens[op['spelling']] = op['literal']
    generated['a64/generated/names.inc'] = 'let a64_names: map = map.new()\n' + ''.join(
        f'map.set_mut(a64_names, "{name}", {value})\n' for name, value in sorted(tokens.items()))
    registers = batches[3]['system_registers']['names']
    generated['a64/generated/names.inc'] += 'let a64_system_registers: map = map.new()\n' + ''.join(
        f'map.set_mut(a64_system_registers, "{name}", list.of({entry["value"]}, {entry["access"]}))\n'
        for name, entry in sorted(registers.items()))
    generated["a64.inc"] = ('import("arm/a64/operands.inc")\n'
                            'import("arm/a64/memory.inc")\n'
                            'import("arm/a64/scalar.inc")\n'
                            'import("arm/a64/mops.inc")\n'
                            'import("arm/a64/generated/instructions.inc")\n'
                            'import("arm/a64/generated/instructions-e5.inc")\n')
    generated["a64-macros.inc"] = ('import("arm/a64.inc")\n'
                                   'import("arm/a64/generated/instructions-macros.inc")\n'
                                   'import("arm/a64/generated/instructions-e5-macros.inc")\n')
    generated["a64-b2.inc"] = 'import("arm/a64.inc")\n'
    generated["a64-b2-macros.inc"] = 'import("arm/a64-macros.inc")\n'
    generated["a64/generated/lanes-immediates.inc"] = 'import("arm/a64/generated/instructions.inc")\n'
    generated["a64/generated/lanes-immediates-macros.inc"] = 'import("arm/a64/generated/instructions-macros.inc")\n'
    notice = (HERE / "NOTICE").read_text(encoding="utf-8")
    notice += ("\nOperand translation rules are adapted from dynasm-rs, under MPL-2.0.\n"
               "The adapted sources are tools/arm64/normalize_a64.py, normalize_a64_e5.py, b4_rules.py, extension_rules.py, e5_rules.py, rules/b1.json through rules/b4.json, and rules/e1.json through rules/e5.json.\n"
               "See tools/arm64/MPL-2.0.txt for the license.\n")
    generated["a64/generated/NOTICE"] = notice
    artifacts = {name: text.encode("ascii") for name, text in generated.items()}
    manifest = {**data, "generator": "a64-finite-forms-v2", "mapping_sha256": digest(canonical(data)),
                "files": {name: digest(value) for name, value in artifacts.items()},
                "macro_mnemonics": sorted(groups)}
    artifacts["a64/generated/manifest.json"] = canonical(manifest)
    artifacts["a64/generated/b2-manifest.json"] = canonical({**batches[1], "files": manifest["files"],
        "macro_mnemonics": sorted({f["mnemonic"] for f in batches[1]["forms"]})})
    if len(batches) > 2:
        artifacts["a64/generated/b3-manifest.json"] = canonical({**batches[2], "files": manifest["files"],
            "macro_mnemonics": sorted({f["mnemonic"] for f in batches[2]["forms"]})})
    if len(batches) > 3:
        artifacts['a64/generated/b4-manifest.json'] = canonical({**batches[3], 'files': manifest['files']})
    for batch in batches[4:]:
        artifacts[f'a64/generated/{batch["batch"].lower()}-manifest.json'] = canonical({**batch, 'files': manifest['files']})
    return artifacts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rules", type=Path, nargs='+', default=[HERE / f"rules/{b}.json" for b in ('b1', 'b2', 'b3', 'b4', 'e1', 'e2', 'e3', 'e4')])
    parser.add_argument("--output", type=Path, default=ROOT / "include/arm")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    batches = [json.loads(path.read_bytes()) for path in args.rules]
    require([b["batch"] for b in batches] == ["B1", "B2", "B3", "B4", "E1", "E2", "E3", "E4"], "rules", "expected B1-B4 and E1-E4 in order")
    e5 = json.loads((HERE / "rules/e5.json").read_bytes())
    artifacts = render(batches, e5)
    for name, value in artifacts.items():
        path = args.output / name
        if args.check:
            require(path.is_file() and path.read_bytes() == value, name, "stale generated artifact")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(value)
    forms = [f for b in batches for f in b["forms"]]
    print(f"{'Checked' if args.check else 'Generated'} {sum(len(b['planned_records']) for b in batches)} records, "
          f"{len(forms)} forms, {len({f['mnemonic'] for f in forms})} API/macro pairs")


if __name__ == "__main__":
    main()

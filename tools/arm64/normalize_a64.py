"""Adapt A64 translation rules to finite operand forms using pinned Arm encodings.

The rule reader and matcher/processor model are adapted from dynasm-rs.
SPDX-License-Identifier: MPL-2.0
"""

from __future__ import annotations

import argparse
import ast
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET
from b4_rules import expand_rule, named_rule, scalar_rule, system_tables
from register_names import read_register_names
from extension_rules import extension_rule

from source import canonical, digest, require

HERE = Path(__file__).resolve().parent
B1 = frozenset("asimdsame asimdmisc asimddiff asimdall asimdperm asisdsame "
               "asisdmisc asisddiff asisdpair floatdp1 floatdp2 floatdp3 "
               "floatcmp floatccmp floatsel".split())
SIZES = {"BYTE": "b", "WORD": "h", "DWORD": "s", "QWORD": "d", "OWORD": "q"}
B2 = frozenset("asimdimm asisdone asimdins asimdext float2int asisdshf asimdshf float2fix asisdelem asimdelem floatimm asimdtbl".split())


def expressions(text):
    """Read the small declarative command language without executing reference code."""
    # Rust slice references are data, not executable expressions.
    text = text.replace("&[", "[")
    source = "[" + text + "]"
    tree = ast.parse(source, mode="eval").body
    result = []
    for node in tree.elts:
        if isinstance(node, ast.Name):
            result.append((node.id, []))
        else:
            require(isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                    and not node.keywords, text, "unsupported command syntax")
            args = [arg.id if isinstance(arg, ast.Name) else ast.literal_eval(arg) for arg in node.args]
            if node.func.id == "Static":
                literal = ast.get_source_segment(source, node.args[1])
                require(literal.startswith("0b"), text, "static requires an explicit bit width")
                args.append(len(literal[2:].replace("_", "")))
            result.append((node.func.id, args))
    return result


def read_rules(root):
    lookup, hashes = {}, {}
    for path in sorted(root.glob("tl_*.py")):
        hashes[path.name] = digest(path.read_bytes())
        for statement in ast.parse(path.read_text(encoding="utf-8")).body:
            require(isinstance(statement, ast.Expr) and isinstance(statement.value, ast.Call)
                    and isinstance(statement.value.func, ast.Name)
                    and statement.value.func.id == "tlentry", path.name, "unexpected rule statement")
            call = statement.value
            args = [ast.literal_eval(value) for value in call.args]
            opts = {kw.arg: ast.literal_eval(kw.value) for kw in call.keywords}
            require(len(args) == 3, path.name, "unexpected rule arguments")
            for name in args[0]:
                key = name, args[1], tuple(args[2])
                require(key not in lookup, name, "duplicate translation rule")
                lookup[key] = {**opts, "rule": f"{path.name}:{statement.lineno}"}
    return lookup, hashes


def rule_alternatives(rule):
    """The reference appends plural alternatives after the singular entry."""
    matchers = ([rule["matcher"]] if "matcher" in rule else []) + rule.get("matchers", [])
    processors = ([rule["processor"]] if "processor" in rule else []) + rule.get("processors", [])
    require(bool(matchers) and len(matchers) == len(processors), rule["rule"], "rule alternative mismatch")
    for selector in ("names", "bits", 'output_mnemonics'):
        require(not rule.get(selector) or len(rule[selector]) == len(matchers),
                rule["rule"], "rule selector count mismatch")
    return list(zip(matchers, processors))


def box_bits(boxes, bits):
    for box in boxes:
        high, width = int(box.get("hibit")), int(box.get("width", "1"))
        cursor = high
        for cell in box.findall("c"):
            count = int(cell.get("colspan", "1"))
            value = (cell.text or "").strip() if count == 1 else "x"
            for bit in range(cursor - count + 1, cursor + 1):
                require(0 <= bit < 32, "XML", "bit outside word")
                bits[bit] = value or "x"
            cursor -= count
        require(cursor == high - width, "XML", "box width mismatch")


def xml_rows(path):
    root = ET.parse(path).getroot()
    title = root.findtext("heading")
    for iclass in root.iter("iclass"):
        diagram = iclass.find("regdiagram")
        if diagram is None:
            require(not iclass.findall("encoding"), path.name, "missing diagram")
            continue
        base = ["x"] * 32
        box_bits(diagram.findall("box"), base)
        fields = [(b.get("name"), int(b.get("width", "1")),
                   int(b.get("hibit")) - int(b.get("width", "1")) + 1)
                  for b in diagram.findall("box") if b.get("name")]
        for encoding in iclass.findall("encoding"):
            vars_ = {d.get("key"): d.get("value") for d in encoding.iter("docvar")}
            name = vars_.get("alias_mnemonic", vars_.get("mnemonic"))
            require(name is not None, path.name, "missing mnemonic")
            templates = ["".join(t.itertext()) for t in encoding.findall("asmtemplate")]
            require(len(templates) == 1, path.name, "expected one syntax template")
            bits = base.copy()
            box_bits(list(encoding.iter("box")), bits)
            fields_ = tuple(f for f in fields if any(bits[i] not in {"0", "1"}
                                                   for i in range(f[2], f[2] + f[1])))
            template = templates[0][len(name):].replace(" ", "")
            variants = [(name, None)]
            if template.startswith("{2}"):
                require(("Q", 1, 30) in fields_, path.name, "suffix 2 without Q")
                template = template[3:]
                fields_ = tuple(f for f in fields_ if f != ("Q", 1, 30))
                variants = [(name, 0), (name + "2", 1)]
            for mnemonic, q in variants:
                yield {"mnemonic": mnemonic, "template": template, "fields": fields_,
                       "encoding": encoding.get("name"), "title": title, "q": q,
                       "bits": bits, "file": path.name}


def modern_rule(row):
    """Resolve fixed-width template changes, including canonical FP zero comparison."""
    matcher, processor = [], []
    for token in row["template"].split(","):
        scalar = re.fullmatch(r"([BHSDQ])<([dnma])>|<([BHSDQ])([dnma])>", token)
        vector = re.fullmatch(r"<V([dnma])>\.([124816]+)([BHSDQ])", token)
        if scalar:
            kind, role = (scalar[1], scalar[2]) if scalar[1] else (scalar[3], scalar[4])
            matcher.append(kind)
            processor.append(f"R({dict(d=0, n=5, m=16, a=10)[role]})")
        elif vector:
            role, lanes, size = vector.groups()
            size_name = next(k for k, v in SIZES.items() if v == size.lower())
            matcher.append(f"VStatic({size_name}, {lanes})")
            processor.append(f"R({dict(d=0, n=5, m=16, a=10)[role]})")
        elif token == "<Vd>.<Tb>" and row["encoding"] == "FCVTXN_asimdmisc_N":
            matcher.append(f"VStatic(DWORD, {4 if row['q'] else 2})")
            processor.append("R(0)")
        elif token in {"#0", "#0.0"}:
            matcher.append("LitFloat(0.0)" if "." in token else "LitInt(0)")
        else:
            raise ValueError(f"unresolved template {row['encoding']}: {token}")
    return {"matcher": ", ".join(matcher), "processor": ", ".join(processor),
            "rule": "current-fixed-template-v1"}


def operand_shapes(matchers, q, index_option=3):
    operands = []
    optional = False
    for name, args in matchers:
        if name in "BHSDQ" and len(name) == 1 and not args:
            operands.append({"kind": name.lower()})
        elif name in {"V", "VStatic"}:
            size = SIZES[args[0]]
            lanes = args[1] if name == "VStatic" else (16 if q else 8) // (1 << "bhsdq".index(size))
            require(lanes > 0, name, "invalid lanes")
            operands.append({"kind": f"v{lanes}{size}"})
        elif name in {"LitFloat", "LitInt"}:
            require(name != "LitFloat" or args == [0.0], name, "unsupported floating literal matcher")
            operands.append({"kind": "imm", "literal": int(args[0]), "float": name == "LitFloat"})
        elif name in {"Imm", "Cond"}:
            require(not args, name, "unexpected matcher parameters")
            operands.append({"kind": name.lower()})
        elif name in {"W", "X"}:
            operands.append({"kind": name.lower()})
        elif name == "Token":
            operands.append({"kind": "name", "literal": args[1], "spelling": args[0]})
        elif name == "Control":
            operands.append({"kind": "creg"})
        elif name == "SysReg":
            operands.append({"kind": "sysreg"})
        elif name in {"WBase", "XBase", "WStack", "XStack"}:
            operands.append({"kind": ("wsp" if name[0] == "W" else "sp") if name.endswith("Stack") else name[0].lower(),
                             "min": 31 if name.endswith("Stack") else 0,
                             "max": 31 if name.endswith("Stack") else 30})
        elif name == "Modifier":
            operands.append({"kind": args[0].lower(), **({"default": 0} if optional and args[0] == "LSL" else {})})
        elif name in {"VElement", "VElementStatic"}:
            size = SIZES[args[0]]
            lanes = {"b": 16, "h": 8, "s": 4, "d": 2}[size]
            operands.append({"kind": f"lane_{size}"})
            operands.append({"kind": "imm", "max": lanes - 1,
                             **({"literal": args[1]} if name == "VElementStatic" else {})})
        elif name == 'VStaticElement':
            size, count = SIZES[args[0]], args[1]
            require((size, count) in {('b', 4), ('h', 2)}, name, 'unsupported element group')
            operands.extend([{'kind': f'lane_{count}{size}'}, {'kind': 'imm', 'max': 3}])
        elif name in {"RegListStatic", "RegList", "RegListElement"}:
            size, count = SIZES[args[1]], int(args[0])
            if name == "RegListElement":
                operands.append({"kind": f"lane_{size}", "list_count": count})
                operands.append({"kind": "imm", "max": (16 >> "bhsd".index(size)) - 1})
            else:
                lanes = int(args[2]) if name == "RegListStatic" else (16 if q else 8) >> "bhsd".index(size)
                operands.append({"kind": f"v{lanes}{size}", "list_count": count})
        elif name in {"RefBase", "RefOffset", "RefPre", "RefIndex", "RefIndexLSL"}:
            kind = {"RefBase": "mem_off", "RefOffset": "mem_off", "RefPre": "mem_pre",
                    "RefIndex": "mem_index", "RefIndexLSL": "mem_index"}[name]
            operands.append({"kind": kind})
            if name == "RefBase":
                operands.append({"kind": "imm", "literal": 0})
            if name in {"RefOffset", "RefPre"}:
                operands.append({"kind": "imm"})
            elif name in {"RefIndex", "RefIndexLSL"}:
                operands.append({"kind": {2: "idx_uxtw", 3: "idx_lsl", 6: "idx_sxtw", 7: "idx_sxtx"}[index_option]})
                operands.append({"kind": "imm", "literal": index_option})
                operands.append({"kind": "imm"})
        elif name == "Offset":
            operands.append({"kind": "target"})
        elif name == "End":
            optional = True
        elif name == "LitMod":
            require(args[0] in {"LSL", "MSL"}, name, "unsupported modifier")
            operands.append({"kind": args[0].lower(), **({"default": 0} if optional else {})})
        else:
            raise ValueError(f"unsupported matcher {name}")
    return operands


def compile_form(row, record, rule, matcher, processor, q, index_option=3):
    # The legacy FP16 conversion rule has a malformed call; Arm defines 32-fbits.
    if row["encoding"] in {f"{m}_asisdshf_C" for m in ("FCVTZS", "FCVTZU", "SCVTF", "UCVTF")}:
        processor = processor.replace("Usubone()(16, 5, 32)", "Usubone(16, 5)")
    if row["template"] == "D<d>,D<n>,#<shift>" and row["bits"][22] == "1":
        processor = processor.replace("Usubone(16, 7)", "Usubone(16, 6)")
    matchers, commands = expressions(matcher), expressions(processor)
    operands = operand_shapes(matchers, q, index_option)
    enc = record["encoding"]
    fixed = enc["fixed_mask"] | enc["should_be_mask"]
    word = enc["fixed_value"] | enc["should_be_value"]
    owners = fixed
    fields, cursor = [], 0
    flat = [i for i, operand in enumerate(operands) if "literal" not in operand]
    # ExtendsX consumes the implicit modifier slot as well as normal registers.
    if any(name == "RefIndex" for name, _ in matchers):
        implicit = next(i for i, o in enumerate(operands) if o["kind"].startswith("idx_")) + 1
        flat = sorted([*flat, implicit])
    constraints = []

    def insert(offset, width, value=None, operand=None, transform=None):
        nonlocal owners, word
        require(0 < width <= 32 and 0 <= offset and offset + width <= 32, row["encoding"], "field exceeds word")
        mask = ((1 << width) - 1) << offset
        if value is None:
            require(not owners & mask, row["encoding"], "dynamic field overlaps assigned bits")
            field = {"operand": operand, "lsb": offset, "width": width}
            if transform:
                field["transform"] = transform
            fields.append(field)
        else:
            require(0 <= value < (1 << width), row["encoding"], "static field overflow")
            dynamic = sum(((1 << f["width"]) - 1) << f["lsb"] for f in fields)
            require(not ((value << offset) & dynamic), row["encoding"], "static one overlaps dynamic field")
            require(not ((word ^ (value << offset)) & (owners & ~dynamic) & mask), row["encoding"], "static field conflict")
            word |= value << offset
        owners |= mask

    if row["q"] is not None:
        insert(30, 1, row["q"])
    # XML specializes JSON decode classes (e.g. FMOV rmode/opcode).
    for bit, value in enumerate(row["bits"]):
        if value in {"0", "1"}:
            insert(bit, 1, int(value))
    def constrain(index, low, high):
        op = operands[index]
        op["min"] = max(low, op.get("min", low))
        op["max"] = min(high, op.get("max", (1 << 64) - 1))
        require(op["min"] <= op["max"], row["encoding"], "empty operand range")

    for command, args in commands:
        if command == "Static":
            offset, value, width = args
            insert(offset, width, value)
        elif command == "NamedBits":
            mask, value = args
            require(value & ~mask == 0, row["encoding"], "invalid named field")
            for bit in range(32):
                if mask & (1 << bit):
                    insert(bit, 1, (value >> bit) & 1)
        elif command == "Rwidth":
            insert(args[0], 1, q)
        elif command == "A":
            require(cursor < len(flat), row["encoding"], "cursor overflow")
            cursor += 1
        elif command == "C":
            require(cursor > 0, row["encoding"], "cursor underflow")
            cursor -= 1
        elif command in {"CUbits", "CUrange"}:
            require(cursor < len(flat), row["encoding"], "validation cursor overflow")
            constrain(flat[cursor], *(args if command == "CUrange" else [0, (1 << args[0]) - 1]))
        elif command == 'CSscaled':
            require(cursor < len(flat), row['encoding'], 'validation cursor overflow')
            width, shift = args
            constrain(flat[cursor], -(1 << (width-1+shift)), ((1 << (width-1))-1) << shift)
            operands[flat[cursor]]['multiple'] = 1 << shift
        elif command == 'Sslice':
            require(cursor < len(flat), row['encoding'], 'slice cursor overflow')
            offset, width, shift = args
            insert(offset, width, operand=flat[cursor], transform={'kind': 'slice', 'shift': shift})
        elif command in {"Rotates", "ExtendsW", "ExtendsX"} and record["group"] != "ldst":
            op = operands[flat[cursor]]
            if command == "Rotates":
                value, width = ["lsl", "lsr", "asr", "ror"].index(op["kind"]), 2
            else:
                value = (2 if command == "ExtendsW" else 3) if op["kind"] == "lsl" else ["uxtb", "uxth", "uxtw", "uxtx", "sxtb", "sxth", "sxtw", "sxtx"].index(op["kind"])
                width = 3
            insert(args[0], width, value)
        elif command == "ExtendsX":
            insert(args[0], 3, index_option)
            cursor += 1
        elif command == "RNext":
            current, previous = flat[cursor], flat[cursor-1]
            constrain(current, 0, 31)
            constraints.append({"kind": "next", "left": current, "right": previous})
            cursor += 1
        elif command == "CUSum":
            constraints.append({"kind": "sum_max", "left": flat[cursor-1], "right": flat[cursor], "max": 1 << args[0]})
        elif command in {"R", "R4", "REven", "RNoZr", "Ubits", "Usubone", "Ufields", "Uslice", "Ulist", "Special", "Cond", "InvCond", "Sbits", "Sscaled", "Uscaled", "Offset", "Urange", "Usubmod", "Usubzero", "Usum"}:
            require(cursor < len(flat), row["encoding"], "operand cursor overflow")
            operand = flat[cursor]
            kind = operands[operand]["kind"]
            if command in {"R", "R4", "REven", "RNoZr"}:
                require(kind not in {"imm", "cond"}, row["encoding"], "register command on non-register")
                width = 4 if command == "R4" else 5
                constrain(operand, 0, 30 if command == "RNoZr" else (1 << width) - 1)
                if command == "REven":
                    operands[operand]["multiple"] = 2
                insert(args[0], width, operand=operand)
            elif command in {"Cond", "InvCond"}:
                require(kind == "cond", row["encoding"], "condition command on non-condition")
                constrain(operand, 0, 13 if command == "InvCond" else 15)
                insert(args[0], 4, operand=operand, transform={"kind": "xor", "value": 1} if command == "InvCond" else None)
            else:
                require(kind in {"imm", "creg", "sysreg", "lsl", "msl", "target", "lsr", "asr", "ror", "uxtb", "uxth", "uxtw", "uxtx", "sxtb", "sxth", "sxtw", "sxtx"}, row["encoding"], "immediate command on non-immediate")
                if command in {"Urange", "Usubmod", "Usubzero", "Usum"}:
                    offset = args[0]
                    if command == "Urange":
                        low, high = args[1:]
                        width = (high-low).bit_length()
                        transform = {"kind": "bias", "value": low}
                    else:
                        width = args[1]
                        low, high = (1, 1 << width) if command == "Usum" else (0, (1 << width)-1)
                        transform = {"kind": {"Usubmod": "negate", "Usubzero": "complement", "Usum": "sum_previous"}[command]}
                        if command == "Usum":
                            transform["operand"] = flat[cursor-1]
                            constraints.append({"kind": "sum_max", "left": flat[cursor-1], "right": operand, "max": 1 << width})
                    constrain(operand, low, high)
                    insert(offset, width, operand=operand, transform=transform)
                elif command in {"Sbits", "Sscaled", "Uscaled", "Offset"}:
                    if command == "Offset":
                        require(args[0] in {"BCOND", "B", "TBZ", "ADR", "ADRP"}, row["encoding"], "unexpected literal relocation")
                        relocation = args[0]
                        offset, width, shift = {"BCOND": (5, 19, 2), "B": (0, 26, 2),
                                                "TBZ": (5, 14, 2), "ADR": (5, 21, 0),
                                                "ADRP": (5, 21, 12)}[relocation]
                        if record["group"] != "ldst":
                            operands[operand]["relocation"] = relocation
                    else:
                        offset, width = args[:2]
                        shift = args[2] if len(args) == 3 else 0
                    signed = command != "Uscaled"
                    constrain(operand, -(1 << (width-1+shift)) if signed else 0,
                              ((1 << (width-int(signed))) - 1) << shift)
                    operands[operand]["multiple"] = 1 << shift
                    if command == "Offset" and relocation in {"ADR", "ADRP"}:
                        insert(29, 2, operand=operand, transform={"kind": "slice", "shift": shift})
                        insert(5, 19, operand=operand, transform={"kind": "slice", "shift": shift+2})
                    else:
                        insert(offset, width, operand=operand, transform={"kind": "slice", "shift": shift})
                elif command == "Ubits":
                    offset, width = args
                    if any(n == "RefIndexLSL" for n, _ in matchers) and offset == 12:
                        operands[operand]["allowed"] = [-1, 0]
                        constrain(operand, -1, 0)
                        insert(offset, width, operand=operand, transform={"kind": "scale_flag", "scale": 0})
                    else:
                        constrain(operand, 0, (1 << width) - 1)
                        insert(offset, width, operand=operand)
                elif command == "Usubone":
                    offset, width = args
                    constrain(operand, 1, 1 << width)
                    insert(offset, width, operand=operand, transform={"kind": "subone", "width": width})
                elif command == "Uslice":
                    offset, width, shift = args
                    insert(offset, width, operand=operand, transform={"kind": "slice", "shift": shift})
                elif command == "Ufields":
                    bitfields = args[0]
                    constrain(operand, 0, (1 << len(bitfields)) - 1)
                    for bit_index, offset in enumerate(reversed(bitfields)):
                        insert(offset, 1, operand=operand, transform={"kind": "slice", "shift": bit_index})
                elif command == "Ulist":
                    options = args[1]
                    if any(n == "RefIndex" for n, _ in matchers) and args[0] == 12:
                        operands[operand]["allowed"] = sorted({-1, *options})
                        constrain(operand, -1, max(options))
                        insert(12, 1, operand=operand, transform={"kind": "scale_flag", "scale": max(options)})
                        cursor += 1
                        continue
                    operands[operand]["allowed"] = options
                    constrain(operand, min(options), max(options))
                    insert(args[0], max(1, (len(options) - 1).bit_length()), operand=operand,
                           transform={"kind": "lookup", "values": options})
                elif command == "Special":
                    special = args[1]
                    if special in {"LOGICAL_IMMEDIATE_W", "LOGICAL_IMMEDIATE_X", "WIDE_IMMEDIATE_W", "WIDE_IMMEDIATE_X", "INVERTED_WIDE_IMMEDIATE_W", "INVERTED_WIDE_IMMEDIATE_X"}:
                        bits = 32 if special.endswith("_W") else 64
                        operands[operand]["special"] = special.lower()
                        operands[operand]["max"] = (1 << 64)-1
                        if special.startswith("LOGICAL"):
                            insert(10, 6, operand=operand, transform={"kind": "scalar_special", "special": special.lower(), "shift": 0})
                            insert(16, 6, operand=operand, transform={"kind": "scalar_special", "special": special.lower(), "shift": 6})
                            if bits == 64:
                                insert(22, 1, operand=operand, transform={"kind": "scalar_special", "special": special.lower(), "shift": 12})
                        else:
                            insert(5, 16, operand=operand, transform={"kind": "scalar_special", "special": special.lower(), "shift": 0})
                            insert(21, 1 if bits == 32 else 2, operand=operand, transform={"kind": "scalar_special", "special": special.lower(), "shift": 16})
                        cursor += 1
                        continue
                    require(special in {"FLOAT_IMMEDIATE", "SPLIT_FLOAT_IMMEDIATE", "STRETCHED_IMMEDIATE"},
                            row["encoding"], "unsupported special immediate")
                    transform = {"kind": special.lower()}
                    operands[operand]["special"] = special.lower()
                    if special != "STRETCHED_IMMEDIATE":
                        operands[operand]["kind"] = "fp"
                    if special == "FLOAT_IMMEDIATE":
                        insert(args[0], 8, operand=operand, transform=transform)
                    else:
                        require(args[0] == 5, row["encoding"], "unexpected split immediate position")
                        insert(5, 5, operand=operand, transform={**transform, "shift": 0})
                        insert(16, 3, operand=operand, transform={**transform, "shift": 5})
                else:
                    raise ValueError(f"unsupported immediate command {command}")
            if command != "Uslice":
                cursor += 1
        else:
            raise ValueError(f"unsupported processor {command}")
    require(cursor == len(flat), row["encoding"], "unconsumed operand")
    # EXT's 64-bit form restricts imm4<3> to zero. SXTL/UXTL are shift-zero aliases.
    if row["encoding"] == "EXT_asimdext_only" and operands[0]["kind"] == "v8b":
        insert(14, 1, 0)
    if row["mnemonic"] in {"SXTL", "SXTL2", "UXTL", "UXTL2"}:
        insert(16, 3, 0)
    # Scalar shift/conversion immh:immb has zero high bits above 2*esize-1.
    if "_asisdshf_" in row["encoding"]:
        for field in fields:
            if field["lsb"] == 16 and operands[field["operand"]]["kind"] == "imm":
                for bit in range(16 + field["width"], 23):
                    if not owners & (1 << bit):
                        insert(bit, 1, 0)
    # Double-precision element forms require sz:L=10 (index is H alone).
    if row["encoding"].endswith("elem_R_SD") and any(o["kind"] == "lane_d" for o in operands):
        insert(21, 1, 0)
    # INS source imm4 low bits are ignored and must be emitted as zero.
    if row["encoding"] in {"INS_asimdins_IV_v", "MOV_INS_asimdins_IV_v"}:
        size = "bhsd".index(operands[0]["kind"][-1])
        if size:
            insert(11, size, 0)
    if row["mnemonic"] in {"TBZ", "TBNZ"} and operands[0]["kind"] == "w":
        insert(31, 1, 0)
    # Arm Decode rejects high immediate bits in 32-bit shift/bitfield forms.
    if record.get("group") in {"dpimm", "dpreg"} and row["bits"][31] == "0":
        required_zero = []
        if any(family in row["encoding"] for family in ("_addsub_shift", "_log_shift", "_bitfield")):
            required_zero.append(15)
        if "_bitfield" in row["encoding"]:
            required_zero.append(21)
        for bit in required_zero:
            if not owners & (1 << bit):
                insert(bit, 1, 0)
    require(owners == 0xFFFFFFFF, row["encoding"], f"unowned bits {~owners & 0xffffffff:08x}")
    if record["group"] == "ldst":
        base_index = next((i for i, op in enumerate(operands) if op["kind"].startswith("mem_")), None)
        registers = [i for i, op in enumerate(operands) if op["kind"] in {"w", "x", "s", "d", "q"}]
        mnemonic = row["mnemonic"]
        if mnemonic in {"LDP", "LDPSW", "LDNP", "LDXP", "LDAXP"}:
            constraints.append({"kind": "distinct", "left": 0, "right": 1})
        if base_index is not None:
            writeback = operands[base_index]["kind"] == "mem_pre" or ("ldst" in row["encoding"] and "post" in row["encoding"])
            if writeback and '_ldsttags' not in row['encoding'] and mnemonic != 'STGP':
                for i in registers:
                    if operands[i]["kind"] in {"w", "x"}:
                        constraints.append({"kind": "base_distinct", "left": base_index, "right": i})
            if mnemonic.startswith(("STXR", "STLXR", "STXP", "STLXP")):
                for i in registers[1:]:
                    constraints.append({"kind": "distinct", "left": 0, "right": i})
                constraints.append({"kind": "base_distinct", "left": base_index, "right": 0})
    extra = {"constraints": constraints} if record["group"] == "ldst" or constraints else {}
    return {**extra, "record_id": record["id"], "encoding_id": row["encoding"],
            "source_pointer": record["pointer"], "mnemonic": "b_cond" if row["encoding"] == "B_only_condbranch" else row["mnemonic"].lower(),
            "rule": rule["rule"], "base": word, "operands": operands, "fields": fields,
            "features": record["features"], "conditions": record["conditions"],
            "fixed_mask": enc["fixed_mask"], "fixed_value": enc["fixed_value"],
            "should_be_mask": enc["should_be_mask"], "should_be_value": enc["should_be_value"]}


def compatible_rule(row, rules):
    """Apply explicit syntax/diagram migrations, never mnemonic-only matching."""
    template, fields = row["template"], row["fields"]
    template = template.replace("V<m>.", "<Vm>.")
    if "_asisdshf_" in row["encoding"] and template == "D<d>,D<n>,#<shift>":
        template = "<V><d>,<V><n>,#<shift>"
    if row["encoding"] == "UMOV_asimdins_X_x":
        template = template.replace(".D[", ".<Ts>[")
    if row["encoding"].startswith("FMOV_") and "float2int" in row["encoding"]:
        fields = tuple(f for f in fields if f[0] not in {"rmode", "opcode"})
    if row["mnemonic"] in {"BIC", "ORR"} and "_asimdimm_" in row["encoding"]:
        fields = tuple(f for f in fields if f[0] != "cmode")
    if row["encoding"].startswith("MOV_UMOV_"):
        fields = tuple((name, 1, 20) if name == "imm5" else (name, width, offset)
                       for name, width, offset in fields)
    return rules.get((row["mnemonic"], template, fields))


def memory_rule(row, record, rules):
    # New diagrams retain decode selectors and preferred fields in the field list.
    # They may be omitted from the old matcher only when JSON fixes every bit.
    enc = record["encoding"]
    fixed = enc["fixed_mask"] | enc["should_be_mask"]
    fields = tuple(f for f in row["fields"] if
                   (((1 << f[1]) - 1) << f[2]) & ~fixed)
    template = row["template"]
    if row["mnemonic"] == "PRFM":
        if row["encoding"] == "PRFM_P_ldst_pos":
            return {"rule": "arm-ldst-pos-prefetch-v1", "matcher": "Imm, RefOffset",
                    "processor": "Ubits(0, 5), R(5), Uscaled(10, 12, 3)"}
    result = rules.get((row["mnemonic"], template, fields))
    if result and result.get("forget"):
        # Byte LSL has its own XML encoding. Omission and explicit #0 select
        # different S bits; retain both rather than discarding this record.
        kind = re.match(r"<([BWX])t>", template)[1]
        return {"rule": result["rule"] + ":byte-lsl",
                "matcher": f"{kind}, RefIndexLSL",
                "processor": "R(0), R(5), R(16), Ubits(12, 1)"}
    return result


def normalize(inventory, xml, dynasm, batch="B1"):
    inv = json.loads(inventory.read_bytes())
    lock = json.loads((HERE / "source-lock.json").read_bytes())
    require(inv["source_lock"] == lock, "inventory", "source lock mismatch")
    families = B1 if batch == "B1" else B2
    extension = batch.startswith('E')
    plans = json.loads((HERE / 'extension-batches.json').read_bytes()) if extension else {}
    if extension:
        require(plans.get('format_version') == 1 and plans['source_version'] == lock['version']['ref'], batch, 'extension source version changed')
        require(batch in plans['batches'], batch, 'unknown extension batch')
    plan = plans['batches'][batch] if extension else None
    selected_ids = set(plan['planned_records']) if extension else set()
    expected = len(plan['planned_records']) if extension else {"B1": 327, "B2": 191, "B3": 369, "B4": 257}[batch]
    records = ([r for r in inv['records'] if r['id'] in selected_ids] if extension else
               [r for r in inv["records"] if r["scope"]["status"] == "selected-candidate"
               and ((r["group"] in {"control", "dpimm", "dpreg", "reserved"}) if batch == "B4" else
                    (r["group"] == "ldst") if batch == "B3" else
                    (r["group"] == "simd_dp" and r["id"].split("/")[3] in families))])
    require(len(records) == expected, batch, "declared source set changed")
    by_encoding = {}
    for record in records:
        parts = record["node_id"].split("/")
        key = parts[-1] if record["kind"] == "Instruction" else parts[-1] + "_" + parts[-2]
        require(key not in by_encoding, key, "ambiguous encoding identity")
        by_encoding[key] = record
    rules, hashes = read_rules(dynasm)
    tables, names = system_tables(xml) if batch == "B4" else ({}, {})
    forms, rows, xml_hashes, blocked, failures, alternatives = [], 0, {}, set(), [], []
    for path in sorted(xml.glob("*.xml")):
        if path.name.startswith("onebigfile"):
            continue
        for row in xml_rows(path):
            record = by_encoding.get(row["encoding"])
            if record is None:
                continue
            rows += 1
            xml_hashes[path.name] = digest(path.read_bytes())
            hard_mask = sum(1 << i for i, b in enumerate(row["bits"]) if b in {"0", "1"})
            hard_value = sum(1 << i for i, b in enumerate(row["bits"]) if b == "1")
            require(not ((hard_value ^ record["encoding"]["fixed_value"]) & hard_mask
                         & record["encoding"]["fixed_mask"]), row["encoding"], "XML/JSON fixed conflict")
            rule = rules.get((row["mnemonic"], row["template"], row["fields"]))
            if batch == "B4":
                rule = named_rule(row, tables, names) or rule
            if (batch == "B4" or extension) and rule is None:
                rule = scalar_rule(row, record, rules)
            if (batch == "B3" or extension and record['group'] == 'ldst') and (rule is None or rule.get("forget")):
                rule = memory_rule(row, record, rules)
            if rule is None and (batch in {"B2", "B3", "B4"} or extension):
                rule = compatible_rule(row, rules)
            if rule is None and extension:
                rule = extension_rule(row)
            if rule is None and extension:
                try:
                    rule = modern_rule(row)
                except ValueError:
                    pass
            if rule is None:
                if batch in {"B2", "B3", "B4"} or extension:
                    blocked.add(record["id"])
                    failures.append({"record": record["id"], "encoding": row["encoding"],
                                     "mnemonic": row["mnemonic"], "reason": "missing translation rule"})
                    continue
                rule = modern_rule(row)
            if rule.get("forget"):
                blocked.add(record["id"])
                failures.append({"record": record["id"], "encoding": row["encoding"],
                                 "reason": "ignored source rule"})
                continue
            selected = 0
            for index, (matcher, processor) in enumerate(rule_alternatives(rule)):
                if rule.get("names") and rule["names"][index] != row["title"]:
                    continue
                if rule.get("bits"):
                    expected = rule["bits"][index]
                    require(len(expected) == 32 and set(expected) <= {"0", "1", "x"},
                            rule["rule"], "invalid encoding selector")
                    actual = "".join(b.strip("()") for b in reversed(row["bits"]))
                    if any(a in "01" and b in "01" and a != b for a, b in zip(actual, expected)):
                        continue
                    active_row = {**row, "bits": [e if e in "01" else a for a, e in
                                                 zip(row["bits"], reversed(expected))]}
                else:
                    active_row = row
                if rule.get('output_mnemonics'):
                    active_row = {**active_row, 'mnemonic': rule['output_mnemonics'][index]}
                qs = (0, 1) if any(name in {"V", "RegList"} for name, _ in expressions(matcher)) else (1,)
                options = (2, 3, 6, 7) if any(name == "RefIndex" for name, _ in expressions(matcher)) else (3,)
                if "RefIndex" in matcher and "&[0, 0]" in processor:
                    options = (2, 6, 7) # LSL is the separate byte XML record.
                for q, option in ((q, option) for q in qs for option in options):
                    selected += 1
                    alternative = {"encoding": row["encoding"], "mnemonic": row["mnemonic"],
                                   "matcher": matcher, "q": q, "rule": rule["rule"]}
                    try:
                        expansions = expand_rule(active_row, matcher, processor) if batch == "B4" or extension else [(matcher, processor)]
                        expanded = [compile_form(active_row, record, rule, m, p, q, option) for m, p in expansions]
                        forms.extend(expanded)
                        if rule.get("operand_sources"):
                            for form in expanded:
                                form["operand_source"] = rule["operand_sources"][index]
                        alternatives.append({**alternative, "status": "converted"})
                    except (ValueError, SyntaxError) as exc:
                        alternatives.append({**alternative, "status": "failed"})
                        blocked.add(record["id"])
                        failures.append({"record": record["id"], "encoding": row["encoding"],
                                         "mnemonic": row["mnemonic"], "matcher": matcher,
                                         "processor": processor, "q": q, "reason": str(exc)})
            require(selected > 0, row["encoding"], "no alternative selected for XML entry")
    expected_rows = {'E1': 39, 'E2': 257, 'E3': 218, 'E4': 86}[batch] if extension else {"B1": 361, "B2": 212, "B3": 369, "B4": 257}[batch]
    require(rows == expected_rows, batch, "XML record set changed")
    converted = {f["record_id"] for f in forms}
    require(converted | blocked == {r["id"] for r in records}, batch, "records lost during conversion")
    if batch == "B1":
        require(not blocked and converted == {r["id"] for r in records}, batch, "records lost during conversion")
    forms.sort(key=lambda f: (f["mnemonic"], f["record_id"], canonical(f["operands"])))
    for form in list(forms):
        if form["operands"] and "default" in form["operands"][-1]:
            last = len(form["operands"]) - 1
            require(form["operands"][-1]["default"] == 0, form["encoding_id"], "unsupported default")
            for field in form["fields"]:
                if field["operand"] == last:
                    require(field.get("transform", {}).get("values", [0])[0] == 0,
                            form["encoding_id"], "nonzero encoded default")
            forms.append({**form, "operands": form["operands"][:-1],
                          "fields": [f for f in form["fields"] if f["operand"] != last]})
    for index, form in enumerate(forms):
        form["id"] = f"{batch.lower()}-{index:04}"
    register_data = {}
    if batch == 'B4':
        version = xml.name.removeprefix('ISA_A64_xml_')
        register_data = {'system_registers': read_register_names(
            xml.parents[1] / ('AARCHMRS_OPENSOURCE_' + version) / 'Registers.json', lock['version'])}
    return {"format_version": 1, "batch": batch, "source_lock": lock, **register_data,
            "inventory_sha256": digest(inventory.read_bytes()), "rules_sha256": hashes,
            "xml_sha256": xml_hashes, "planned_records": sorted(r["id"] for r in records),
            "blocked_records": sorted(blocked), "failures": failures,
            "alternatives": alternatives, "xml_entries": rows, "forms": forms}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inventory", type=Path, required=True)
    parser.add_argument("--xml", type=Path, required=True)
    parser.add_argument("--rules", type=Path, required=True)
    parser.add_argument("--batch", choices=("B1", "B2", "B3", "B4", "E1", "E2", "E3", "E4"), default="B1")
    parser.add_argument("--output", type=Path, default=HERE / "rules/b1.json")
    args = parser.parse_args()
    data = normalize(args.inventory, args.xml, args.rules, args.batch)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(canonical(data))
    converted = {f['record_id'] for f in data['forms']}
    print(f"Planned {len(data['planned_records'])}; converted {len(converted)} records, "
          f"{len(data['forms'])} forms; incomplete {len(data['blocked_records'])} records")


if __name__ == "__main__":
    main()

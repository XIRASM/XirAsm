"""Batch all generated A64 forms through natural syntax, direct APIs, and Clang."""

import argparse
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import shutil
import subprocess
import struct
import tempfile
import threading
from functools import lru_cache

MODIFIERS = {'lsl', 'msl', 'lsr', 'asr', 'ror', 'uxtb', 'uxth', 'uxtw', 'uxtx', 'sxtb', 'sxth', 'sxtw', 'sxtx'}
ORACLE_ARCH = 'armv9.6-a+crypto+fp16+fp16fml+memtag+mtetc+occmo+pops+sme+tlbid+tlbiw'

ROOT = Path(__file__).resolve().parents[3]


def run(command, cwd):
    return subprocess.run(list(map(str, command)), cwd=cwd, capture_output=True,
                          text=True, encoding="utf-8", errors="replace", timeout=90)


def success(command, cwd):
    result = run(command, cwd)
    if result.returncode:
        raise RuntimeError(f"{Path(command[0]).name}: {result.stdout[:2000]}\n{result.stderr[:4000]}")
    return result


def includes():
    return [ROOT / "include/arm/a64.inc", ROOT / "include/arm/a64-macros.inc",
            ROOT / "include/arm/a64-b2.inc", ROOT / "include/arm/a64-b2-macros.inc",
            *sorted((ROOT / "include/arm/a64").rglob("*.inc"))]


def sync(xir):
    for source in includes():
        target = xir.parent / "include" / source.relative_to(ROOT / "include")
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        if source.read_bytes() != target.read_bytes():
            raise RuntimeError("installed include hash mismatch")


def spell(operand, register, immediate=0, condition="eq"):
    kind = operand["kind"]
    if kind == "imm":
        value = operand.get("literal", immediate)
        text = str(value) + (".0" if operand.get("float") else "")
        return "#" + text, f"a64_imm({value})"
    if kind == "cond":
        return condition, f'a64_cond("{condition}")'
    if kind == "fp":
        return "#" + repr(immediate), f"a64_fp({immediate!r})"
    if kind == 'name':
        return operand['spelling'], f'a64_name("{operand["spelling"]}")'
    if kind in {'sp', 'wsp'}:
        return kind, f'a64_reg("{kind}")'
    if kind == 'creg':
        return f'c{register}', f'a64_control("c{register}")'
    if kind == 'sysreg':
        text = f's{2+(register >> 14)}_{(register >> 11)&7}_c{(register >> 7)&15}_c{(register >> 3)&15}_{register&7}'
        return text, f'a64_sysreg("{text}")'
    if kind in MODIFIERS:
        return f"{kind} #{immediate}", f'a64_shift("{kind}", {immediate})'
    if operand.get("list_count"):
        texts = [f"v{register if i == 0 else (register+i)&31}.{kind[1:]}" for i in range(operand["list_count"])]
        return "{" + ", ".join(texts) + "}", "a64_reglist(list.of(" + ", ".join(json.dumps(t) for t in texts) + "))"
    text = f"v{register}.{kind[1:]}" if kind.startswith("v") else f"{kind}{register}"
    if kind in {"w", "x"} and register == 31:
        text = kind + "zr"
    return text, f'a64_reg("{text}")'


def fp_value(immediate):
    bits = ((immediate & 128) << 24) | ((0x3e000000 if immediate & 64 else 0x40000000)) | ((immediate & 63) << 19)
    return struct.unpack("<f", struct.pack("<I", bits))[0]


@lru_cache(maxsize=None)
def scalar_domain(special):
    width = 32 if special.endswith('_w') else 64
    mask = (1 << width)-1
    values = set()
    if special.startswith('logical'):
        for size in (2, 4, 8, 16, 32, 64):
            if size > width:
                continue
            for ones in range(1, size):
                for rotation in range(size):
                    run = (1 << ones)-1
                    element = ((run >> rotation) | (run << (size-rotation))) & ((1 << size)-1)
                    values.add(sum(element << i for i in range(0, width, size)))
    else:
        for shift in range(0, width, 16):
            for half in (0, 1, 2, 127, 255, 256, 32767, 32768, 65534, 65535):
                value = half << shift
                values.add(mask ^ value if special.startswith('inverted') else value)
    return tuple(sorted(values))


def scalar_accepts(special, value):
    width = 32 if special.endswith('_w') else 64
    mask = (1 << width)-1
    if value < 0 or value > mask:
        return False
    if special.startswith('logical'):
        return value in scalar_domain(special)
    if special.startswith('inverted'):
        value ^= mask
    return any(value & ~(65535 << shift) == 0 for shift in range(0, width, 16))


def domain(operand):
    if "literal" in operand:
        return [operand["literal"]]
    if operand["kind"] == "fp":
        return [fp_value(i) for i in range(256)]
    if operand.get("special") == "stretched_immediate":
        return [sum(255 << (i*8) for i in range(8) if bits & (1 << i)) for bits in range(256)]
    if operand.get('special', '').startswith(('logical_immediate', 'wide_immediate', 'inverted_wide_immediate')):
        return list(scalar_domain(operand['special']))
    if "allowed" in operand:
        return operand["allowed"]
    if operand["kind"] in {"imm", "target", "sysreg", "creg"} | MODIFIERS:
        low, high = operand.get("min", 0), operand.get("max", 0)
        step = operand.get("multiple", 1)
        if (high-low)//step <= 256:
            return list(range(low, high+1, step))
        return sorted({low, low+step, 0, ((low+high)//(2*step))*step, high-step, high})
    if operand["kind"] == "cond":
        return list(range(operand.get('min', 0), operand.get('max', 15)+1))
    if operand['kind'] in {'sp', 'wsp'}:
        return [31]
    low, high = operand.get('min', 0), operand.get('max', 31)
    return sorted(v for v in {low, high, 0, 1, 3, 7, 15, 16} if low <= v <= high)


def make_case(form, values):
    operands, i = [], 0
    while i < len(values):
        operand, value = form["operands"][i], values[i]
        if operand["kind"].startswith("lane_"):
            text = f"v{value}.{operand['kind'].removeprefix('lane_')}"
            index = values[i+1]
            if operand.get("list_count"):
                registers = [f"v{value if n == 0 else (value+n)&31}.{operand['kind'][-1]}"
                             for n in range(operand["list_count"])]
                operands.append(("{" + ", ".join(registers) + f"}}[{index}]",
                                 "a64_lanelist(list.of(" + ", ".join(map(json.dumps, registers)) + f"), {index})"))
            else:
                operands.append((f"{text}[{index}]", f'a64_lane("{text}", {index})'))
            i += 2
        elif operand["kind"] in {"mem_off", "mem_pre"}:
            base = "sp" if value == 31 else f"x{value}"
            offset = values[i+1]
            pre = operand["kind"] == "mem_pre"
            memory = f"[{base}]" if not pre and offset == 0 else f"[{base}, #{offset}]"
            operands.append((memory + ("!" if pre else ""),
                             f'a64_{"pre" if pre else "mem"}("{base}", {offset})'))
            i += 2
        elif operand["kind"] == "mem_index":
            base = "sp" if value == 31 else f"x{value}"
            extend = form["operands"][i+1]["kind"].removeprefix("idx_")
            reg = values[i+1]
            width = "w" if extend in {"uxtw", "sxtw"} else "x"
            index = width + ("zr" if reg == 31 else str(reg))
            amount = values[i+3]
            modifier = ("" if extend == "lsl" else f", {extend}") if amount == -1 else f", {extend} #{amount}"
            operands.append((f"[{base}, {index}{modifier}]",
                             f'a64_index("{base}", "{index}", "{extend}", {amount})'))
            i += 4
        elif operand["kind"] == "target":
            operands.append((f"#{value}", f"a64_rel({value})"))
            i += 1
        else:
            operands.append(spell({k: v for k, v in operand.items() if k != "literal"}, value, value,
                                  "eq ne cs cc mi pl vs vc hi ls ge lt gt le al nv".split()[value] if operand["kind"] == "cond" else "eq"))
            i += 1
    natural = form["mnemonic"] + " " + ", ".join(p[0] for p in operands)
    if form['mnemonic'] == 'b_cond':
        natural = 'b.' + operands[0][0] + ' ' + operands[1][0]
    # Arm permits the optional LSL #0 here; LLVM 22 only accepts its omission.
    oracle = natural
    if form['mnemonic'] == 'tlbi':
        if form['operand_source']['rt_fixed']:
            oracle = 'tlbi ' + operands[0][0]
        elif len(operands) == 1:
            oracle += ', xzr'
    if form['mnemonic'] == 'ic':
        if operands[0][0] != 'ivau':
            oracle = 'ic ' + operands[0][0]
        elif len(operands) == 1:
            oracle += ', xzr'
    if form["encoding_id"] == "MOVI_asimdimm_N_b" and natural.endswith(", lsl #0"):
        oracle = natural.removesuffix(", lsl #0")
    return {"id": form["id"], "record": form["record_id"], "oracle": oracle,
            "natural": natural,
            "api": f"a64_{form['mnemonic']}(list.of(" + ", ".join(p[1] for p in operands) + "))"}


def constraint_accepts(constraint, values):
    left, right = values[constraint['left']], values[constraint['right']]
    if constraint['kind'] == 'distinct':
        return left != right
    if constraint['kind'] == 'base_distinct':
        return left == 31 or left != right
    if constraint['kind'] == 'next':
        return left == right+1
    if constraint['kind'] == 'sum_max':
        return left+right <= constraint['max']
    raise ValueError(f'unknown constraint: {constraint}')


def accepts(form, values):
    for operand, value in zip(form["operands"], values):
        kind = operand["kind"]
        if kind == 'fp':
            if value not in domain(operand):
                return False
            continue
        maximum = 15 if kind == "cond" else (2**64-1 if kind in {"imm", "target", "fp", "name", "creg", "sysreg"} | MODIFIERS else 31)
        if value < operand.get("min", 0) or value > operand.get("max", maximum):
            return False
        if "literal" in operand and value != operand["literal"]:
            return False
        if "allowed" in operand and value not in operand["allowed"]:
            return False
        if value % operand.get("multiple", 1):
            return False
        if operand.get('special', '').startswith(('logical_immediate', 'wide_immediate', 'inverted_wide_immediate')) and not scalar_accepts(operand['special'], value):
            return False
    return all(constraint_accepts(c, values) for c in form.get('constraints', []))


def valid_seed(form, domains, fixed=None):
    values = [d[min(i+1, len(d)-1)] for i, d in enumerate(domains)]
    if fixed:
        values[fixed[0]] = fixed[1]
    involved = sorted({c[k] for c in form.get("constraints", []) for k in ("left", "right")}
                      - ({fixed[0]} if fixed else set()))
    assigned = set(range(len(values))) - set(involved)
    constraints = form.get('constraints', [])
    def search(depth):
        if depth == len(involved):
            return values.copy() if accepts(form, values) else None
        index = involved[depth]
        assigned.add(index)
        operand = form['operands'][index]
        for value in domains[index]:
            if value % operand.get('multiple', 1):
                continue
            values[index] = value
            if all(constraint_accepts(c, values) for c in constraints
                   if c['left'] in assigned and c['right'] in assigned):
                result = search(depth+1)
                if result is not None:
                    return result
        assigned.remove(index)
        return None
    result = search(0)
    if result is not None:
        return result
    raise ValueError(f"no valid test seed for {form['id']} {fixed}")


def form_domains(form):
    domains = [domain(o) for o in form['operands']]
    if any(c['kind'] == 'next' for c in form.get('constraints', [])):
        for i, operand in enumerate(form['operands']):
            if operand['kind'] in {'w', 'x'}:
                domains[i] = list(range(operand.get('min', 0), operand.get('max', 31)+1))
    return domains


def cases(forms):
    result = []
    for form in forms:
        domains = form_domains(form)
        vectors = {tuple(d[0] for d in domains), tuple(d[-1] for d in domains)}
        for index, values in enumerate(domains):
            for value in values:
                try:
                    vector = valid_seed(form, domains, (index, value)) if form.get("constraints") else [d[min(i+1, len(d)-1)] for i, d in enumerate(domains)]
                except ValueError:
                    # Pair constraints can make an individual register impossible in this slot.
                    if any(c['kind'] == 'next' for c in form.get('constraints', [])):
                        continue
                    raise
                vector[index] = value
                vectors.add(tuple(vector))
        # Historical B1/B2 domains include special values checked by their helpers.
        result.extend(make_case(form, values) for values in sorted(vectors)
                      if not form["id"].startswith(("b3-", "b4-", "e")) or accepts(form, values))
    return result


def rejection_cases(forms):
    by_shape = defaultdict(list)
    def shape(form):
        return (form["mnemonic"], tuple((o["kind"], o.get("list_count", 0)) for o in form["operands"]))
    for form in forms:
        by_shape[shape(form)].append(form)
    result = {}
    for form in forms:
        values = valid_seed(form, [domain(o) for o in form["operands"]]) if form["id"].startswith(("b3-", "b4-", "e")) else [domain(o)[0] for o in form["operands"]]
        for index, operand in enumerate(form["operands"]):
            if operand["kind"] in {"fp", "name", "sp", "wsp"} or operand.get("special"):
                continue
            low = operand.get("literal", operand.get("min", 0))
            high = operand.get("literal", operand.get("max", 15 if operand["kind"] == "cond" else 31))
            invalid = {low-1, high+1}
            if operand.get("multiple", 1) > 1:
                invalid.add(low+1)
            if "allowed" in operand:
                invalid |= set(range(low, high+1)) - set(operand["allowed"])
            for value in invalid:
                candidate = values.copy()
                candidate[index] = value
                # The option slot is derived from the index descriptor, not user input.
                if index and form["operands"][index-1]["kind"].startswith("idx_"):
                    continue
                if not any(accepts(f, candidate) for f in by_shape[shape(form)]):
                    # Invalid condition values cannot be rendered as a condition spelling.
                    if operand["kind"] == "cond":
                        continue
                    case = make_case(form, candidate)
                    result[case["natural"]] = case
    return list(result.values())


def verify_rejections(args, out, forms):
    negatives = rejection_cases(forms)
    extras = [
        "fmla v0.4s, v1.4s, v16.h[0]", "fmla v0.4s, v1.4s, v2.4s, #0",
        "dup v0.4s, v1.4s, #0", "dup v0.4s, v1.s", "ins v0.h[0], v1.s[0]",
        "tbl v0.16b, v1.16b, v2.16b", "tbl v0.16b, {}, v2.16b",
        "tbl v0.16b, {v0.16b, v2.16b}, v2.16b",
        "tbl v0.16b, {v0.16b, v1.8b}, v2.16b",
        "tbl v0.16b, {v0.16b-v4.16b}, v2.16b",
        "fmov s0, sp", "fmov sp, d0", "fmov s0, w31", "fmov d0, x31",
        "fmov s0, #0.0", "fmov d0, #-0.0", "fmov h0, #1.1",
        "fmov d0, #0.12499999999999999", "fmov d0, #31.000000000000004",
        "movi d0, #1", "movi v0.2d, #0x00ff00fe00000000",
        "movi v0.4s, #256", "movi v0.4s, #255, msl #0",
        "movi v0.4s, #1, lsr #8", "movi v0.16b, #1, lsl #8",
        "shl v0.1d, v1.1d, #1", "fmla v0.4d, v1.4d, v2.d[0]",
        "shl d0, d1, #0.0", "fcmp d0, #1.0",
        "const foo: u64 = 8\nmovi v0.4s, #1, lslfoo",
        'a64_fmov(list.of(list.of(24, 256), a64_reg("s0")))',
        'a64_dup(list.of(a64_reg("v0.4s"), list.of(20, 0)))',
        'a64_dup(list.of(a64_reg("v0.4s"), list.of(20, 0, 4)))',
        'a64_shl(list.of(a64_reg("d0"), a64_reg("d1"), list.of(0, 1, 1)))',
        'a64_tbl(list.of(a64_reg("v0.16b"), list.of(10, 0, 0), a64_reg("v2.16b")))',
        'a64_tbl(list.of(a64_reg("v0.16b"), list.of(10, 0, 5), a64_reg("v2.16b")))',
        'a64_ins(list.of(list.of(18, 32, 0), a64_lane("v1.b", 0)))',
        'a64_shl(list.of(a64_reg("d0"), a64_reg("d1"), list.of(25, 0)))',
    ]
    entries = [(surface, case[surface]) for case in negatives for surface in ("natural", "api")]
    entries += [("extra", value) for value in extras]
    entries = entries[args.rejection_start:]
    stopped = threading.Event()
    def check(entry):
        if stopped.is_set():
            return
        directory = out / f"reject-{threading.get_ident()}"
        directory.mkdir(exist_ok=True)
        asm, binary = directory / "reject.asm", directory / "reject.bin"
        asm.write_text('import("arm/a64-macros.inc")\n' + entry + '\n', encoding="ascii")
        result = run([args.xirasm.resolve(), asm, "-o", binary], out)
        if result.returncode == 0 or binary.exists():
            stopped.set()
            raise RuntimeError(f"negative case unexpectedly accepted: {entry}")
    with ThreadPoolExecutor(max_workers=8) as pool:
        for index, _ in enumerate(pool.map(check, (entry for _, entry in entries))):
            if index % 2048 == 0:
                print(f"PASS rejection {index+1}/{len(entries)}", flush=True)
    print(f"PASS {len(entries)} rejection cases", flush=True)
    return len(entries)


def verify_captures(args, out):
    source = '''import("arm/a64-macros.inc")
import("arm/a64-b2-macros.inc")
fn marked(value: u64) -> u64 {
    const stamp: string = sym.unique("evaluations")
    return value;
}
fn marked_fp(value: f64) -> f64 {
    const stamp: string = sym.unique("evaluations")
    return value;
}
macro forward(dst, src, element) {
    const INDEX: u64 = 99
    fmla dst, src, element
}
const INDEX: u64 = 1
forward v0.4s, v1.4s, v2.s[marked(INDEX)]
shl d0, d1, #marked(3)
movi v0.4s, #marked(255), lsl #marked(8)
fmov d0, #marked_fp(1.5)
tbl v0.16b, {v31.16b-v1.16b}, v2.16b
fcmp d0, #marked_fp(0.0)
assert(sym.unique("evaluations") == "evaluations__6", "operand evaluated more than once")
'''
    expected_asm = 'fmla v0.4s, v1.4s, v2.s[1]\nshl d0, d1, #3\nmovi v0.4s, #255, lsl #8\nfmov d0, #1.5\ntbl v0.16b, {v31.16b, v0.16b, v1.16b}, v2.16b\nfcmp d0, #0.0\n'
    asm, binary = out / "capture.asm", out / "capture.bin"
    ref, obj, expected = out / "capture.s", out / "capture.o", out / "capture.expected"
    asm.write_text(source, encoding="ascii")
    ref.write_text('.text\n' + expected_asm, encoding="ascii")
    success([args.clang, "--target=aarch64-linux-gnu", "-c", ref, "-o", obj], out)
    success([args.objcopy, "-O", "binary", "--only-section=.text", obj, expected], out)
    success([args.xirasm.resolve(), asm, "-o", binary], out)
    words = expected.read_bytes()
    if binary.read_bytes() != words:
        raise RuntimeError("capture forwarding/single evaluation mismatch")
    asm.write_text('''import("arm/a64-macros.inc")
fn forbidden() -> u64 {
    assert(false, "UNEXPECTED_EVALUATION")
    return 0;
}
fmla v0.4s, x1, v2.s[forbidden()]
''', encoding="ascii")
    result = run([args.xirasm.resolve(), asm, "-o", out / "shape.bin"], out)
    if result.returncode == 0 or "UNEXPECTED_EVALUATION" in result.stderr or "invalid operand classes" not in result.stderr:
        raise RuntimeError("invalid shape evaluated an expression or failed for the wrong reason: " + result.stderr)
    print("PASS captures, single evaluation, register range, shared imports and shape preflight", flush=True)


def verify(args, out):
    xir = args.xirasm.resolve()
    if args.sync:
        sync(xir)
    for source in includes():
        target = xir.parent / "include" / source.relative_to(ROOT / "include")
        if source.read_bytes() != target.read_bytes():
            raise RuntimeError(f"stale installed include: {source.name}")
    manifest = json.loads((ROOT / "include/arm/a64/generated/manifest.json").read_bytes())
    forms = [f for f in manifest["forms"] if args.batch == "all" or f["id"].startswith(args.batch.lower() + "-")]
    if args.mnemonic:
        forms = [f for f in forms if f["mnemonic"] in args.mnemonic]
    if not forms:
        raise ValueError("no generated forms match the requested selection")
    matrix = ([make_case(f, valid_seed(f, [domain(o) for o in f['operands']])) for f in forms]
              if args.phase == 'smoke' else cases(forms))
    report = {"status": "running", "phase": args.phase, "batch": args.batch,
              "mnemonics": args.mnemonic, "rejection_start": args.rejection_start,
              "records": len({f["record_id"] for f in forms}),
              "forms": len(forms), "macros": len({f["mnemonic"] for f in forms}),
              "validated_records": [], "cases": [],
              "clang": success([args.clang, "--version"], out).stdout.splitlines()[0]}
    (out / "cases.json").write_text(json.dumps(matrix, indent=2), encoding="ascii")
    try:
        for start in (range(0, len(matrix), 256) if args.phase != "rejections" else ()):
            shard = matrix[start:start + 256]
            source, obj, expected = [out / f"positive-{start}.{ext}" for ext in ("s", "o", "expected")]
            source.write_text(".text\n" + "\n".join(c["oracle"] for c in shard) + "\n", encoding="ascii")
            success([args.clang, "--target=aarch64-linux-gnu", '-march=' + ORACLE_ARCH, "-c", source, "-o", obj], out)
            success([args.objcopy, "-O", "binary", "--only-section=.text", obj, expected], out)
            reference = expected.read_bytes()
            for surface, entry in (("natural", "a64-macros"), ("api", "a64")):
                asm, binary = [out / f"{surface}-{start}.{ext}" for ext in ("asm", "bin")]
                asm.write_text(f'import("arm/{entry}.inc")\n' + "\n".join(c[surface] for c in shard) + "\n", encoding="ascii")
                success([xir, asm, "-o", binary], out)
                actual = binary.read_bytes()
                if len(actual) != len(reference) or len(actual) != len(shard)*4:
                    raise RuntimeError(f"word count mismatch {surface} {start}")
                for index, case in enumerate(shard):
                    offset = index*4
                    if actual[offset:offset+4] != reference[offset:offset+4]:
                        raise RuntimeError(f"byte mismatch {surface} {case}: "
                                           f"{actual[offset:offset+4].hex()} != {reference[offset:offset+4].hex()}")
            report["cases"].extend(c["id"] for c in shard)
            if start % 2048 == 0 or start+256 >= len(matrix):
                print(f"PASS {min(start+256, len(matrix))}/{len(matrix)} paired API/macro cases", flush=True)
        negatives = [
            ("abs v32.8b, v0.8b", "natural invalid register"),
            ("add v0.8b, v1.8b, v2.4h", "natural mismatched arrangement"),
            ("a64_abs(list.of(a64_reg(\"x0\"), a64_reg(\"v1.8b\")))", "API invalid operand class"),
            ("a64_add(list.of(a64_reg(\"v0.8b\"), a64_reg(\"v1.8b\")))", "API arity"),
        ]
        for index, (entry, label) in enumerate(negatives):
            asm = out / f"negative-{index}.asm"
            binary = out / f"negative-{index}.bin"
            import_name = "arm/a64-macros.inc" if entry.startswith(tuple(m + " " for m in manifest["macro_mnemonics"])) else "arm/a64.inc"
            asm.write_text(f'import("{import_name}")\n{entry}\n', encoding="ascii")
            result = run([xir, asm, "-o", binary], out)
            if result.returncode == 0 or binary.exists():
                raise RuntimeError(f"negative case unexpectedly accepted: {label}")
            report.setdefault("negatives", []).append(label)
        if len(report["negatives"]) != len(negatives):
            raise RuntimeError("negative accounting changed")
        report["validated_records"] = sorted({case["record"] for case in matrix}) if args.phase != "rejections" else []
        report["rejection_cases"] = verify_rejections(args, out, forms) if args.phase != 'smoke' else 0
        verify_captures(args, out)
        report["status"] = "passed"
    except Exception as exc:
        report["status"] = "failed"
        report["error"] = str(exc)
        raise
    finally:
        (out / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="ascii")


def main(default_batch="all"):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--xirasm", type=Path, default=ROOT / "zig-out/bin/xirasm.exe")
    parser.add_argument("--clang", default=shutil.which("clang") or "clang")
    parser.add_argument("--objcopy", default=shutil.which("llvm-objcopy") or "llvm-objcopy")
    parser.add_argument("--sync", action="store_true")
    parser.add_argument("--batch", choices=("all", "B1", "B2", "B3", "B4", "E1", "E2", "E3", "E4"), default=default_batch)
    parser.add_argument("--phase", choices=("all", "rejections", "smoke"), default="all")
    parser.add_argument("--mnemonic", action="append", help="Restrict regression forms to selected mnemonics")
    parser.add_argument("--rejection-start", type=int, default=0, help="Resume the deterministic rejection matrix at an offset")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.rejection_start < 0 or (args.rejection_start and args.phase != "rejections"):
        parser.error("--rejection-start requires --phase rejections and a non-negative offset")
    if args.output:
        args.output = args.output.resolve()
        args.output.mkdir(parents=True, exist_ok=False)
        verify(args, args.output)
    else:
        with tempfile.TemporaryDirectory(prefix="a64-check-") as directory:
            verify(args, Path(directory))


if __name__ == "__main__":
    main()

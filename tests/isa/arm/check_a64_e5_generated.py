"""Independent Clang differential checks for FEAT_MOPS and FEAT_CSSC."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

from check_a64_generated import ORACLE_ARCH, ROOT, success, sync


RULES = ROOT / "tools/arm64/rules/e5.json"
CONFLICTS = {"abs", "cnt", "smax", "smin", "umax", "umin"}
E5_ORACLE_ARCH = ORACLE_ARCH + "+mops-go"


def reg_name(kind, value):
    if value == 31:
        return "wzr" if kind == "w" else "xzr"
    return f"{kind}{value}"


def mops_kind(mnemonic):
    if mnemonic.startswith("setgo"):
        return "setgo"
    if mnemonic.startswith("set"):
        return "set"
    if mnemonic.startswith("cpy"):
        return "cpy"
    return None


def operand_text(form, values):
    kind = mops_kind(form["mnemonic"])
    if kind is not None:
        regs = [reg_name("x", value) for value in values]
        if kind == "setgo":
            return f"[{regs[0]}]!, {regs[1]}!"
        if kind == "set":
            return f"[{regs[0]}]!, {regs[1]}!, {regs[2]}"
        return f"[{regs[0]}]!, [{regs[1]}]!, {regs[2]}!"
    parts = []
    for operand, value in zip(form["operands"], values):
        if operand["kind"] in {"w", "x"}:
            parts.append(reg_name(operand["kind"], value))
        else:
            parts.append(f"#{value}")
    return ", ".join(parts)


def cases(form):
    register_patterns = [
        (0, 1, 2),
        (30, 29, 28),
        (31, 1, 2),
        (0, 31, 2),
        (0, 1, 31),
    ]
    # Arm's machine-readable grammar permits XZR in MOPS register fields, but
    # LLVM 22 rejects XZR in the bracketed writeback spellings. Keep the Clang
    # differential on mutually accepted syntax; source-domain coverage remains
    # checked by the pinned rules and generator validation.
    if mops_kind(form["mnemonic"]) is not None:
        register_patterns = register_patterns[:2]
    result = []
    for pattern_index, pattern in enumerate(register_patterns):
        values = []
        register_index = 0
        for operand in form["operands"]:
            if operand["kind"] in {"w", "x"}:
                values.append(pattern[register_index])
                register_index += 1
            else:
                low, high = operand.get("min", 0), operand.get("max", 0)
                values.append(low if pattern_index == 0 else high if pattern_index == 1 else 0)
        value_tuple = tuple(values)
        if value_tuple not in result:
            result.append(value_tuple)
    return result


def assemble_pair(args, out, forms):
    matrix = []
    for form in forms:
        for values in cases(form):
            operands = operand_text(form, values)
            matrix.append({
                "form": form["id"],
                "encoding": form["encoding_id"],
                "source": f'{form["mnemonic"]} {operands}',
            })

    reference_source = out / "e5-reference.s"
    reference_object = out / "e5-reference.o"
    reference_binary = out / "e5-reference.bin"
    natural_source = out / "e5-natural.xir"
    natural_binary = out / "e5-natural.bin"
    reference_source.write_text(".text\n" + "\n".join(row["source"] for row in matrix) + "\n",
                                encoding="ascii")
    natural_source.write_text('import("arm/a64-macros.inc")\n' +
                              "\n".join(row["source"] for row in matrix) + "\n",
                              encoding="ascii")
    success([args.clang, "--target=aarch64-linux-gnu", "-march=" + E5_ORACLE_ARCH,
             "-c", reference_source, "-o", reference_object], out)
    success([args.objcopy, "-O", "binary", "--only-section=.text",
             reference_object, reference_binary], out)
    success([args.xirasm.resolve(), natural_source, "-o", natural_binary], out)
    expected = reference_binary.read_bytes()
    actual = natural_binary.read_bytes()
    if actual != expected:
        for index, row in enumerate(matrix):
            start = index * 4
            if actual[start:start + 4] != expected[start:start + 4]:
                raise RuntimeError(
                    f'E5 byte mismatch at {row["form"]} {row["source"]}: '
                    f'{actual[start:start + 4].hex()} != {expected[start:start + 4].hex()}'
                )
        raise RuntimeError("E5 output length mismatch")
    return matrix


def verify_aliases(args, out):
    standard = out / "e5-standard-conflicts.xir"
    aliases = out / "e5-prefixed-conflicts.xir"
    standard_binary = out / "e5-standard-conflicts.bin"
    alias_binary = out / "e5-prefixed-conflicts.bin"
    lines = [
        "abs w0, w1",
        "cnt x2, x3",
        "smax w4, w5, w6",
        "smin x7, x8, #-5",
        "umax w9, w10, #255",
        "umin x11, x12, x13",
    ]
    standard.write_text('import("arm/a64-macros.inc")\n' + "\n".join(lines) + "\n",
                        encoding="ascii")
    aliases.write_text('import("arm/a64-macros.inc")\n' + "\n".join(
        "cssc_" + line for line in lines
    ) + "\n", encoding="ascii")
    success([args.xirasm.resolve(), standard, "-o", standard_binary], out)
    success([args.xirasm.resolve(), aliases, "-o", alias_binary], out)
    if standard_binary.read_bytes() != alias_binary.read_bytes():
        raise RuntimeError("standard CSSC mnemonics differ from cssc_ compatibility aliases")

    neon = out / "e5-neon-conflicts.xir"
    neon_binary = out / "e5-neon-conflicts.bin"
    neon.write_text(
        'import("arm/a64-macros.inc")\n'
        "abs v0.16b, v1.16b\n"
        "cnt v2.16b, v3.16b\n"
        "smax v4.4s, v5.4s, v6.4s\n"
        "smin v7.8h, v8.8h, v9.8h\n"
        "umax v10.16b, v11.16b, v12.16b\n"
        "umin v13.4s, v14.4s, v15.4s\n",
        encoding="ascii",
    )
    success([args.xirasm.resolve(), neon, "-o", neon_binary], out)


def verify_rejections(args, out):
    cases_ = {
        "missing-decoration": "setp x0, x1, x2",
        "wrong-copy-role": "cpyp [x0]!, x1!, x2",
        "trailing-junk": "setp [x0]garbage, x1!junk, x2!",
        "set-source-writeback": "setp [x0]!, x1!, x2!",
        "copy-count-plain": "cpyp [x0]!, [x1]!, x2",
        "set-overlap": "setp [x0]!, x0!, x2",
        "copy-overlap": "cpyp [x0]!, [x1]!, x1!",
        "setgo-overlap": "setgop [x0]!, x0!",
        "signed-underflow": "smax w0, w1, #-129",
        "unsigned-overflow": "umax x0, x1, #256",
    }
    for name, line in cases_.items():
        source = out / f"reject-{name}.xir"
        binary = out / f"reject-{name}.bin"
        source.write_text('import("arm/a64-macros.inc")\n' + line + "\n", encoding="ascii")
        result = subprocess.run(
            [args.xirasm.resolve(), source, "-o", binary],
            cwd=out,
            capture_output=True,
            text=True,
        )
        if result.returncode == 0 or binary.exists() and binary.stat().st_size:
            raise RuntimeError(f"E5 rejection unexpectedly assembled: {line}")


def verify(args, out):
    sync(args.xirasm)
    data = json.loads(RULES.read_bytes())
    forms = data["forms"]
    matrix = assemble_pair(args, out, forms)
    verify_aliases(args, out)
    verify_rejections(args, out)
    report = {
        "status": "passed",
        "records": len(set(data["planned_records"])),
        "forms": len(forms),
        "clang_pairs": len(matrix),
        "standard_conflict_mnemonics": sorted(CONFLICTS),
        "negative_cases": 10,
    }
    (out / "report.json").write_text(json.dumps(report, indent=2), encoding="ascii")
    print(report)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--xirasm", type=Path, default=ROOT / "zig-out/bin/xirasm.exe")
    parser.add_argument("--clang", default=shutil.which("clang") or "clang")
    parser.add_argument("--objcopy", default=shutil.which("llvm-objcopy") or "llvm-objcopy")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.output:
        args.output = args.output.resolve()
        args.output.mkdir(parents=True, exist_ok=False)
        verify(args, args.output)
    else:
        with tempfile.TemporaryDirectory(prefix="a64-e5-check-") as directory:
            verify(args, Path(directory))


if __name__ == "__main__":
    main()

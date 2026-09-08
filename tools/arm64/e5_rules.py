"""Finite-form translation rules for batch E5 (FEAT_MOPS, FEAT_CSSC).

The matcher/processor command language is the same one used by normalize_a64.py
(adapted from dynasm-rs, MPL-2.0). Unlike the earlier extension batches these two
families do not appear in the static dynasm tables, so their finite forms are
declared here instead of being discovered from tl_*.py.

Layout summary, every value pinned to the A64 XML regdiagrams:

* CSSC dp_1src (ABS/CNT/CTZ):       <Wd>,<Wn>          -> R(0), R(5)
* CSSC dp_2src (SMAX/SMIN/UMAX/UMIN):<Wd>,<Wn>,<Wm>     -> R(0), R(5), R(16)
* CSSC minmax immediate:             <Wd>,<Wn>,#imm8    -> R(0), R(5), S/Ubits(10,8)
* MOPS copy (CPY*):                  [<Xd>]!,[<Xs>]!,<Xn>! (operand order d,s,n)
* MOPS set  (SET*/SETG*):            [<Xd>]!,<Xn>!,<Xs>   (operand order d,n,s)
* MOPS set-go (SETGO*, FEAT_MOPS_GO + FEAT_MTE): [<Xd>]!,<Xn>! with Rs RES1.

MOPS square brackets and the writeback "!" carry no encoding bits; the natural
macro layer strips them (see include/arm/a64/mops.inc). The sz field is fixed to
00 for every covered form and the SET op2 selector is taken from the pinned
record, so both are emitted as Static fields.
"""

from __future__ import annotations

from source import require

SIGNED_MINMAX = {"SMAX", "SMIN"}
CSSC_SCALAR_CONFLICTS = {"abs", "cnt", "smax", "smin", "umax", "umin"}


def fragment_value(record, name):
    """Return a fully-fixed encoding fragment's value, or None when dynamic."""
    enc = record["encoding"]
    for frag in enc["fragments"]:
        if frag["name"] != name:
            continue
        width, lsb = frag["width"], frag["lsb"]
        mask = ((1 << width) - 1) << lsb
        if enc["fixed_mask"] & mask == mask:
            return (enc["fixed_value"] >> lsb) & ((1 << width) - 1)
        return None
    return None


def e5_rule(row, record):
    """Map one pinned XML row/record pair to a (matcher, processor) pair.

    Returns None when the row is not an E5 form; normalize_a64_e5 treats that as
    a hard error because every planned record must resolve.
    """
    mnemonic = row["mnemonic"]
    template = row["template"]
    features = record.get("features", [])
    is_mops = any("FEAT_MOPS" in str(f) for f in features)
    if not is_mops:
        width = "X" if row["bits"][31] == "1" else "W"
        if template == f"<{width}d>,<{width}n>":
            return f"{width}, {width}", "R(0), R(5)"
        if template == f"<{width}d>,<{width}n>,<{width}m>":
            return f"{width}, {width}, {width}", "R(0), R(5), R(16)"
        if template.startswith(f"<{width}d>,<{width}n>,#"):
            command = "Sbits(10, 8)" if mnemonic in SIGNED_MINMAX else "Ubits(10, 8)"
            return f"{width}, {width}, Imm", f"R(0), R(5), {command}"
        return None

    # FEAT_MOPS forms always use 64-bit address/count registers.
    if "memset_go" in record["id"]:
        require(template == "[<Xd>]!,<Xn>!", row["encoding"], "unexpected SETGO template")
        op2 = fragment_value(record, "op2")
        require(op2 is not None, row["encoding"], "SETGO op2 is not pinned")
        processor = ("R(0), R(5), Static(16, 0b11111), Static(30, 0b00), "
                     f"Static(12, 0b{op2:04b})")
        return "X, X", processor
    if template == "[<Xd>]!,[<Xs>]!,<Xn>!":
        return "X, X, X", "R(0), R(16), R(5), Static(30, 0b00)"
    if template == "[<Xd>]!,<Xn>!,<Xs>":
        op2 = fragment_value(record, "op2")
        require(op2 is not None, row["encoding"], "SET op2 is not pinned")
        processor = ("R(0), R(5), R(16), Static(30, 0b00), "
                     f"Static(12, 0b{op2:04b})")
        return "X, X, X", processor
    return None

"""Normalize batch E5 (FEAT_MOPS, FEAT_CSSC) into finite A64 forms.

Standalone companion to normalize_a64.py: it reuses xml_rows/compile_form and the
pinned-inventory/XML consistency checks, but sources its translation rules from
e5_rules.py instead of the dynasm static tables and the B/E1-E4 dispatch chain.
The generated rules/e5.json has the same shape as the other batch files so the
shared finite-form renderer can consume it independently.

Usage:
    python normalize_a64_e5.py --inventory inventory.json --xml <xml dir> \
        --plan extension-batch-e5.json --output rules/e5.json
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from normalize_a64 import xml_rows, compile_form
from e5_rules import e5_rule
from source import canonical, digest, require

HERE = Path(__file__).resolve().parent
BATCH = "E5"


def normalize(inventory: Path, xml: Path, plan_path: Path):
    inv = json.loads(inventory.read_bytes())
    lock = json.loads((HERE / "source-lock.json").read_bytes())
    require(inv["source_lock"] == lock, "inventory", "source lock mismatch")

    plan_doc = json.loads(plan_path.read_bytes())
    require(plan_doc.get("format_version") == 1
            and plan_doc.get("source_version") == lock["version"]["ref"],
            BATCH, "plan source version changed")
    plan = plan_doc["batches"][BATCH]
    selected = set(plan["planned_records"])
    records = [r for r in inv["records"] if r["id"] in selected]
    require(len(records) == len(selected), BATCH, "declared source set changed")

    by_encoding = {}
    for record in records:
        parts = record["node_id"].split("/")
        key = parts[-1] if record["kind"] == "Instruction" else parts[-1] + "_" + parts[-2]
        require(key not in by_encoding, key, "ambiguous encoding identity")
        by_encoding[key] = record

    forms, xml_entries, xml_hashes = [], 0, {}
    alternatives, blocked, failures = [], set(), []
    for path in sorted(xml.glob("*.xml")):
        if path.name.startswith("onebigfile"):
            continue
        for row in xml_rows(path):
            record = by_encoding.get(row["encoding"])
            if record is None:
                continue
            xml_entries += 1
            xml_hashes[path.name] = digest(path.read_bytes())
            hard_mask = sum(1 << i for i, b in enumerate(row["bits"]) if b in {"0", "1"})
            hard_value = sum(1 << i for i, b in enumerate(row["bits"]) if b == "1")
            enc = record["encoding"]
            require(not ((hard_value ^ enc["fixed_value"]) & hard_mask & enc["fixed_mask"]),
                    row["encoding"], "XML/JSON fixed conflict")

            rule_pair = e5_rule(row, record)
            require(rule_pair is not None, row["encoding"], "missing E5 translation rule")
            matcher, processor = rule_pair
            rule = {"rule": f"e5_rules.py:{row['mnemonic'].lower()}"}
            try:
                form = compile_form(row, record, rule, matcher, processor, row["q"])
            except (ValueError, SyntaxError) as exc:
                blocked.add(record["id"])
                failures.append({"record": record["id"], "encoding": row["encoding"],
                                 "mnemonic": row["mnemonic"], "matcher": matcher,
                                 "processor": processor, "reason": str(exc)})
                alternatives.append({"encoding": row["encoding"], "mnemonic": row["mnemonic"],
                                     "matcher": matcher, "status": "failed"})
                continue
            kind = ("setgo" if form["mnemonic"].startswith("setgo") else
                    "set" if form["mnemonic"].startswith("set") else
                    "cpy" if form["mnemonic"].startswith("cpy") else None)
            if kind == "setgo":
                form["constraints"] = [{"kind": "distinct", "left": 0, "right": 1}]
            elif kind in {"set", "cpy"}:
                form["constraints"] = [
                    {"kind": "distinct", "left": 0, "right": 1},
                    {"kind": "distinct", "left": 0, "right": 2},
                    {"kind": "distinct", "left": 1, "right": 2},
                ]
            forms.append(form)
            alternatives.append({"encoding": row["encoding"], "mnemonic": row["mnemonic"],
                                 "matcher": matcher, "status": "converted"})

    require(not failures, BATCH, "E5 forms failed to compile")
    converted = {f["record_id"] for f in forms}
    require(converted == {r["id"] for r in records}, BATCH, "records lost during conversion")
    require(xml_entries == len(records), BATCH, "XML entry count changed")
    require(all(a["status"] == "converted" for a in alternatives), BATCH,
            "unaccounted translation alternative")

    forms.sort(key=lambda f: (f["mnemonic"], f["record_id"], canonical(f["operands"])))
    for index, form in enumerate(forms):
        form["id"] = f"{BATCH.lower()}-{index:04d}"

    return {"format_version": 1, "batch": BATCH, "source_lock": lock,
            "inventory_sha256": digest(inventory.read_bytes()),
            "xml_sha256": xml_hashes, "planned_records": sorted(r["id"] for r in records),
            "blocked_records": sorted(blocked), "failures": failures,
            "alternatives": alternatives, "xml_entries": xml_entries, "forms": forms}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inventory", type=Path, required=True)
    parser.add_argument("--xml", type=Path, required=True)
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=HERE / "rules/e5.json")
    args = parser.parse_args()
    data = normalize(args.inventory, args.xml, args.plan)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(canonical(data))
    print(f"Planned {len(data['planned_records'])}; converted "
          f"{len({f['record_id'] for f in data['forms']})} records, "
          f"{len(data['forms'])} forms")


if __name__ == "__main__":
    main()

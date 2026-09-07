"""Export an auditable A64 inventory and the reviewed SIMD pilot mapping."""

from __future__ import annotations

import argparse
from collections import Counter
from pathlib import Path
import re
import sys
import tempfile

from source import (InputError, NODE_TYPES, baseline_possible, canonical,
                    feature_names, literal_choices, load_json, merge_encoding,
                    objects, pointer_part, read_source, require, rule_closure,
                    rule_references, summarize_encoding)

HERE = Path(__file__).resolve().parent
TRUE = {"_type": "AST.Bool", "value": True}
PILOT = {name + "_asimdsame_only": name.lower() for name in ("ADD", "SUB", "MUL", "AND", "ORR")}


def map_pilot(record, rules):
    raw, encoding = record["source"], record["encoding"]
    name, at = raw["name"], record["pointer"]
    mnemonic = PILOT[name]
    require(raw["_type"] == "Instruction.Instruction", at, "pilot must be an instruction")
    require(all(raw.get(key) is None for key in
                ("assemble", "disassemble", "assertions", "decode", "preferred")) and
            not raw.get("properties"), at, "pilot has unmapped semantics")
    for condition in record["conditions"]:
        expr = condition["expression"]
        require(expr == TRUE or (expr.get("_type") == "AST.Function" and
                expr.get("name") == "IsFeatureImplemented" and
                expr.get("arguments") == [{"_type": "AST.Identifier", "value": "FEAT_AdvSIMD"}]
                and not expr.get("parameters")), at, "pilot has unmapped inherited condition")
    require(encoding["covered_mask"] == 0xFFFFFFFF and not encoding["should_be_mask"],
            at, "pilot has missing or should-be bits")
    fields = {}
    variable_mask = 0
    for part in encoding["fragments"]:
        mask = ((1 << part["width"]) - 1) << part["lsb"]
        if mask & ~encoding["fixed_mask"]:
            require(not mask & encoding["fixed_mask"] and part["name"] is not None and
                    part["field_lsb"] == 0 and part["name"] not in fields,
                    at, "pilot has unsupported partial or split field")
            fields[part["name"]] = {"lsb": part["lsb"], "width": part["width"]}
            variable_mask |= mask
    expected = {"Rd": 5, "Rn": 5, "Rm": 5, "Q": 1}
    if mnemonic in {"add", "sub", "mul"}:
        expected["size"] = 2
    require({key: value["width"] for key, value in fields.items()} == expected and
            variable_mask | encoding["fixed_mask"] == 0xFFFFFFFF,
            at, "pilot variable fields differ from reviewed family")
    symbols = raw["assembly"]["symbols"]
    require(len(symbols) == 13, at, "pilot syntax shape changed")
    for index, value in ((0, mnemonic.upper()), (3, "."), (7, "."), (11, ".")):
        require(symbols[index] == {"_type": "Instruction.Symbols.Literal", "value": value},
                at, "pilot literal changed")
    for index, rule in ((1, "SPACE"), (5, "COMMA"), (9, "COMMA")):
        require(symbols[index] == {"_type": "Instruction.Symbols.RuleReference", "rule_id": rule},
                at, "pilot separator changed")
    arrangement_rules = {symbols[index].get("rule_id") for index in (4, 8, 12)}
    require(len(arrangement_rules) == 1 and None not in arrangement_rules, at,
            "pilot arrangements must share one rule")
    arrangements = {}
    for literal in literal_choices(next(iter(arrangement_rules)), rules):
        match = re.fullmatch(r"([1-9][0-9]*)([BHSD])", literal)
        require(match is not None, at, "unrecognized arrangement literal")
        lanes, size = int(match[1]), "BHSD".index(match[2])
        bits = lanes * (8 << size)
        require(bits in {64, 128}, at, "unsupported vector width")
        arrangements[literal.lower()] = {"lanes": lanes, "element_bits": 8 << size,
                                          "Q": int(bits == 128), "size": size,
                                          "dsl_id": (size << 1) | int(bits == 128)}
    encoded_in = raw.get("_meta", {}).get("encoded_in", {})
    for index, display, field in ((2, "<Vd>", "Rd"), (6, "<Vn>", "Rn"), (10, "<Vm>", "Rm")):
        symbol = symbols[index]
        require(symbol.get("_type") == "Instruction.Symbols.RuleReference", at, "expected vector rule")
        rule = rules[symbol["rule_id"]]
        require(rule.get("display") == display and rule.get("assemble") is None and
                rule.get("disassemble") is None and rule.get("condition", TRUE) == TRUE and
                rule.get("symbols", {}).get("symbols") == [
                    {"_type": "Instruction.Symbols.Literal", "value": "V"},
                    {"_type": "Instruction.Symbols.RuleReference", "rule_id": "UInteger"}],
                at, "pilot vector rule changed")
        require(encoded_in.get(display) == [{"_type": "AST.Identifier", "value": field}],
                at, "pilot register field mapping changed")
    require(encoded_in.get("<T>") == [{"_type": "AST.Identifier", "value": field}
                                      for field in (["size", "Q"] if "size" in fields else ["Q"])],
            at, "pilot arrangement field mapping changed")
    return {"record_id": record["id"], "source_pointer": at, "mnemonic": mnemonic,
            "adapter": "advsimd-three-register-v1", "fixed_mask": encoding["fixed_mask"],
            "fixed_value": encoding["fixed_value"], "fields": fields,
            "arrangements": arrangements, "register_tag_range": [128, 159],
            "register_roles": {"vd": "Rd", "vn": "Rn", "vm": "Rm"},
            "api": f"arm64_{mnemonic}_vec", "api_file": "include/arm/arm64/simd.inc",
            "natural_syntax": "pending", "product": "existing-handwritten",
            "independent_validation": "pending-production-integration"}


def build_inventory(data, features, schemas, lock, scope):
    require(scope.get("format_version") == 1 and scope.get("isa") == "A64",
            "scope", "unsupported scope manifest")
    require(isinstance(scope.get("groups"), dict) and
            all(value in {"regular", "scalable"} for value in scope["groups"].values()),
            "scope", "unknown group classification")
    require(isinstance(scope.get("baseline_features"), list) and
            all(isinstance(name, str) for name in scope["baseline_features"]) and
            len(scope["baseline_features"]) == len(set(scope["baseline_features"])),
            "scope", "invalid baseline feature list")
    require(data.get("_type") == "Instruction.Instructions", "/", "expected Instructions")
    require(isinstance(data.get("instructions"), list), "/instructions", "expected ISA list")
    roots = [(i, node) for i, node in enumerate(data["instructions"]) if node.get("name") == "A64"]
    require(len(roots) == 1, "/instructions", "expected exactly one A64 root")
    schemas.validate(features, "/features")
    known_features = {node["name"] for _, node in objects(features["parameters"])
                      if node.get("_type", "").startswith("Parameters.") and "name" in node}
    enabled = set(scope["baseline_features"])
    require(enabled <= known_features, "scope", "unknown baseline feature")
    nodes, records, references, used_operations = [], [], [], set()
    counts = Counter()
    record_names = set()

    def operation(name, at, active=()):
        if name is None:
            return None
        require(name not in active, at, "cyclic operation alias")
        require(name in data["operations"], at, f"undefined operation {name}")
        value = data["operations"][name]
        if name not in used_operations:
            schemas.validate(value, "/operations/" + pointer_part(name))
            used_operations.add(name)
        if value["_type"] == "Instruction.OperationAlias":
            return operation(value["operation_id"], at, active + (name,))
        require(value["_type"] == "Instruction.Operation", at, "unsupported operation kind")
        return name

    def walk(node, at, ancestors, parent_bits, conditions, parent_operation=None, parent_kind=None):
        kind = node.get("_type", "").removeprefix("Instruction.")
        require(kind in NODE_TYPES, at, f"unsupported tree node {kind}")
        if parent_kind is None:
            require(kind == "InstructionSet" and node.get("read_width") == 32,
                    at, "expected A64 instruction set")
        else:
            allowed = {"Instruction", "InstructionAlias"} if parent_kind == "Instruction" else {"Instruction", "InstructionGroup"}
            require(kind in allowed, at, "invalid child node kind")
        schemas.validate(node, at, tree_node=True)
        name = node["name"]
        path = ancestors + [name]
        node_id = "/".join(path)
        counts[kind] += 1
        raw = {k: v for k, v in node.items() if k != "children"}
        bits = parent_bits if kind == "InstructionAlias" else merge_encoding(node["encoding"], parent_bits, at + "/encoding")
        expression = node.get("condition", TRUE)
        inherited = conditions + [{"source": at + "/condition", "expression": expression}]
        feature_set = set()
        for entry in inherited:
            feature_set.update(feature_names(entry["expression"], known_features, entry["source"]))
        op_id = node.get("operation_id") or parent_operation
        terminal = operation(op_id, at + "/operation_id")
        if kind == "InstructionAlias":
            require(terminal == operation(parent_operation, at), at, "alias operation differs from parent")
        nodes.append({"id": node_id, "pointer": at, "source": raw})
        references.extend(rule_references(raw.get("assembly"), at + "/assembly"))
        if kind in {"Instruction", "InstructionAlias"}:
            require(node_id not in record_names, at, f"duplicate A64 record id {node_id}")
            record_names.add(node_id)
            require(len(path) > 2 and path[1] in scope["groups"], at, "unclassified A64 group")
            group = scope["groups"][path[1]]
            possible = [baseline_possible(entry["expression"], enabled) for entry in inherited]
            if group == "scalable":
                classification = {"status": "deferred", "reason": "scalable-register-model"}
            elif False in possible:
                classification = {"status": "deferred", "reason": "feature-or-condition-outside-baseline"}
            else:
                classification = {"status": "selected-candidate", "reason": "baseline-feature-filter"}
            record = {"id": lock["version"]["ref"] + "/" + node_id,
                      "node_id": node_id, "pointer": at, "source": raw,
                      "ancestors": ["/".join(path[:i]) for i in range(1, len(path))],
                      "kind": kind, "group": path[1], "conditions": inherited,
                      "features": sorted(feature_set), "operation_id": op_id,
                      "terminal_operation_id": terminal,
                      "alias_target": "/".join(ancestors) if kind == "InstructionAlias" else None,
                      "encoding": summarize_encoding(bits), "scope": classification,
                      "translation": "unmapped-family", "product": "not-audited",
                      "evidence": {"bytes": "pending", "negative": "pending",
                                   "natural": "pending", "privilege": "not-classified"}}
            records.append(record)
        children = node.get("children", [])
        require(isinstance(children, list), at + "/children", "expected child list")
        names = [child.get("name") for child in children]
        require(len(names) == len(set(names)), at + "/children", "duplicate sibling names")
        for index, child in enumerate(children):
            walk(child, f"{at}/children/{index}", path, bits, inherited, op_id, kind)

    index, root = roots[0]
    walk(root, f"/instructions/{index}", [], [None] * 32, [])
    require(dict(counts) == lock["a64_node_counts"], "/instructions", "A64 record counts differ from lock")
    reachable = rule_closure(references, data["assembly_rules"], schemas)
    records.sort(key=lambda row: row["id"])
    pilots = []
    for record in records:
        if record["source"]["name"] in PILOT:
            pilots.append(map_pilot(record, data["assembly_rules"]))
            record["translation"] = "advsimd-three-register-v1"
            record["product"] = "existing-handwritten"
    require(len(pilots) == len(PILOT), "pilot", "missing pilot record")
    # The nodes table owns raw source once; records reference it through node_id.
    for record in records:
        del record["source"]
    summary = {"node_counts": dict(counts), "records": len(records),
               "by_group": dict(Counter(r["group"] for r in records)),
               "by_scope": dict(Counter(r["scope"]["status"] for r in records)),
               "by_reason": dict(Counter(r["scope"]["reason"] for r in records)),
               "by_translation": dict(Counter(r["translation"] for r in records)),
               "reachable_rules": len(reachable), "reachable_operations": len(used_operations),
               "pilot_records": len(pilots),
               "pilot_arrangements": sum(len(p["arrangements"]) for p in pilots),
               "instruction_nodes_with_alias_children": len({r["alias_target"] for r in records
                                                              if r["alias_target"] is not None}),
               "completeness": "structural A64 inventory; family semantics and product coverage remain pending"}
    metadata = {"format_version": 1, "reader_version": 1, "source_lock": lock, "scope": scope}
    return {"inventory.json": {**metadata, "nodes": sorted(nodes, key=lambda row: row["id"]), "records": records},
            "rules.json": {name: data["assembly_rules"][name] for name in reachable},
            "operations.json": {name: data["operations"][name] for name in sorted(used_operations)},
            "features.json": features, "pilot.json": {**metadata, "forms": pilots},
            "summary.json": {**metadata, **summary}}


def output_artifacts(output: Path, artifacts: dict, check: bool):
    rendered = {name: canonical(value) for name, value in artifacts.items()}
    if check:
        require(output.is_dir(), "output", "inventory directory missing")
        existing = {path.name for path in output.iterdir()}
        require(existing == set(rendered), "output", "missing or extra inventory artifacts")
        for name, content in rendered.items():
            require((output / name).read_bytes() == content, name, "stale inventory artifact")
        return
    output.mkdir(parents=True, exist_ok=True)
    require(not ({path.name for path in output.iterdir()} - set(rendered)),
            "output", "unrelated files in inventory directory")
    with tempfile.TemporaryDirectory(prefix=".inventory-", dir=output.parent) as staging:
        stage = Path(staging)
        for name, content in rendered.items():
            (stage / name).write_bytes(content)
        for name in rendered:
            (stage / name).replace(output / name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--lock", type=Path, default=HERE / "source-lock.json")
    parser.add_argument("--scope", type=Path, default=HERE / "scope.json")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        require(not args.output.resolve().is_relative_to(args.source_root.resolve()),
                "output", "output must be outside the official source directory")
        lock = load_json(args.lock.read_bytes(), "source lock")
        scope = load_json(args.scope.read_bytes(), "scope")
        data, features, schemas = read_source(args.source_root, lock)
        artifacts = build_inventory(data, features, schemas, lock, scope)
        output_artifacts(args.output, artifacts, args.check)
        report = artifacts["summary.json"]
        print(f"{'CHECK' if args.check else 'PASS'}: {report['records']} A64 records, "
              f"{report['pilot_records']} pilot forms, {report['pilot_arrangements']} arrangements")
        print("Scope:", report["by_scope"], "Translation:", report["by_translation"])
    except (InputError, OSError, KeyError, TypeError, RecursionError) as exc:
        print(f"inventory failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

"""Read pinned AARCHMRS data; architectural expressions remain structured data."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re

from jsonschema import Draft4Validator, ValidationError, validators
from referencing import Registry, Resource
from referencing.jsonschema import DRAFT4

SCHEMA_VERSION = "2.9.5"
SCHEMA_URI = "https://aarchmrs.invalid/schema/"
NODE_TYPES = {"InstructionSet", "InstructionGroup", "Instruction", "InstructionAlias"}


def typed_properties(validator, properties, instance, schema):
    # Reject a mismatched tagged union before descending into its nested fields.
    # This changes only traversal cost, not Draft 4 validation semantics.
    tags = properties.get("_type", {}).get("enum")
    if isinstance(instance, dict) and "_type" in instance and tags and instance["_type"] not in tags:
        yield ValidationError("unexpected type discriminator")
        return
    yield from Draft4Validator.VALIDATORS["properties"](validator, properties, instance, schema)


TypedValidator = validators.extend(Draft4Validator, {"properties": typed_properties})


class InputError(ValueError):
    """An input cannot be interpreted without losing information."""


def require(condition: bool, location: str, message: str) -> None:
    if not condition:
        raise InputError(f"{location}: {message}")


def canonical(value: object) -> bytes:
    return (json.dumps(value, sort_keys=True, indent=2, ensure_ascii=True,
                       allow_nan=False) + "\n").encode("ascii")


def digest(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def load_json(raw: bytes, location: str) -> object:
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, location, f"duplicate JSON key {key!r}")
            result[key] = value
        return result

    def invalid_number(value):
        raise InputError(f"{location}: invalid JSON number {value}")

    try:
        return json.loads(raw, object_pairs_hook=pairs, parse_constant=invalid_number)
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise InputError(f"{location}: invalid JSON") from exc


def pointer_part(value: str) -> str:
    return value.replace("~", "~0").replace("/", "~1")


def objects(value, location=""):
    if isinstance(value, dict):
        yield location, value
        for key, child in value.items():
            yield from objects(child, f"{location}/{pointer_part(key)}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from objects(child, f"{location}/{index}")


class Schemas:
    """Use the supplied schemas through an offline-only reference registry."""

    def __init__(self, contents: dict[str, bytes]):
        self.schemas = {}
        self.hashes = {name: digest(raw) for name, raw in sorted(contents.items())}
        resources = []
        for name, raw in sorted(contents.items()):
            schema = load_json(raw, f"schema/{name}")
            require(schema.get("$schema", "http://json-schema.org/draft-04/schema#") ==
                    "http://json-schema.org/draft-04/schema#", f"schema/{name}", "unsupported schema dialect")
            # Keep the explicitly selected Draft 4 subclass across references.
            # The dialect declaration otherwise reselects the stock validator.
            schema.pop("$schema", None)
            resources.append((SCHEMA_URI + name,
                              Resource.from_contents(schema, default_specification=DRAFT4)))
            self.schemas[name.removesuffix(".json").replace("/", ".")] = schema
        self.registry = Registry().with_resources(resources)
        self.validators = {}

    def validate(self, node: dict, location: str, *, tree_node=False):
        kind = node.get("_type")
        require(kind in self.schemas, location, f"unknown typed structure {kind!r}")
        if kind not in self.validators:
            uri = SCHEMA_URI + kind.replace(".", "/") + ".json"
            self.validators[kind] = TypedValidator({"$ref": uri}, registry=self.registry)
        # Tree children are validated once each, avoiding repeated subtree walks.
        instance = {k: v for k, v in node.items() if k != "children"} if tree_node else node
        try:
            error = next(self.validators[kind].iter_errors(instance), None)
        except Exception as exc:
            raise InputError(f"{location}: schema reference could not be resolved") from exc
        if error is not None:
            path = "/".join(pointer_part(str(part)) for part in error.absolute_path)
            raise InputError(f"{location}/{path}: schema validation failed ({error.validator})")


def read_source(root: Path, lock: dict):
    require(lock.get("lock_version") == 1, "source lock", "unsupported lock version")
    require(lock.get("version", {}).get("schema") == SCHEMA_VERSION,
            "source lock", "unsupported schema version")
    documents = {}
    for name in ("Instructions.json", "Features.json"):
        raw = (root / name).read_bytes()
        require(digest(raw) == lock["files"].get(name), name, "source hash mismatch")
        doc = load_json(raw, name)
        require(isinstance(doc, dict), name, "expected object")
        require(doc.get("_meta", {}).get("version") == lock["version"], name,
                "source metadata differs from lock")
        documents[name] = doc
    schema_files = {p.relative_to(root / "schema").as_posix(): p.read_bytes()
                    for p in sorted((root / "schema").rglob("*.json"))}
    schemas = Schemas(schema_files)
    require(bool(schema_files), "schema", "missing schemas")
    require(digest(canonical(schemas.hashes)) == lock.get("schema_tree_sha256"),
            "schema", "schema tree hash mismatch")
    require(len(schema_files) == lock.get("schema_files"), "schema", "schema count mismatch")
    return documents["Instructions.json"], documents["Features.json"], schemas


def bit_value(value, width: int, location: str, *, wildcard=True) -> str:
    require(isinstance(value, dict) and value.get("_type") == "Values.Value",
            location, "unsupported bit value structure")
    spelling = value.get("value")
    pattern = r"'[01x]+'" if wildcard else r"'[01]+'"
    require(isinstance(spelling, str) and re.fullmatch(pattern, spelling) is not None,
            location, "unsupported bit value spelling")
    bits = spelling[1:-1]
    require(len(bits) == width, location, "bit value width mismatch")
    return bits


def merge_encoding(encoding: dict, parent: list, location: str) -> list:
    """Inherit unspecified bits; retain field fragments and separate should-be bits."""
    require(encoding.get("_type") == "Instruction.Encodeset.Encodeset",
            location, "expected Encodeset")
    require(type(encoding.get("width")) is int and encoding["width"] == 32,
            location, "A64 encodings must be 32 bits")
    require(len(parent) == 32, location, "invalid parent encoding width")
    result = list(parent)
    covered = 0
    for index, field in enumerate(encoding["values"]):
        at = f"{location}/values/{index}"
        require(field.get("_type") in {"Instruction.Encodeset.Field", "Instruction.Encodeset.Bits"},
                at, "unsupported encodeset member")
        span = field["range"]
        start, width = span["start"], span["width"]
        require(type(start) is int and type(width) is int and
                0 <= start < 32 and 0 < width <= 32 - start, at, "invalid bit range")
        mask = ((1 << width) - 1) << start
        require(not (covered & mask), at, "overlapping local bit ranges")
        covered |= mask
        bits = bit_value(field["value"], width, at + "/value")
        should = bit_value(field["should_be_mask"], width, at + "/should_be_mask", wildcard=False)
        name = field.get("name")
        for offset, (bit, preferred) in enumerate(zip(reversed(bits), reversed(should))):
            position = start + offset
            previous = parent[position]
            require(preferred != "1" or bit != "x", at, "should-be bit has no value")
            old_hard = previous and previous["value"] != "x" and not previous["should_be"]
            new_hard = bit != "x" and preferred == "0"
            if old_hard:
                require(not new_hard or bit == previous["value"], at,
                        f"contradictory inherited fixed bit {position}")
                bit, preferred = previous["value"], "0"
            result[position] = {"value": bit, "should_be": preferred == "1",
                                "field": name, "field_bit": offset, "source": at}
    return result


def summarize_encoding(bits: list) -> dict:
    fixed_mask = fixed_value = should_mask = should_value = covered = 0
    fragments = []
    for position, slot in enumerate(bits):
        if slot is None:
            continue
        covered |= 1 << position
        if slot["value"] != "x":
            if slot["should_be"]:
                should_mask |= 1 << position
                should_value |= int(slot["value"]) << position
            else:
                fixed_mask |= 1 << position
                fixed_value |= int(slot["value"]) << position
        if (fragments and fragments[-1]["source"] == slot["source"] and
                fragments[-1]["lsb"] + fragments[-1]["width"] == position and
                fragments[-1]["field_lsb"] + fragments[-1]["width"] == slot["field_bit"]):
            fragments[-1]["width"] += 1
        else:
            fragments.append({"name": slot["field"], "lsb": position, "width": 1,
                              "field_lsb": slot["field_bit"], "source": slot["source"]})
    return {"width": 32, "fixed_mask": fixed_mask, "fixed_value": fixed_value,
            "should_be_mask": should_mask, "should_be_value": should_value,
            "covered_mask": covered, "fragments": fragments}


def feature_names(condition: dict, known: set[str], location: str) -> list[str]:
    names = set()
    for at, node in objects(condition, location):
        if node.get("_type") == "AST.Function" and node.get("name") == "IsFeatureImplemented":
            args = node.get("arguments")
            require(isinstance(args, list) and len(args) == 1 and
                    args[0].get("_type") == "AST.Identifier" and not node.get("parameters"),
                    at, "unsupported feature predicate")
            name = args[0]["value"]
            require(name in known, at, f"undefined feature {name}")
            names.add(name)
    return sorted(names)


def baseline_possible(condition: dict, enabled: set[str]):
    """Three-valued filter only; None preserves operand-dependent conditions."""
    kind = condition.get("_type")
    if kind == "AST.Bool":
        return condition["value"]
    if kind == "AST.Function" and condition["name"] == "IsFeatureImplemented":
        return condition["arguments"][0]["value"] in enabled
    if kind == "AST.UnaryOp" and condition["op"] == "!":
        value = baseline_possible(condition["expr"], enabled)
        return None if value is None else not value
    if kind == "AST.BinaryOp" and condition["op"] in {"&&", "||"}:
        left = baseline_possible(condition["left"], enabled)
        right = baseline_possible(condition["right"], enabled)
        if condition["op"] == "&&":
            return False if left is False or right is False else True if left is True and right is True else None
        return True if left is True or right is True else False if left is False and right is False else None
    return None


def rule_references(value: dict, location: str):
    for at, node in objects(value, location):
        if node.get("_type") == "Instruction.Symbols.RuleReference":
            yield at, node["rule_id"]


def rule_closure(roots, rules, schemas) -> list[str]:
    visited, active = set(), set()

    def visit(name, at):
        require(name in rules, at, f"undefined assembly rule {name}")
        # Recursive list grammar is valid; preserve references without expanding.
        if name in active:
            return
        if name in visited:
            return
        active.add(name)
        rule = rules[name]
        source = "/assembly_rules/" + pointer_part(name)
        require(rule.get("_type") in {"Instruction.Rules.Rule", "Instruction.Rules.Choice",
                                      "Instruction.Rules.Token"}, source, "unsupported rule kind")
        schemas.validate(rule, source)
        for child_at, child in rule_references(rule, source):
            visit(child, child_at)
        active.remove(name)
        visited.add(name)

    for at, name in roots:
        visit(name, at)
    return sorted(visited)


def literal_choices(name: str, rules: dict, active=()) -> list[str]:
    at = "/assembly_rules/" + pointer_part(name)
    require(name not in active and name in rules, at, "invalid literal rule reference")
    node = rules[name]
    if node["_type"] == "Instruction.Rules.Choice":
        assemblies = node["choices"]
    else:
        require(node["_type"] == "Instruction.Rules.Rule", at, "expected literal rule")
        require(node.get("assemble") is None and node.get("disassemble") is None and
                node.get("condition", {"_type": "AST.Bool", "value": True}) ==
                {"_type": "AST.Bool", "value": True}, at, "literal rule has semantics")
        assemblies = [node["symbols"]]
    values = []
    for assembly in assemblies:
        require(assembly is not None and len(assembly["symbols"]) == 1,
                at, "expected a single literal alternative")
        symbol = assembly["symbols"][0]
        if symbol["_type"] == "Instruction.Symbols.Literal":
            values.append(symbol["value"])
        else:
            require(symbol["_type"] == "Instruction.Symbols.RuleReference", at, "unknown literal symbol")
            values.extend(literal_choices(symbol["rule_id"], rules, active + (name,)))
    require(len(values) == len(set(values)), at, "duplicate literal alternatives")
    return values

"""Reader/generator boundary tests; no architecture download is required."""

import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tools" / "arm64"))

from inventory import build_inventory, output_artifacts
from source import (InputError, Schemas, TypedValidator, baseline_possible, bit_value,
                    canonical, feature_names, literal_choices, load_json,
                    merge_encoding, read_source, rule_closure, summarize_encoding)
from jsonschema import Draft4Validator


def field(start=0, width=4, value="xxxx", name="Rd", should="0000"):
    return {"_type": "Instruction.Encodeset.Field", "name": name,
            "range": {"start": start, "width": width},
            "value": {"_type": "Values.Value", "value": f"'{value}'"},
            "should_be_mask": {"_type": "Values.Value", "value": f"'{should}'"}}


def encoding(*fields):
    return {"_type": "Instruction.Encodeset.Encodeset", "width": 32, "values": list(fields)}


def literal(value):
    return {"_type": "Instruction.Symbols.Literal", "value": value}


def reference(name):
    return {"_type": "Instruction.Symbols.RuleReference", "rule_id": name}


def assembly(*symbols):
    return {"_type": "Instruction.Assembly", "symbols": list(symbols)}


def rule(symbol):
    return {"_type": "Instruction.Rules.Rule", "symbols": assembly(symbol)}


def feature(name):
    return {"_type": "AST.Function", "name": "IsFeatureImplemented",
            "arguments": [{"_type": "AST.Identifier", "value": name}]}


class EncodingTests(unittest.TestCase):
    def test_low_bit_and_partial_constant(self):
        bits = merge_encoding(encoding(field(9, 4, "10x1")), [None] * 32, "test")
        result = summarize_encoding(bits)
        self.assertEqual(result["fixed_mask"], 0b1101 << 9)
        self.assertEqual(result["fixed_value"], 0b1001 << 9)

    def test_inherit_unspecified_bits(self):
        parent = merge_encoding(encoding(field(28, 4, "1010")), [None] * 32, "parent")
        bits = merge_encoding(encoding(field()), parent, "child")
        self.assertEqual(summarize_encoding(bits)["fixed_value"], 0xA0000000)
        self.assertEqual(bits[28]["source"], "parent/values/0")

    def test_inherited_hard_bit_is_not_relaxed(self):
        parent = merge_encoding(encoding(field(value="1010")), [None] * 32, "parent")
        bits = merge_encoding(encoding(field()), parent, "child")
        self.assertEqual(summarize_encoding(bits)["fixed_mask"], 15)
        self.assertEqual(summarize_encoding(bits)["fixed_value"], 10)

    def test_child_field_replaces_part_of_parent_field(self):
        parent = merge_encoding(encoding(field(0, 8, "xxxxxxxx", should="00000000")),
                                [None] * 32, "parent")
        bits = merge_encoding(encoding(field(2, 2, "xx", "child", "00")), parent, "child")
        fragments = summarize_encoding(bits)["fragments"]
        self.assertEqual([(f["lsb"], f["width"], f["field_lsb"]) for f in fragments],
                         [(0, 2, 0), (2, 2, 0), (4, 4, 4)])

    def test_should_be_is_not_hard_fixed(self):
        bits = merge_encoding(encoding(field(value="1010", should="0101")), [None] * 32, "test")
        result = summarize_encoding(bits)
        self.assertEqual(result["fixed_mask"], 10)
        self.assertEqual(result["should_be_mask"], 5)
        self.assertEqual(result["should_be_value"], 0)

    def test_child_can_refine_should_be(self):
        parent = merge_encoding(encoding(field(value="0000", should="1111")), [None] * 32, "parent")
        bits = merge_encoding(encoding(field(value="1010")), parent, "child")
        self.assertEqual(summarize_encoding(bits)["fixed_value"], 10)

    def test_uncovered_bits_remain_uncovered(self):
        result = summarize_encoding(merge_encoding(encoding(), [None] * 32, "test"))
        self.assertEqual(result["covered_mask"], 0)
        self.assertEqual(result["fixed_mask"], 0)

    def test_conflicting_parent(self):
        parent = merge_encoding(encoding(field(value="1010")), [None] * 32, "parent")
        with self.assertRaisesRegex(InputError, "contradictory inherited"):
            merge_encoding(encoding(field(value="0010")), parent, "child")

    def test_invalid_ranges(self):
        for start, width in ((-1, 4), (32, 1), (30, 4), (0, 0), (0, 33), (False, 4), (0, 4.0)):
            with self.subTest(start=start, width=width), self.assertRaisesRegex(InputError, "invalid bit range"):
                merge_encoding(encoding(field(start, width)), [None] * 32, "test")

    def test_overlapping_local_fields(self):
        with self.assertRaisesRegex(InputError, "overlapping"):
            merge_encoding(encoding(field(), field(2)), [None] * 32, "test")

    def test_unsupported_width(self):
        value = encoding(field())
        value["width"] = 16
        with self.assertRaisesRegex(InputError, "32 bits"):
            merge_encoding(value, [None] * 32, "test")

    def test_unknown_field_kind(self):
        value = field()
        value["_type"] = "Instruction.Encodeset.Future"
        with self.assertRaisesRegex(InputError, "unsupported encodeset"):
            merge_encoding(encoding(value), [None] * 32, "test")

    def test_should_be_requires_value(self):
        with self.assertRaisesRegex(InputError, "no value"):
            merge_encoding(encoding(field(should="0001")), [None] * 32, "test")

    def test_invalid_bit_spellings(self):
        for value in ("0xff", "'01z0'", "'010'", "'01010'", 5):
            with self.subTest(value=value), self.assertRaises(InputError):
                bit_value({"_type": "Values.Value", "value": value}, 4, "test")


class ReferenceTests(unittest.TestCase):
    @staticmethod
    def permissive_rule_schemas():
        # Only closure behavior is under test here; real schema validation has
        # separate tests and the pinned-source integration check.
        return Schemas({f"Instruction/Rules/{name}.json": canonical({"type": "object"})
                        for name in ("Rule", "Choice", "Token")})

    def test_recursive_grammar_is_preserved_without_expansion(self):
        rules = {"a": rule(reference("b")), "b": rule(reference("a"))}
        self.assertEqual(rule_closure([("root", "a")], rules, self.permissive_rule_schemas()), ["a", "b"])

    def test_missing_grammar_reference(self):
        with self.assertRaisesRegex(InputError, "undefined assembly rule"):
            rule_closure([("root", "a")], {"a": rule(reference("missing"))}, self.permissive_rule_schemas())

    def test_literals_resolve_without_rule_name_semantics(self):
        rules = {"arbitrary": rule(literal("8B")), "option": {
            "_type": "Instruction.Rules.Choice", "choices": [assembly(reference("arbitrary")), assembly(literal("16B"))]}}
        self.assertEqual(literal_choices("option", rules), ["8B", "16B"])

    def test_literal_rule_cycle(self):
        with self.assertRaisesRegex(InputError, "reference"):
            literal_choices("a", {"a": rule(reference("a"))})

    def test_missing_literal_reference(self):
        with self.assertRaisesRegex(InputError, "reference"):
            literal_choices("missing", {})

    def test_semantic_rule_is_not_literal(self):
        value = rule(literal("8B"))
        value["assemble"] = {"_type": "AST.StatementBlock", "statements": []}
        with self.assertRaisesRegex(InputError, "semantics"):
            literal_choices("a", {"a": value})

    def test_no_silent_duplicate_alternatives(self):
        value = {"_type": "Instruction.Rules.Choice", "choices": [assembly(literal("8B"))] * 2}
        with self.assertRaisesRegex(InputError, "duplicate"):
            literal_choices("a", {"a": value})

    def test_unknown_feature(self):
        with self.assertRaisesRegex(InputError, "undefined feature"):
            feature_names(feature("FEAT_unknown"), {"FEAT_FP"}, "test")

    def test_feature_expression_preserved(self):
        value = {"_type": "AST.BinaryOp", "op": "||", "left": feature("FEAT_FP"),
                 "right": feature("FEAT_SVE")}
        original = copy.deepcopy(value)
        self.assertEqual(feature_names(value, {"FEAT_FP", "FEAT_SVE"}, "test"), ["FEAT_FP", "FEAT_SVE"])
        self.assertEqual(value, original)
        self.assertTrue(baseline_possible(value, {"FEAT_FP"}))

    def test_operand_condition_is_unknown(self):
        value = {"_type": "AST.BinaryOp", "op": "==", "left": {"_type": "AST.Identifier", "value": "Rn"},
                 "right": {"_type": "AST.Integer", "value": 31}}
        self.assertIsNone(baseline_possible(value, set()))
        self.assertFalse(baseline_possible({"_type": "AST.BinaryOp", "op": "&&", "left": value,
                                           "right": feature("FEAT_SVE")}, set()))

    def test_multiple_feature_arguments_rejected(self):
        value = feature("FEAT_FP")
        value["arguments"].append(value["arguments"][0])
        with self.assertRaisesRegex(InputError, "unsupported feature"):
            feature_names(value, {"FEAT_FP"}, "test")


class IntegrityTests(unittest.TestCase):
    def test_source_lock_version_and_hash_drift(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaisesRegex(InputError, "lock version"):
                read_source(root, {"lock_version": 9})
            lock = {"lock_version": 1, "version": {"schema": "future"}}
            with self.assertRaisesRegex(InputError, "schema version"):
                read_source(root, lock)
            lock = {"lock_version": 1, "version": {"schema": "2.9.5"},
                    "files": {"Instructions.json": "0" * 64}}
            (root / "Instructions.json").write_bytes(b"{}")
            with self.assertRaisesRegex(InputError, "source hash mismatch"):
                read_source(root, lock)

    def test_referenced_schema_preserves_typed_validation(self):
        schema = {"$schema": "http://json-schema.org/draft-04/schema#", "type": "object",
                  "properties": {"_type": {"enum": ["A"]}, "child": {"$ref": "B.json"}}}
        child = {"$schema": "http://json-schema.org/draft-04/schema#", "type": "object",
                 "properties": {"_type": {"enum": ["B"]}, "value": {"type": "integer"}},
                 "required": ["value"]}
        schemas = Schemas({"A.json": canonical(schema), "B.json": canonical(child)})
        schemas.validate({"_type": "A", "child": {"_type": "B", "value": 5}}, "test")
        with self.assertRaisesRegex(InputError, "schema validation failed"):
            schemas.validate({"_type": "A", "child": {"_type": "B", "value": "bad"}}, "test")

    def test_unknown_schema_dialect(self):
        with self.assertRaisesRegex(InputError, "unsupported schema dialect"):
            Schemas({"A.json": canonical({"$schema": "https://example.invalid/new-schema"})})

    def test_duplicate_json_keys(self):
        with self.assertRaisesRegex(InputError, "duplicate JSON key"):
            load_json(b'{"name":1,"name":2}', "test")

    def test_non_json_numbers(self):
        for token in (b"NaN", b"Infinity", b"-Infinity"):
            with self.subTest(token=token), self.assertRaises(InputError):
                load_json(token, "test")

    def test_canonical_order(self):
        self.assertEqual(canonical({"b": 1, "a": 2}), canonical({"a": 2, "b": 1}))

    def test_unknown_typed_structure(self):
        with self.assertRaisesRegex(InputError, "unknown typed structure"):
            Schemas({}).validate({"_type": "Future"}, "test")

    def test_offline_schema_reference(self):
        schemas = Schemas({"Known.json": canonical({"type": "object", "properties": {
            "child": {"$ref": "https://external.invalid/unavailable.json"}}})})
        with self.assertRaisesRegex(InputError, "could not be resolved"):
            schemas.validate({"_type": "Known", "child": {}}, "test")

    def test_typed_validator_agrees_with_standard(self):
        schema = {"oneOf": [{"type": "object", "properties": {"_type": {"enum": ["A"]},
                   "value": {"type": "integer"}}, "required": ["value"]},
                  {"type": "object", "properties": {"_type": {"enum": ["B"]}, "value": {"type": "string"}},
                   "required": ["value"]}]}
        for value in ({"_type": "A", "value": 5}, {"_type": "B", "value": "x"},
                      {"_type": "A", "value": "x"}, {"value": True}, {"value": 5}, None, {}):
            with self.subTest(value=value):
                self.assertEqual(TypedValidator(schema).is_valid(value), Draft4Validator(schema).is_valid(value))

    def test_missing_stale_and_extra_output(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "result"
            data = {"one.json": {"value": 1}, "two.json": []}
            with self.assertRaisesRegex(InputError, "missing"):
                output_artifacts(output, data, True)
            output_artifacts(output, data, False)
            output_artifacts(output, data, True)
            (output / "one.json").write_text("{}", encoding="ascii")
            with self.assertRaisesRegex(InputError, "stale"):
                output_artifacts(output, data, True)
            output_artifacts(output, data, False)
            (output / "extra").touch()
            with self.assertRaisesRegex(InputError, "extra"):
                output_artifacts(output, data, True)
            with self.assertRaisesRegex(InputError, "unrelated"):
                output_artifacts(output, data, False)


class TreeTests(unittest.TestCase):
    """Tree enumeration and reference integrity independent of family translation."""

    def setUp(self):
        self.schemas = Schemas({name.replace(".", "/") + ".json": canonical({"type": "object"})
                               for name in ("Instruction.InstructionSet", "Instruction.InstructionGroup",
                                            "Instruction.Instruction", "Instruction.InstructionAlias",
                                            "Instruction.Operation", "Instruction.OperationAlias", "Features")})
        def instruction(name):
            return {"_type": "Instruction.Instruction", "name": name, "encoding": encoding(field()),
                    "operation_id": "op", "children": [{"_type": "Instruction.InstructionAlias",
                    "name": "alias", "operation_id": "alias_op", "assembly": assembly(literal("ALIAS"))}]}
        self.data = {"_type": "Instruction.Instructions", "instructions": [
            {"name": "A32", "_type": "ignored-other-isa"},
            {"_type": "Instruction.InstructionSet", "name": "A64", "encoding": encoding(),
             "read_width": 32, "children": [{"_type": "Instruction.InstructionGroup", "name": "dpreg",
                "encoding": encoding(), "children": [instruction("one"), instruction("two")]}]}],
            "assembly_rules": {}, "operations": {"op": {"_type": "Instruction.Operation"},
                "alias_op": {"_type": "Instruction.OperationAlias", "operation_id": "op"}}}
        self.features = {"_type": "Features", "parameters": []}
        self.scope = {"format_version": 1, "isa": "A64", "baseline_features": [],
                      "groups": {"dpreg": "regular"}}
        self.lock = {"version": {"ref": "test"}, "a64_node_counts": {
            "InstructionSet": 1, "InstructionGroup": 1, "Instruction": 2, "InstructionAlias": 2}}

    def build(self):
        with patch.dict("inventory.PILOT", {}, clear=True):
            return build_inventory(self.data, self.features, self.schemas, self.lock, self.scope)

    def test_nonleaf_instructions_and_same_named_aliases_retained(self):
        result = self.build()
        records = result["inventory.json"]["records"]
        self.assertEqual(len(records), 4)
        self.assertEqual(len({r["id"] for r in records}), 4)
        self.assertEqual(result["summary.json"]["instruction_nodes_with_alias_children"], 2)
        self.assertTrue(all("A32" not in r["id"] for r in records))
        self.assertEqual({r["alias_target"] for r in records if r["kind"] == "InstructionAlias"},
                         {"A64/dpreg/one", "A64/dpreg/two"})

    def test_duplicate_a64_root(self):
        self.data["instructions"].append(self.data["instructions"][1])
        with self.assertRaisesRegex(InputError, "exactly one A64"):
            self.build()

    def test_duplicate_sibling_rejected(self):
        children = self.data["instructions"][1]["children"][0]["children"]
        children[1]["name"] = "one"
        with self.assertRaisesRegex(InputError, "duplicate sibling"):
            self.build()

    def test_unexpected_node_kind(self):
        self.data["instructions"][1]["children"][0]["_type"] = "Instruction.Future"
        with self.assertRaisesRegex(InputError, "unsupported tree node"):
            self.build()

    def test_missing_operation(self):
        del self.data["operations"]["op"]
        with self.assertRaisesRegex(InputError, "undefined operation"):
            self.build()

    def test_alias_operation_cycle(self):
        self.data["operations"]["alias_op"]["operation_id"] = "alias_op"
        with self.assertRaisesRegex(InputError, "cyclic operation"):
            self.build()

    def test_alias_operation_mismatch(self):
        self.data["operations"]["other"] = {"_type": "Instruction.Operation"}
        self.data["operations"]["alias_op"]["operation_id"] = "other"
        with self.assertRaisesRegex(InputError, "differs from parent"):
            self.build()

    def test_record_count_drift(self):
        self.lock["a64_node_counts"]["Instruction"] = 3
        with self.assertRaisesRegex(InputError, "counts differ"):
            self.build()

    def test_unclassified_group(self):
        self.scope["groups"] = {}
        with self.assertRaisesRegex(InputError, "unclassified"):
            self.build()

    def test_invalid_scope(self):
        self.scope["groups"]["dpreg"] = "typo"
        with self.assertRaisesRegex(InputError, "unknown group classification"):
            self.build()

    def test_inherited_condition_retained(self):
        condition = {"_type": "AST.Bool", "value": False}
        self.data["instructions"][1]["children"][0]["condition"] = condition
        result = self.build()
        for record in result["inventory.json"]["records"]:
            self.assertEqual(record["scope"]["status"], "deferred")
            self.assertIn(condition, [c["expression"] for c in record["conditions"]])


if __name__ == "__main__":
    unittest.main()

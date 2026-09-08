"""Regression checks for normalized field ownership and rejected source drift."""

import copy
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools/arm64"))
from generate_a64 import render, signature, validate
from generate_a64_e5 import validate_e5
from normalize_a64 import compile_form, expressions, rule_alternatives
from source import InputError


class GenerationChecks(unittest.TestCase):
    def test_reference_singular_and_plural_alternatives_are_combined(self):
        rule = {"rule": "reference", "matcher": "W, Imm, Offset",
                "processor": "R(0), Ubits(19, 5), Offset(TBZ)",
                "matchers": ["X, Imm, Offset"],
                "processors": ["R(0), CUbits(6), Uslice(19, 5, 0), Uslice(31, 1, 5), A, Offset(TBZ)"],
                "names": ["W form", "X form"]}
        self.assertEqual([m for m, p in rule_alternatives(rule)],
                         ["W, Imm, Offset", "X, Imm, Offset"])
        rule["names"] = ["X form"]
        with self.assertRaisesRegex(InputError, "selector count mismatch"):
            rule_alternatives(rule)

    @classmethod
    def setUpClass(cls):
        cls.rules = json.loads((ROOT / "tools/arm64/rules/b2.json").read_bytes())

    def test_source_set_and_alternatives_complete(self):
        validate(self.rules)
        self.assertEqual(self.rules["xml_entries"], 212)
        self.assertEqual(len(set(self.rules["planned_records"])), 191)
        self.assertEqual({a["status"] for a in self.rules["alternatives"]}, {"converted"})

    def test_b1_fcvtn_covers_both_narrowing_modes(self):
        rules = json.loads((ROOT / "tools/arm64/rules/b1.json").read_bytes())
        forms = {}
        for mnemonic in ("fcvtn", "fcvtn2"):
            forms[mnemonic] = {
                tuple(operand["kind"] for operand in candidate["operands"])
                for candidate in rules["forms"]
                if candidate["mnemonic"] == mnemonic
            }
        self.assertEqual(forms["fcvtn"], {("v4h", "v4s"), ("v2s", "v2d")})
        self.assertEqual(forms["fcvtn2"], {("v8h", "v4s"), ("v4s", "v2d")})

    def test_b3_source_set_and_memory_constraints_complete(self):
        rules = json.loads((ROOT / "tools/arm64/rules/b3.json").read_bytes())
        validate(rules)
        self.assertEqual(rules["xml_entries"], 369)
        self.assertEqual(len(set(rules["planned_records"])), 369)
        self.assertEqual({a["status"] for a in rules["alternatives"]}, {"converted"})
        self.assertTrue(any(o["kind"] == "mem_pre" for f in rules["forms"] for o in f["operands"]))
        self.assertTrue(any(o["kind"] == "mem_index" for f in rules["forms"] for o in f["operands"]))
        self.assertTrue(any(f.get("constraints") for f in rules["forms"]))

    def test_b4_source_set_and_system_roles(self):
        rules = json.loads((ROOT / 'tools/arm64/rules/b4.json').read_bytes())
        validate(rules)
        self.assertEqual(rules['xml_entries'], 257)
        self.assertEqual(len(set(rules['planned_records'])), 257)
        self.assertEqual({a['status'] for a in rules['alternatives']}, {'converted'})
        tlbi = [f for f in rules['forms'] if f['mnemonic'] == 'tlbi'
                and f['operands'][0]['spelling'] == 'alle1' and len(f['operands']) == 2]
        self.assertEqual(len(tlbi), 1)
        self.assertEqual((tlbi[0]['operands'][1]['min'], tlbi[0]['operands'][1]['max']), (31, 31))
        names = rules['system_registers']['names']
        self.assertEqual(names['nzcv']['value'], 0x5a10)
        self.assertEqual(names['nzcv']['access'], 3)
        self.assertEqual(names['cntvct_el0']['access'], 1)

    def test_wide_immediate_acceptance_is_not_sampling(self):
        from check_a64_generated import scalar_accepts, scalar_domain
        self.assertNotIn(12345, scalar_domain('wide_immediate_x'))
        self.assertTrue(scalar_accepts('wide_immediate_x', 12345))
        self.assertTrue(scalar_accepts('wide_immediate_w', 12345 << 16))
        self.assertFalse(scalar_accepts('wide_immediate_w', 1 << 32))
        self.assertFalse(scalar_accepts('wide_immediate_x', 0x123456789))

    def test_extension_batches_complete_and_disjoint(self):
        plans = json.loads((ROOT / 'tools/arm64/extension-batches.json').read_bytes())['batches']
        seen = set()
        for batch in ('b1', 'b2', 'b3', 'b4', 'e1', 'e2', 'e3', 'e4'):
            data = json.loads((ROOT / f'tools/arm64/rules/{batch}.json').read_bytes())
            validate(data)
            records = set(data['planned_records'])
            self.assertFalse(seen & records)
            seen |= records
            if batch.startswith('e'):
                self.assertEqual(records, set(plans[batch.upper()]['planned_records']))
        self.assertEqual(len(seen), 1743)

    def test_e5_batch_complete_and_disjoint(self):
        previous = set()
        for batch in ("b1", "b2", "b3", "b4", "e1", "e2", "e3", "e4"):
            data = json.loads((ROOT / f"tools/arm64/rules/{batch}.json").read_bytes())
            previous.update(data["planned_records"])
        e5 = json.loads((ROOT / "tools/arm64/rules/e5.json").read_bytes())
        validate_e5(e5)
        records = set(e5["planned_records"])
        self.assertEqual(len(records), 154)
        self.assertEqual(len(e5["forms"]), 154)
        self.assertFalse(previous & records)
        for form in e5["forms"]:
            if form["mnemonic"].startswith("setgo"):
                self.assertEqual(len(form.get("constraints", [])), 1)
            elif form["mnemonic"].startswith(("set", "cpy")):
                self.assertEqual(len(form.get("constraints", [])), 3)

    def test_shared_generator_preserves_e5_entrypoints(self):
        batches = [
            json.loads((ROOT / f"tools/arm64/rules/{batch}.json").read_bytes())
            for batch in ("b1", "b2", "b3", "b4", "e1", "e2", "e3", "e4")
        ]
        artifacts = render(batches)
        self.assertIn(b'import("arm/a64/mops.inc")', artifacts["a64.inc"])
        self.assertIn(b'import("arm/a64/generated/instructions-e5.inc")', artifacts["a64.inc"])
        self.assertIn(
            b'import("arm/a64/generated/instructions-e5-macros.inc")',
            artifacts["a64-macros.inc"],
        )
        self.assertIn(b"a64_e5_abs_shape(shaped)", artifacts["a64/generated/instructions-macros.inc"])

    def test_grouped_lanes_have_distinct_signatures(self):
        kinds = ('lane_b', 'lane_h', 'lane_s', 'lane_4b', 'lane_2h', 'v2h')
        self.assertEqual(len({signature([{'kind': k}]) for k in kinds}), len(kinds))

    def test_pair_case_matrix_covers_all_even_starts(self):
        from check_a64_generated import cases, form_domains, valid_seed
        data = json.loads((ROOT / 'tools/arm64/rules/e2.json').read_bytes())
        form = next(f for f in data['forms'] if f['mnemonic'] == 'casp' and f['operands'][0]['kind'] == 'x')
        domains = form_domains(form)
        for value in range(0, 32, 2):
            result = valid_seed(form, domains, (0, value))
            self.assertEqual(result[:2], [value, value+1])
        self.assertTrue(any('x30, xzr' in c['natural'] for c in cases([form])))

    def test_extension_xml_and_plan_drift_rejected(self):
        data = json.loads((ROOT / 'tools/arm64/rules/e1.json').read_bytes())
        data['xml_entries'] -= 1
        with self.assertRaisesRegex(InputError, 'XML conversion incomplete'):
            validate(data)
        data['planned_records'][0] = 'unknown'
        with self.assertRaisesRegex(InputError, 'planned source set changed'):
            validate(data)

    def test_missing_form_is_not_coverage(self):
        data = copy.deepcopy(self.rules)
        record = data["forms"][0]["record_id"]
        data["forms"] = [f for f in data["forms"] if f["record_id"] != record]
        with self.assertRaisesRegex(InputError, "source record missing"):
            validate(data)

    def test_failed_alternative_is_not_coverage(self):
        data = copy.deepcopy(self.rules)
        data["alternatives"][0]["status"] = "failed"
        with self.assertRaisesRegex(InputError, "unaccounted"):
            validate(data)

    def test_mixed_source_version_is_rejected(self):
        data = copy.deepcopy(self.rules)
        data["source_lock"] = {}
        with self.assertRaisesRegex(InputError, "source lock mismatch"):
            validate(data)

    def test_static_zero_width_is_preserved(self):
        self.assertEqual(expressions("Static(19, 0b0000)"), [("Static", [19, 0, 4])])
        with self.assertRaisesRegex(InputError, "unsupported command syntax"):
            expressions("Usubone()(16, 5, 32)")

    def test_parser_never_executes_rule_text(self):
        with self.assertRaises((InputError, ValueError)):
            expressions("__import__('os').system('unexpected')")

    def test_signature_separates_lists_and_lanes(self):
        shapes = [
            [{"kind": "v16b"}, {"kind": "v16b", "list_count": count}, {"kind": "v16b"}]
            for count in range(5)
        ]
        shapes += [[{"kind": "lane_s"}, {"kind": "imm"}], [{"kind": "v4s"}, {"kind": "imm"}]]
        self.assertEqual(len({signature(s) for s in shapes}), len(shapes))

    def test_unknown_bits_are_never_silently_zeroed(self):
        row = {"encoding": "test", "mnemonic": "TEST", "q": None,
               "template": "", "bits": ["x"] * 32}
        record = {"encoding": {"fixed_mask": 0xffff0000, "fixed_value": 0,
                               "should_be_mask": 0, "should_be_value": 0}}
        with self.assertRaisesRegex(InputError, "unowned bits"):
            compile_form(row, record, {"rule": "test"}, "Imm", "Ubits(0, 8)", 0)


if __name__ == "__main__":
    unittest.main()

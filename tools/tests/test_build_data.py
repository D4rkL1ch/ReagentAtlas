"""Offline tests for the recipe source step of build_data.py.

Run: python tools/tests/test_build_data.py
"""

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import build_data as b  # noqa: E402


class ParseLua(unittest.TestCase):
    def value(self, text):
        return b.parse_lua_value(text, 0)[0]

    def test_scalars(self):
        self.assertEqual(self.value("42"), 42)
        self.assertEqual(self.value("nil"), None)
        self.assertEqual(self.value("1.5"), 1.5)

    def test_strings_with_escapes(self):
        self.assertEqual(self.value(r"'Kor\'gall'"), "Kor'gall")
        self.assertEqual(self.value('"AH"'), "AH")

    def test_nested_tables(self):
        self.assertEqual(self.value("{'a',nil,{1,2},3}"), ["a", None, [1, 2], 3])
        self.assertEqual(self.value("{}"), [])

    def test_keyed_tables(self):
        self.assertEqual(self.value("{[10]={{7.5,4.5}},[12]={{1,2}}}"), {10: [[7.5, 4.5]], 12: [[1, 2]]})

    def test_load_table_reads_only_records(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "db.lua"
            path.write_text("QuestieDB.keys = {\n    ['name'] = 1,\n}\nreturn {\n[7] = {'Seven',{1}},\n[8] = {'Eight'},\n}\n",
                            encoding="utf-8")
            self.assertEqual(b.load_questie_table(path), {7: ["Seven", [1]], 8: ["Eight"]})


class Drops(unittest.TestCase):
    ZONES = {1: "Tanaris", 2: "Silithus"}

    @staticmethod
    def npc(zone):
        return ["NPC", 1, 1, 1, 1, 0, None, None, zone]

    def test_field_past_the_record_end_is_none(self):
        self.assertIsNone(b.field(["only name"], b.QITEM_VENDORS))

    def test_zone_falls_back_to_spawns(self):
        npc = ["NPC", 1, 1, 1, 1, 0, {2: [[1, 1]]}, None, 0]
        self.assertEqual(b.npc_zone(npc, self.ZONES), "Silithus")
        self.assertEqual(b.npc_zone(self.npc(99), self.ZONES), "")

    def test_few_droppers_are_named(self):
        npcs = {n: self.npc(1) for n in range(1, b.MAX_NAMED_DROPS + 1)}
        self.assertEqual(b.summarize_drops(set(npcs) | {999}, npcs, self.ZONES), {"d": sorted(npcs)})

    def test_many_droppers_are_summarized_busiest_zone_first(self):
        npcs = {n: self.npc(1 if n < 3 else 2) for n in range(b.MAX_NAMED_DROPS + 1)}
        self.assertEqual(b.summarize_drops(set(npcs), npcs, self.ZONES),
                         {"dn": b.MAX_NAMED_DROPS + 1, "dz": ["Silithus", "Tanaris"], "dzn": 2})

    def test_no_known_droppers(self):
        self.assertEqual(b.summarize_drops({5}, {}, self.ZONES), {})


class Chains(unittest.TestCase):
    @staticmethod
    def recipe(skill, reagents, out=None):
        recipe = {"prof": 1, "skill": skill, "reagents": {item: 1 for item in reagents}}
        if out:
            recipe["out"] = out
        return recipe

    def test_counts_high_end_recipes_through_outputs(self):
        recipes = {
            1: self.recipe(275, [10, 11], out=20),  # crystal + bar -> arcanite
            2: self.recipe(300, [20], out=30),
            3: self.recipe(310, [20]),
            4: self.recipe(100, [10]),              # low skill: followed, not counted
        }
        counts = b.chain_counts(recipes, [10, 20, 99], set())
        self.assertEqual(counts, {10: 3, 20: 2, 99: 0})

    def test_low_skill_steps_still_lead_to_high_end_recipes(self):
        recipes = {1: self.recipe(25, [10], out=20), 2: self.recipe(300, [20])}
        self.assertEqual(b.chain_counts(recipes, [10], set()), {10: 1})

    def test_each_recipe_counts_once_across_paths(self):
        recipes = {
            1: self.recipe(300, [10], out=20),
            2: self.recipe(300, [10], out=21),
            3: self.recipe(300, [20, 21]),
        }
        self.assertEqual(b.chain_counts(recipes, [10], set()), {10: 3})

    def test_cycles_end(self):
        recipes = {1: self.recipe(300, [10], out=20), 2: self.recipe(300, [20], out=10)}
        self.assertEqual(b.chain_counts(recipes, [10], set()), {10: 2})

    def test_conversions_are_not_followed(self):
        recipes = {1: self.recipe(300, [10], out=20), 2: self.recipe(300, [20])}
        self.assertEqual(b.chain_counts(recipes, [10], {1}), {10: 0})

    def test_conversions_are_transmutes_and_leather_only(self):
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, "Item.csv").write_text(
                "ID,ClassID,SubclassID\n10,7,6\n20,7,6\n30,7,7\n40,7,7\n50,7,5\n60,7,5\n", encoding="utf-8")
            recipes = {
                1: self.recipe(100, [10], out=20),      # Light to Medium Leather
                2: self.recipe(250, [30], out=40),      # Smelt Thorium
                3: self.recipe(250, [50], out=60),      # Bolt of Runecloth
                4: self.recipe(275, [30], out=50),      # Transmute: Fire to Earth
                5: self.recipe(275, [30, 40], out=50),  # Transmute: Arcanite
            }
            names = {4: "Transmute: Fire to Earth", 5: "Transmute: Arcanite"}
            self.assertEqual(b.conversion_recipes(Path(tmp), recipes, names), {1, 4})


class LuaOutput(unittest.TestCase):
    def test_strings_are_escaped(self):
        self.assertEqual(b.lua_str('a"b\\c'), '"a\\"b\\\\c"')


if __name__ == "__main__":
    unittest.main()

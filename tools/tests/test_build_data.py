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


CORRECTIONS = """
local X = QuestieLoader:CreateModule("X")
function X:Load()
    local itemKeys = QuestieDB.itemKeys
    local zoneIDs = ZoneDB.zoneIDs
    return {
        [1] = { -- Thing, with a -- in the comment and a "quote"
            [itemKeys.name] = "It's -- here",
            [itemKeys.npcDrops] = {}, -- only show vendors
            [itemKeys.vendors_add] = {5,6},
            [itemKeys.zone] = zoneIDs.TANARIS,
            [itemKeys.flags] = npcFlags.VENDOR + npcFlags.REPAIR,
        },
        --[[ [2] = { [itemKeys.name] = "commented out" }, ]]
        [3] = {
            [itemKeys.spawns] = {[zoneIDs.SILITHUS] = {{1.5,2}}},
            [itemKeys.npcDrops_remove] = {7},
        },
    }
end
function X:LoadDynamic()
    return { [9] = { [itemKeys.name] = "dynamic" } }
end
"""


class Corrections(unittest.TestCase):
    ZONES = {"TANARIS": 440, "SILITHUS": 1377}
    KEYS = {"name": 0, "npcDrops": 1, "vendors": 2, "zone": 3, "flags": 4, "spawns": 5}

    def load(self, text=CORRECTIONS, zones=None):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "fixes.lua"
            path.write_text(text, encoding="utf-8")
            return b.load_corrections(path, self.ZONES if zones is None else zones)

    def test_reads_only_static_load(self):
        fixes = self.load()
        self.assertEqual(sorted(fixes), [1, 3])
        self.assertEqual(fixes[1]["name"], "It's -- here")
        self.assertEqual(fixes[1]["npcDrops"], [])
        self.assertEqual(fixes[1]["zone"], 440)
        self.assertIsInstance(fixes[1]["flags"], b.LuaExpr)
        self.assertEqual(fixes[3]["spawns"], {1377: [[1.5, 2]]})

    def test_unknown_zone_stops_the_build(self):
        with self.assertRaises(ValueError):
            self.load(zones={})

    def test_apply_replaces_adds_and_removes(self):
        records = {1: ["Thing", [10, 11], [5]], 3: ["Other", [7, 8]]}
        b.apply_corrections(records, self.KEYS, self.load())
        self.assertEqual(records[1][:4], ["It's -- here", [], [5, 6], 440])
        self.assertEqual(records[3][1], [8])
        self.assertEqual(records[3][5], {1377: [[1.5, 2]]})

    def test_apply_creates_records_and_ignores_unknown_fields(self):
        records: dict = {}
        b.apply_corrections(records, {"name": 0}, {4: {"name": "New", "waypoints": {}}, 5: {"npcDrops_add": [1]}})
        self.assertEqual(records, {4: ["New"], 5: []})

    def test_nil_clears_a_field(self):
        records = {1: ["Thing", [1]]}
        b.apply_corrections(records, self.KEYS, {1: {"npcDrops": None}})
        self.assertEqual(records[1], ["Thing", None])

    def test_keys_and_zones_from_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            db = Path(tmp) / "db.lua"
            db.write_text("QuestieDB.itemKeys = {\n    ['name'] = 1, -- string\n    ['npcDrops'] = 2,\n}\n", encoding="utf-8")
            zones = Path(tmp) / "zones.lua"
            zones.write_text("constants.zoneIDs = {\n  -- DUSKWOOD = 99,\n  DUSKWOOD = 10,\n  DUSKWOOD = 11,\n}\n", encoding="utf-8")
            self.assertEqual(b.load_questie_keys(db), {"name": 0, "npcDrops": 1})
            self.assertEqual(b.load_questie_zones(zones), {"DUSKWOOD": 10})

    def test_layers_match_what_fetch_downloads(self):
        import fetch_db2
        fetched = {Path(p).name for p in fetch_db2.QUESTIEDB_CORRECTIONS}
        needed = {f for fs in b.QUESTIE_LAYERS.values() for f in fs} | {b.QUESTIE_ZONES}
        self.assertEqual(fetched, needed)
        self.assertFalse(any("generated" in p for p in fetch_db2.QUESTIEDB_CORRECTIONS))


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


class LearnSkills(unittest.TestCase):
    def era(self, tmp):
        era = Path(tmp)
        era.joinpath("SpellEffect.csv").write_text(
            "SpellID,Effect,EffectTriggerSpell\n3814,36,3813\n9001,36,9000\n", encoding="utf-8")
        era.joinpath("SkillLineAbility.csv").write_text(
            "Spell,TrivialSkillLineRankLow\n3813,170\n9000,100\n7000,60\n", encoding="utf-8")
        era.joinpath("trainer_spells.csv").write_text(
            "spell,reqskill,reqskillvalue\n3814,197,150\n3814,197,160\n9001,164,80\n7000,0,0\n8000,197,50\n",
            encoding="utf-8")
        return era

    def test_trainer_skill_follows_forever_rebalance(self):
        recipes = {3813: {"prof": 197}, 9000: {"prof": 197}, 7000: {"prof": 185}, 8000: {"prof": 197}}
        yellow = {3813: 145, 9000: 100, 7000: 60, 8000: 70}
        with tempfile.TemporaryDirectory() as tmp:
            result = b.trainer_learn_skills(self.era(tmp), recipes, yellow)
        # 3813: lowest trainer value, moved by Forever's yellow shift (170 -> 145).
        # 9000: trainer is for another profession. 7000: taught directly, 0 means 1.
        # 8000: no Classic Era rank to shift from.
        self.assertEqual(result, {3813: 125, 7000: 1})

    def test_trainer_skill_never_above_yellow(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = b.trainer_learn_skills(self.era(tmp), {3813: {"prof": 197}}, {3813: 160})
        self.assertEqual(result, {3813: 140})
        with tempfile.TemporaryDirectory() as tmp:
            era = self.era(tmp)
            era.joinpath("SkillLineAbility.csv").write_text("Spell,TrivialSkillLineRankLow\n3813,140\n", encoding="utf-8")
            self.assertEqual(b.trainer_learn_skills(era, {3813: {"prof": 197}}, {3813: 145}), {3813: 145})

    def test_missing_era_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(b.trainer_learn_skills(Path(tmp), {1: {"prof": 197}}, {1: 50}), {})


class LuaOutput(unittest.TestCase):
    def test_strings_are_escaped(self):
        self.assertEqual(b.lua_str('a"b\\c'), '"a\\"b\\\\c"')


if __name__ == "__main__":
    unittest.main()

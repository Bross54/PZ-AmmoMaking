"""Ammo Making - does tools/pz_compat.py notice what it is meant to notice?

    python tools/test_pz_compat.py

Needs no game install: it takes the recorded snapshot (tests/
engine_snapshot.lua), damages it the way a game update could, and checks
that the verdict changes. It also checks the Lua scanner on small pieces
of source. A drift detector that always says PASS is worse than none.
"""

import copy
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import pz_compat as tool  # noqa: E402

passed = failed = 0


def check(condition, message):
    global passed, failed
    if condition:
        passed += 1
    else:
        failed += 1
        print("  FAIL: " + message)


def levels(report, level):
    return [text for found, text in report.lines if found == level]


# ---------------------------------------------------------------- the scanner
source = '''
-- a comment naming ghostGlobal(1, 2)
local text = "a string naming otherGhost(3)"
local player =
    getSpecificPlayer(0)

local inventory,
      other =
    player:getInventory()

local entry = { key = "x", min = 0, max = 100 }

for _,
    input
in ipairs(
    list
)
do
    input:hasTag(
        ItemTag.HAMMER,
        2
    )
end

self.character:
    getInventory():
    containsID(
        7
    )

if InventoryItemFactory and InventoryItemFactory.CreateItem then
    InventoryItemFactory.CreateItem("x")
end

HaloTextHelper.addText(player, "hello", "x")
madeUpGlobal(1)
Events.OnGameStart.Add(handler)
'''
calls = tool.mod_calls({"sample.lua": source})
check("ghostGlobal" not in calls["globals"], "a name in a comment is not a call")
check("otherGhost" not in calls["globals"], "a name in a string is not a call")
check("getSpecificPlayer" in calls["globals"], "a bare call is a global")
check(calls["callCounts"]["getSpecificPlayer"] == {1: "sample.lua"}, "with its argument count")
check("player" not in calls["globals"] and "inventory" not in calls["globals"] and "other" not in calls["globals"], "locals declared over several lines are not globals")
check("input" not in calls["globals"], "a loop variable on its own line is not a global")
check("min" not in calls["globals"] and "key" not in calls["globals"], "table fields are not globals")
check(calls["methods"]["hasTag"] == {2: "sample.lua"}, "a method call over several lines is counted with its arguments")
check(calls["methods"]["getInventory"] == {0: "sample.lua"}, "a call with no arguments counts none")
check(calls["methods"]["containsID"] == {1: "sample.lua"}, "a method named on the line after its colon is found")
check("containsID" not in calls["globals"] and "getInventory" not in calls["globals"], "and is not taken for a global")
check("InventoryItemFactory" in calls["probed"], "a global the code asks about first is marked as probed")
check("madeUpGlobal" in calls["globals"] and "madeUpGlobal" not in calls["probed"], "an unknown bare call is a global, not probed")
check(calls["callCounts"]["HaloTextHelper.addText"] == {3: "sample.lua"}, "a static call is counted with its arguments")
check(calls["events"] == {"OnGameStart": "sample.lua"}, "an event registration is found")
check("ItemTag.HAMMER" in calls["members"], "a member of a global is recorded")

# ---------------------------------------------------------------- signatures
check(tool.signature("zombie.inventory.InventoryItem, float", False) == "InventoryItem,float", "simple type names")
check(tool.signature("java.util.List<java.lang.String>, int", True) == "static List,int", "generics are dropped")
check(tool.signature("zombie.scripting.objects.ItemTag...", False) == "ItemTag...", "varargs are kept")
check(tool.signature("", False) == "", "no parameters")
check(tool.fits("InventoryItem,float", 2) and not tool.fits("InventoryItem,float", 1) and not tool.fits("InventoryItem,float", 3), "a method takes exactly its parameters")
check(tool.fits("", 0) and not tool.fits("", 1), "a method without parameters takes none")
check(tool.fits("ItemTag...", 0) and tool.fits("ItemTag...", 3), "a varargs method takes any number")
check(tool.fits("static String", 1) and tool.fits("static String", 2) and not tool.fits("static String", 0), "a global function tolerates extra arguments, not missing ones")

parsed = tool.parse_javap('''Compiled from "X.java"
public class zombie.a.X extends zombie.a.Y implements zombie.a.I {
  public int count;
  private int hidden;
  public zombie.a.X(zombie.iso.IsoCell, boolean);
  public boolean hasTag(zombie.scripting.objects.ItemTag);
  public boolean hasTag(zombie.scripting.objects.ItemTag...);
  public static <T> T pick(java.util.List<T>) throws java.io.IOException;
  private void secret();
}
''')
x = parsed["zombie.a.X"]
check(x["extends"] == "zombie.a.Y", "the superclass is read")
check(x["methods"]["hasTag"] == ["ItemTag", "ItemTag..."], "both overloads are read")
check(x["methods"]["pick"] == ["static List"], "a generic static method is read")
check("secret" not in x["methods"], "private methods are not exposed")
check(x["constructors"] == ["static IsoCell,boolean"], "the public constructor is read")
check(x["fields"] == {"count"}, "public fields only")
check(tool.strip_lua('a = "x -- y" -- z\nb = [[long\n-- text]] c()') == 'a = "" \nb = "" c()', "comments and string contents are removed")

# ---------------------------------------------------------------- the verdict
recorded = tool.read_snapshot()
check(recorded is not None, "tests/engine_snapshot.lua exists")
facts = tool.mod_facts()
facts["art"] = tool.mod_item_art()
facts["pressDraft"] = tool.press_draft()
calls = tool.mod_calls(tool.mod_sources())


def verdict(change):
    snapshot = copy.deepcopy(recorded)
    change(snapshot)
    return tool.judge(snapshot, facts, calls, recorded, True)


baseline = verdict(lambda s: None)
check(baseline.worst == 0, "the recorded snapshot itself passes: " + "; ".join(levels(baseline, "BREAKING") + levels(baseline, "WARNING")))


def breaking(what, change, needle):
    report = verdict(change)
    found = [text for text in levels(report, "BREAKING") if needle in text]
    check(report.worst == 2 and found, what + " is BREAKING (" + "; ".join(levels(report, "BREAKING"))[:200] + ")")


def warning(what, change, needle):
    report = verdict(change)
    found = [text for text in levels(report, "WARNING") if needle in text]
    check(report.worst == 1 and found, what + " is a WARNING and nothing worse (" + "; ".join(levels(report, "WARNING") + levels(report, "BREAKING"))[:200] + ")")


def set_path(*path_and_value):
    *path, value = path_and_value

    def change(snapshot):
        node = snapshot
        for key in path[:-1]:
            node = node[key]
        node[path[-1]] = value
    return change


def drop(*path):
    def change(snapshot):
        node = snapshot
        for key in path[:-1]:
            node = node[key]
        del node[path[-1]]
    return change


breaking("a vanilla item that is gone", set_path("items", "Base.BrassScrap", False), "Base.BrassScrap does not exist")
breaking("a round that is gone", set_path("items", "Base.Bullets9mm", False), "Base.Bullets9mm does not exist")
breaking("a gunpowder jar of twelve uses", set_path("items", "Base.GunPowder", "uses", 12), "Base.GunPowder holds 12 uses")
breaking("an item tag nothing carries", set_path("itemTags", "base:hammer", 0), "no vanilla item carries base:hammer")
breaking("a station tag nothing provides", set_path("benchTags", "Forge", {"stations": 0, "vanillaRecipes": 0}), "no station provides Forge")
breaking("a timed action that is gone", set_path("timedActions", "MakingHammer_Surface", False), "timed action MakingHammer_Surface does not exist")
breaking("an event that is gone", set_path("events", "OnPreDistributionMerge", False), "event OnPreDistributionMerge is not registered")
breaking("a Java global that is gone", set_path("globals", "getGameTime", False), "getGameTime is neither")
breaking("a global the mod asks about before using, gone since the recorded build", set_path("globals", "instanceItem", False), "instanceItem is neither")
check(recorded["globals"]["InventoryItemFactory"] is False and "InventoryItemFactory" in calls["probed"], "the older item factory is absent on the recorded build, and the mod only asks about it")
breaking("a member of a Lua class that is gone", set_path("members", "BuildingHelper.getShovelAnim", False), "BuildingHelper.getShovelAnim does not exist")
breaking("a method that is gone from one class and still on another", drop("classes", "IsoGridSquare", "methods", "hasWater"), "IsoGridSquare.hasWater is gone")
breaking("a method that is gone everywhere", drop("classes", "IsoGridSquare", "methods", "RecalcAllWithNeighbours"), ":RecalcAllWithNeighbours() is defined by no engine class")
breaking("a method that takes another number of arguments", set_path("classes", "IsoGridSquare", "methods", "AddWorldInventoryItem", ["InventoryItem,float"]), ":AddWorldInventoryItem() is called with")
breaking("a global function that needs more arguments", set_path("functions", "getSpecificPlayer", ["static int,int"]), "getSpecificPlayer() is called with 1 argument")
breaking("a static method that needs more arguments", set_path("members", "ModData.getOrCreate", ["static String,boolean"]), "ModData.getOrCreate() is called with 1 argument")
breaking("a class no longer exposed to Lua", set_path("classes", "IsoThumpable", "exposed", False), "no longer exposed to Lua")
breaking("the analyzer's tile claimed by an entity", set_path("sprites", "industry_03_61", "entity", "Some_Station"), "is now claimed by entity Some_Station")
breaking("the analyzer's tile removed", set_path("sprites", "industry_03_61", False), "tile industry_03_61 is not defined")


def no_nine(snapshot):
    for group in ("firearms", "magazines"):
        for entry in snapshot[group].values():
            if entry["ammoType"] == "base:bullets_9mm":
                entry["ammoType"] = "base:bullets_10mm"


breaking("a round no firearm takes", no_nine, "nothing fires Base.Bullets9mm")
breaking("an ammo type that names another item", set_path("ammoTypes", "base:bullets_9mm", "Base.Bullets9mmNew"), "ammo type base:bullets_9mm is Base.Bullets9mmNew")
breaking("an ammo type that is gone", drop("ammoTypes", "base:shotgun_shells"), "ammo type base:shotgun_shells is not registered")

warning("a new game version", set_path("version", "42.21.0"), "game version 42.21.0, recorded")
warning("a vanilla recipe whose body changed", set_path("recipes", "place_ammo_in_box", "000000000000"), "recipes.place_ammo_in_box changed")
warning("a vanilla recipe that is gone", set_path("recipes", "SmeltCopperOre", False), "vanilla recipe SmeltCopperOre does not exist")
warning("an item whose weight changed", set_path("items", "Base.CopperScrap", "weight", 9), "items.Base.CopperScrap.weight changed")
warning("a firearm that changed its magazine", set_path("firearms", "Pistol", "magazine", "Base.Other"), "firearms.Pistol.magazine changed")
warning("a firearm function the designs rely on", set_path("design", "ISReloadWeaponAction.onShoot", False), "ISReloadWeaponAction.onShoot is gone")
warning("a wrapped firearm function whose body changed", set_path("designBodies", "ISRackFirearm:ejectSpentRounds", "000000000000"), "the body of ISRackFirearm:ejectSpentRounds changed")
warning("a wrapped firearm function that is no longer one piece", set_path("designBodies", "ISInsertMagazine:loadAmmo", False), "the body of ISInsertMagazine:loadAmmo could not be read")
check(len(recorded["designBodies"]) == len(recorded["design"]) and all(recorded["designBodies"].values()), "a digest is recorded for every firearm function the hooks rely on")
warning("the press's window icon dropped by vanilla", set_path("pressDraft", "iconsInVanillaSkins", "Build_Handpress", False), "the press's window icon Build_Handpress is used by no vanilla skin")
warning("a firearm method the designs rely on", drop("classes", "HandWeapon", "methods", "setSpentRoundCount"), "HandWeapon.setSpentRoundCount is gone")
warning("a sound that is gone", set_path("sounds", "Shoveling", False), "sound Shoveling does not exist")
warning("an icon the mod borrows that is gone", set_path("art", "icons", "PistolAmmo", False), "icon PistolAmmo is used by no vanilla item")
warning("a model the mod borrows that is gone", set_path("art", "models", "IronOre", False), "model IronOre is used by no vanilla item or model script")
check(len(facts["art"]["icons"]) >= 10 and "IronOre" in facts["art"]["models"], "the mod's borrowed icons and models are read from its item script")
warning("the analyzer's tile becoming a moveable", set_path("sprites", "industry_03_61", "moveable", True), "is now a vanilla moveable")
warning("the press's tag taken by vanilla", set_path("benchTags", "AmmoMakingReloadingPress", {"stations": 1, "vanillaRecipes": 0}), "the press's own tag, is now used by vanilla")
warning("the press's timed action removed", set_path("timedActions", "UseHandPress", False), "timed action UseHandPress does not exist")
warning("a build input of the press draft removed", set_path("pressDraft", "items", "Base.SteelBarHalf", False), "the press add-on's build recipe names Base.SteelBarHalf")
warning("a vanilla entity taking the press draft's name", set_path("pressDraft", "entityNameFree", False), "vanilla now has an entity with the press add-on's name")
warning("a vanilla entity claiming a press sprite", set_path("pressDraft", "spritesUnclaimed", False), "a vanilla entity now claims one of the press's sprite names")
check(facts["pressDraft"]["benchTag"] == facts["press"]["benchTag"], "the press draft's CraftBench tag is the calibre model's")
check(facts["pressDraft"]["rows"] == facts["pressDraft"]["sprites"], "the press draft's faces are the tile sheet's sprites, in order")
warning("a new overload on a method the mod calls", set_path("classes", "IsoGridSquare", "methods", "hasWater", ["", "boolean"]), "classes.IsoGridSquare.methods.hasWater changed")

no_jar = tool.judge(copy.deepcopy(recorded), facts, calls, recorded, False)
check(no_jar.worst == 1 and any("javap not found" in text for text in levels(no_jar, "WARNING")), "without javap the Java checks are skipped and said to be skipped")
missing = tool.judge(copy.deepcopy(recorded), facts, calls, None, True)
check(missing.worst == 1 and any("--update" in text for text in levels(missing, "WARNING")), "without a recorded snapshot the tool says how to make one")

print("Passed: %d  Failed: %d" % (passed, failed))
sys.exit(1 if failed else 0)

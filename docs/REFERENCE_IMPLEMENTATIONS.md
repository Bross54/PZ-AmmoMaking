# Reference implementations

Other Build 42 mods were read as **structural references** during the third
pass of 2026-10-03: to see how a pattern is written in a mod that people
actually run, after the pattern had been read in vanilla's own files.

Rules that were kept:

- **Order of trust**: the installed vanilla files, then `projectzomboid.jar`,
  then these mods. Where a mod and vanilla disagree, vanilla wins. A mod is
  a clue that a pattern works in Build 42, never proof that it works here.
- **Nothing was copied.** No code, script, item, recipe, texture or name of
  another mod is in this repository. Each pattern below was implemented
  from the vanilla files, in this mod's own way.
- **No dependency.** Ammo Making requires no other mod and loads none.

The mods are the ones installed on the development machine
(`steamapps/workshop/content/108600/<id>`). 232 Build 42 mod folders in 192
Workshop items were surveyed.

## 1. An optional add-on mod beside the main mod

**Where**: Hot Brass (Workshop 3610677934): three sibling mod folders, of
which `Hot_Brass_Ammo_Crafting` and `Hot_Brass_Tactical_Reload` say
`require=HBVCEFb42`. Alice's Weapon Sling (3775549570): an optional radial
menu add-on with `require=alicesWeaponSling`.

**Pattern**: a Workshop item holds several mods under `mods/`; an add-on is
a mod of its own with a `require=` line, ticked separately in the mod list.

**Why it was useful**: it is the only switch Build 42 has for things the
engine reads before any Lua runs. Scripts (items, recipes, entities, tile
sheets) cannot be hidden afterwards, so a feature that must not exist in a
game by default has to be absent from the mod.

**What Ammo Making does**: `mod/AmmoMakingPress` and
`mod/AmmoMakingSpentCases` beside `mod/AmmoMaking`, each `require=\AmmoMaking`.
`AC_Features.lua` in the main mod treats "the add-on is active" as the
feature switch, and all logic stays in the main mod: an add-on ships no Lua
(the release builder refuses one that does).

**Vanilla evidence**: `ChooseGameInfo.readModInfo` (jar) strips a backslash
from the `require=` value and splits it on commas, so `\AmmoMaking` and
`AmmoMaking` are the same requirement. Both spellings are in use among the
installed mods.

## 2. Asking whether another mod is active

**Where**: Hot Brass (`SpentCasingPhysics/ModSupport.lua`), Gunworks
(3722064198), More Traits (1299328280), Vehicle Repair Overhaul
(2757712197): `getActivatedMods():contains("<id>")`, almost always with the
bare id. One vehicle mod uses a leading backslash in one file and none in
another.

**What Ammo Making does**: `AC_Features.isModActive(id)` looks for the bare
id **and** the backslash form, guards a missing function, a failing call
and a list without `contains`, and answers "not active" for anything
unexpected.

**Vanilla evidence**: `LuaManager.GlobalObject.getActivatedMods` returns
`ZomboidFileSystem.getModIDs()` (jar). Which spelling the list holds at run
time is **REQUIRES FUTURE IN-GAME VERIFICATION**; accepting both makes it
moot.

## 3. Custom sandbox options

**Where**: Hot Brass (booleans), Useful Barrels (3436537035; integer and
double), NWMF Weaponry (3651242585; enum, read during the loot merge).

**Pattern**: `media/sandbox-options.txt` with `VERSION = 1,` and
`option <Table>.<Name> { type, default, page, translation, }`; texts in
`Translate/EN/Sandbox.json` as `Sandbox_<page>`, `Sandbox_<translation>` and
`Sandbox_<translation>_tooltip`; read as `SandboxVars.<Table>.<Name>`.

**What Ammo Making does**: one option in the main mod
(`AmmoMaking.QualityTracking`, boolean, default false) and one in the
spent-cases add-on (`AmmoMaking.SpentCaseRecovery`, integer 0 to 100).
Each is read defensively: only the boolean `true`, or a whole number in
range, is a setting.

**Vanilla evidence**: `zombie.sandbox.CustomSandboxOptions` (jar) parses
exactly those keys; the types it knows are `boolean`, `double`, `enum`,
`integer`, `string`. The files carry no comment, because it is not known
that the option parser skips one.

## 4. A crafting station of the mod's own

**Where**: Hot Brass Ammo Crafting, the only installed mod with a genuinely
new station: an `entity` with `component CraftBench { Recipes =
AmmoReloadingBench, }`, `face S` / `face E` rows naming sprites of its own
tile sheet (`pack=` and `tiledef=` in `mod.info`), a `component
CraftRecipe` that builds it from the build menu, an `xuiSkin` entry, and
recipes tagged `AmmoReloadingBench`. No Lua registers the tag.

**Why it was useful**: it confirms, in a mod that ships, the conclusion the
press design had reached from the jar alone: a recipe tag is a free string,
and a station needs sprites of its own.

**What Ammo Making does**: `mod/AmmoMakingPress`: the entity follows
vanilla's `Hand_Press` field for field, its skin is a file of its own as
vanilla's is, its tile properties are exactly those of vanilla's hand
press, and its recipes are generated from the calibre model. Differences
from the reference, on purpose: no moveable `item` is declared (vanilla's
hand press has none, and the tile's `IsMoveAble` is what vanilla's own
pickup uses), and the press is an add-on that is off by default.

**Vanilla evidence**: `docs/RELOADING_PRESS_DESIGN.md` 2.

## 5. Firearm hooks: casings and per-magazine data

**Where**:

- Hot Brass wraps `ISRackFirearm.ejectSpentRounds` and
  `ISReloadWeaponAction.ejectSpentRounds` by storing the original and
  calling it, and places casing items with
  `square:AddWorldInventoryItem(type, x, y, z)`. It finds the casing by
  `weapon:getAmmoType():getItemKey()`, and treats `isRackAfterShoot()` and
  `isManuallyRemoveSpentRounds()` guns apart from the rest.
- Gunworks keeps a per-round list in the ModData of magazines and guns and
  wraps `ISLoadBulletsInMagazine:animEvent`, `ISInsertMagazine:loadAmmo`,
  `ISEjectMagazine:unloadAmmo`, `ISUnloadBulletsFromMagazine:animEvent`,
  `ISUnloadBulletsFromFirearm:animEvent`, `ISReloadWeaponAction:loadAmmo`
  and `ISRackFirearm:removeBullet`: the seven touch points
  `AMMO_QUALITY_RUNTIME_DESIGN.md` had listed from vanilla's files.

**Why it was useful**: two shipping mods replace these functions by
table-field assignment, which is what makes the approach credible in Build
42. The functions and the two flags were already known from vanilla.

**What Ammo Making does differently**:

- `AC_SpentCases` adds a listener and does **not** remove and re-register
  vanilla's `onShoot` or its attack hook, as both references do. It only
  wraps the one function that has no event.
- `AC_QualityCarrier` keeps an **aggregate** (count, handloaded, quality
  sum), not a per-round list, and never re-implements what vanilla does:
  each wrapper observes vanilla's own counts before and after the call.
  A list and a count can disagree; an aggregate that follows the count
  cannot get ahead of it.
- Every wrapper calls the original exactly once, hands its result on, and
  guards its own steps so that a failure never reaches vanilla's action.

**Standing down**: with Hot Brass's framework active (`HBVCEFb42`), the
spent-cases feature is off: both would leave a casing for the same shot.
Gunworks replaces more of the reload actions than this mod has been checked
against; quality tracking is not switched off beside it, and a record it
cannot follow resolves to factory rounds.

## 6. Loot injection

**Where**: Hot Brass and NWMF insert into `ProceduralDistributions.list` in
an `Events.OnPreDistributionMerge` handler; KI5's vehicle mods and KnoxGPS
do it at file load, in `media/lua/server/`.

**What Ammo Making does**: the event, as it has since the first pass (it
does not depend on load order), into lists that a container really names,
never creating a list, with every weight in `AC_Loot.lua`.

## 7. Hiding or teaching recipes from Lua

**Where**: Hot Brass rewrites recipe scripts at world load
(`recipe:Load(name, "{ NeedToBeLearn = True, OnAddToMenu = False, }")`) to
hide recipes whose companion mod is absent; More Traits and tsarslib call
`learnRecipe` or add to the known-recipe list.

**Not used.** Rewriting a loaded recipe from Lua is one more behaviour that
only the game can confirm, and an add-on mod removes the recipes outright
with nothing to confirm. It is the fallback if the add-on structure turns
out not to work.

## Mods that touch the same vanilla functions

For whoever tests the mod beside others:

| Mod | What it does to firearms | With Ammo Making |
|---|---|---|
| Hot Brass framework (`HBVCEFb42`) | leaves casings; wraps `ejectSpentRounds`; re-registers `onShoot` and the attack hook | spent cases stand down. Quality tracking is untested beside it |
| Hot Brass Ammo Crafting (`HBAmmoCraft`) | its own casings, primers, projectiles and reloading bench | separate items and recipes; nothing shared |
| Gunworks (`SWMG`), Marz Vanilla Guns | per-round ammunition lists; wraps the seven reload functions and `onShoot` | untested. Both mods' wrappers call the function they found, so the order of loading decides who wraps whom |
| Auto Reload (`AutoReload`) | wraps `stop` and `perform` of the reload actions | no overlap with what this mod wraps |

Hot Brass looks for a mod id `ammomaker` and changes its behaviour beside
it. That is another mod; Ammo Making's id is `AmmoMaking`.

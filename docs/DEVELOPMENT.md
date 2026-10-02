# Development notes

Target: Project Zomboid Build 42.20 Stable. Everything in this file can be
checked without the game unless it is marked **REQUIRES IN-GAME VERIFICATION**.

## Real-game validation (Build 42.20.4)

Results of a manual test in the real game, reported by the developer. Only
what was actually observed in game is listed as confirmed; offline tests
never move an item into that list.

### CONFIRMED IN B42.20.4

- The pickaxe mining timed action starts and completes without a debugger
  break or NullPointerException (the `hasTag` / `StartAction` failure is
  gone).
- The `DigPickAxe` animation plays with the pickaxe.
- Zinc ore (`AmmoMaking.ZincOre`) appears on the ground after a successful
  extraction.
- The reserve decrements: a reserve-2 tile logged `remaining 1/2` after the
  first extraction.
- A tile that is exhausted becomes Exhausted and produces no more ore.
- Mining a tile with no workable copper returns `no_ore`.
- Walking away during mining cancels the action and produces no ore.
- Geological sample digging still works with `Base.Shovel`, with the
  `DigShovel` animation.
- The compatibility self-check passes on 42.20.4.

### STILL UNVERIFIED

- **Mining depletion persistence after save/reload** - REQUIRES IN-GAME
  VERIFICATION.
- **Laboratory analyzer processing persistence after save/reload** - REQUIRES
  IN-GAME VERIFICATION.
- The single mining result message and its XP text (changed after the test
  above), and that the XP total in the console log rises by the logged
  amount.
- `Base.CopperOre` spawning (the copper tile tested had no ore, so no copper
  ore item was created), picking the ore up, and the `Shoveling` sound
  with a pickaxe.
- The whole placed laboratory analyzer loop, and everything else under
  *REQUIRES IN-GAME VERIFICATION* at the end of this file.
- **All of metallurgy** (added 2026-10-02 without a game run): see
  *Metallurgy* below.

## Module map

| File | Layer | Responsibility |
|---|---|---|
| `shared/AC_Text.lua` | shared | `AC_Text.get(key, fallback, ...)`: translation lookup with an English fallback so a missing key never reaches the screen |
| `shared/AC_WorldData.lua` | shared | Save identity and the per-save geology / copper / zinc seeds; cache reset on `OnInitGlobalModData` |
| `shared/AC_Geology.lua` | shared | Deterministic noise, concentration, grades, 3x3 survey, terrain rules (`isSurveyableSquare`, `isWaterSquare`) |
| `shared/AC_GeologySampling.lua` | shared | Sample items, shovel checks, field / advanced assays, kit uses, result lines |
| `shared/AC_LaboratoryAnalyzer.lua` | shared | Laboratory analyzer rules for placed and dropped analyzers: state machine, timing, power, sample storage, cancel, pick-up rule, state repair, finding the analyzer among clicked objects, debug-only completion |
| `server/BuildingObjects/AC_LaboratoryAnalyzerObject.lua` | server | `ISBuildingObject` placement cursor; `create()` turns the analyzer item into an `IsoThumpable` |
| `shared/AC_Deposits.lua` | shared | Per-tile reserves derived from geology, depletion records in global ModData |
| `shared/AC_Mining.lua` | shared | Pickaxe rules, prospect lookup, `extract()` (the only mutation point of the mining loop) |
| `shared/AC_Materials.lua` | shared | Every station recipe of the mod: item ids, material units, the Lua mirror of the recipe script (metallurgy and case stock written here, components appended from `AC_Calibres`), conservation check, `OnCreate` callbacks (XP, then a recipe's effect), the Ammo Making requirement attached to the recipe scripts at boot |
| `shared/AC_Calibres.lua` | shared | **Every balance number of the ammunition stage.** Calibre definitions, class defaults (pistol, rifle, shotgun), primer families, priming-compound sources, powder, wadding, the prepared press; builds the component recipes, their material units and the item list from that data; validates it |
| `shared/AC_CaseQuality.lua` | shared | Case quality: pure roll, ModData read/write, the two recipe effects (quality on formed cases, inherited by assembled rounds) |
| `shared/AC_Recycling.lua` | shared | Brass recycling: what is plain brass, the scrapping recipes grouped by brass content, the recast, and `validate()` (it loses brass, it awards nothing). Data and arithmetic only |
| `shared/AC_Loot.lua` | shared | Die sets as rare loot: tier weights, target lists, `buildEntries`, `validate`, and the one `OnPreDistributionMerge` handler that appends the entries to vanilla's procedural lists |
| `shared/AC_QualityTally.lua` | shared | The quality tally of loaded ammunition as pure functions (`repair`, `reconcile`, `split`, `merge`, `consume`, `unload`). **Arithmetic only: no other file calls it**, nothing is stored and no vanilla function is wrapped (`AMMO_QUALITY_RUNTIME_DESIGN.md` 7, 8) |
| `shared/AC_SaveData.lua` | shared | How persisted numbers are read (`number`, `whole`, `isFinite`) and the schema of every ModData key (`SCHEMA`, `check`). Stores nothing |
| `scripts/AC_Recipes.txt` | script | **Generated** (`tests/write_recipes.lua`): 55 `craftRecipe` blocks in module `Base`, ids prefixed `AmmoMaking_`: metallurgy 4, case stock 2, gunpowder 1, primers 8 (four families × two charges), four per calibre × 9, scrapping 3, recast 1 |
| `scripts/AC_Items.txt` | script | Mod items (module `AmmoMaking`) |
| `shared/AC_Compat.lua` | shared | Startup compatibility self-check |
| `shared/AC_AmmoMakingSkill.lua` | shared | Perk registration, XP helpers; `awardXP()` logs every mining and laboratory grant |
| `shared/AC_AmmoQuality.lua`, `shared/AC_AmmoInspection.lua` | shared | Ammunition quality prototype (test cartridge only), and `AmmoInspection.inspectComponent`: the read-only inspection of real cases and loose handloaded rounds |
| `client/AC_GeologySamplingContextMenu.lua` | client | Dig / assay / laboratory menus (place, start, cancel, collect, pick up) |
| `client/AC_DigGeologicalSampleAction.lua` | client | Shovel timed action |
| `client/AC_PickUpAnalyzerAction.lua` | client | Timed action that picks a placed analyzer up again |
| `client/AC_MiningContextMenu.lua` | client | Mining options and tooltips |
| `client/AC_MineOreAction.lua` | client | Pickaxe timed action |
| `client/AC_GeologyAssayUI.lua`, `client/AC_AmmoInspectionUI.lua` | client | Result panels |
| `client/AC_GeologyDebug.lua` | client | The "Ammo Making Debug" tree (`-debug` only): Geology, Analyzer, Metallurgy, Ammunition |
| `client/AC_AmmoContextMenu.lua` | client | *Inspect Ammunition* on cases and loose handloaded rounds; the test cartridge's inspection and debug presets |

Load order is alphabetical within `shared/`, `client/` and `server/`. Modules
reference each other from inside functions, so the order does not matter at
load time, with the exceptions that say so with a `require`: `AC_Materials`
builds its recipe list from `AC_Calibres` and `AC_Recycling` while it loads,
`AC_Loot`, `AC_Recycling` and `AC_Compat` read `AC_Calibres`, and
`AC_SaveData` reads the test cartridge's defaults from `AC_AmmoQuality`. The
test harness honours `require` the same way. The placement cursor lives in `server/BuildingObjects/` like every
vanilla `ISBuildingObject` subclass.

## Gameplay constants

All tunables live in module-local `CONFIG` tables. They are intentionally not
centralised into one file: each value sits next to the code that reads it and
the tables are small. Nothing here has been balanced yet.

| Constant | Where | Current value | Read by |
|---|---|---|---|
| `baseScale`, `detailScale` | `AC_Geology.CONFIG` | 55, 18 | noise layers |
| `copperThreshold`, `zincThreshold` | `AC_Geology.CONFIG` | 0.50, 0.52 | ore rarity |
| `surveyRadius` | `AC_Geology.CONFIG` | 1 (3x3) | survey, mining coverage, debug tools |
| `reserveByGrade` | `AC_Deposits.CONFIG` | None/Trace 0, Poor/Moderate 1, Good 2, Rich 3, Very Rich 4 | initial reserve |
| `modDataKey` | `AC_Deposits.CONFIG` | `AmmoMakingDeposits` | save data |
| `fieldKitUses`, `advancedFieldKitUses` | `AC_GeologySampling.CONFIG` | 20, 10 | kit lifetime |
| `fieldMeasurementError` | `AC_GeologySampling.CONFIG` | 15 points | field assay |
| `advancedMeasurementError`, `advancedRangeHalfWidth` | `AC_GeologySampling.CONFIG` | 10, 10 | advanced assay |
| `digActionTime`, `digSound`, `digSoundRadius`, `shovelWearChance` | `AC_GeologySampling.CONFIG` | 150, `Shoveling`, 15, 10 % | dig action |
| `fieldAssayXP`, `advancedAssayXP` | `AC_GeologySampling.CONFIG` | 3, 6 | assay XP |
| `processingHours`, `measurementError`, `assayXP` | `AC_LaboratoryAnalyzer.CONFIG` | 24 h, 2 points, 10 | laboratory |
| `worldSprite` | `AC_LaboratoryAnalyzer.CONFIG` | `industry_03_61` (temporary vanilla tile) | placement cursor, compat check |
| `placeActionTime`, `pickUpActionTime` | `AC_LaboratoryAnalyzer.CONFIG` | 100, 50 ticks | placement (`ISBuildAction` subtracts 50 for Handy, keep > 50), pickup |
| `baseActionTime`, `skillTimeReductionPerLevel` | `AC_Mining.CONFIG` | 400, 4 % per level | mining duration |
| `minimumAssayRank` | `AC_Mining.CONFIG` | 1 | which assays unlock mining |
| `xpPerOre`, `pickaxeWearChance` | `AC_Mining.CONFIG` | 5, 15 % | extraction |
| `thinningThreshold` | `AC_Mining.CONFIG` | 1 | "vein is thinning" message |
| `sound`, `soundRadius` | `AC_Mining.CONFIG` | `Shoveling`, 20 | placeholder mining sound |
| `PICKAXE_TYPES` | `AC_Mining` | `Base.PickAxe`, `Base.PickAxeForged` | accepted tools |
| perk XP thresholds | `AC_AmmoMakingSkill.lua` | 75 … 9000 | levelling |
| `unitsPerIngot` | `AC_Materials.CONFIG` | 100 | metal accounting (ore 100, scrap 10, small brass sheet 10, case cup 5) |
| `xpSmeltZincOre`, `xpCastIngot`, `xpCastBrass` | `AC_Materials.CONFIG` | 3, 5, 25 | XP per completed furnace craft |
| `xpForgeBrassSheets`, `xpPunchCaseCups` | `AC_Materials.CONFIG` | 5, 1 | XP per forged ingot / punched sheet |
| `requiredLevel` | `AC_Materials.CONFIG` | 0 | Ammo Making level of metallurgy and case-stock recipes |
| `DEFAULTS.assembleLevel`, `xp`, `time` | `AC_Calibres` | 3; die set 10 / 300, case 1 / 80, bullet 1 / 80, assemble 2 / 40 | per-calibre steps. Levels derive from `assembleLevel` (`levelsFor`: die set and case two below, bullet one below, minimum 1); a definition may override any step |
| `DEFAULTS.cupsPerCase`, `bulletsPerScrap`, `powderUses` | `AC_Calibres` | 1, 2, 1 | cups per case, bullets per copper scrap, gunpowder uses per round (whole, never below 1). Overrides: .45 ACP 1 / 1 / 1, .357 Magnum 1 / 2 / 2, .44 Magnum 2 / 1 / 3, 5.56 2 / 2 / 3, .30-30 2 / 1 / 4, .308 3 / 1 / 5 |
| `CLASSES.rifle` | `AC_Calibres` | primer LargeRifle, cups 2, bullets 1, powder 4, round level 5; XP case 2, assemble 4; time 400 / 160 / 120 / 80 | what a `class = "rifle"` definition inherits before `DEFAULTS`. `CLASSES.pistol` is empty |
| `PRIMERS[..]` | `AC_Calibres` | SmallPistol: brass 1, compound 2, 10 per sheet, level 2. LargePistol: 2, 4, 5, level 3. SmallRifle: 1, 3, 10, level 4. LargeRifle: 2, 6, 5, level 4. XP 2 / time 120 (pistol), 3 / 150 (rifle) | primer families; each has a `class` |
| `COMPOUND_SOURCES` | `AC_Calibres` | toy cap 2 units, match use 1 unit; a primer needs 2 | priming charge |
| `POWDER` | `AC_Calibres` | 2 charcoal + 2 fertilizer uses → 1 jar (10 uses), level 3, XP 5, time 150 | gunpowder |
| `baseQuality`, `qualityPerLevel`, `spread` | `AC_CaseQuality.CONFIG` | 50, 4, 15 | case quality roll (1–100) |
| recipe `time`, charcoal counts, output counts | `AC_Recipes.txt` + `AC_Materials.RECIPES` | furnace 200, 4 / 4 / 4 / 10 charcoal; forge 200, 1 charcoal, 10 sheets; punch 100, 2 cups | station recipes (the two must match; a test compares them) |

## Invariants of the mining loop

These are enforced by the code and asserted by `tests/run_tests.lua`.

- **Extraction.** One completed `AC_MineOreAction` results in at most one
  reserve decrement, one ore item, one XP grant and one pickaxe wear roll.
  `AC_Mining.extract()` is the only function that does any of these, and it does
  them only after the item exists and has been placed on the square.
- **Cancellation.** `stop()` never extracts. `isValid()` fails, and the engine
  drops the action, when the pickaxe leaves the hands or breaks, the sample is no
  longer carried, the square stops being mineable, or the tile is already known
  to be exhausted. Nothing is written in any of those cases.
- **Persistence.** Only `extract()` writes to global ModData: a successful
  extraction increments the tile's extracted count; an attempt on a tile with
  no ore records the tile as worked with an extracted count of 0. Menus, lookups
  and validity checks never create entries. Untouched ground is never stored.
- **Knowledge.** The carried assay decides whether "Mine … Ore" is offered and
  what grade the label shows. The tile's deterministic geology decides what
  actually comes out. An assay can be wrong in both directions.
- **Hidden information.** Outside `-debug`, no menu label, tooltip, message or
  field-assay line contains an exact concentration or a reserve count. A tile is
  labelled exhausted only after someone has worked it. The XP gain in the
  result message is not geology and is allowed.

## Timed-action conventions (reviewed, no change needed)

`AC_MineOreAction` and `AC_DigGeologicalSampleAction` follow the vanilla
`ISBaseTimedAction` pattern:

- `new()` sets `character`, `maxTime = getDuration()`, `stopOnWalk`, `stopOnRun`,
  `stopOnAim`, `caloriesModifier`.
- `isValid()` is cheap, has no side effects and re-checks every precondition each
  tick (tool in hand, tool usable, sample carried, square mineable, tile not
  exhausted, item still in inventory on a multiplayer client).
- `waitToStart()` turns the character towards the square.
- `start()` re-resolves the item by id on a multiplayer client, sets job type and
  delta, chooses the animation and hand model, initialises sound state.
- `update()` keeps facing the square, sets the metabolic target, updates the job
  delta, applies muscle strain, retries the work sound every few seconds and
  emits a world sound for zombies.
- `stop()` stops the sound, clears the job delta, then calls
  `ISBaseTimedAction.stop(self)`.
- `perform()` clears the job delta, stops the sound, does the work, shows the
  result, then calls `ISBaseTimedAction.perform(self)` last.

The pickaxe action calls `BuildingHelper.getShovelAnim` directly, as the dig
action does; on 42.20.4 it returns `CharacterActionAnims.DigPickAxe` for a
pickaxe. The animation is confirmed in game; the `Shoveling` sound with a
pickaxe is still **REQUIRES IN-GAME VERIFICATION.**

### Mining result feedback

`perform()` shows exactly one halo message per completed action, built by
`AC_MineOreAction.getSuccessText()`:

| Outcome | Message |
|---|---|
| ore, reserve left | `Zinc ore extracted - +5 Ammo Making XP` (`- vein thinning out -` when 1 unit is left) |
| ore, last unit | `Zinc ore extracted - deposit exhausted - +5 Ammo Making XP` |
| ore, `-debug` | `Zinc ore extracted - 1/2 remaining - +5 Ammo Making XP` |
| no ore | `No workable zinc ore here` |

The exact reserve appears only with `-debug`: normal play keeps the
hidden-information rule. The separator is a plain ` - ` like the other
messages; whether the halo font has an em dash was not checked. The XP figure
is the amount the mod requested (`AC_Mining.CONFIG.xpPerOre`, unchanged).

Every XP grant from mining and laboratory collection goes through
`AmmoMakingSkill.awardXP()`, which prints one console line with the perk's
total before and after, read with `getXp():getXP(perk)` as vanilla
`ISPlayerStatsUI` does:

```text
[AmmoMaking] Mining: +5 Ammo Making XP (total 40 -> 45)
[AmmoMaking] Laboratory: +10 Ammo Making XP (total 45 -> 55)
```

If the engine scales XP (sandbox multiplier, boosts), the difference in the
totals shows what was really applied; the mod does not assume either way.

### Kahlua hazard: "No implementation found" on an overloaded Java method

Confirmed on 42.20.4 from the installed `projectzomboid.jar` (javap) and the
game's `console.txt`. When Lua calls an overloaded Java method with arguments no
overload accepts, `MultiLuaJavaInvoker.call` returns its pooled
`MethodArguments` object to the pool twice before raising "No implementation
found for function". The pool then hands the same object to two calls at once.
The next Java call that runs Lua which in turn calls Java with the same number of
parameters - `IsoGameCharacter:StartAction(action)` running the action's
`start()` - has its return values cleared underneath it and throws
`NullPointerException: Cannot assign field "callFrame" because "a" is null` at
`ReturnValues.put`, after `start()` has already run. A `pcall` around the bad
call does not help: the pool is already damaged.

This is what broke mining: `item:hasTag("Shovel")` (only `hasTag(ItemTag)` and
`hasTag(ItemTag...)` exist) failed on every right-click with a pickaxe in hand,
and the next "Mine ... Ore" then failed in `ISBaseTimedAction.begin`. Every
such NPE in the log follows a `hasTag` failure. Rule: never pass a guessed
argument type to a Java method; use only signatures seen in vanilla Lua or the
jar.

`AC_PickUpAnalyzerAction` follows the same conventions (read-only `isValid()`,
work in `perform()`), as vanilla `ISBuildAction` does in single-player.

## Laboratory analyzer

Two kinds of analyzer exist in the world. `AC_LaboratoryAnalyzer` handles both
through `getAnalyzerData()`:

| Kind | World object | State lives in | Pickup |
|---|---|---|---|
| Placed (current) | `IsoThumpable` from `AC_LaboratoryAnalyzerObject:create()`, flagged `AmmoMakingLaboratoryAnalyzerWorldObject` in its ModData (object name `AmmoMakingLaboratoryAnalyzer` as a fallback) | the object's ModData | `AC_PickUpAnalyzerAction`, only when idle and empty |
| Dropped (original) | the item on the floor (`IsoWorldInventoryObject`) | the item's ModData | vanilla; cannot be blocked |

Flow: item → **Place** (vanilla cursor, `ISBuildAction`, `create()`) → **Start
Lab Assay** (the sample moves into the analyzer; the result is rolled at once so
a reload cannot re-roll it) → processing (powered hours only) → **Collect**
(sample back at rank 3, XP once) or **Cancel** (sample back unchanged, no XP) →
**Pick Up** once idle.

Rules, all in `AC_LaboratoryAnalyzer` and covered by the offline tests:

- **One sample at a time**: `startAssay` refuses a busy analyzer.
- **Pick-up rule**: `canPickUp()` is true only for a placed analyzer that is
  idle and empty. Otherwise the menu shows Pick Up disabled with the reason.
  The timed action re-checks every tick (read-only `isIdleAndEmpty`) and
  `perform()` runs `canPickUp()` again before changing anything. The item is
  created before the object is removed; if that fails the analyzer stays.
- **Cancel** returns the stored sample exactly as it went in and discards the
  unseen laboratory result, so it cannot be used to re-roll.
- **Vanilla removal paths**: the object is created non-thumpable (zombies
  cannot break it) and non-dismantable (vanilla's dismantle and move handling
  skip it). A sledgehammer "Destroy" can still remove it and would lose a
  stored sample; that vanilla action is not intercepted.
- **Placement carries state**: an item that still holds a sample (a dropped
  analyzer picked up mid-assay) keeps it on the placed object. The processing
  clock restarts at placement, so time in an inventory does not count.
- **State repair**: `initialize()` repairs unknown states, idle with a sample,
  processing/ready without a sample, non-numeric timers and missing results,
  and prints one WARNING per repair.
- **Power**: `haveElectricity()` or (`hasGridPower()` and a room), the rule
  vanilla 42.20 uses for the car battery charger. `isHydroPowerOn()` is only a
  fallback for a build without `hasGridPower`.
- **Lazy time accounting**: elapsed hours are credited when the analyzer is
  next looked at (menu, start, cancel, collect, pickup), using the power state
  at that moment. What this guarantees, and what it does not:
  - unpowered at a check: the hours since the previous check are not
    credited, and the clock restarts, so processing does not advance;
  - powered again: hours from that check on are credited at the next check;
  - opening the menu repeatedly adds nothing: each check credits only the time
    since the previous one;
  - **limitation**: the whole interval between two checks follows the power
    state at the later check. An outage nobody looked at, which ended before
    the next check, is credited as powered time; power lost just before a
    check discards the powered hours since the previous one. Continuous power
    tracking would need a global object system (as vanilla uses for traps and
    farming) and is out of scope. The offline tests pin both directions of
    this limitation so a change to it is deliberate.
- **Console log** (only on player interaction, never per tick):

  ```text
  [AmmoMaking] Laboratory Assay Analyzer placed at x, y, z
  [AmmoMaking] Laboratory assay started for sample x, y; processing time = 24 hours
  [AmmoMaking] Laboratory analyzer powered: 5.00 h since last check credited; 19.00 h remaining
  [AmmoMaking] Laboratory analyzer UNPOWERED: 3.00 h since last check not credited (paused); 19.00 h remaining
  [AmmoMaking] Laboratory analyzer completed sample x, y
  [AmmoMaking] Laboratory: +10 Ammo Making XP (total a -> b)
  [AmmoMaking] Laboratory tested sample collected: sample x, y; analyzer idle
  [AmmoMaking] Laboratory assay cancelled; sample x, y returned
  [AmmoMaking] Laboratory Assay Analyzer picked up at x, y
  [AmmoMaking] Laboratory assay start refused: no_power | busy | invalid_sample | ...
  [AmmoMaking] Laboratory sample collection refused: not_ready | empty | ...
  [AmmoMaking] Analyzer pickup refused: processing | ready | gone | ...
  [AmmoMaking] Analyzer placement aborted: <reason>
  ```

- **XP**: granted only by a successful collection, once, from the menu
  handler (`AC_LaboratoryAnalyzer.CONFIG.assayXP`, 10). Start, completion,
  cancel, pickup and the debug tools grant none. The collect message reads
  `Laboratory tested sample collected - +10 Ammo Making XP`.

### Next in-game test: placed analyzer (`-debug`)

The loop the code supports, each step with the log line to look for:

1. Spawn the analyzer and a sample (debug menu: Spawn Laboratory Analyzer,
   Spawn Assayed Sample). Inventory → **Place Laboratory Assay Analyzer** on a
   powered indoor tile. Log: `placed at`. The item leaves the inventory.
2. Right-click it → **Start Lab Assay: Sample x, y**. Log: `assay started`.
   The sample leaves the inventory; no XP line.
3. While processing: no second Start option, **Pick Up** disabled with the
   reason, **Cancel Laboratory Assay** offered.
4. Debug → **Inspect Analyzer State** prints the state without advancing it.
5. Debug → **Complete Analyzer Job (no XP; collect normally)**. Log:
   `DEBUG: analyzer processing finished early` and `completed sample`; still
   no XP line.
6. **Collect Laboratory Sample**. One sample returns (laboratory tested), one
   `Laboratory: +10 Ammo Making XP` line, the halo shows the XP.
7. **Pick Up Laboratory Assay Analyzer** once idle. One analyzer item returns,
   the object disappears. Log: `picked up at`.
8. Power: start an assay, cut power (generator off / grid off), wait, check
   (`UNPOWERED ... not credited`), restore power, wait, check (`powered ...
   credited`). Remaining hours only drop in the powered interval.
9. Cancel: start, cancel; the original sample returns unchanged, no XP line.

Save/reload of a processing analyzer is part of the analyzer test when a
save/reload is possible; until then it stays **REQUIRES IN-GAME
VERIFICATION**.
- **Multiplayer**: placing and picking up are disabled on clients
  (`isPlacementAvailable()`): Build 42 runs `create()` on the server, and a
  client-side pickup would add the item only locally. Starting, cancelling
  and collecting also change client-local state today; sample ownership and
  server-side validation belong to a future multiplayer design.

Build 42 evidence, checked against the installed game's Lua and jar. That
install is 42.20.4 (Steam update of 2026-09-03; the 42.20.4 runtime ran from the
same unchanged files). An earlier note said 42.20.2, read from a stale log.

| Assumption | Evidence |
|---|---|
| `ISBuildingObject` fields used (`noNeedHammer`, `dragNilAfterPlace`, `ignoreNorth`, `maxTime`, `player`, `character`) and base `isValid()` → `buildUtil.canBePlace` | CONFIRMED: `server/BuildingObjects/ISBuildingObject.lua`, `ISBuildUtil.lua` |
| `ISBuildAction:perform()` calls `create()` only when not a multiplayer client, and subtracts 50 ticks for Handy | CONFIRMED: `client/BuildingObjects/TimedActions/ISBuildAction.lua` |
| `IsoThumpable.new(cell, square, sprite, north, self)`, `AddSpecialObject`, `transmitCompleteItemToClients`, item removed after the object exists | CONFIRMED pattern: `TrapBO`, `ISSimpleFurniture` |
| Removal with `transmitRemoveItemFromSquare` then `RemoveTileObject` | CONFIRMED pattern: `ISAddTakeDispenserBottle:complete()` |
| `setIsDismantable(false)` keeps a thumpable out of vanilla dismantle / move handling | CONFIRMED: `ISMoveableSpriteProps.fromObject`, `ISDestroyCursor`; vanilla `MOTrap.lua` sets it the same way |
| `hasModData()`, `getObjectIndex() == -1`, `hasGridPower()` | CONFIRMED: vanilla Lua usage, method names present in the jar |
| `industry_03_61` exists and is not a vanilla moveable | CONFIRMED: `media/newtiledefinitions.tiles.txt` has no `IsMoveAble`, so vanilla furniture pickup cannot grab the analyzer |
| `getSprite(name)` returns nil for an unknown tile | **WRONG, corrected on 2026-10-02.** JAR `IsoSpriteManager#getSprite`: an unknown name is created on the spot and returned, with `IsoSprite.DEFAULT_SPRITE_ID` (20000000) as its id. The game-start probe of the analyzer's sprite therefore reported OK for any name; it now compares `sprite:getID()` with the default id (public, and called by vanilla's debug Lua) |
| The placed object keeps its ModData through save/reload and chunk unload | **REQUIRES IN-GAME VERIFICATION** |

The placed analyzer was first written locally and never pushed. It was recovered
from `recovery/local-pre-claude` (commit `18d22b3`) and ported by hand. That
branch's `AC_GeologySamplingContextMenu.lua` and `AC_LaboratoryAnalyzer.lua` were
not restored: they predate localization, laboratory XP and the shared terrain
rule, and the menu calls the removed `AC_GeologySampling.updateLaboratoryAssay`.
Its `AC_SpriteInspector.lua` became a debug submenu entry.

## Metallurgy

Design, recipe table and vanilla evidence: `docs/METALLURGY_DESIGN.md` and
`docs/VANILLA_METALLURGY_RESEARCH.md`. What a developer needs to know here:

- **The engine does the work.** The recipes are plain `craftRecipe` blocks on
  the vanilla bench tags `PrimitiveFurnace` and `Furnace`. Mod Lua never
  consumes or creates an item in this stage and stores nothing.
- **Two sources of truth, pinned together.** `scripts/AC_Recipes.txt` is what
  the game loads; `AC_Materials.RECIPES` is what the tests reason about. The
  section *AC_Recipes.txt equals AC_Materials.RECIPES* parses the script and
  compares every field, input and output. Change both or the suite fails.
- **The script is generated.** `tests/write_recipes.lua` renders
  `AC_Materials.RECIPES` through `tests/render_recipes.lua` and rewrites the
  body of `AC_Recipes.txt`, keeping its leading comment. The suite asserts
  the file equals the rendering, so the script is never typed by hand.
- **Adding a recipe**: add the mirror entry (copy a vanilla block; only
  fields, flags and tags in the tests' whitelists) with a `callback` and an
  `xp` or `xpKey`, run the writer, add the name to `Recipes.json`, and any
  new item id to `AC_Compat.REQUIRED_ITEMS` and `AC_Materials.UNITS`. The
  conservation, translation and compat tests then cover it without further
  changes. For a calibre see *Ammunition components* below.
- **Skill.** `SkillRequired` / `xpAward` cannot name the Ammo Making perk in a
  script: scripts are parsed before mod Lua registers it, and the engine
  drops unknown perks (jar: `CraftRecipe.Load`, `GameWindow.initShared`). XP
  therefore comes from `OnCreate` (`AC_Materials.on<Recipe>(craftRecipeData,
  character)`), and `applySkillRequirements()` adds "Ammo Making:
  `requiredLevel`" to each recipe script on `OnGameBoot` and again on
  `OnGameStart`. It is idempotent: a recipe that already has a required skill
  is skipped. The engine then scales craft time itself
  (`CraftRecipe.getTime`: 5 % per level above the requirement).
- **Kahlua rule respected**: `addRequiredSkill` is called only with
  `(perk, number)`, the one signature in the jar, and only after the method
  was found on the object.

Console lines:

```text
[AmmoMaking] Station recipes: 51 given the Ammo Making requirement, 0 already had it, 0 not found, 0 unsupported
[AmmoMaking] Crafting (AmmoMaking_CastBrassIngots): +25 Ammo Making XP (total 40 -> 65)
[AmmoMaking] WARNING: recipe skill requirements not applied: <error>
```

The first line is printed only when something was attached or something is
wrong; a second run that finds everything in place is silent.

Invariants (asserted by the tests): units out = units in for every mod
recipe; brass is exactly 700 + 300 → 1000 units; kept tools hold no metal;
hot recipes consume their charcoal; no recipe loop exists over mod and vanilla
copper recipes together; ten ore become exactly 200 case cups; XP is granted
once per `OnCreate` call and never without a character.

### Case stock

`AmmoMaking_ForgeSmallBrassSheets` (`PrimitiveForge`, copied from vanilla
`Forge_Copper_Sheet`) and `AmmoMaking_PunchBrassCaseCups` (`AnySurfaceCraft`,
`MakingHammer_Surface`). Unlike furnace recipes they carry a `timedAction`,
as their vanilla templates do. The cup has no calibre and no ModData.

### Ammunition components

Design, recipe table, the generated balance tables and vanilla evidence:
`docs/AMMUNITION_DESIGN.md`, `docs/VANILLA_AMMUNITION_RESEARCH.md`,
`docs/RIFLE_AMMUNITION_RESEARCH.md`, `docs/SHOTGUN_AMMUNITION_RESEARCH.md`.
The planned press: `docs/RELOADING_PRESS_DESIGN.md`. Boxes, loot, magazines
and recycling: `docs/AMMUNITION_ROADMAP.md`.

- **Data, not code.** `AC_Calibres.LIST` holds one definition per calibre;
  `AC_Calibres.define()` fills everything it leaves out from `DEFAULTS` and
  derives the item ids from the suffix. `buildRecipes()` returns the mirror
  entries (gunpowder, primers per family and compound source, four per
  calibre) and `AC_Materials` appends them at load, after `require
  "AC_Calibres"`. A test scans every other Lua file for a calibre suffix
  and fails if it finds one.
- **Primer families** are entries of `AC_Calibres.PRIMERS`; a calibre names
  one in `primerFamily`. Primer recipes are generated per family and
  compound source. No file outside `AC_Calibres.lua` contains a primer item
  id (tested).
- **Classes.** `class` is `"pistol"` (default), `"rifle"` or `"shotgun"`.
  `AC_Calibres.CLASSES[class]` supplies what a definition leaves out, between
  `DEFAULTS` and the definition, and a `label` for the summaries. A primer
  family's `class` must equal its calibre's, unless the calibre's class names
  another in `primerClass`; only the shotgun class does (`"pistol"`). Nothing
  else branches on a class: rifle and shell recipes come out of the same
  generator, and there is no rifle or shotgun file.
- **The shell** is a calibre whose `case` is the hull and whose `bullet` is
  the shot charge (explicit item ids), with `wads = 1`: one more assembly
  input, `AC_Calibres.WAD.items`, written `mode:destroy` (a mirror input with
  `destroy = true`).
- **The press** is described and switched off: `AC_Calibres.PRESS`,
  `buildPressRecipes(calibre)` and `validatePress()`. `buildRecipes()` adds
  the press recipes only when `PRESS.enabled`; with it off nothing of the
  press exists outside `AC_Calibres.lua` and the tests.
- **One place for balance.** `CONFIG`, `POWDER`, `COMPOUND_SOURCES`,
  `PRIMERS`, `DEFAULTS`, `CLASSES`, `LIST` and `PRESS` in `AC_Calibres.lua`
  hold every number. `AC_Recipes.txt`, the balance tables of
  `docs/AMMUNITION_DESIGN.md` §2 and the calibre table of `README.md` are
  generated from them by `tests/write_recipes.lua`; the suite fails while any
  of the three differs from the model.
- **Validation.** `AC_Calibres.validate(list, primers)` is pure and returns
  problems as `"<calibre>: text"`: duplicate ids or suffixes, an unknown
  class, an item used by two calibres or two roles, a non-vanilla round, an
  unknown primer family, a primer family of a class the calibre's class may
  not take, an unknown `primerClass`, fractional cups / bullets / powder /
  wads, a shell without a wad, a component that unlocks after its
  round, a primer that does not use exactly one sheet. The suite requires
  the live model to return none and feeds it broken copies; `AC_Compat` runs
  it at game start.
- **Adding a calibre**: a `LIST` entry (`id`, `suffix`, `round`, `ammoType`,
  plus only what differs), three items in `AC_Items.txt`, their names in
  `ItemName.json`, four recipe names in `Recipes.json`,
  `tests/write_recipes.lua`, and the new ids in the test mock's
  `knownScriptItems`. Debug kits, compat probes, conservation and
  progression tests follow the list.
- **Recipe fields beyond metallurgy's**: `xp` and `requiredLevel` (per
  recipe), `effect` (`caseQuality` on forming, `roundQuality` on assembly),
  `source = "powder"` (only on gunpowder mixing), `tool = true` (the die set
  recipe makes no tracked material).
- **Effects.** `AC_Materials.onRecipeCreated` grants XP, then runs
  `AC_CaseQuality.EFFECTS[recipe.effect](craftRecipeData, character)` inside
  a `pcall`. A failing effect prints one WARNING and changes nothing else:
  the craft has already happened and the XP is granted.
- **Engine calls in the effects**: `craftRecipeData:getAllCreatedItems()`
  and `getAllConsumedItems()`, both with no arguments (overloads exist; the
  no-argument forms are in the jar and vanilla Lua calls the second),
  `item:getFullType()`, `item:getModData()`, `ZombRandFloat(0.0, 1.0)`. Each
  method is looked up before it is called.
- **Levels are enforced only through the attached requirement.** The
  compatibility check names every recipe whose requirement is missing and
  what level it should have had.
- **Compatibility lines for calibres**: `OK: calibre model (9 calibres, 4
  primer families)`, then `OK: calibre <id> complete` or `WARNING: calibre
  <id> incomplete (missing …; the other calibres are unaffected)`, one
  summary line per class (`Pistol calibres: 5/5 complete`), and
  `OK: Base.GunPowder holds 10 uses` (read from the item script's
  `getUseDelta()`; a different number is a WARNING because the powder
  accounting assumes ten).
- **Material model.** A `UNITS` entry is `{ metal, units }` or
  `{ contents = { material = n } }`; `uses` marks a drainable, whose input
  lines count uses (as the engine does) and whose output is a full item
  unless the mirror says `oneUse`. Alloy parts pay for an alloy only in the
  recipe marked `alloy`.

Console lines:

```text
[AmmoMaking] Calibre definitions loaded (9)
[AmmoMaking] Crafting (AmmoMaking_FormCase9mm): +1 Ammo Making XP (total 80 -> 81)
[AmmoMaking] WARNING: caseQuality failed for AmmoMaking_FormCase9mm: <error>
```

### Multiplayer requirements (not implemented)

- `OnCreate` runs on the server (`ISHandcraftAction:complete` →
  `performRecipe`). Grant XP there with vanilla's `addXp(character, perk,
  amount)` instead of the single-player `getXp():AddXP`.
- Run `applySkillRequirements()` on the server and on every client.
- Case quality is written in `OnCreate`, on the server. Whether ModData set
  there reaches clients needs checking before quality is used for anything.
- Component inspection is client-side and read-only; it needs nothing.
- The press, when built, is a vanilla `CraftBench` entity with vanilla
  authority and persistence (`docs/RELOADING_PRESS_DESIGN.md` §8).
- Nothing else: the ammunition stage has no custom state, command or timed
  action. Everything it changes, it changes through vanilla recipes.

## Persisted data (ModData)

Everything the mod stores in a save, reviewed from the code on 2026-10-02.
Whether item and world-object ModData survive save/reload and chunk unloading
is engine behaviour and is listed under *REQUIRES IN-GAME VERIFICATION*; the
depletion store was seen working in game.

**Nothing else is persisted.** Geology and seeds are recomputed each session
from the save's identity (`AC_WorldData`; its `cached*` fields are a runtime
cache). Ammo Making XP is the engine's perk. Calibres, recipes, loot weights
and recycling yields are code, not save data, so changing them never needs a
migration. Die-set loot changes the game's loot tables in memory each world
load and stores nothing.

**The tables below are also data.** `AC_SaveData.SCHEMA` declares every
structure and key: owner, carrier, type, range, default, what happens to a
damaged value, and whether a version would matter. Three tests hold it to
the code:

- a scan of the mod's source fails when a ModData key is used that the
  schema does not declare, or declared and no longer used;
- everything the mod itself writes (a dug sample, each assay, the analyzer
  in each state, a formed case, an assembled round) passes
  `AC_SaveData.check()`;
- **the fuzz**: every declared key, damaged fifteen ways (missing, wrong
  type, a word, negative, zero, 900, huge, infinity, NaN, a table, a
  fraction), is pushed through the menus, the assays, the analyzer, mining
  and inspection: 28,130 calls. None may raise, and every number that comes
  back must be in its range and printable.

Persisted numbers are read through `AC_SaveData.number()` / `whole()` /
`isFinite()`, not bare `tonumber()`: to `tonumber`, NaN and infinity are
numbers, and 900 is a number that is not a quality.

### Global: `ModData.getOrCreate("AmmoMakingDeposits")`

The only global table, and the only `ModData.*` call in the mod. Created
lazily by `AC_Deposits.getStore()` on any read; nothing is transmitted.

| Key | Value | Lifecycle | Malformed data |
|---|---|---|---|
| `version` | `1` (`AC_Deposits.CONFIG.version`) | set when missing; compared on every read of the store (*Versions and migrations*, below) | restored when nil; a higher one marks a later release's store, left as it is |
| `tiles` | table keyed `"x,y"` | created with the store | a non-table is replaced by `{}` with a warning (the records are lost) |
| `tiles[k].copper`, `.zinc` | units extracted, integer ≥ 0; `0` means "worked, nothing there" | written on the first extraction attempt, only ever increases; removed only by the debug reset | a non-table record reads as unworked; a count is a whole number of 0 or more, anything else (a word, NaN, an infinity) reads as 0 |

Only worked tiles are stored. Reserves come from geology, so a rebalance
keeps old saves valid: the stored number is what was taken, not what is left.

### Item: `AmmoMaking.GeologicalSample`

| Key | Value | Written | Read |
|---|---|---|---|
| `sampleX`, `sampleY` | tile coordinates | when dug | prospect lookup (guarded with `tonumber`), result panel, menu labels |
| `trueCopper`, `trueZinc` | hidden 3x3 average, 0–100 | when dug | every assay, as 0–100 (out of range is clamped; not a finite number is 0) |
| `assayRank` | 0 none, 1 field, 2 advanced, 3 laboratory | by each assay | everywhere as `tonumber(v) or 0` |
| `copperGrade`, `zincGrade` | grade name | by each assay | prospect lookup, result panel |
| `copperMin/Max`, `zincMin/Max` | 0–100, rank 2 only | advanced assay | result panel (`?` when not 0–100) |
| `labCopperResult`, `labZincResult` | 0–100 | laboratory collection | result panel (`?` when not 0–100) |
| `AmmoMakingGeologicalSample`, `geologySeed`, `trueCopperPeak`, `trueZincPeak`, `assayType`, `labStartedAt`, `labReadyAt`, `labProcessing` | markers and records | when dug or assayed | **never read by logic** (`labProcessing` is only ever written `false`) |

A sample that goes into the analyzer is removed; its fields travel as
`stored_<field>` on the analyzer and a new item is created on collect or
cancel.

### Item: `AmmoMaking.FieldAssayKit`, `AmmoMaking.AdvancedFieldAssayKit`

`AmmoMakingAssayKitInitialized` (flag), `assayKitType` (never read),
`assayMaxUses` (20 or 10), `assayUsesRemaining` (counts down). Created the
first time a kit is looked at, which is when the inventory menu opens on a
sample.

Damaged counters are repaired in place the next time the kit is looked at
(`repairKit`): `assayMaxUses` must be a whole number from 1 to the kit
type's own count, `assayUsesRemaining` from 0 to that. Uses that are not a
number at all become 0: a damaged kit is an empty kit, never a refilled
one. Valid data is never written to.

### Laboratory analyzer: the placed `IsoThumpable`'s ModData, or the dropped item's

Both carriers use the same keys (`AC_LaboratoryAnalyzer.getAnalyzerData`).

| Key | Value | Malformed data |
|---|---|---|
| `AmmoMakingLaboratoryAnalyzerWorldObject` | `true` on a placed object | falls back to the object name |
| `labAnalyzerState` | `idle`, `processing`, `ready` | `normalizeState` repairs an unknown state and logs it |
| `storedSample` | `true` while a sample is inside | must be exactly `true` |
| `stored_<field>` | the fifteen sample fields | copied back as they are |
| `labRemainingHours`, `labLastUpdateAt` | hours | dropped and rebuilt when not a finite number; the remaining time is kept within 0 and one full run |
| `labReadyAt` | hours | read only by the one migration below; dropped when not a finite number |
| `labCopperResult`, `labZincResult` | 0–100, rolled at start | measured again from the stored truth when missing, not a number or not 0–100 |
| `labStartedAt`, `AmmoMakingLaboratoryAnalyzer` | records | not read by logic |

**The one migration in the mod**: an analyzer saved by the first version, with
`labReadyAt` and no `labRemainingHours`, gets its remaining hours computed
from `labReadyAt` (`updateState`). The dropped item is the legacy carrier and
is still supported; placing it copies its state onto the object.

### Item: a calibre's case (or hull) and its round

| Key | On | Value | Lifecycle | Malformed data |
|---|---|---|---|---|
| `caseQuality` | case | 1–100 | rolled in the forming recipe's `OnCreate`; the case is consumed at assembly | not a finite number → none; clamped to 1–100 |
| `AmmoMakingCase` | case | `true` | with it | never read |
| `casingQuality` | round | 1–100, the average of the consumed cases | written at assembly; **gone once the round is loaded or boxed** | not a finite number → none; clamped to 1–100 |
| `AmmoMakingHandloaded` | round | `true` | with it | never read |

### Item: `AmmoMaking.TestCartridge` (prototype)

`AmmoMakingQualityInitialized`, the four component qualities, `powderLoad`,
`reloadCount` and the three derived values (`AmmoQuality.DEFAULTS`). A field
that is missing or not a finite number gets its default back on the next
inspection.

**One name, two meanings.** `casingQuality` is a prototype field on the test
cartridge and the inherited case quality on a real round.
`AmmoQuality.initialize` must never be given a real round (it would write
100 over the round's record); the only caller checks the item type first,
and a test asserts that inspecting a real component writes nothing.

### What the review found, and what was done

| Finding | Action |
|---|---|
| A round's `casingQuality` was returned unclamped: damaged data showed as "Excellent (900)" | **fixed**: clamped like a case's quality |
| A test cartridge with its flag set and a field missing raised "arithmetic on a nil value" in the menu click | **fixed**: missing or non-numeric fields are restored to their defaults |
| The deposits `version` is written and never read | **now read**: see *Versions and migrations* |
| Several keys are written and never read (table above) | left: harmless, and removing a key from a system confirmed in game buys nothing |
| `labProcessing` is tested for `true` and only ever written `false` | left: dead state on in-game-confirmed code; noted for the next change to that file |
| A sample whose grade is damaged into a non-string still counts as a prospect; `storedSample` damaged into a truthy non-`true` value loses the stored sample | left: each needs hand-edited or corrupt save data, none raises an error, and geology (not the sample) still decides what a tile yields |

Found by the fuzz on 2026-10-02 (none raised an error; each was a value
escaping its range) and fixed at the place the value is read:

| Finding | Fix |
|---|---|
| A kit whose `assayUsesRemaining` was damaged into 900, 1e15 or infinity had that many assays; a negative one stayed negative | `repairKit`: rewritten into 0..`assayMaxUses` |
| A kit's name showed `(18/inf)` or `(18/nan)` for a damaged `assayMaxUses` | the same repair |
| An analyzer's `labRemainingHours` of 900 or infinity meant a run that never finished | kept within 0 and one full run in `updateState` |
| A damaged `labCopperResult` / `labZincResult` (900, −5, NaN) was handed back on the sample as it was | measured again when not 0–100 |
| A sample's `trueCopper` of NaN produced NaN measurements and a NaN laboratory result | `measuredValue` and `laboratoryMeasurement` read the truth as 0–100 |
| The result panel printed `inf`, `nan` or a raw non-string grade for damaged coordinates, ranges and grades | `displayData`: a view for the panel in which each such field is a usable value or `?`; the sample is not changed |
| A case or round quality of NaN passed the "is it a number" test and reached the inspection text | `AC_SaveData.isFinite` |
| A test cartridge field of NaN or infinity survived the repair and poisoned the derived values | restored to its default like any other damaged field |
| A deposits count of infinity or NaN read as infinity or NaN | read as a whole count; not a finite number is 0 |

No schema migration was added: nothing has been renamed since the keys were
introduced, apart from the `labReadyAt` case that is already handled.

### Versions and migrations

The strategy, as of 2026-10-02:

| Structure | Version | Why |
|---|---|---|
| Depletion store (global) | `version = 1`, `AC_Deposits.CONFIG.version` | the one structure with a layout that could change (a table of records) |
| Quality tally (not stored yet) | its own `version`, `AC_QualityTally.CONFIG.version` | a record that later releases may extend |
| Sample, kits, analyzer, case, round, test cartridge | none | flat keys read one by one, each with its own range and default. A key added later is simply absent in an old save and reads as its default; the analyzer's one change of shape (`labReadyAt`) is recognised by shape |
| Calibres, recipes, loot, recycling, XP values | not save data | code and scripts: changing them needs no migration |

Two functions in `AC_SaveData` carry it:

- `versionStatus(value, current)`: `missing`, `current`, `older`, `newer`
  or `damaged`.
- `upgrade(data, current, steps)`: runs `steps[v]` for each layout from the
  stored one up to `current`, advancing `data.version` after each. The
  usual case is one comparison and no step.

The rules, each asserted by the section *Save data versions*:

| Rule | How |
|---|---|
| An older valid save stays valid | steps convert, they never reset; a field no step knows is kept |
| A migration is idempotent | the version is advanced only after a step returns, and a current structure runs nothing |
| A failed step does not corrupt | the version stays where it was and the step runs again at the next load; a step must tolerate its own partial result |
| A save from a **later** release is not damaged by an earlier one | `newer`: nothing is repaired, reset or stamped. The depletion store is read where it is understood (a later store's `tiles` table is used as it is; anything else reads as unworked ground and is left alone), with one warning per world load |
| Not run every frame | there is no event: the check is one comparison inside the store accessor |
| No duplication | a step moves or converts data and creates no item; the suite's fuzz still requires every count to stay within its range after any damage |

**There is no migration step in the mod**: `AC_Deposits.MIGRATIONS` is
empty, because the store has had one layout. The first change of layout is
then one function in that table and `CONFIG.version` raised by one; the
runner, its failure behaviour and the later-release rule are already
tested, with an invented three-layout structure.

One limit worth knowing: on a later release's store whose records this
release cannot read, an extraction is not recorded (there is nowhere it
could safely be written), so that tile's depletion would not persist. That
can only happen after downgrading the mod across a change of layout.

### Reads that write

Not bugs, but worth knowing when adding multiplayer or a "view only" tool:

- Any deposits read creates the global table (never a tile record).
- Opening a menu on an analyzer runs `updateState`, which credits time,
  repairs state and may rename a dropped analyzer. The read-only path is
  `isIdleAndEmpty`.
- Opening the inventory menu on a sample initialises and renames the kits.
- Inspecting the **test cartridge** fills in and recomputes its prototype
  fields. Inspecting a real case or round (`inspectComponent`) only reads.

## Multiplayer hazards (review; nothing is implemented)

The full authority map, each known duplication and how it would be closed,
and the order of work are in `MULTIPLAYER_DESIGN.md`. What follows is the
summary that was written with the code.

Mining and analyzer placement are disabled for multiplayer clients
(`AC_Mining.isAvailable`, `AC_LaboratoryAnalyzer.isPlacementAvailable`, both
`not isClient()`); the mining design is in `MULTIPLAYER_MINING.md`. The mod
has no `sendClientCommand`, no `OnClientCommand` and no `ModData.transmit`.
State that a server would have to own, as the code stands:

| System | Client-side state change today | Needs |
|---|---|---|
| Deposits | the global depletion table, written by `extract` | server-owned store, transmitted (designed) |
| Seeds | derived from the local world identity | the server's identity on every client |
| Digging a sample | local `AddItem`, sample ModData, shovel wear | a server command |
| Field and advanced assay | kit and sample ModData, XP | a server command |
| Laboratory analyzer | object or item ModData, the sample removed and re-created, XP, and time credited by whichever client opens the menu | server-owned state and `transmitModData`; the lazy timer per client is the main hazard |
| **Ammunition (this stage)** | **none of its own** | see below |

**The systems added on 2026-10-02**, classified by where their state
lives:

| System | Mutable state of its own | Class | Future multiplayer work |
|---|---|---|---|
| Brass recycling | none: four vanilla `craftRecipe` blocks, no XP, no effect | **vanilla-authoritative** | none |
| Die-set loot | none in a save; it appends to the loot tables in memory on each world load | **vanilla-authoritative**, once the entries are in the server's tables | the handler is in `shared/`, so a dedicated server runs it too; on a client it changes tables the client never rolls from (harmless). REQUIRES FUTURE IN-GAME VERIFICATION on a server |
| Ammo boxes | none: vanilla's recipe | **vanilla-authoritative** | none |
| Save-data readers and repairs | none of their own; they run where the owning system runs | as the owning system | a repair that writes (a kit's counters, the analyzer's timer) happens on whichever side reads the data: the same hazard the analyzer row above already names |
| Press recipes (off) | none | vanilla-authoritative | none; the station is a vanilla entity |
| Spent cases, quality tally (not built) | would be item ModData written at the shot and at reload | **server-required-later** | every write where vanilla writes the count (`not isClient()`), synced by `syncHandWeaponFields` / `syncItemFields` (`AMMO_QUALITY_RUNTIME_DESIGN.md`) |
| Inspection | none: reads only | **client-local** | none |

Nothing added in this pass needs networking code, and none was written.

The ammunition stage was built so that it adds nothing to this list. Every
change it makes goes through a vanilla `craftRecipe`, which the server
performs. The two things that happen in `OnCreate` are the open points:

- XP is granted with the single-player call; a server needs vanilla's
  `addXp(character, perk, amount)`.
- Case and round quality are written to item ModData in `OnCreate`; whether
  that reaches clients is unverified. Nothing gameplay-relevant reads it.

`applySkillRequirements()` changes recipe scripts in memory and has to run on
the server and on every client; it already runs on `OnGameBoot` and
`OnGameStart`. Inspection is client-side and read-only. The press, when it is
built, is a vanilla entity with vanilla authority. No networking code was
added in this pass: there is no current exploit to close, because the
client-side systems are disabled for clients.

## Compatibility self-check

`AC_Compat.run()` executes once on `OnGameStart`. Every assumption is a
result, `OK`, `WARNING` or `UNVERIFIED`. A normal start prints only what needs
attention and a short summary:

```text
[AmmoMaking] WARNING: calibre 5.56 incomplete (missing Base.556Bullets; the other calibres are unaffected)
[AmmoMaking] Pistol calibres: 5/5 complete
[AmmoMaking] Rifle calibres: 2/3 complete
[AmmoMaking] Shotgun shells: 1/1 complete
[AmmoMaking] Compatibility check: 171 ok, 2 warnings, 0 unverified
```

In `-debug` mode, or from the debug menu, the `[AmmoMaking] OK: …` line of
every probe is printed as well (`AC_Compat.run(true)`). The class labels come
from `AC_Calibres.CLASSES[class].label`. It probes item scripts, the item factory, global ModData, the square
and character methods the actions call, client globals, whether the translation
file loaded (and which perk-description key spelling resolves) and the geology
seed, and what the placed laboratory analyzer relies on (square and character
methods, `ISBuildingObject`, `IsoThumpable.new`, that the `server/` cursor file
loaded, and that the world sprite exists), and metallurgy (the vanilla and
zinc item ids, each furnace recipe script, its `OnCreate` callback, whether
`CraftRecipe:addRequiredSkill` exists and whether the Ammo Making requirement
is attached). It also reports the calibre model, the prepared press, the
vanilla ammo boxes (each round's box item and the `place_ammo_in_box` recipe
id), brass recycling (`AC_Recycling.validate`), and die-set loot: the model,
and what the registration found when the world loaded (a list that is
missing, emptied or named by no container on this build is a WARNING; die
sets can then only be forged). It never changes game state and cannot raise.
The debug menu can re-run it.

## Debug tools (`-debug` only)

Right-click the ground → **Ammo Making Debug**, one tree grouped by stage:

```text
Ammo Making Debug
├─ Geology       Inspect Current Tile · Survey Current Area (3x3) · Show Geology Seed ·
│                Inspect Clicked Tile Objects · Reset Depletion (tile / 3x3) ·
│                Spawn Sampling Kit · Spawn Mining Kit · Spawn Assayed Sample
├─ Analyzer      Spawn Laboratory Analyzer · (clicked analyzer:) Inspect Analyzer State ·
│                Complete Analyzer Job
├─ Metallurgy    Spawn Metallurgy Kit · Spawn Case Stock Kit · Spawn Recycling Kit ·
│                Inspect Station Recipes · Print Material Ledger (inventory)
├─ Ammunition    Spawn Calibre Kit ▸ one entry per calibre · Spawn Primer and Powder Kit ·
│                Print Calibre Definitions · Print Primer Families ·
│                Verify Ammo Dependencies · Inspect Ammo Components (inventory)
├─ Set Ammo Making Level ▸ 0 … 10
└─ Run Compatibility Check
```

Everything prints to `console.txt`. From the Lua console:
`AC_GeologyDebug.tile(getPlayer())`.

- **Spawn Metallurgy Kit**: tongs, a ceramic crucible, an iron ingot mold
  (it does not break), 22 charcoal, one zinc ore, ten scrap of each metal,
  six copper and two zinc ingots: every furnace recipe once, with the two
  cast ingots completing a 7 + 3 brass batch. About 130 weight. No furnace
  is spawned; build one or use vanilla debug.
- **Spawn Case Stock Kit**: a ball-peen hammer, tongs, a metalworking
  punch, one charcoal, one brass ingot and two small brass sheets: forge the
  ingot at a forge, punch the sheets at any surface.
- **Spawn Calibre Kit → <calibre>**: the die set, a hammer, and the cups,
  copper scrap, primers of the calibre's family, gunpowder and, for a shell,
  wadding for five rounds of that calibre, computed from its definition.
- **Print Calibre Definitions**: one console line per calibre, whatever its
  class (class, round, case and cups, bullet and bullets per scrap, primer
  family and item, powder uses, wads if any, die set, the four levels) and
  any problem `AC_Calibres.validate()` finds. Read-only.
- **Print Primer Families**: one console line per family (class, item, brass
  and compound, primers per sheet, level, the rounds that take it).
  Read-only.
- **Verify Ammo Dependencies**: `AC_Compat.runAmmunition()`, only the
  ammunition probes (the calibre model, each round's items and recipes, the
  gunpowder jar). Prints problems, one summary line per class and its own
  totals; it does not count as the once-per-start compatibility check.
- **Spawn Primer and Powder Kit**: punch, hammer, mortar and pestle, two
  small brass sheets, ten toy caps, a matchbox, two charcoal and a bag of
  fertilizer: both primer recipes and one powder mix. `AddItem` honours a
  vanilla item's `count`, so some vanilla entries may arrive in multiples.
- **Inspect Ammo Components (inventory)**: every case and round of a known
  calibre the player carries, with its stored quality and label. Read-only.
- **Print Material Ledger (inventory)**: one console line per kind of
  carried item that holds tracked material (`2 x Base.BrassIngot: brass
  200`) and the total per material. It is the in-game form of the
  conservation rule: print it, craft, print it again; the totals are equal,
  or lower after a recycling recipe. Drainables (gunpowder, matches,
  fertilizer) are not counted, because their remaining uses are not read.
  Read-only.
- **Inspect Station Recipes**: one console line per recipe: whether the
  script manager knows it, its required-skill count, required level, XP, predicted time at
  the player's level and the conservation verdict. Read-only.

Right-clicking a square that holds an Ammo Making analyzer (placed or dropped)
adds two more entries to the Analyzer submenu; they never appear for other
squares:

- **Inspect Analyzer State**: state, stored sample, remaining hours, hours
  not yet credited, the inputs of the power rule, the rolled result and
  whether pickup is allowed. Read-only: it credits no time.
- **Complete Analyzer Job (no XP; collect normally)**: sets the remaining
  time of a running assay to zero and lets `updateState()` finish it the
  normal way. It keeps the result rolled at start, ignores power, grants no
  XP and does not touch `CONFIG.processingHours`; the sample is then
  collected through the normal menu, which grants the XP.
  `AC_LaboratoryAnalyzer.debugFinishProcessing()` refuses unless
  `isDebugEnabled()` is true, even when called from the Lua console.

Inspect Clicked Tile Objects lists every object, special object and world item
on the clicked square with its sprite name (how the analyzer's sprite was
found), plus a placed or dropped analyzer's stored state, read without
advancing it.

## Offline tests

```text
lua5.1 tests/run_tests.lua
```

`tests/mock_pz.lua` mocks the Project Zomboid API; `tests/run_tests.lua` loads
every mod file and runs the checks. The suite proves Lua logic only. Sections
that drive the placement cursor, the placed object or the pickup action run
against mocked engine objects and say so in their names; they check control
flow, not engine behaviour.

Any Lua 5.1 runtime works. Without a `lua5.1` binary (for example on Windows),
Python's `lupa` package ships one: `lupa.lua51.LuaRuntime().execute(...)` with
`arg = { [0] = "<repo>/tests/run_tests.lua" }` set before `dofile`. A syntax
check is `loadfile(path)` on every `.lua` file in the same runtime.

The tests load the real `AC_AmmoMakingSkill.lua` with a minimal `PerkFactory`
mock, so `awardXP()` and its log line are the mod's own code; perk
registration itself is engine behaviour and not tested.

The metallurgy sections read `AC_Items.txt`, `AC_Recipes.txt`, `Recipes.json`
and `ItemName.json` from disk with a small parser written for the blocks this
mod uses. They prove what the files contain and that the numbers conserve
metal. The `CraftRecipe` script objects are mocked; that the game loads the
recipes, shows them at a furnace and calls `OnCreate` is not tested.

The component sections add: the calibre model (complete definitions, items
declared, no calibre named in other Lua), case quality (pure roll, storage,
both effects against mocked recipe data), progression (levels per step, the
attached requirement), and for **every** calibre the complete chain on a
mirrored inventory: exactly 100 rounds from the ingots, scrap, caps and
fertilizer its definition implies, with nothing left over, plus fifteen ore
run through every recipe to 100 rounds of 9mm with metal unchanged. Further
sections pin the calibre matrix, check primer-family parity, prove that no
component or die set of one calibre can be used by another (in the mirror,
in the generated script text and on an executed inventory), and simulate a
career from the first ore through pistols and shells and on to rifles,
printing the ore needed for each level, when the first shell and the first
rifle round are made, and the share of XP by family of work. Tampered recipes
(two rounds out, no case, no primer, no bullet, no powder, an undeclared
source, a jar from one dismantled round) must be rejected by the conservation
check; that is how the alloy-parts flaw in an earlier version of the check
was found.

Later sections: whole-chain random crafting (about 44,000 valid crafts from
ore to rounds over eight seeds, every recipe run at least once, one ledger
per material checked after every craft), the generated tables (balance,
economy, loot, recycling and the README's calibre table equal the rendering
of the model), the prepared press recipes (same material, same die set, 60 %
of the time, absent from the live list), component inspection against items
whose ModData refuses every write, and startup cost (which events the mod
listens to, and that no menu, action or callback validates the model or
rebuilds a recipe list).

Added on 2026-10-02:

- **Economy**: six canonical batches and a mixed loadout from ore, checked
  against a mirror-inventory run, with outlier bounds.
- **Save data**: the schema against a scan of the source, everything the
  mod writes against the schema, and the fuzz (28,130 calls on damaged
  data).
- **Brass recycling**: the loss, the zero XP, the round trip until the
  brass is gone, the bound on what a stock of brass can ever earn, and the
  validator's refusals.
- **Die-set loot**: the model against `tests/vanilla_snapshot.lua` (which
  lists the game uses), the pinned weights, registration against a mocked
  `ProceduralDistributions`, idempotence, dead and missing lists.
- **Ammo boxes**: the snapshot of vanilla's box recipes against the calibre
  model, and that the mod has no box item, box recipe or `base:ammo` item.

`tests/vanilla_snapshot.lua` is generated by `tests/snapshot_vanilla.lua
"<install dir>"` from the installed game. The suite reads the snapshot, not
the install, so it runs anywhere; re-run the generator after a game
update (`tools/pz_compat.py --update` does it, see below).

### Tile sheets: `tools/build_tiles.py`

```text
python tools/build_tiles.py --selftest
python tools/build_tiles.py --verify --install "<Project Zomboid install>"
python tools/build_tiles.py art/reloading_press/tiles.json
```

Reads and writes the game's `.tiles` and `.pack` formats and builds a tile
sheet from PNGs and a JSON description. `--verify` writes vanilla's own
files back byte for byte; `--selftest` (needs Pillow) builds a sheet and
compares it pixel for pixel. It writes into the description's `build/`
folder and never into `mod/`. Used for the prepared reloading press
(`RELOADING_PRESS_DESIGN.md` 7.2).

### After a game update: `tools/pz_compat.py`

```text
python tools/pz_compat.py --install "<Project Zomboid install>"
python tools/pz_compat.py --install "<install>" --update
python tools/test_pz_compat.py
```

The first compares the installed game with what the mod relies on and
prints one line per finding: `PASS`, `WARNING` (a fact moved, or could not
be checked) or `BREAKING` (something the mod uses is gone or no longer
fits). Exit code 0, 1 or 2. The install can also come from the `PZ_INSTALL`
environment variable; `javap` from `--javap`, `JAVA_HOME` or `PATH`.

What it compares is **not a list kept by hand**. `tools/mod_facts.lua` asks
the loaded mod what it names (every item, tag, station tag and timed action
of every recipe, the calibres, the loot lists, the analyzer's tile, the
sounds), and a scan of the mod's Lua finds every global, `Table.member`,
event and `receiver:method(arguments)` it reaches for. A new calibre or
recipe is covered without touching the tool. The one table kept by hand is
the list of Java classes behind the objects the mod talks to (a Lua call
does not say what class its receiver has).

| Checked | From | BREAKING when |
|---|---|---|
| Vanilla items the mod names | item scripts | one does not exist |
| Drainable use counts (gunpowder 10, matches 10, a matchbox 50, fertilizer 8) | `UseDelta` | a count differs from the material model |
| Item tags of recipe lines | item scripts | no vanilla item carries the tag |
| Station tags | entity `CraftBench` scripts, vanilla recipes | nothing provides the tag |
| Timed actions | `timedactions.txt` | one a recipe names is gone |
| The engine's ammo types | jar, `AmmoType` and `ItemKey` | a type no longer names the round the mod makes |
| A firearm or magazine for every round | item scripts | none takes the calibre's ammo type |
| The analyzer's tile | tile definitions, entity scripts | undefined, or claimed by an entity |
| Icons, models, display categories, item types and tags the mod's items borrow | item and model scripts | (WARNING) one is used by no vanilla item or model script any more |
| Events the mod listens to | jar, `LuaEventManager` | not registered |
| Globals and `Table.member` | jar (`@LuaMethod` names, exposed classes), vanilla Lua (with `derive` parents) | neither defines it |
| Calls of Java globals and static methods | jar | no overload takes that many arguments |
| `receiver:method(n arguments)` | jar, the listed classes and their exposed ancestors | no class has the method, none takes that count, or a class that had it on the recorded build lost it |

WARNING, among others: the game version changed; a vanilla recipe the
conservation model or the box check refers to changed its body (recorded as
a digest); a firearm changed its magazine, ammo type or chamber flags; a
vanilla function or `HandWeapon` method the firearm designs rely on is gone
(`SPENT_CASE_RESEARCH.md`, `AMMO_QUALITY_RUNTIME_DESIGN.md`: nothing shipped
calls them); the press's bench tag came into use by vanilla; the loot or
box snapshot differs from the install.

`--update` rewrites `tests/engine_snapshot.lua` and
`tests/vanilla_snapshot.lua` from the install. Run the suite afterwards: it
reads the snapshots.

`tools/test_pz_compat.py` needs no install. It damages the recorded
snapshot the way an update could (an item gone, a jar of twelve uses, a
method with another argument count, the tile claimed by an entity, a new
version) and requires the verdict to change, and it checks the Lua scanner
on source written in this mod's style. A drift detector that always says
PASS would be worse than none.

**The mock uses the same snapshot.** `tests/mock_pz.lua` wraps every mocked
engine object, Java global and static method with the recorded overloads
and refuses a call the engine would refuse, by Kahlua's own rules (read
from `LuaJavaInvoker.prepareCall` in the jar): too few arguments, too many
for a method with a receiver, a string where an object is wanted (the
`hasTag("Shovel")` failure), nil for a primitive. The section *Mock
fidelity* then asserts that no call in the whole run was refused except the
ones provoked on purpose, that the mock has no method the real class lacks,
and that every vanilla item, use count, sprite and recipe the mock claims
is in the installed scripts. A mocked object is still a Lua table: its
Java class is not checked, and nothing here says what a method does.

**Mutation run, now in the repository.** `python tests/run_mutants.py`
applies each fault of its list to the real file, runs the suite in a fresh
Lua state, restores the file and reports any fault the suite did not notice.
`check` only verifies that every fault still applies. See the header of the
file; it must not run while anything else reads the repository.

On 2026-10-02 the list held 98 faults: recycling that returns all the brass
or grants XP, die sets in an unused or the wrong list or ten times as
likely, a press that saves material, drops its die set or is switched on, a
box that is a carton, save-data readers that trust a stored 900 or NaN, a
refilled damaged kit, debug lines in a normal game, a duplicate recipe or
item id, a hand-edited script, a tampered snapshot, and the faults of the
earlier run (charges, primers, cups, yields, levels, XP, kept tools). The
first run killed 93. The five survivors were real gaps (the per-list loot
cap was not pinned, a damaged kit could be refilled instead of emptied, a
damaged true grade could be stored as a NaN range that only the display
hid, `set()`'s clamp was untested, the English translation of one line was
only checked through its fallback); each got an assertion, and all 98 are
now killed.

**The first source-level mutation run.** On 2026-10-02, 59 single changes were applied
one at a time to the real mod files (the calibre model, the materials module,
the compatibility check, the debug and inspection code, the generated script,
the item script and the translation files), the whole suite was run for each,
and the file was restored: an extra round or bullet or primer per craft, a
smaller charge, another calibre's case or bullet, any or the wrong primer
family, a consumed die set or hammer, XP granted twice, changed cups or
sheets or alloy yields, a mis-mapped vanilla round or ammo type, a removed
compatibility probe, a hand-edited script, a kept or missing wad, a shell
with a rifle primer, a double powder yield, changed levels and XP values, the
press switched on or keeping its hammer or dropping its die set, a debug menu
shown in normal play, an inspection that writes to its item, a missing name,
a removed or duplicated item, an unclamped round quality, a ten-fold mining
XP, a compatibility summary that counts an incomplete calibre as complete.
Every one made the suite fail: 52 with failed assertions in a complete run,
7 with failed assertions followed by the suite stopping on a Lua error. One
further change turned out to leave the behaviour identical and was replaced.
The run is not part of the repository; it is a loop over `(file, old text,
new text)` around the suite.

Static checks worth running after a change (no game needed): the suite, a
`loadfile` on every `.lua`, `tests/write_recipes.lua` followed by `git diff`
(an unexpected diff means the script and the mirror had drifted), and a look
for a script field or tag that is not in the tests' whitelists.

## Item and recipe audit (2026-10-02, second pass)

A static pass over the item script, the recipe script, the three translation
files, every Lua file and the installed game's item scripts.

### Recipes

<!-- RECIPE AUDIT TABLE: generated by tests/write_recipes.lua from AC_Materials.RECIPES. Do not edit. -->

| Family | Recipes | Station tags | Ammo Making level | XP per craft | Time | Kept tools | Consumed lines | Output lines |
|---|---|---|---|---|---|---|---|---|
| Metallurgy (ore to brass) | 4 | `PrimitiveFurnace`, `Furnace` | 0 | 3 to 25 | 200 | 0 to 3 | 2 to 3 | 1 |
| Case stock (sheets, cups) | 2 | `PrimitiveForge`, `AnySurfaceCraft` | 0 | 1 to 5 | 100 to 200 | 2 | 1 to 2 | 1 |
| Gunpowder | 1 | `AnySurfaceCraft` | 3 | 5 | 150 | 1 | 2 | 1 |
| Primers | 8 | `AnySurfaceCraft` | 2 to 4 | 2 to 3 | 120 to 150 | 2 | 2 | 1 |
| Die sets | 9 | `Forge` | 1 to 3 | 10 | 300 to 400 | 3 | 2 | 1 |
| Cases and hulls | 9 | `AnySurfaceCraft` | 1 to 3 | 1 to 3 | 80 to 160 | 2 | 1 | 1 |
| Bullets and shot | 9 | `AnySurfaceCraft` | 2 to 4 | 1 | 80 to 120 | 2 | 1 | 1 |
| Assembly | 9 | `AnySurfaceCraft` | 3 to 5 | 2 to 5 | 40 to 80 | 1 | 4 to 5 | 1 |
| Scrapping brass | 3 | `AnySurfaceCraft` | 0 | 0 | 100 | 1 | 1 | 1 |
| Recasting brass scrap | 1 | `Furnace` | 0 | 0 | 200 | 3 | 2 | 1 |
| **All** | **55** | | | | | | | |

<!-- END RECIPE AUDIT TABLE -->

Checked for each of the 55, by name, in the section *Station recipes*:

| Property | What the suite asserts |
|---|---|
| Script and mirror | every mirror recipe has a script block and every block a mirror recipe; the script body equals the rendering of the mirror; no duplicate id |
| Inputs | count, items or tags, flags, per line, script against mirror; every item named by id exists and is probed at game start; only vanilla tags and flags seen in the template recipes |
| Keep and destroy | a kept line is `mode:keep` in both; every tool named by tag and every die set is kept; `mode:destroy` only on the wad line |
| Outputs | count and item, script against mirror; the item exists |
| Skill gate | no `SkillRequired` line (the engine would drop it); the level in the mirror is what `applySkillRequirements` attaches |
| XP callback | the `OnCreate` target exists, grants once, and grants the mirror's amount (0 for recycling) |
| Time | at least 20, so the engine's skill speed-up applies |
| Station | a vanilla bench tag; furnace recipes have no timed action, like vanilla's |
| Translation | a name in `Recipes.json`, and no name without a recipe |
| Dependency | every item in a recipe is in `AC_Compat.REQUIRED_ITEMS` |
| Material accounting | every output has a material declaration (or the recipe is a declared tool recipe); every consumed item is tracked or a known untracked input; conservation per material; a loss where one is required |

### Items

41 items, no duplicate id. **Automated since 2026-10-02** (section *Item
audit* of the suite, against `tests/engine_snapshot.lua`, which
`tools/pz_compat.py` writes from the installed scripts); before that a
one-off script compared each with the installed game:

- every `Icon` is one a vanilla item uses, every `StaticModel` and
  `WorldStaticModel` a vanilla model, every tag (`base:hasmetal`,
  `base:heavyitem`, `base:ingot`) and `DisplayCategory` (`Ammo`, `Material`,
  `Tool`) vanilla's; every item is `ItemType = base:normal` with a positive
  weight and a name in `ItemName.json` equal to its `DisplayName`;
- 36 are in recipes; the sample, the two kits and the analyzer are handled
  by the geology code; `AmmoMaking.TestCartridge` by the quality prototype;
- none is referenced only by tests, and none is in no recipe and no Lua;
- every item is probed at game start except the prototype cartridge;
- every item has a source in normal play (a recipe, loot, digging or
  mining) except exactly four: the two kits, the analyzer and the test
  cartridge;
- the five items of the geology stage name no `WorldStaticModel`; the 36
  of the later stages all do.

Known and intended:

- The **assay kits and the analyzer** are created by nothing but the debug
  menu (no recipe, no loot). The README lists it as a limitation.
- The **test cartridge** is created by no mod code at all; it comes from the
  game's own debug item list. It is the only carrier of the multi-quality
  prototype (`AmmoInspection.inspect`, `AmmoQuality.*`, the debug presets
  and some 35 translation keys). Kept: it is the worked example for the
  quality stage, and marked as a prototype everywhere.
- **Weights.** A round's case, projectile and primer together weigh no more
  than the vanilla round (asserted against the snapshot). Three bullets
  were too heavy for that and were corrected in this pass.

### Translations

`IG_UI.json`, 163 keys: none dead. Ten perk level descriptions are read by
the engine, two metal names are built as `"IGUI_AmmoMaking_Metal_" .. name`.
Two keys named in Lua are deliberately absent (`ContextMenu_Dig` is
vanilla's; `IGUI_perks_AmmoMaking_Description1` is a probe of the other
spelling).

### Code

- **Functions the mod never calls:** `AmmoMakingSkill.hasLevel` (kept: a
  two-line helper on the in-game-confirmed skill module);
  `AC_Calibres.get`, `AC_LaboratoryAnalyzer.getState`,
  `AC_Loot.chancePerContainer` and `AC_Recycling.getRecovery` (used by the
  tests and the document generators); `AC_SaveData.check` and
  `getStructure` (tests, and `-debug` inspection). Eleven more are reachable
  only through the debug menu, as intended.
- **Dead state, left in place:** `labProcessing` is only ever written
  `false`, so the four places that test it for `true` never fire. They are
  on the sampling and analyzer code that was seen working in game, and a
  save could in principle carry `true`; the schema records it.
  `blends_street_` in `AC_Geology.isSurveyableSquare` is a named case that
  returns what the fall-through returns; it documents the intent.
- **Removed in this pass:** three item-id keys nothing read
  (`AC_Geology.ITEMS.CopperIngot`, `.ZincIngot`,
  `AC_GeologySampling.ITEMS.LaboratoryAnalyzer`); seven stale comments (the
  pickaxe animation, the die-set item list, the tool bonus, `labReadyAt`,
  the inspection title, the item table, the compatibility check's "once per
  game start").
- No debug helper is reachable in normal play: the debug tree, the quality
  presets, the level menu and the debug lines of an inspection are behind
  `isDebugEnabled()`, and a mutation that removes a gate fails the suite.

### Per-interaction cost

Every event the mod listens to: `OnInitGlobalModData` (2),
`OnGameBoot` (1), `OnGameStart` (2), `OnPreDistributionMerge` (1), and five
context-menu fills. Nothing per frame, tick or minute.

| Path | Finding | Action |
|---|---|---|
| Inventory right-click, any item | type compares only: no scan, no table, no print | none needed |
| World right-click, any square | finding an analyzer among the clicked objects is the only work before the first early-out | none needed |
| World right-click on natural ground | the mining menu scanned the whole inventory for samples **once per metal** | **fixed**: one scan, handed to both lookups |
| Right-click on a factory round | `getModData()` made the engine create an empty table on a vanilla item | **fixed**: `hasModData()` is asked first |
| An open result panel | two panels translated their constant strings **every frame** | **fixed**: looked up once per panel |
| Any menu, action or callback | none calls model validation, recipe building, loot, recycling or the schema check | pinned by the *Startup cost* test |
| Game start | the calibre recipes are built four times across `AC_Materials`, `AC_Compat` and the press validation; the distribution table is walked once per world load | left: once per load |
| Any read of the depletion store | since the version check was added, one number comparison per read (`AC_SaveData.upgrade` returns at once for a current layout and consults no step) | none needed; pinned by a test |
| Mining action | `isValid()` looks the prospect sample up again on each call, a recursive inventory scan | **left**: the action was seen working in game, the lookup is what notices a sample being dropped, and the cost lasts as long as one mining action. Worth revisiting with the game's profiler |
| Right-click on an analyzer | its state is brought up to date three times for one menu | **left**: analyzer clicks only, on code seen working in game |

The compatibility check used to run once per Lua session; the Lua state
survives a return to the main menu, so a second save loaded in the same
session got none. It now resets on `OnInitGlobalModData`.

## REQUIRES IN-GAME VERIFICATION

- **Mining depletion persistence after save/reload** (extracted counts in
  global ModData).
- **Laboratory analyzer processing persistence after save/reload** (state on
  the placed object's ModData).
- `Base.CopperOre` being created and dropped (only zinc ore has been seen in
  game so far), and `Base.PickAxeForged` (the 42.20.4 test used a pickaxe;
  which id was not recorded). The compatibility check reports the ids at
  startup.
- Picking the dropped ore up. That it appears on the ground is confirmed for
  zinc.
- The single mining result message and the `Mining: +5 Ammo Making XP (total
  a -> b)` log line, added after the 42.20.4 test.
- Water detection: `IsoGridSquare:hasWater()` only. Its presence is confirmed on
  42.20.4 by the compatibility check; that it returns true on lake and river
  tiles still needs a look in game. The old `square:Is(IsoFlagType.water)`
  fallback was removed: `Is()` does not exist on 42.20.4 (vanilla now uses
  `square:has(IsoFlagType...)`), and calling it raised "Tried to call nil" on
  every land tile.
- Player-built floors on grass: whether `square:getFloor()` returns the built
  floor or the original grass.
- The `Shoveling` sound with a pickaxe. (Mining starting, completing and the
  `DigPickAxe` animation are confirmed on 42.20.4.)
- Shovel detection uses only `Base.Shovel`, `Base.Shovel2` and
  `Base.HandShovel`; `Base.Shovel` is confirmed on 42.20.4, the other two are
  not. Other vanilla digging tools (`EntrenchingTool`,
  `SpadeForged`, `SpadeWood`) are not accepted; vanilla's own check is
  `item:hasTag(ItemTag.DIG_GRAVE)` in `client/Mining/DiggingUtil.lua` if they
  should be.
- Whether the JSON translation file is loaded and which perk-description key
  spelling the skill panel uses.
- The placed laboratory analyzer (see *Next in-game test: placed analyzer*):
  the placement cursor (ghost sprite, walking,
  placement time), the `industry_03_61` object appearing and blocking the tile,
  its ModData surviving save/reload and leaving/re-entering the area, pickup
  removing the object and giving exactly one item, Pick Up disabled while
  processing or ready, cancel returning the sample.
- Grid power through `IsoGridSquare:hasGridPower()` inside a building, and
  generator power, for both placed and dropped analyzers; processing pausing
  without power and resuming with it.
- The debug tools Inspect Analyzer State and Complete Analyzer Job.
- A dropped analyzer from an older save still working, and one picked up
  mid-assay keeping its sample when placed.
- **Metallurgy** (nothing in it has run in game):
  - the four recipes appear at the right furnace (Smelt Zinc Ore at a
    Primitive Furnace, the three casting recipes at a Simple Furnace) with
    their names from `Recipes.json`;
  - inputs are consumed, crucible / tongs / mold are kept, a clay mold
    breaks, and the outputs are 10 zinc scrap, 1 ingot, 10 `Base.BrassIngot`;
  - the `Crafting (...)` XP line appears once per craft, also in a batch;
  - the boot line reports 55 recipes given the requirement, the UI shows Ammo
    Making 0, and a higher level shortens the craft;
  - zinc item names, icons and world models; carrying the 40-weight zinc ore;
  - every metallurgy line of the compatibility check is OK.
- **Ammunition components** (nothing in it has run in game): the list in
  `docs/AMMUNITION_DESIGN.md` §13: one round per assembly craft, drainable
  inputs taking uses, kept tools, level gates, quality on cases and rounds,
  ModData persistence, a handloaded round firing like a vanilla one.
- **12 gauge shells**: `docs/SHOTGUN_AMMUNITION_RESEARCH.md` §6 (the
  `mode:destroy` wad line, one shell per craft, boxing, the shells bandolier,
  nine pellets).
- **Component inspection**: *Inspect Ammunition* appears on an empty case and
  on a loose handloaded round and on nothing else; the window opens; a stack
  of cases shows the first one's quality.
- **The compatibility output**: a normal start prints the three class lines
  and the totals and no `OK:` line; `-debug` prints them all.
- **The debug tree**: nested submenus open and every leaf acts.
- **The reloading press**: everything in `docs/RELOADING_PRESS_DESIGN.md` §9;
  nothing of it is in the game yet.
- **Die-set loot** (`LOOT_AND_RECYCLING.md` 5): the line `[AmmoMaking] Die
  set loot: 22 entries added, …` at world load and `OK: die set loot (22
  entries in 4 lists)` in the check; a die set actually found in a gun-store
  display case, a garage gun locker or a hunter's things; the feel of the
  weights against the sandbox loot settings; the same on a dedicated server.
- **Brass recycling**: the three scrapping recipes at a surface and the
  recast at a furnace; a mixed input line filled from several components
  (the debug Recycling Kit is built for exactly that); no XP line for any of
  the four.
- **Ammo boxes**: vanilla's *place ammo in box* offered for handloaded
  rounds, and for a stack mixing them with factory rounds.
- **Save-data repairs**: nothing new to see in a healthy save; a kit, an
  analyzer or a sample with hand-damaged values should read as documented
  and never raise.
- **Inspection in `-debug`**: the three `[debug]` lines under an inspected
  case or round, and none of them in a normal game.
- **The compatibility check on a second save** loaded in the same session:
  it should print its summary again.
- **Per-interaction cost**: the mining action's per-tick sample lookup and
  the analyzer menu's repeated state update were left as they are; whether
  either shows in the game's profiler is unknown.
- **Spent cases and a quality carrier** are not built; what would have to be
  seen first is in `SPENT_CASE_RESEARCH.md` 6 and
  `AMMO_QUALITY_RUNTIME_DESIGN.md` 6.
- **Case stock** (nothing in it has run in game): Forge Small Brass Sheets
  at a forge gives 10 sheets from one ingot and keeps hammer and tongs; Punch
  Brass Case Cups in the crafting menu at a surface gives 2 cups per sheet and
  keeps punch and hammer; the hammering animations; names, icons and models.

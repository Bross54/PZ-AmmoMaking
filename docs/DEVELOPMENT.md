# Development notes

Target: Project Zomboid Build 42.20 Stable. Everything in this file can be
checked without the game unless it is marked **REQUIRES IN-GAME VERIFICATION**.

## Module map

| File | Layer | Responsibility |
|---|---|---|
| `shared/AC_Text.lua` | shared | `AC_Text.get(key, fallback, ...)`: translation lookup with an English fallback so a missing key never reaches the screen |
| `shared/AC_WorldData.lua` | shared | Save identity and the per-save geology / copper / zinc seeds; cache reset on `OnInitGlobalModData` |
| `shared/AC_Geology.lua` | shared | Deterministic noise, concentration, grades, 3x3 survey, terrain rules (`isSurveyableSquare`, `isWaterSquare`) |
| `shared/AC_GeologySampling.lua` | shared | Sample items, shovel checks, field / advanced assays, kit uses, result lines |
| `shared/AC_LaboratoryAnalyzer.lua` | shared | Laboratory analyzer rules for placed and dropped analyzers: state machine, timing, power, sample storage, cancel, pick-up rule, state repair |
| `server/BuildingObjects/AC_LaboratoryAnalyzerObject.lua` | server | `ISBuildingObject` placement cursor; `create()` turns the analyzer item into an `IsoThumpable` |
| `shared/AC_Deposits.lua` | shared | Per-tile reserves derived from geology, depletion records in global ModData |
| `shared/AC_Mining.lua` | shared | Pickaxe rules, prospect lookup, `extract()` (the only mutation point of the mining loop) |
| `shared/AC_Compat.lua` | shared | Startup compatibility self-check |
| `shared/AC_AmmoMakingSkill.lua` | shared | Perk registration, XP helpers |
| `shared/AC_AmmoQuality.lua`, `shared/AC_AmmoInspection.lua` | shared | Ammunition quality prototype |
| `client/AC_GeologySamplingContextMenu.lua` | client | Dig / assay / laboratory menus (place, start, cancel, collect, pick up) |
| `client/AC_DigGeologicalSampleAction.lua` | client | Shovel timed action |
| `client/AC_PickUpAnalyzerAction.lua` | client | Timed action that picks a placed analyzer up again |
| `client/AC_MiningContextMenu.lua` | client | Mining options and tooltips |
| `client/AC_MineOreAction.lua` | client | Pickaxe timed action |
| `client/AC_GeologyAssayUI.lua`, `client/AC_AmmoInspectionUI.lua` | client | Result panels |
| `client/AC_GeologyDebug.lua` | client | "Ammo Making Debug" submenu (`-debug` only) |
| `client/AC_AmmoContextMenu.lua` | client | Ammunition inspection and debug presets |

Load order is alphabetical within `shared/`, `client/` and `server/`. Modules
only reference each other from inside functions, so the order does not matter at
load time. The placement cursor lives in `server/BuildingObjects/` like every
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
  labelled exhausted only after someone has worked it.

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

Placeholders that still need the game: the pickaxe action uses
`BuildingHelper.getShovelAnim` (pcall-guarded, falls back to `DigShovel`) and the
`Shoveling` sound. **REQUIRES IN-GAME VERIFICATION.**

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
  next looked at, using the power state at that moment. Continuous power
  tracking would need a global object system (as vanilla uses for traps and
  farming) and is out of scope.
- **Multiplayer**: placing and picking up are disabled on clients
  (`isPlacementAvailable()`): Build 42 runs `create()` on the server, and a
  client-side pickup would add the item only locally. Starting, cancelling
  and collecting also change client-local state today; sample ownership and
  server-side validation belong to a future multiplayer design.

Build 42 evidence, checked against the installed 42.20.2 Lua and jar:

| Assumption | Evidence |
|---|---|
| `ISBuildingObject` fields used (`noNeedHammer`, `dragNilAfterPlace`, `ignoreNorth`, `maxTime`, `player`, `character`) and base `isValid()` → `buildUtil.canBePlace` | CONFIRMED: `server/BuildingObjects/ISBuildingObject.lua`, `ISBuildUtil.lua` |
| `ISBuildAction:perform()` calls `create()` only when not a multiplayer client, and subtracts 50 ticks for Handy | CONFIRMED: `client/BuildingObjects/TimedActions/ISBuildAction.lua` |
| `IsoThumpable.new(cell, square, sprite, north, self)`, `AddSpecialObject`, `transmitCompleteItemToClients`, item removed after the object exists | CONFIRMED pattern: `TrapBO`, `ISSimpleFurniture` |
| Removal with `transmitRemoveItemFromSquare` then `RemoveTileObject` | CONFIRMED pattern: `ISAddTakeDispenserBottle:complete()` |
| `hasModData()`, `getObjectIndex() == -1`, `hasGridPower()` | CONFIRMED: vanilla Lua usage, method names present in the jar |
| `industry_03_61` exists and is not a vanilla moveable | CONFIRMED: `media/newtiledefinitions.tiles.txt` has no `IsMoveAble`, so vanilla furniture pickup cannot grab the analyzer |
| `getSprite(name)` returns nil for an unknown tile | STRONG INDICATION: vanilla TileGeometryEditor relies on it |
| The placed object keeps its ModData through save/reload and chunk unload | **REQUIRES IN-GAME VERIFICATION** |

The placed analyzer was first written locally and never pushed. It was recovered
from `recovery/local-pre-claude` (commit `18d22b3`) and ported by hand. That
branch's `AC_GeologySamplingContextMenu.lua` and `AC_LaboratoryAnalyzer.lua` were
not restored: they predate localization, laboratory XP and the shared terrain
rule, and the menu calls the removed `AC_GeologySampling.updateLaboratoryAssay`.
Its `AC_SpriteInspector.lua` became a debug submenu entry.

## Compatibility self-check

`AC_Compat.run()` executes once on `OnGameStart` and prints one line per
assumption: `[AmmoMaking] OK: …`, `WARNING: …` or `UNVERIFIED: …`, followed by a
summary. It probes item scripts, the item factory, global ModData, the square
and character methods the actions call, client globals, whether the translation
file loaded (and which perk-description key spelling resolves) and the geology
seed, and what the placed laboratory analyzer relies on (square and character
methods, `ISBuildingObject`, `IsoThumpable.new`, that the `server/` cursor file
loaded, and that the world sprite exists). It never changes game state and
cannot raise. The debug menu can re-run it.

## Debug tools (`-debug` only)

Right-click the ground → **Ammo Making Debug**: Inspect Current Tile, Survey
Current Area (3x3), Show Geology Seed, Inspect Clicked Tile Objects (sprites,
analyzer state), Reset Depletion (tile / 3x3), Spawn Sampling Kit, Spawn Mining
Kit, Spawn Laboratory Analyzer, Spawn Assayed Sample (current 3x3), Set Ammo
Making Level, Run Compatibility Check. Everything prints to `console.txt`. From
the Lua console: `AC_GeologyDebug.tile(getPlayer())`.

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
`arg = { [0] = "<repo>/tests/run_tests.lua" }` set before `dofile`.

## REQUIRES IN-GAME VERIFICATION

- Vanilla item ids `Base.CopperOre`, `Base.PickAxe`, `Base.PickAxeForged`
  (the compatibility check reports them at startup).
- `instanceItem` vs `InventoryItemFactory.CreateItem` on 42.20 (either works).
- `IsoGridSquare:AddWorldInventoryItem` placing the ore where the player can see
  and pick it up.
- Water detection: `IsoGridSquare:hasWater()` or `Is(IsoFlagType.water)`.
- Player-built floors on grass: whether `square:getFloor()` returns the built
  floor or the original grass.
- The shovel animation and `Shoveling` sound with a pickaxe.
- Whether the JSON translation file is loaded and which perk-description key
  spelling the skill panel uses.
- The placed laboratory analyzer: the placement cursor (ghost sprite, walking,
  placement time), the `industry_03_61` object appearing and blocking the tile,
  its ModData surviving save/reload and leaving/re-entering the area, pickup
  removing the object and giving exactly one item, Pick Up disabled while
  processing or ready, cancel returning the sample.
- Grid power through `IsoGridSquare:hasGridPower()` inside a building, and
  generator power, for both placed and dropped analyzers.
- A dropped analyzer from an older save still working, and one picked up
  mid-assay keeping its sample when placed.

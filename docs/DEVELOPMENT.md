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
| `shared/AC_LaboratoryAnalyzer.lua` | shared | Placeable powered analyzer: state machine, timing, sample storage |
| `shared/AC_Deposits.lua` | shared | Per-tile reserves derived from geology, depletion records in global ModData |
| `shared/AC_Mining.lua` | shared | Pickaxe rules, prospect lookup, `extract()` (the only mutation point of the mining loop) |
| `shared/AC_Compat.lua` | shared | Startup compatibility self-check |
| `shared/AC_AmmoMakingSkill.lua` | shared | Perk registration, XP helpers |
| `shared/AC_AmmoQuality.lua`, `shared/AC_AmmoInspection.lua` | shared | Ammunition quality prototype |
| `client/AC_GeologySamplingContextMenu.lua` | client | Dig / assay / laboratory menus |
| `client/AC_DigGeologicalSampleAction.lua` | client | Shovel timed action |
| `client/AC_MiningContextMenu.lua` | client | Mining options and tooltips |
| `client/AC_MineOreAction.lua` | client | Pickaxe timed action |
| `client/AC_GeologyAssayUI.lua`, `client/AC_AmmoInspectionUI.lua` | client | Result panels |
| `client/AC_GeologyDebug.lua` | client | "Ammo Making Debug" submenu (`-debug` only) |
| `client/AC_AmmoContextMenu.lua` | client | Ammunition inspection and debug presets |

Load order is alphabetical within `shared/` then `client/`. Modules only reference
each other from inside functions, so the order does not matter at load time.

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

## Compatibility self-check

`AC_Compat.run()` executes once on `OnGameStart` and prints one line per
assumption: `[AmmoMaking] OK: …`, `WARNING: …` or `UNVERIFIED: …`, followed by a
summary. It probes item scripts, the item factory, global ModData, the square
and character methods the actions call, client globals, whether the translation
file loaded (and which perk-description key spelling resolves) and the geology
seed. It never changes game state and cannot raise. The debug menu can re-run it.

## Debug tools (`-debug` only)

Right-click the ground → **Ammo Making Debug**: Inspect Current Tile, Survey
Current Area (3x3), Show Geology Seed, Reset Depletion (tile / 3x3), Spawn
Sampling Kit, Spawn Mining Kit, Spawn Laboratory Analyzer, Spawn Assayed Sample
(current 3x3), Set Ammo Making Level, Run Compatibility Check. Everything prints
to `console.txt`. From the Lua console: `AC_GeologyDebug.tile(getPlayer())`.

## Offline tests

```text
lua5.1 tests/run_tests.lua
```

`tests/mock_pz.lua` mocks the Project Zomboid API; `tests/run_tests.lua` loads
every mod file in the game's order and runs the checks. The suite proves Lua
logic only.

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
- The laboratory analyzer as a dropped world item: power detection, state kept
  when picked up and placed again.

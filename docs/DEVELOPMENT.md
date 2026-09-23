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
| `shared/AC_Compat.lua` | shared | Startup compatibility self-check |
| `shared/AC_AmmoMakingSkill.lua` | shared | Perk registration, XP helpers; `awardXP()` logs every mining and laboratory grant |
| `shared/AC_AmmoQuality.lua`, `shared/AC_AmmoInspection.lua` | shared | Ammunition quality prototype |
| `client/AC_GeologySamplingContextMenu.lua` | client | Dig / assay / laboratory menus (place, start, cancel, collect, pick up) |
| `client/AC_DigGeologicalSampleAction.lua` | client | Shovel timed action |
| `client/AC_PickUpAnalyzerAction.lua` | client | Timed action that picks a placed analyzer up again |
| `client/AC_MiningContextMenu.lua` | client | Mining options and tooltips |
| `client/AC_MineOreAction.lua` | client | Pickaxe timed action |
| `client/AC_GeologyAssayUI.lua`, `client/AC_AmmoInspectionUI.lua` | client | Result panels |
| `client/AC_GeologyDebug.lua` | client | "Ammo Making Debug" submenu (`-debug` only), including the analyzer inspect / complete tools |
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

Right-clicking a square that holds an Ammo Making analyzer (placed or dropped)
adds two more entries; they never appear for other squares:

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

# Balance options of the save

Status: **implemented in Lua and data, checked offline only.** That the
options arrive in the game and change what they say is
`REQUIRES FUTURE IN-GAME VERIFICATION` (section 5).

Four sandbox options on the **Ammo Making** page let a server owner change
the mod's balance without editing Lua. Each is a multiplier whose default is
**1**: a save that never touches them plays exactly as before, and at the
defaults no code path differs from the release without them (the loot tables
are not even read again, section 3).

Engine facts are marked **JAR** (`javap` of the 42.20.4
`projectzomboid.jar`), **FILE** (the installed `media/` files) or **CLUE**
(an installed Workshop mod: a hint, never proof).

## 1. The options

| Option (sandbox name) | Range | Default | Applied by | What it scales |
|---|---|---|---|---|
| `AmmoMaking.DepositReserveMultiplier` | 0.5 to 3 | 1 | the mod (`AC_Deposits`) | ore units per worked copper or zinc tile |
| `AmmoMaking.DieSetLootMultiplier` | 0 to 2 | 1 | the mod (`AC_Loot`) | the loot weight of every die set and bullet mould; 0 takes them out of loot |
| `AmmoMaking.ComponentLootMultiplier` | 0 to 2 | 1 | the mod (`AC_Loot`) | the loot weight of the gunpowder, loose primers, brass scrap and small brass sheets the mod adds; 0 takes them out |
| `MultiplierConfig.AmmoMaking` | 0 to 1000 | 1 | the engine | Ammo Making XP, when vanilla's global XP multiplier is switched off |

`AC_Balance.lua` holds the table and is the one reader. Every value is
checked there: a number outside the range is clamped to the nearest end, and
anything that is not a finite number (a word, `nil`, NaN, infinity, a broken
`SandboxVars` table) is no setting and gives 1. `AC_Balance.validate()`
refuses a default other than 1 and a range that cannot hold it, so the
"nothing changes by default" rule is enforced, not hoped for. The sandbox
file's ranges are the clamp's (a test compares them).

The spent-case add-on's `AmmoMaking.SpentCaseRecovery` (0 to 100, default
50) was already an option; it stays in the add-on, which owns the items it
counts (`docs/SPENT_CASE_RESEARCH.md`).

### 1.1 What is deliberately not an option

| Tunable | Why not |
|---|---|
| Recycling yield (half) | It is the inputs and outputs of the generated recipe scripts (`AC_Recipes.txt`), which the engine reads before any Lua runs; a sandbox value cannot change them. Only a lower yield is XP-safe (above about 58 % re-forming a 12 gauge hull out-earns loading it, `docs/LOOT_AND_RECYCLING.md` 2.4), and lowering it from Lua would mean destroying crafted outputs in `OnCreate` after the engine made them. Not worth a second, fragile path for a number that should not go up. |
| Press time advantage | It is the press add-on's recipe `time`, also script data. |
| Die-set rarity per tier, per list | One multiplier over the table keeps the tiers' order and the per-list design; the table stays in `AC_Loot.CONFIG`. |
| XP per recipe | Scaling all of it is what the XP multiplier does; changing one recipe's share would change the progression the tests pin. |
| Skill book loot | The books are `DisplayCategory = SkillBook`, so the game's own skill book loot setting already scales them with every vanilla book (`docs/LOOT_AND_RECYCLING.md` 1.4). A mod multiplier on top would count the same setting twice. |
| Skill book XP multipliers | They are vanilla's own (1.5 to 8, the Aiming and Reloading books'); a book's multiplier and this XP multiplier both apply, as for any vanilla skill (`docs/AMMUNITION_DESIGN.md` 9.2). |

## 2. Ore per deposit tile

`AC_Deposits.getReserveForConcentration` returns the grade's reserve
(`AC_Deposits.CONFIG.reserveByGrade`) times the multiplier, rounded to whole
ore. A workable grade never falls below one unit and trace or empty ground
stays at nothing, so the option changes how much a deposit holds and never
where deposits are.

| Grade | x0.5 | x1 | x1.5 | x3 |
|---|---|---|---|---|
| None, Trace | 0 | 0 | 0 | 0 |
| Poor | 1 | 1 | 2 | 3 |
| Moderate | 1 | 1 | 2 | 3 |
| Good | 1 | 2 | 3 | 6 |
| Rich | 2 | 3 | 5 | 9 |
| Very Rich | 2 | 4 | 6 | 12 |

The save stores what was **taken** from a tile, not what is left
(`AC_Deposits`, STORE LAYOUT), so changing the option in a running save
needs no migration: a tile worked out at x1 holds four more at x3, and a tile
partly worked at x3 is simply exhausted at x0.5 (never below nothing).

Why 0.5 to 3: below a half every grade from Poor to Good is one ore and the
grades stop meaning anything; above three a Very Rich tile is twelve 40-weight
chunks, more than a character can carry away, and the assay chain (which
exists to find the good tiles) stops mattering. XP is paid per ore and per
assay, never per tile, so the option changes walking, not the rate of XP.

## 3. Loot multipliers

### 3.1 When they can be read (JAR)

`IsoWorld.init` runs, in this order: `OnPreDistributionMerge`,
`OnDistributionMerge`, `OnPostDistributionMerge`, `OnInitWorld`,
`SandboxOptions.load()` (which reads the save's `map_sand.bin` and calls
`toLua()`), `ItemPickerJava.Parse()`, `ItemPickerJava.InitSandboxLootSettings()`,
… `OnLoadMapZones`, `OnLoadedMapZones`, … `WorldStreamer.create()` and the
first `CellLoader.LoadCellBinaryChunk`. So **at the pre-merge event, where the
mod inserts its entries, `SandboxVars` does not yet hold the save's options**:
on a save loaded from the main menu it holds whatever was last handed to Lua
(the main menu resets it to the defaults, FILE
`client/OptionScreens/MainScreen.lua` `setDefaultSandboxVars`). A CLUE agrees:
Plysken Solar Revolution (Workshop 3725311427) found its loot multiplier
inert in single player for this reason and moved to `OnLoadedMapZones` and
`ItemPickerJava.Parse()`.

### 3.2 What the mod does

1. `OnPreDistributionMerge` (unchanged): the entries go in at their table
   weights. Each (list, item) pair the mod itself inserts is recorded in
   `AC_Loot.owned`; an item that was already in a list (vanilla's or another
   mod's) is never recorded, so it is never rescaled or removed.
2. `OnLoadedMapZones`: the save's options are in Lua and no cell is loaded
   yet. `AC_Loot.applyMultipliers()` sets every owned entry to its table
   weight times its multiplier, takes it out at 0 (a weight of 0 is not
   "never": the engine adds the zombie-density bonus to every entry), and
   puts it back when it was taken out and is wanted again.
3. Only when that changed a weight does the mod call
   `ItemPickerJava.Parse()` (JAR: public static, the class is exposed to
   Lua; it clears the rooms, containers and procedural lists it parsed
   before and reads the Lua tables again). At the defaults nothing changed,
   nothing is parsed again, and the console says nothing.

The weights are set from the table each time, never multiplied in place, so
a second world in the same Lua state (load a save with x2, quit, load one
with x1) ends with the right weights.

### 3.3 What the maximum means, per room

`docs/LOOT_AND_RECYCLING.md` 1.2 judges die sets per room, because a
container is filled from one of the lists it names, chosen per room. At the
default the fullest room of twelve containers (`all.militarylocker`) holds
0.91 die sets on average and a gun store of eight display cases about one in
twelve; the tests cap every room of twelve at one.

The per-room figure is linear in the weight (a die set's chance per roll is
1 % or less, far from where `Rand.Next(10000)` saturates), so x2 doubles it:
the fullest room of twelve then holds at most **two** die sets on average and
a gun store about one in six. That is the ceiling the maximum was chosen for,
and `tests/suite_balance.lua` checks it by recomputing the per-room table
with the weights scaled, not by multiplying the default's result. Above it
die sets would be ordinary finds in the rooms that name the lists, and
forging them (the main path) would stop mattering. The sandbox's own
tool-loot setting scales die sets on top (they are `Tool` loot).

The bullet moulds of lead casting (`LOOT_AND_RECYCLING.md` 1.5) take the
same option: they are tools found beside the die sets. Their fullest room
of twelve containers holds 0.12 moulds at the default, 0.24 at x2
(`tests/suite_casting.lua`).

Components at x2 stay under 4 % per roll, under 2 % of their list's weight
and under 16 % of the containers filled from the list. Brass scrap is ten
units, a tenth of an ingot, and a loose primer is one round's primer: even
doubled, found stock tops up the chain and does not replace the mine and the
assay.

## 4. Ammo Making XP

JAR `IsoGameCharacter$XP.AddXP(Perk, float, boolean, boolean, boolean,
boolean)`: after the trait and skill-book factors, when
`SandboxOptions.multipliersConfig.xpMultiplierGlobalToggle` is on (the
default) the amount is multiplied by `MultiplierConfig.Global`; when it is
off, by the option named `"MultiplierConfig." + perk.getType()`
(`getOptionByName(...).asConfigOption().getValueAsString()`, parsed as a
float). JAR `PerkFactory$Perk.getType()` returns the perk itself and
`toString()` its id, so for this skill the name is
`MultiplierConfig.AmmoMaking`. JAR `SandboxOptions$MultiplierConfig` declares
that option for the vanilla skills only (0 to 1000, default 1), and there is
no null check between the lookup and its use.

So vanilla already has a per-skill multiplier, but not for a custom skill.
The mod declares `MultiplierConfig.AmmoMaking` (double, 0 to 1000, default 1,
the vanilla skills' range) in its sandbox file. JAR
`SandboxOptions.newCustomOption` builds a `DoubleSandboxOption` whose
constructor calls `addOption`, which is what `getOptionByName` reads. The
engine then scales Ammo Making exactly as it scales Carpentry: by the global
multiplier while the toggle is on, by this option when it is off. The mod
never multiplies XP itself (a test checks that the amount handed to `AddXP`
is unscaled), so the factor is never applied twice.

A side effect: without the option, a save with the global toggle switched
off would reach the lookup with no option of that name, and by the bytecode
the first Ammo Making XP award would raise a NullPointerException
(`REQUIRES FUTURE IN-GAME VERIFICATION`; it was never reported because the
toggle is on by default).

**XP safety at every value.** Every Ammo Making award is multiplied alike, so
the mod's XP rules, which are comparisons between amounts, hold for any
factor: recycling teaches 0 at any multiplier, and re-forming a scrapped case
never returns more XP than loading it (the 58 % argument scales on both
sides). The suite checks both at 0, 0.01, 1, 10 and 1000. At 0 nothing is
learnt and the levelled recipes stay locked, as with any vanilla skill set to
0.

## 5. Requires future in-game verification

- That the four options appear on the Ammo Making sandbox page with their
  labels, and arrive in `SandboxVars` (single player, and from a dedicated
  server's `servertest_SandboxVars.lua`).
- That `OnLoadedMapZones` fires on every world load (new game, loaded save,
  dedicated server) before any container is filled, and that the console line
  `[AmmoMaking] Loot multipliers: …` appears when a loot multiplier is not 1.
- That `ItemPickerJava.Parse()` called again from Lua leaves vanilla's loot
  intact (same items, same sandbox loot settings) and other mods' entries in
  place.
- That **containers already filled keep what they hold**: the multipliers act
  only on containers filled from then on, so changing them in a running save
  changes the rest of the map, not what was already generated.
- That with vanilla's global XP multiplier switched off, Ammo Making XP is
  scaled by `MultiplierConfig.AmmoMaking`, and with it on, by the global one.
- That changing the reserve multiplier mid-save shows at once in the mining
  menu and the debug tile info.

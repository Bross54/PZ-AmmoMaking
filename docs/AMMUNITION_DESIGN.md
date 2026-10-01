# Ammunition components: from brass to vanilla rounds

Status: **implemented on 2026-10-02, offline-verified only.** The first
complete chain (9 mm) and a second calibre (.38 Special) exist as recipes,
items, a calibre model, a case-quality module, probes, debug tools and tests.
Nothing in this document has been run in the game; what needs it is in §12.

Vanilla facts used here are in `docs/VANILLA_AMMUNITION_RESEARCH.md`, read
from the installed Build 42.20.4 files and jar.

## 1. Rules

- The product is the **vanilla round item** (`Base.Bullets9mm`,
  `Base.Bullets38`); vanilla firearms and magazines are untouched. One item
  is one cartridge, and a recipe output is not multiplied by the item's
  `count` field.
- **A genuine raw-material loop.** No recipe in the chain consumes finished
  ammunition. A test fails if one ever does.
- Vanilla items, stations, tools and recipe patterns first. No custom world
  object, no chemistry subsystem, no lead geology.
- Ammo Making is the only skill. It changes access, time and case quality,
  never the amount of material.
- A calibre is data. No Lua outside `AC_Calibres.lua` names one.

## 2. The 9 mm chain

```text
survey → sample → assay → mine → smelt → cast → brass          (earlier stages)

Base.BrassIngot ──Forge Small Brass Sheets──► 10 AmmoMaking.SmallBrassSheet
                                                   │                    │
                              Punch Brass Case Cups│                    │Make Small Pistol Primers
                                                   ▼                    │ + 10 toy caps, or 20 match uses
                                      2 AmmoMaking.BrassCaseCup         ▼
                                                   │          10 AmmoMaking.SmallPistolPrimer
                                   Form 9mm Case   │ (die set)          │
                                                   ▼                    │
                                        AmmoMaking.Case9mm ─────────────┤
                                        (quality rolled here)           │
Base.CopperScrap ──Swage 9mm Copper Bullets (die set)──► 2 Bullet9mm ───┤
                                                                        │
2 charcoal + 2 uses of Base.Fertilizer ──Mix Gunpowder (mortar)──►      │
                                     Base.GunPowder (10 uses) ──1 use───┤
                                                                        ▼
                                                    Assemble 9mm Round (die set)
                                                                        ▼
                                                             1 Base.Bullets9mm
```

The die set (`AmmoMaking.DieSet9mm`) is forged once from two
`Base.SteelBarQuarter` at a Simple Forge and kept by every 9 mm recipe.

## 3. Recipes

All in `media/scripts/AC_Recipes.txt`, generated from the Lua mirror (§9).
"Level" is the Ammo Making level attached to the recipe script at boot.

| Recipe | Consumed | Kept | Station | Output | Level | XP | time |
|---|---|---|---|---|---|---|---|
| `AmmoMaking_ForgeDieSet9mm` | 2 `Base.SteelBarQuarter`, 2 charcoal | ball-peen hammer, pliers/tongs, whetstone/file | `Forge` | 1 `AmmoMaking.DieSet9mm` | 1 | 10 | 300 |
| `AmmoMaking_FormCase9mm` | 1 `AmmoMaking.BrassCaseCup` | die set, hammer | `AnySurfaceCraft` | 1 `AmmoMaking.Case9mm` | 1 | 1 | 80 |
| `AmmoMaking_SwageBullets9mm` | 1 `Base.CopperScrap` | die set, hammer | `AnySurfaceCraft` | 2 `AmmoMaking.Bullet9mm` | 2 | 1 | 80 |
| `AmmoMaking_MakeSmallPistolPrimersFromCaps` | 1 `AmmoMaking.SmallBrassSheet`, 10 `Base.CapGunCap` | punch, hammer | `AnySurfaceCraft` | 10 `AmmoMaking.SmallPistolPrimer` | 2 | 2 | 120 |
| `AmmoMaking_MakeSmallPistolPrimersFromMatches` | 1 small brass sheet, 20 uses of `Base.Matches` / `Base.Matchbox` | punch, hammer | `AnySurfaceCraft` | 10 primers | 2 | 2 | 120 |
| `AmmoMaking_MixGunpowder` | 2 `tags[base:charcoal]`, 2 uses of `Base.Fertilizer` | mortar and pestle | `AnySurfaceCraft` | 1 `Base.GunPowder` (10 uses) | 3 | 5 | 150 |
| `AmmoMaking_AssembleRound9mm` | 1 case, 1 primer, 1 bullet, 1 use of `Base.GunPowder` | die set | `AnySurfaceCraft` | 1 `Base.Bullets9mm` | 3 | 2 | 40 |

The .38 Special recipes are the same four calibre recipes with `38Special`
ids and `Base.Bullets38`.

Vanilla templates (research §7): the die set from
`Forge_Small_Metalworking_Punch_Set`; the cold recipes from the punch and
hammer lines of the scrap-armour recipes and `NailSpikeWeapon`
(`timedAction = MakingHammer_Surface`); hand work (`Making`) from
`GatherGunpowder`; the mortar line from `MakeAerosolBomb`. Categories are
vanilla's: `Tools`, `Metalworking`, `Miscellaneous`, `Weaponry`. Batch
crafting is vanilla's default, so one-round-per-craft assembly is queued with
the batch slider.

One craft per round rather than a batch recipe: a vanilla round is one item,
case quality is per case, and vanilla dismantles one round at a time.

## 4. Items

| Item | Purpose | Notes |
|---|---|---|
| `AmmoMaking.SmallPistolPrimer` | primer, shared by a primer family | Weight 0.001; icon `SnapCap` |
| `AmmoMaking.DieSet9mm`, `AmmoMaking.DieSet38Special` | the calibre's kept tool for forming, swaging and assembling | looks like `Base.SmallPunchSet`; no condition, so no wear |
| `AmmoMaking.Case9mm`, `AmmoMaking.Case38Special` | empty case; the first item that carries quality | Weight 0.005 |
| `AmmoMaking.Bullet9mm`, `AmmoMaking.Bullet38Special` | copper bullet | Weight 0.01 |

All use vanilla icons and models as placeholders. Reused, not duplicated:
`Base.Bullets9mm`, `Base.Bullets38`, `Base.GunPowder`, `Base.CopperScrap`,
`Base.Fertilizer`, `Base.CapGunCap`, `Base.Matches`, `Base.Matchbox`,
`Base.SteelBarQuarter`, charcoal, and every tool.

## 5. Why these sources

**Bullet: copper.** Vanilla has no lead in any form (research §3). Copper is
already mined, and `Base.CopperScrap` is what vanilla's own smelting yields.
A lead ore would mean new geology for no gain in this pass.

**Primer: brass cup + toy caps or match heads.** Vanilla has no primer,
percussion cap or detonator. It does have `Base.CapGunCap` (toy caps, boxed
by the hundred) and matches, both real loot, both classic improvised priming
charges, and vanilla itself abstracts energetic materials as household items
(a cold pack in the smoke bomb, sparklers in the aerosol bomb). Two recipes
so that a common item (matches) and a rarer, cheaper-per-primer one (caps)
both work. Neither is free and neither needs ammunition.

**Powder: charcoal + fertilizer → vanilla `Base.GunPowder`.** Vanilla's only
sources of gunpowder are dismantling rounds and foraging. It has charcoal
(renewable through the charcoal pit) and fertilizer, no sulfur and no nitrate
item. The recipe uses fertilizer as the nitrate stand-in and a mortar and
pestle, vanilla's grinding tool; it invents no resource. The output is the
vanilla item, so vanilla's pipe bomb and firecracker recipes accept it.

**Charge: one use per round**, the amount vanilla returns from
`GatherGunpowder`. A calibre may take more, never less, so taking a round
apart and building a new one cannot gain powder.

## 6. Case quality

`AC_CaseQuality.lua`. The finished case is the first quality-bearing item;
ore, ingots, brass, sheets and cups carry none.

- One number, 1–100, on the scale and with the labels of the existing
  `AmmoQuality` prototype (`AmmoQuality.labelFor`: Excellent ≥ 90, Very Good
  ≥ 80, Good ≥ 70, Average ≥ 60, Poor ≥ 50, Very Poor ≥ 30, Dangerous).
- `roll(level, random01, toolBonus)` =
  `50 + 4 × level + toolBonus + (random01 × 2 − 1) × 15`, rounded and clamped.
  Level 1 gives 39–69, level 5 55–85, level 10 75–100. The worst roll at any
  level is above Dangerous. The function is pure; the game passes
  `ZombRandFloat(0, 1)`, the tests pass fixed numbers.
- `toolBonus` is 0 for the hand die set. It is the hook for a future
  reloading press.
- Rolled in the forming recipe's `OnCreate` for each created case and stored
  in the case's ModData (`AmmoMakingCase`, `caseQuality`).
- At assembly the created round gets the average quality of the consumed
  cases in its ModData as `casingQuality`, the field the `AmmoQuality`
  prototype already reads, plus `AmmoMakingHandloaded`. A round made from
  cases without a quality is left untouched.
- Quality changes nothing about material: no failure, no scrap, no bonus
  output.
- Nothing reads the round's quality yet (misfires are out of scope). The
  debug entry *Inspect Ammo Components* lists it.

Persistence relies on item ModData, as geological samples already do; vanilla
itself writes ModData onto crafted single outputs. That it survives stacking
and a magazine round-trip is listed in §12; loading a round into a magazine
almost certainly drops per-item data, which is a problem for the later
misfire stage, not for this one.

## 7. Progression

Perk thresholds are 75 / 150 / 300 XP for levels 1–3 (225 and 525 in total).

| Level | Opens |
|---|---|
| 0 | all metallurgy, brass sheets, case cups |
| 1 | forging a die set, forming cases |
| 2 | swaging bullets, making primers |
| 3 | mixing gunpowder, assembling rounds |

A first ten-ore brass batch through to cups earns about 285 XP (mining,
smelting, casting, alloying, sheets, cups), which is level 2. Forming the
cases and swaging the bullets for it carries the player to level 3 before the
last components are ready. Every level can be earned from recipes already
open below it.

The gate is the requirement `AC_Materials.applySkillRequirements()` attaches
to each recipe script at boot (metallurgy research §6 explains why it cannot
be a script field). If it cannot be attached the recipes are open to
everyone, and the compatibility check reports it per recipe.

## 8. Material balance

Units as in metallurgy: 100 per ingot, 10 per scrap or small sheet, 5 per
cup. A component may hold several materials (`AC_Materials.UNITS`).

| Item | Brass | Copper | Priming compound | Powder |
|---|---|---|---|---|
| `Case9mm` | 5 | | | |
| `Bullet9mm` | | 5 | | |
| `SmallPistolPrimer` | 1 | | 2 | |
| `Base.CapGunCap` | | | 2 | |
| `Base.Matches` / `Matchbox`, per use | | | 1 | |
| `Base.GunPowder`, per use (10 per jar) | | | | 1 |
| `Base.Bullets9mm` | 6 | 5 | 2 | 1 |

**100 rounds of 9 mm** (the test *Complete 9mm chain* runs exactly this and
ends with nothing left over):

| Input | Amount | Becomes |
|---|---|---|
| `Base.BrassIngot` | 6 | 60 small sheets: 50 → 100 cups → 100 cases; 10 → 100 primers |
| `Base.CopperScrap` | 50 | 100 bullets |
| `Base.CapGunCap` | 100 (one box) | priming for 100 primers (or 200 match uses) |
| `Base.Fertilizer` | 20 uses (2.5 bags) | 10 jars = 100 charges |
| charcoal | 6 (sheets) + 2 (die set) + 20 (powder) | |
| `Base.SteelBarQuarter` | 2, once | the die set |

In ore: 6 brass ingots are 4.2 copper ore and 1.8 zinc ore, 50 copper scrap
are 5 copper ore: **11 ore for 100 rounds**. The placeholder ratio of 20 cups
per ingot is kept; with these numbers it is not unreasonable and it is one
line in `AC_Materials.lua`. All of this is balance-tunable and untuned.

Invariants (all asserted):

1. Every recipe is exact per material, except `AmmoMaking_MixGunpowder`,
   the one declared *source* recipe, which creates powder from untracked raw
   inputs and must consume something.
2. A round contains exactly what went into it.
3. Alloy parts pay for an alloy only in the alloy recipe: a bullet's copper
   cannot stand in for a case's brass.
4. Kept tools and die sets are never consumed.
5. Vanilla `GatherGunpowder` is modelled: it returns one use, not a jar, and
   nothing else. Rounds → powder → rounds gains nothing; powder alone
   assembles nothing.
6. Over 3000 random crafts across all mod and modelled vanilla recipes, no
   metal and no priming compound is created, and powder rises only by ten
   uses per mix, bounded by the fertilizer.
7. No recipe moves metal back out of a round, and none recycles a case, so
   there is no XP loop: every XP-granting craft consumes net material.

## 9. Code

| File | Content |
|---|---|
| `shared/AC_Calibres.lua` | `LIST` (calibre definitions), `DEFAULTS`, `PRIMERS`, `COMPOUND_SOURCES`, `POWDER`; `define`, `get`, `identify`; `buildRecipes`, `buildUnits`, `getItems` |
| `shared/AC_CaseQuality.lua` | `roll`, `set` / `get`, `onCasesFormed`, `onRoundsAssembled`, `EFFECTS` |
| `shared/AC_Materials.lua` | appends the component recipes and units; per-recipe `xp`, `requiredLevel`, `effect`, `source`; multi-material conservation |
| `scripts/AC_Recipes.txt` | **generated** from `AC_Materials.RECIPES` |
| `tests/render_recipes.lua`, `tests/write_recipes.lua` | renderer and writer for the script |

### Adding a calibre

1. One entry in `AC_Calibres.LIST`: `id`, `suffix`, `round`, `ammoType`, and
   only the values that differ from `DEFAULTS`.
2. Three items in `AC_Items.txt` (`Case<suffix>`, `Bullet<suffix>`,
   `DieSet<suffix>`) and their names in `ItemName.json`.
3. Four recipe names in `Recipes.json`.
4. `lua5.1 tests/write_recipes.lua`, then the suite.
5. In the tests' mock, the new ids in `MOCK.knownScriptItems` (they stand for
   "exists in the game").

A calibre with another primer needs one `PRIMERS` entry and its item; the
primer recipes are generated per family and compound source. .38 Special was
added this way and changed no Lua logic.

### A future reloading press

Designed for, not built: a press is a new bench tag on the calibre recipes
(or a second recipe set with shorter `time`), a non-zero `toolBonus` passed
to `AC_CaseQuality.onCasesFormed`, and larger batch outputs. Components,
units, quality storage and the calibre model stay as they are.

## 10. Multiplayer

As metallurgy: vanilla crafting carries the recipes; XP must move to the
server-side call; the requirement must be attached on server and clients.
Case quality is written inside `OnCreate`, which runs on the server in
multiplayer; whether ModData written there reaches clients is unverified.

## 11. Out of scope, deliberately

Other calibres beyond the one demonstration, shotgun shells, lead, a press
object, recycling of cases or brass scrap, misfires and any use of round
quality, annealing, ballistics, loot spawns for die sets.

## 12. REQUIRES FUTURE IN-GAME VERIFICATION

- The seventeen recipes appear at their stations and in the surface crafting
  menu, with their names.
- `item 1 Base.Bullets9mm` yields one round; `item 1 [Base.GunPowder]` takes
  one use; `item 2 [Base.Fertilizer]` two uses; `item 20
  [Base.Matches;Base.Matchbox]` draws uses across items; Mix Gunpowder yields
  a full jar.
- The die set, hammer, punch and mortar are kept.
- The level requirements block and unblock the recipes as listed.
- `craftRecipeData:getAllCreatedItems()` / `getAllConsumedItems()` work from
  Lua inside `OnCreate`; cases receive a quality; rounds inherit it.
- Case ModData survives stacking, container transfers and save/reload; what
  happens to a round's ModData in a magazine.
- A handloaded round fires like a vanilla one.
- Placeholder icons: an empty case currently looks like a loose round.

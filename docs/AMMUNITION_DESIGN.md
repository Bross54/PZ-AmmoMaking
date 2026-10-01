# Ammunition components: from brass to vanilla rounds

Status: **the pistol-calibre foundation is implemented, offline-verified
only.** Five calibres (9 mm, .38 Special, .45 ACP, .357 Magnum, .44 Magnum),
two primer families, gunpowder, a calibre model with validation, case quality,
probes, debug tools and tests exist. Nothing in this document has been run in
the game; what needs it is in §13.

Vanilla facts used here are in `docs/VANILLA_AMMUNITION_RESEARCH.md`, read
from the installed Build 42.20.4 files and jar. Rifle calibres are researched,
not implemented: `docs/RIFLE_AMMUNITION_RESEARCH.md`.

All balance numbers in this document are **tunable and untuned**.

## 1. Rules

- The product is the **vanilla round item**; vanilla firearms and magazines
  are untouched. One item is one cartridge, and a recipe output is not
  multiplied by the item's `count` field.
- **A genuine raw-material loop.** No recipe in the chain consumes finished
  ammunition. A test fails if one ever does.
- Vanilla items, stations, tools and recipe patterns first. No custom world
  object, no chemistry subsystem, no lead geology.
- Ammo Making is the only skill. It changes access, time and case quality,
  never the amount of material.
- A calibre is data. No Lua outside `AC_Calibres.lua` names a calibre or a
  primer item.

## 2. Pistol calibre matrix

| Calibre | Vanilla output | Case | Projectile | Primer family | Cups per case | Bullets per scrap | Powder uses | Round level | Die set |
|---|---|---|---|---|---|---|---|---|---|
| 9mm | `Base.Bullets9mm` | `AmmoMaking.Case9mm` | `AmmoMaking.Bullet9mm` | SmallPistol | 1 | 2 | 1 | 3 | `AmmoMaking.DieSet9mm` |
| .38 Special | `Base.Bullets38` | `AmmoMaking.Case38Special` | `AmmoMaking.Bullet38Special` | SmallPistol | 1 | 2 | 1 | 3 | `AmmoMaking.DieSet38Special` |
| .45 ACP | `Base.Bullets45` | `AmmoMaking.Case45ACP` | `AmmoMaking.Bullet45ACP` | LargePistol | 1 | 1 | 1 | 4 | `AmmoMaking.DieSet45ACP` |
| .357 Magnum | `Base.Bullets357` | `AmmoMaking.Case357Magnum` | `AmmoMaking.Bullet357Magnum` | SmallPistol | 1 | 2 | 2 | 4 | `AmmoMaking.DieSet357Magnum` |
| .44 Magnum | `Base.Bullets44` | `AmmoMaking.Case44Magnum` | `AmmoMaking.Bullet44Magnum` | LargePistol | 2 | 1 | 3 | 5 | `AmmoMaking.DieSet44Magnum` |

The die set, case and bullet of a calibre unlock before its round: die set
and case two levels earlier, bullet one level earlier, never below 1
(`AC_Calibres.levelsFor`).

Vanilla firearms these feed (research §1a): M9 Pistol; SN38 Revolver; M1911
Pistol and Trapper Carbine; Patrol Revolver and L92 Carbine; B-F Pistol and
Magnum revolver.

## 3. The chain

```text
survey → sample → assay → mine → smelt → cast → brass          (earlier stages)

Base.BrassIngot ──Forge Small Brass Sheets──► 10 AmmoMaking.SmallBrassSheet
                                                   │                    │
                              Punch Brass Case Cups│                    │Make <family> Primers
                                                   ▼                    │ + 10 toy caps, or 20 match uses
                                      2 AmmoMaking.BrassCaseCup         ▼
                                                   │          10 small or 5 large pistol primers
                         Form <calibre> Case       │ (die set)          │
                         1 or 2 cups               ▼                    │
                                             empty case ────────────────┤
                                        (quality rolled here)           │
Base.CopperScrap ──Swage <calibre> Copper Bullets (die set)──► 2 or 1 ──┤
                                                                        │
2 charcoal + 2 uses of Base.Fertilizer ──Mix Gunpowder (mortar)──►      │
                                Base.GunPowder (10 uses) ──1 to 3 uses──┤
                                                                        ▼
                                                 Assemble <calibre> Round (die set)
                                                                        ▼
                                                          1 vanilla round item
```

## 4. Recipes

All in `media/scripts/AC_Recipes.txt`, **generated** from the Lua mirror
(§10): 31 blocks. "Level" is the Ammo Making level attached to the recipe
script at boot.

Shared component recipes (5):

| Recipe | Consumed | Kept | Station | Output | Level | XP | time |
|---|---|---|---|---|---|---|---|
| `AmmoMaking_MixGunpowder` | 2 `tags[base:charcoal]`, 2 uses of `Base.Fertilizer` | mortar and pestle | `AnySurfaceCraft` | 1 `Base.GunPowder` (10 uses) | 3 | 5 | 150 |
| `AmmoMaking_MakeSmallPistolPrimersFromCaps` | 1 `AmmoMaking.SmallBrassSheet`, 10 `Base.CapGunCap` | punch, hammer | `AnySurfaceCraft` | 10 `AmmoMaking.SmallPistolPrimer` | 2 | 2 | 120 |
| `AmmoMaking_MakeSmallPistolPrimersFromMatches` | 1 sheet, 20 uses of `Base.Matches` / `Base.Matchbox` | punch, hammer | `AnySurfaceCraft` | 10 small primers | 2 | 2 | 120 |
| `AmmoMaking_MakeLargePistolPrimersFromCaps` | 1 sheet, 10 `Base.CapGunCap` | punch, hammer | `AnySurfaceCraft` | 5 `AmmoMaking.LargePistolPrimer` | 3 | 2 | 120 |
| `AmmoMaking_MakeLargePistolPrimersFromMatches` | 1 sheet, 20 match uses | punch, hammer | `AnySurfaceCraft` | 5 large primers | 3 | 2 | 120 |

(plus the six metallurgy and case-stock recipes of the earlier stages.)

Per calibre (4 × 5 = 20), `<S>` being the calibre's id suffix:

| Recipe | Consumed | Kept | Station | Output | XP | time |
|---|---|---|---|---|---|---|
| `AmmoMaking_ForgeDieSet<S>` | 2 `Base.SteelBarQuarter`, 2 charcoal | ball-peen hammer, pliers/tongs, whetstone/file | `Forge` | 1 die set | 10 | 300 |
| `AmmoMaking_FormCase<S>` | `cupsPerCase` `AmmoMaking.BrassCaseCup` | die set, hammer | `AnySurfaceCraft` | 1 case | 1 (.44: 2) | 80 |
| `AmmoMaking_SwageBullets<S>` | 1 `Base.CopperScrap` | die set, hammer | `AnySurfaceCraft` | `bulletsPerScrap` bullets | 1 | 80 |
| `AmmoMaking_AssembleRound<S>` | 1 case, 1 primer of the family, 1 bullet, `powderUses` uses of `Base.GunPowder` | die set | `AnySurfaceCraft` | 1 vanilla round | 2 (.45, .357: 3; .44: 4) | 40 |

Vanilla templates (research §7): the die set from
`Forge_Small_Metalworking_Punch_Set`; the cold recipes from the punch and
hammer lines of the scrap-armour recipes and `NailSpikeWeapon`; hand work
(`Making`) from `GatherGunpowder`; the mortar line from `MakeAerosolBomb`.
Categories are vanilla's: `Tools`, `Metalworking`, `Miscellaneous`,
`Weaponry`.

**Batches.** Vanilla batch crafting is on by default for every recipe (jar:
`CraftRecipe.allowBatchCraft` starts `true`), so single-unit recipes are
queued with vanilla's slider; no custom UI and no batch recipes. Components
that naturally come in multiples do: 10 sheets per ingot, 2 cups per sheet,
10 or 5 primers per sheet, 2 bullets per scrap for the light bullets, 10
charges per mix. The round stays one per craft: a vanilla round is one item,
case quality is per case, and vanilla dismantles one round at a time. The
tests check that k crafts are exactly k times one craft with tools used once.

## 5. Primer families

| Family | Item | Brass | Compound | Per small brass sheet | Level | Calibres |
|---|---|---|---|---|---|---|
| SmallPistol | `AmmoMaking.SmallPistolPrimer` | 1 | 2 | 10 | 2 | 9mm, .38 Special, .357 Magnum |
| LargePistol | `AmmoMaking.LargePistolPrimer` | 2 | 4 | 5 | 3 | .45 ACP, .44 Magnum |

The mapping follows real-world practice and lives only in the calibre
definition (`primerFamily`). Both families use the same abstraction and the
same inputs: one small brass sheet and the same priming charge (10 toy caps
or 20 match uses). A large primer is two small ones in material, so neither
family is cheaper per unit. An assembly recipe accepts only its own family's
item.

Why toy caps and match heads, why copper bullets and why charcoal plus
fertilizer: research §§3–6 and §9. In short, vanilla has no primer, lead,
sulfur or nitrate item, and these are the loot items and mined metal that fit
vanilla's own way of abstracting such things.

## 6. Material scaling

Gameplay units, not grains. The standard pistol round is the baseline; a
calibre changes one or more of three whole-number knobs.

| Knob | Meaning | Values | Real-world reason |
|---|---|---|---|
| `cupsPerCase` | brass cups drawn into one case (5 units each) | 1; .44 Magnum 2 | a .44 Magnum case has nearly twice the brass of a 9 mm |
| `bulletsPerScrap` | bullets from one copper scrap (10 units) | 2 = light (9mm, .38, .357); 1 = heavy (.45, .44) | 115–158 gr against 230–240 gr |
| `powderUses` | uses of `Base.GunPowder` per round | 1; .357 Magnum 2; .44 Magnum 3 | about 5 gr for standard pistol rounds, 15 gr and 23 gr for the magnums |

Per round:

| Calibre | Brass (case + primer) | Copper | Powder | Priming compound |
|---|---|---|---|---|
| 9mm | 5 + 1 = 6 | 5 | 1 | 2 |
| .38 Special | 6 | 5 | 1 | 2 |
| .45 ACP | 5 + 2 = 7 | 10 | 1 | 4 |
| .357 Magnum | 6 | 5 | 2 | 2 |
| .44 Magnum | 10 + 2 = 12 | 10 | 3 | 4 |

No calibre is cheaper than 9 mm in any material and .44 Magnum is the most
expensive in every one (asserted). .38 Special equals 9 mm: one cup and half a
scrap are the smallest steps the unit system has, and vanilla itself treats
the two as the light pair.

**Powder charges are whole uses.** The engine reads recipe amounts as whole
items or uses and vanilla never writes a fractional one (research §9a), so a
charge is 1, 2 or 3 uses of the vanilla jar. `Base.GunPowder` is not
redefined and there is no custom powder item. Vanilla's `GatherGunpowder`
returns one use from any round; since every charge is at least one,
dismantling can never return more powder than went in (for the magnums it
returns less).

**Per 100 rounds** (each run in the tests from these inputs to exactly 100
rounds with nothing left over):

| Calibre | Brass ingots | Copper scrap | Toy caps | Fertilizer uses | Charcoal | Ore (copper + zinc) |
|---|---|---|---|---|---|---|
| 9mm, .38 Special | 6 | 50 | 100 | 20 | 28 | 11 |
| .45 ACP | 7 | 100 | 200 | 20 | 29 | 17 |
| .357 Magnum | 6 | 50 | 100 | 40 | 48 | 11 |
| .44 Magnum | 12 | 100 | 200 | 60 | 74 | 22 |

Plus two `Base.SteelBarQuarter`, once, for the calibre's die set. The
placeholder of 20 cups per ingot is kept.

## 7. Die sets

One per calibre, forged from two steel bar quarters at a Simple Forge, kept by
that calibre's case, bullet and assembly recipes. All five are generated from
the same recipe template and have no Lua of their own. The forging cost does
not scale with calibre: it is a one-off tool, and the per-round materials
already carry the scaling.

A die set only works for its own calibre: its item id appears in no other
calibre's recipes, the validator rejects a definition that shares one, and
the tests check the mirror, the generated script and an executed inventory.

**Future press.** The die sets are the part a press reuses:

```text
now:     AnySurfaceCraft   + the calibre's die set
later:   Reloading Press   + the same die set
```

A press is a second bench tag on the same calibre recipes (or a parallel
recipe set with shorter `time` and a batch output), with a non-zero
`toolBonus` passed to `AC_CaseQuality.onCasesFormed`. Components, units,
quality storage and the calibre model stay as they are. Nothing of the press
is built.

## 8. Case quality

`AC_CaseQuality.lua`, one code path for every calibre; it names none.

- One number, 1–100, on the scale and labels of the `AmmoQuality` prototype
  (Excellent ≥ 90, Very Good ≥ 80, Good ≥ 70, Average ≥ 60, Poor ≥ 50, Very
  Poor ≥ 30, Dangerous).
- `roll(level, random01, toolBonus)` =
  `50 + 4 × level + toolBonus + (random01 × 2 − 1) × 15`, rounded and clamped
  on every path (roll, write, read). Pure; the game passes
  `ZombRandFloat(0, 1)`, the tests a fixed sequence, and the same sequence
  gives the same qualities for every calibre.
- Rolled in the forming recipe's `OnCreate` for each created case, stored in
  the case's ModData (`AmmoMakingCase`, `caseQuality`).
- At assembly the round gets the average quality of the consumed cases **of
  its own calibre** as `casingQuality`, plus `AmmoMakingHandloaded`.
- It never changes material: the worst and the best case make the same round
  from the same inputs (asserted per calibre). No failure, no scrap, no bonus
  output, no duplication.

**Limit, established from vanilla Lua.** Loading a firearm or magazine turns
round items into a count (`ISReloadWeaponAction`; research §1a). Quality on a
loose round therefore does not survive loading. It is inspection information
on loose rounds only. Misfires or wear cannot be built on it; that stage
needs a different carrier (for example a running average stored on the
magazine or firearm at load time), which is a design question for later and
is not started.

## 9. Progression and XP economy

Perk thresholds per level: 75, 150, 300, 750, 1500, 3000, … (cumulative 75,
225, 525, 1275, 2775, 5775).

| Level | Opens |
|---|---|
| 0 | all metallurgy, brass sheets, case cups |
| 1 | 9mm and .38 Special die sets and cases |
| 2 | 9mm and .38 bullets; small pistol primers; .45 and .357 die sets and cases |
| 3 | **9mm and .38 Special rounds**; gunpowder; large pistol primers; .45 and .357 bullets; .44 die set and case |
| 4 | **.45 ACP and .357 Magnum rounds**; .44 bullets |
| 5 | **.44 Magnum rounds** |

The ladder stops at 5 on purpose. The curve doubles from level 4 to 5 and
again to 6: level 6 costs 5775 XP, about 110 ore of work, which would be a
grind wall for one calibre.

**Simulated career** (test *XP economy*; a mirror inventory, ore counted,
loot assumed available, every craft blocked until its level is reached). Each
cycle is a ten-ore brass batch plus the copper for its bullets, turned into
as many rounds as possible of the best calibre available:

| Level reached | Ore mined | Rounds made so far |
|---|---|---|
| 1 | 10 | 0 |
| 2 | 10 | 0 |
| 3 | 19 | 0 |
| 4 | 29 | 166 |
| 5 | 63 | 332 |

After eight cycles: 158 ore, 889 rounds, 8487 XP.

Answers to the review questions:

- **Ore per level**: about 10 for levels 1–2, 19 for level 3, 29 for level
  4, 63 for level 5.
- **Is ammunition unlocked before there is material to use it on?** No.
  Level 3 arrives while the first batch's cases and bullets are being made,
  and the first rounds follow in the same cycle.
- **Can a cheap reversible recipe farm XP?** No. Every recipe consumes
  something. The only cycle among all items is round ↔ gunpowder through
  vanilla `GatherGunpowder`, and it destroys the case, primer and bullet;
  powder alone assembles nothing, so the loop earns no XP (asserted per
  calibre).
- **Is any batch over-rewarded?** No recipe gives more than 25 XP per craft
  (the ten-ingot brass batch), none more than 0.5 XP per unit of material,
  and no recipe type gives 45 % of a career's XP.

No XP value of the earlier stages was changed. The larger calibres give
slightly more per round (3 or 4 instead of 2) for their extra material.

## 10. Material conservation

Units: 100 per ingot, 10 per scrap or small sheet, 5 per cup; a component may
hold several materials (`AC_Materials.UNITS`, built by
`AC_Calibres.buildUnits`).

Invariants (all asserted):

1. Every recipe is exact per material, except `AmmoMaking_MixGunpowder`, the
   one declared *source* recipe, which must still consume something.
2. A round contains exactly its case, primer, bullet and charge.
3. Alloy parts pay for an alloy only in the alloy recipe.
4. Kept tools and die sets are never consumed.
5. Vanilla `GatherGunpowder` is modelled per calibre: one use, never a jar,
   nothing else.
6. Over 3000 random crafts across every mod and modelled vanilla recipe, no
   metal and no priming compound is created, and powder rises only by ten
   uses per mix.
7. No component fits another calibre; no primer fits the other family.
8. Fifteen ore run through every recipe to 100 rounds of 9mm ends with the
   same metal it started with.

## 11. Code

| File | Content |
|---|---|
| `shared/AC_Calibres.lua` | `LIST`, `DEFAULTS`, `PRIMERS`, `COMPOUND_SOURCES`, `POWDER`; `define`, `levelsFor`, `validate`, `get`, `getPrimer`, `identify`; `buildRecipes`, `buildUnits`, `getItems` |
| `shared/AC_CaseQuality.lua` | `roll`, `set` / `get`, `onCasesFormed`, `onRoundsAssembled`, `EFFECTS` |
| `shared/AC_Materials.lua` | appends the component recipes and units; per-recipe `xp`, `requiredLevel`, `effect`, `source`; multi-material conservation |
| `shared/AC_Compat.lua` | calibre model validation, one completeness line per calibre, gunpowder uses per jar |
| `scripts/AC_Recipes.txt` | **generated** from `AC_Materials.RECIPES` |
| `tests/render_recipes.lua`, `tests/write_recipes.lua` | renderer and writer for the script |

### Adding a calibre

1. One entry in `AC_Calibres.LIST`: `id`, `suffix`, `round`, `ammoType`, and
   only what differs from `DEFAULTS` (`primerFamily`, `cupsPerCase`,
   `bulletsPerScrap`, `powderUses`, `assembleLevel`, single `xp` steps).
2. Three items in `AC_Items.txt` (`Case<suffix>`, `Bullet<suffix>`,
   `DieSet<suffix>`), their names in `ItemName.json`.
3. Four recipe names in `Recipes.json`.
4. `lua5.1 tests/write_recipes.lua`, then the suite.
5. In the tests' mock, the new ids in `MOCK.knownScriptItems`.

.45 ACP, .357 Magnum and .44 Magnum were added this way; the only Lua that
changed for them was the model's own new fields.

## 12. Out of scope, deliberately

Rifle calibres and shotgun shells, a reloading press object, lead, deeper
primer or powder chemistry, misfires, firearm damage or malfunctions, any use
of round quality, recycling, spent casings, multiplayer, custom UI, loot
spawns for die sets.

## 13. REQUIRES FUTURE IN-GAME VERIFICATION

- The 31 recipes appear at their stations and in the surface crafting menu
  with their names.
- One assembly craft yields one round, for each of the five vanilla rounds.
- `item N [Base.GunPowder]` takes N uses (1, 2, 3); `item 2 [Base.Fertilizer]`
  two uses; `item 20 [Base.Matches;Base.Matchbox]` draws uses across items;
  Mix Gunpowder yields a full ten-use jar.
- `item 2 [AmmoMaking.BrassCaseCup]` takes two cups for a .44 Magnum case.
- Die sets, hammer, punch and mortar are kept.
- The level requirements block and unblock the recipes as in §9.
- `craftRecipeData:getAllCreatedItems()` / `getAllConsumedItems()` work from
  Lua inside `OnCreate`; cases receive a quality; rounds inherit it.
- Case ModData survives stacking, container transfers and save/reload.
- Handloaded rounds of every calibre load and fire like vanilla ones.
- The compatibility check reports five complete calibres and a ten-use jar.
- Placeholder icons: empty cases look like loose rounds; both primers share
  an icon.

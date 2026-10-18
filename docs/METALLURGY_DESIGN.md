# Metallurgy: ore to brass on the vanilla furnaces

Status: **implemented on 2026-10-02, offline-verified only.** The recipes,
items, callbacks, probes and tests exist; nothing in this stage has been run in
the game yet. What needs the game is listed in §11.

Target: Project Zomboid Build 42.20.4.

Guiding decision (project owner): **metallurgy extends Build 42's own furnace
system; it is not a parallel one.** There is no custom furnace object, fuel,
heat, timer or persistence. The mod contributes three zinc items, four recipes
attached to vanilla furnace bench tags, and one small Lua module. Lead, a
second projectile metal melted from vanilla junk and cast into bullets, is
§12.

Evidence for every vanilla fact used here is in
`docs/VANILLA_METALLURGY_RESEARCH.md` (read from the installed game files and
jar).

## 1. The chain

```text
survey → sample → assay → mine                      (existing systems)
            │                       │
     Base.CopperOre          AmmoMaking.ZincOre
            │  vanilla               │  mod
            │  Smelt Copper Ore      │  Smelt Zinc Ore
            │  4 charcoal            │  4 charcoal
            │  Primitive Furnace     │  Primitive Furnace
            ▼                        ▼
   Base.CopperScrap ×10      AmmoMaking.ZincScrap ×10
            │  mod                   │  mod
            │  Cast Copper Ingot     │  Cast Zinc Ingot
            │  10 scrap, 4 charcoal  │  10 scrap, 4 charcoal
            │  Simple Furnace        │  Simple Furnace
            ▼                        ▼
   Base.CopperIngot          AmmoMaking.ZincIngot
            └───────────┬────────────┘
                        ▼  mod: Cast Cartridge Brass
                           7 copper + 3 zinc ingots, 10 charcoal, Simple Furnace
                 Base.BrassIngot ×10
```

The player experience is vanilla's: build a furnace, open its crafting UI, pick
the recipe, wait. Furnaces have no lit or fuel state; charcoal is a recipe
input.

## 2. Recipes

All in `media/scripts/AC_Recipes.txt`, `module Base`, `category = Blacksmithing`,
`time = 200` (the value of every vanilla furnace recipe).

| Recipe id (display name) | Bench tag (station) | Consumed | Kept | Output | XP |
|---|---|---|---|---|---|
| `AmmoMaking_SmeltZincOre` (Smelt Zinc Ore) | `PrimitiveFurnace` (any furnace) | 1 `AmmoMaking.ZincOre`, 4 charcoal | — | 10 `AmmoMaking.ZincScrap` | 3 |
| `AmmoMaking_CastCopperIngot` (Cast Copper Ingot) | `Furnace` (Simple or Advanced) | 10 `Base.CopperScrap`, 4 charcoal | empty `Base.CeramicCrucible`, tongs, ingot mold | 1 `Base.CopperIngot` | 5 |
| `AmmoMaking_CastZincIngot` (Cast Zinc Ingot) | `Furnace` | 10 `AmmoMaking.ZincScrap`, 4 charcoal | same | 1 `AmmoMaking.ZincIngot` | 5 |
| `AmmoMaking_CastBrassIngots` (Cast Cartridge Brass) | `Furnace` | 7 `Base.CopperIngot`, 3 `AmmoMaking.ZincIngot`, 10 charcoal | same | 10 `Base.BrassIngot` | 25 |

Where each line comes from:

| Mod recipe | Vanilla template | What was changed |
|---|---|---|
| Smelt Zinc Ore | `SmeltCopperOre` | the two item ids; `OnCreate` added |
| Cast … Ingot | `CastIronIngot` (tongs `mode:keep flags[MayDegradeLight]`, mold `mode:keep`, `Furnace` tag) + the kept empty crucible of `ExtractIronFrom…Item` | scrap is consumed directly instead of crucible-with-metal uses; 4 charcoal instead of 12 |
| Cast Cartridge Brass | the same casting block | two metals in, 10 ingots out, 10 charcoal |

Charcoal means `tags[base:charcoal]`: Charcoal, Wood Charcoal or Coke. Tongs
means `tags[base:crudetongs;base:tongs]`. The mold is
`[Base.ClayIngotMold;Base.IronIngotMold;Base.SteelIngotMold]`.

Vanilla behaviours inherited rather than implemented:

- Clay molds and crude tongs carry `base:breakonsmithing` and break after a
  recipe whose category is `Blacksmithing`. Iron and steel molds and proper
  tongs do not.
- Batch crafting is on by default.
- Vanilla "Smelt Copper Ore" is not redefined, overridden or duplicated.

Why scrap is consumed directly: vanilla's crucible-with-metal items
(`CeramicCrucible_Iron`, `_Steel`) are drainables filled by a Java callback
and exist only for iron and steel. Copying that would need three more items
and a refill callback for no gameplay gain. The empty crucible as a kept tool
is also a vanilla pattern.

## 3. Items

| Item | Status | Definition |
|---|---|---|
| `Base.CopperOre`, `Base.CopperScrap`, `Base.CopperIngot` | vanilla, reused | — |
| `Base.BrassIngot` | vanilla, reused; vanilla has no recipe for it | — |
| `Base.BrassScrap` | vanilla, untouched; reserved for later recycling | — |
| `AmmoMaking.ZincOre` | changed | copies `Base.CopperOre`: Weight 40.0, `RequiresEquippedBothHands`, `base:hasmetal;base:heavyitem`; icon and models of `IronOre` |
| `AmmoMaking.ZincScrap` | new | copies `Base.CopperScrap`: Weight 0.5, `base:hasmetal`; icon and world model of `AluminumScrap` |
| `AmmoMaking.ZincIngot` | changed | copies `Base.CopperIngot`: Weight 6.0, `base:hasmetal;base:ingot`; icon `Ingot_Silver`, models of `SilverBar` |

All three zinc items are justified: the ore is what mining drops, the scrap is
what the vanilla ore convention produces, the ingot is the alloy input. No
`AmmoMaking.Copper*` or `AmmoMaking.Brass*` items exist, and a test fails if
one is added.

The zinc items use vanilla art as placeholders. Zinc has no ore-specific tags:
vanilla's `base:copperore` / `base:coppersource` are read by nothing, and a
zinc pair would have to be registered through `registries.lua` for no use.

## 4. Ore preparation

None. Vanilla puts the ore chunk straight into the furnace; so does zinc.

## 5. Skill

Ammo Making is the only skill involved. Vanilla furnace recipes have no skill
gate and award no XP, so no Blacksmith requirement is added.

| Lever | How | Value |
|---|---|---|
| XP | each recipe's `OnCreate` calls `AC_Materials.on<Recipe>`, which awards once per completed craft through `AmmoMakingSkill.awardXP` (console line `Crafting (<recipe id>): +N Ammo Making XP (total a -> b)`) | 3 / 5 / 5 / 25 |
| Time | at boot `AC_Materials.applySkillRequirements()` adds "Ammo Making: 0" to each recipe script with the engine's `CraftRecipe.addRequiredSkill`. The engine's own `getTime(character)` then shortens the craft by 5 % per level: 200 at level 0, 100 at level 10 | engine rule |
| Access | `CONFIG.requiredLevel` = 0: the whole chain is open from the start | 0 |
| Tool wear | `MayDegradeLight` uses the recipe's relevant skill level, which is now Ammo Making | engine rule |
| Yield, quality | none. Skill never changes what a recipe consumes or produces | — |

Why this is Lua and not `SkillRequired` / `xpAward` in the script: the engine
resolves those names while parsing scripts, before mod Lua runs, and drops an
unknown perk with a warning. The Ammo Making perk is registered from Lua.
Moving it to `media/perks.txt` would make the script fields work but would
change the perk registration that is confirmed working in game; that is left
as a later option (research §6).

If the engine does not expose `addRequiredSkill` to Lua, the recipes still
work; only the time lever is lost, and the compatibility check says so.

## 6. Material conservation

Unit: 1 ingot = 100 units; ore = 100; scrap = 10 (`AC_Materials.UNITS`).

Invariants, each asserted by `tests/run_tests.lua`:

1. Every mod recipe has units out = units in. 1 ore → 10 scrap → 1 ingot.
2. The alloy is exact: 700 copper + 300 zinc units in, 1000 brass units out,
   30 % zinc.
3. Kept inputs (crucible, tongs, mold) contain no metal and are never consumed.
4. Every recipe consumes its charcoal.
5. Over the whole graph, vanilla copper recipes included, no item can be
   turned back into itself, and no sequence of recipes increases the metal in
   an inventory (500 random crafts on a mirrored inventory).
6. `AC_Recipes.txt` and `AC_Materials.RECIPES` are identical field by field,
   so the numbers the tests check are the numbers the game loads.
7. Nothing produces or consumes `Base.BrassScrap` yet. `Base.BrassIngot`
   feeds the case-stock and component stages (`docs/AMMUNITION_DESIGN.md`),
   which are held to the same invariants.
8. The parts of an alloy pay for it only in the alloy recipe.

The engine consumes inputs and creates outputs; mod Lua never moves an item in
this stage, so a crash cannot half-apply a recipe on our side.

## 7. Quality

Deferred to cartridge-case manufacturing (owner decision).
`Base.BrassIngot` stays a plain vanilla item with no mod ModData. `OnCreate`
receives the created items if a later stage wants to mark them.

## 8. Code

| File | Content |
|---|---|
| `media/scripts/AC_Recipes.txt` | the four furnace `craftRecipe` blocks among the mod's recipes; the file is generated from the Lua mirror |
| `media/scripts/AC_Items.txt` | zinc ore / scrap / ingot |
| `media/lua/shared/AC_Materials.lua` | item ids, `UNITS`, `RECIPES` mirror, `VANILLA_RECIPES` (for the loop check), `checkConservation`, `getExpectedTime`, the `OnCreate` callbacks, `applySkillRequirements` |
| `media/lua/shared/AC_Compat.lua` | probes for the metallurgy item ids, each recipe script, its callback and its requirement |
| `media/lua/client/AC_GeologyDebug.lua` | Spawn Metallurgy Kit (with a teleport to the nearest furnace or a Smelting Furnace built next to the player), Inspect Station Recipes, Print Material Ledger |
| `Translate/EN/Recipes.json`, `ItemName.json` | recipe and item names |

`AC_Materials.CONFIG`: `unitsPerIngot` 100, `xpSmeltZincOre` 3, `xpCastIngot` 5,
`xpCastBrass` 25, `requiredLevel` 0. Charcoal counts and `time` live in the
script and its mirror. Nothing is balanced yet.

## 9. Multiplayer

No custom state persists and no custom timed action exists, so vanilla
crafting carries the stage. Two things need work before multiplayer:

- `OnCreate` runs on the server there (`ISHandcraftAction:complete`).
  `AmmoMakingSkill.awardXP` uses the single-player XP call; a server-side
  grant should use vanilla's `addXp(character, perk, amount)`.
- `applySkillRequirements()` must run on the server and on every client so
  both agree on the recipe's requirement.

## 10. Decisions

Project owner: one brass recipe (7 + 3 → 10); Ammo Making only; no ore
preparation; brass quality deferred; vanilla copper and brass items reused.

Made during implementation, all conservative and all in `CONFIG` or one script
line: ore smelting at the Primitive Furnace and casting at the Simple Furnace
(vanilla's own split); 4 charcoal per ingot and 10 per brass batch; XP 3 / 5 /
25; requirement level 0.

## 11. REQUIRES FUTURE IN-GAME VERIFICATION

- The four recipes appear at the right furnace tier, consume and produce as
  written, keep the crucible, tongs and mold.
- `Base.BrassIngot` is what the brass recipe produces.
- The `OnCreate` callbacks fire once per craft, including batch crafts.
- `addRequiredSkill` works from Lua; the UI shows Ammo Making 0; the craft
  gets faster with level.
- `Recipes.json` / `ItemName.json` names appear.
- Zinc placeholders (icons, world models) look acceptable; a 40-weight zinc
  ore behaves like copper ore when carried.
- Clay mold and crude tongs break as with vanilla casting.
- The compatibility check reports every metallurgy line as OK.

## 12. Lead and cast bullets

Status: **implemented on 2026-10-17, offline-verified only.**
`media/lua/shared/AC_Casting.lua`; the per-calibre half is in
`AC_Calibres.lua` (`CLASSES[class].mould`, `calibre.castBullet`). The
ammunition side (what a cast round is) is `AMMUNITION_DESIGN.md` 6.1.

A second projectile metal, cheaper than copper because it needs no mine:
melted from vanilla junk, cast in a mould over the same furnaces.

```text
Base.LeadPipe (1)  ──Melt Lead from Lead Pipe──►  2 ┐
Base.JigLure  (5)  ──Melt Lead from Jig Lures──►  1 ┤ AmmoMaking.LeadScrap (10 lead)
                     Primitive Furnace, 1 charcoal, │
                     kept crucible and tongs, 0 XP  │
                                                    ▼
                     Cast <calibre> Lead Bullets: 1 scrap, 1 charcoal,
                     kept crucible, tongs and the class's mould
                                                    ▼
             AmmoMaking.CastBullet<suffix> ×bulletsPerScrap
             (12 gauge: AmmoMaking.LeadShotCharge12Gauge)
                                                    ▼
             Assemble <calibre> Round (Cast Bullet): the copper assembly
             with its bullet line swapped ──► the same vanilla round
```

### 12.1 What vanilla 42.20.4 has (FILE)

Searched in `scripts/generated/items/`, `recipes/`, `entities/`, the
translations and the loot tables:

| Candidate | In 42.20.4 | Used |
|---|---|---|
| `Base.LeadPipe` "Lead Pipe" (`items/weapon.txt`) | `base:weapon`, Weight 1.5, `base:hasmetal`; no recipe consumes it. Loot (live lists, `tests/vanilla_snapshot.lua`): `PlumbingSupplies` (20), `MeleeWeapons`, `_Mid`, `_Late`, `DrugShackWeapons` (8 each), `DerelictHouseCrime` (0.1), and the junk tables of bins, closets and derelict houses; carried by zombies (`shared/Definitions/AttachedWeaponDefinitions.lua`); foraged as junk (`Foraging/Categories/JunkWeapons.lua`) | yes |
| `Base.JigLure` "Jig Lure" (`items/normal.txt`) | `base:normal`, Weight 0.1, a fishing lure; no recipe consumes it. Loot: `CrateFishing`, `SurvivalGear` (10 each), `FishingStoreGear` (6), `CrateRandomJunk` (1) | yes |
| Car batteries `Base.CarBattery1` to `3` | `base:drainable`, `UseDelta = 0.00001`, a vehicle part | no: a recipe line counts uses of a drainable, so `item 1` would take one use of charge, not the battery; and it is a scarce vehicle part |
| Lead ingot, scrap or ore; fishing sinker; wheel weight | none (no item, no tag; `grep -i lead` over the items finds only the pipe) | — |
| Bullet mould | none; vanilla's molds are ingot, bar, sheet, vise and anvil molds | the mod's own |

### 12.2 Recipes

All generated into `AC_Recipes.txt` from `AC_Casting.buildRecipes()`,
`module Base`, appended to `AC_Materials.RECIPES` after the calibre
recipes.

| Recipe | Station | Consumed | Kept | Output | Level | XP | time |
|---|---|---|---|---|---|---|---|
| `AmmoMaking_MeltLeadFromLeadPipe` | `PrimitiveFurnace` | 1 `Base.LeadPipe` (`mode:destroy flags[AllowDestroyedItem]`), 1 charcoal | crucible, tongs | 2 `AmmoMaking.LeadScrap` | 0 | 0 | 200 |
| `AmmoMaking_MeltLeadFromJigLures` | `PrimitiveFurnace` | 5 `Base.JigLure`, 1 charcoal | crucible, tongs | 1 `AmmoMaking.LeadScrap` | 0 | 0 | 200 |
| `AmmoMaking_ForgeBulletMouldPistol`, `...Shotgun` | `Forge` | 2 `Base.IronBarQuarter`, 2 charcoal | ball-peen hammer, pliers or tongs, whetstone or file | 1 mould | 2 / 3 | 0 | 300 |
| `AmmoMaking_CastBullets<S>` (six) | `PrimitiveFurnace` | 1 `AmmoMaking.LeadScrap`, 1 charcoal | crucible, tongs, the class's mould | `bulletsPerScrap` cast bullets | the swage's | the swage's | the swage's |
| `AmmoMaking_CastBullets<S>In{Stone,Clay,Sand}Mould` (eighteen) | `PrimitiveFurnace` | as the iron cast; the sand mould is consumed | as the iron cast, with that material's mould | as the iron cast | the swage's | the swage's | the swage's |
| `AmmoMaking_CarveStoneBulletMould<C>`, `ShapeClay...`, `FireClay...`, `RamSand...` (eight) | `AnySurfaceCraft`; the firing `KilnSmall;KilnLarge` | see 12.8 | see 12.8 | 1 mould (or unfired mould) | 2 / 3 | 0 | 300 / 120 / 20 / 60 |
| `AmmoMaking_AssembleCastRound<S>` (six) | `AnySurfaceCraft` | the copper assembly's lines, the cast bullet for the copper one | die set | 1 vanilla round | the assembly's | the assembly's | the assembly's |

Templates: the melt is vanilla's `ExtractIronFromSmallItem` (kept empty
crucible and tongs, one charcoal, the junk line `mode:destroy
flags[...AllowDestroyedItem]`, `PrimitiveFurnace`); the mould is the die
set's forging line (`Forge_Small_Metalworking_Punch_Set`) with iron for
steel; the cast is the melt with a mould kept as vanilla keeps its ingot
mold. Category `Blacksmithing` for the furnace recipes, so the
`base:breakonsmithing` of clay molds and crude tongs applies as in vanilla.

Items: `AmmoMaking.LeadScrap` copies `Base.CopperScrap` (0.5,
`base:hasmetal`); the moulds are `Tool`s of 0.8 (two bar quarters weigh
1.0); each cast bullet weighs its copper bullet. Own icons; world models
borrowed (`docs/PLACEHOLDER_ASSETS.md`).

### 12.3 Why these numbers

- **Same metal per bullet.** A lead scrap holds 10 units, a copper scrap's
  amount, and casts `bulletsPerScrap` bullets: the units, the bullet
  counts and the per-100 tables are the copper ones with lead for copper.
  `validate()` refuses a lead scrap of another size.
- **Melting by weight, with a loss.** 1.5 kg of pipe gives 1.0 kg of
  scrap; five lures (0.5 kg, lead heads on steel hooks) one 0.5 kg scrap.
  The tests check every source against the installed game's weights.
- **Melting teaches nothing (0 XP).** The junk is loot; paying for melting
  it would pay for searching. The same rule as recycling.
- **Casting pays what swaging pays.** Same level, XP and time per craft
  (`AC_Casting.STEP_OF`), and the cast round's assembly is the copper
  round's. A round earns the same XP with either bullet, so lead opens no
  faster climb; the career numbers of `AMMUNITION_DESIGN.md` 9.1 hold.
- **A mould pays nothing when forged**, as a kit pays per assay: iron bar
  quarters are cheap, and a free XP recipe would be a grind. Its level is
  that of the first bullet it casts (pistol 2, buckshot 3).
- **It does not undercut the mine.** Lead replaces only the bullet. The
  brass of the case and primer, and so all the zinc, which only an assayed
  deposit gives, is unchanged: a hundred cast 9mm rounds still take 6
  brass ingots (1.8 zinc ore), and save the 5 copper ore of the bullets;
  for the heavy .45 and .44 bullets the saving is 10 copper ore a hundred.
  The tests check that a cast round takes all of its brass and no copper.
  What limits lead is supply, what the world holds: one pipe is four 9mm
  bullets, a hundred rounds 25 pipes or 250 lures (50 pipes for .45);
  one copper ore is 20 bullets.
- **One charcoal per craft** at a furnace that has no fuel of its own
  (`VANILLA_METALLURGY_RESEARCH.md` 3): the heat a melt or a pour costs.
- **No way back.** No recipe turns a cast bullet or a round into lead
  (vanilla's Gather Gunpowder returns powder only), so lead recycling has
  nothing to recover: `AC_Recycling.getSources()` is unchanged.

### 12.4 Rifles cast only with a gas check

A plain cast bullet strips in the rifling and leads the bore at the 2,200
to 3,000 ft/s of the 5.56, .30-30 and .308. What made cast rifle loads work
was a gas check, a small copper cup crimped on the bullet's base, so the
rifle class has a mould (`AmmoMaking.BulletMouldRifle`) and `gasCheck`:

- *Punch Copper Gas Checks* (`AC_Casting.GAS_CHECK`): 1 `Base.CopperScrap`
  gives 10 `AmmoMaking.GasCheck` cold on a surface, punch and hammer kept,
  no XP, at the level of the first rifle bullet.
- The rifle's cast assembly takes the copper assembly's lines, the cast
  bullet for the copper one, and one gas check. The round holds the lead of
  the bullet and the gas check's copper: one unit, a tenth of a jacketed
  bullet's, still from the mine.
- Even checked, a cast bullet at rifle speed shoots worse than a jacketed
  one: the rifle class rolls its cast bullets `castQualityBonus` (-10) lower,
  on top of the mould's bonus.
- The rifle mould is found only among a hunter's things (the gun store's
  case would be over its mould cap with three).

Pistol rounds and buckshot stay under about 1,400 ft/s, where plain lead
was the usual load, and need no gas check.

### 12.5 Lead geology: not built

`AC_Deposits.METALS` is `{ copper, zinc }`, iterated by sampling and the
assay results, and `AC_Deposits.getConcentration` and `AC_Geology`
branch per metal (`getCopperConcentration`, `getZincConcentration`, one
threshold each). A third ore would change what every sample, assay and
deposit tile reports, which is the system seen working in game. Lead comes
from vanilla junk instead; a lead ore could be added later as a deposit
generator of its own without touching the two that exist.

### 12.6 Loot

The two moulds are also found (`LOOT_AND_RECYCLING.md` 1.5), scaled by the
die-set loot option. Lead scrap and cast bullets are never loot.

### 12.8 Moulds of stone, clay and sand

The forged iron mould needs a Forge. Three more materials cast the same
bullets without one, for worse quality (`AC_Casting.MOULD_MATERIALS`):

| Material | Made | Lasts | Bullet quality |
|---|---|---|---|
| iron | forged, 2 iron bar quarters (above) | wears very slowly, as a die set: condition 10, `ConditionLowerChanceOneIn = 15`, `MayDegradeVeryLight`; some 900 casts | +0 |
| stone | carved from 1 `Base.StoneBlock` with a hammer and a chisel, the lines of vanilla's `Make_Stone_Block_from_Stone` (`HammerStoneStanding`, `Masonry`) | wears: condition 10, `ConditionLowerChanceOneIn = 10`, `MayDegradeLight`; some 300 casts | -5 |
| clay | 2 `Base.Clay` shaped with a sharp knife (`Making`, as vanilla's `PressClayBrickManually`), then fired in a kiln with a fire starter and a log or charcoal, the lines of vanilla's `FireClayIngotMold` | one cast: tagged `base:destructible;base:breakonsmithing` like `Base.ClayIngotMold`, and the engine sets a kept item so tagged to condition 0 after a `Blacksmithing` recipe | -10 |
| sand | 1 use of a dug `Base.Sandbag` and 1 `Base.Clay` as the binder, with a sharp knife | one cast: the cast consumes it | -20 |

Clay and sand are dug with a shovel (vanilla fills `Base.Claybag` and
`Base.Sandbag`; `EmptySackClay` gives eight `Base.Clay`); a stone block is
cut by vanilla masonry. None of them is loot, and making a mould pays no
XP. Every cast, whatever the mould, has the iron cast's level, XP, time,
lead and bullets: the material changes only quality and durability.

**Quality.** A cast bullet now carries a quality (`bulletQuality` on the
item), rolled like a case's (`AC_CaseQuality.roll`: level, spread) plus the
mould's bonus. A round assembled with cast bullets takes the cases'
average and the bullets' average, half each
(`AC_CaseQuality.CONFIG.projectileShare`); a copper round is still its
case's. At level 5 and an even roll: iron 70, stone 65, clay 60, sand 50;
with a case of 70, a sand-cast round is 60. Quality has no effect at the
shot while the effects are locked (`AMMO_QUALITY_RUNTIME_DESIGN.md` 9.4); it
is shown by *Inspect Ammunition* and carried in magazines when quality
tracking is on.

### 12.10 Lubing cast bullets with candle wax

*Lube <calibre> Lead Bullets with Candle Wax* (`AC_Casting.LUBE`): 5 cast
bullets and 10 uses of a vanilla candle (`Base.Candle`, a drainable of 333
uses) give the same 5 bullets back, each `qualityBonus` (+5) better, once:
the bullet is marked (`bulletLubed`) and lubing it again adds nothing. A
*treatment*: no XP, the calibre's bullet level, and no step of the chain
(the tests leave treatments out of the progression and the cycle check).

### 12.7 REQUIRES FUTURE IN-GAME VERIFICATION

- The melts and casts appear at a Primitive Furnace (and the higher
  furnaces), the moulds at a Forge; each consumes and keeps as written.
- A broken lead pipe is accepted (`AllowDestroyedItem` with
  `mode:destroy`, as vanilla's junk melt).
- The cast round is the vanilla round and stacks with factory rounds.
- The borrowed world models (`SilverScrap`, `Pliers`, `SteelSlug`) look
  acceptable; the mould and lead icons read in the inventory.
- Rifle casting (12.4): the gas check recipe, the rifle mould, and that
  the cast rifle round is the vanilla round.
- Lubing (12.10): the candle loses ten uses, the bullets come back with
  their quality raised.
- The stone, clay and sand moulds (12.8): the clay mould is offered at a
  kiln and fires, breaks after one cast; the stone mould shows and loses
  condition; the sand mould is used up; the borrowed icons and models
  (`RoughBlock`, the ceramic ingot cast, `Sandbag`) read sensibly.

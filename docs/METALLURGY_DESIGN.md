# Metallurgy: ore to brass on the vanilla furnaces

Status: **implemented on 2026-10-02, offline-verified only.** The recipes,
items, callbacks, probes and tests exist; nothing in this stage has been run in
the game yet. What needs the game is listed in §11.

Target: Project Zomboid Build 42.20.4.

Guiding decision (project owner): **metallurgy extends Build 42's own furnace
system; it is not a parallel one.** There is no custom furnace object, fuel,
heat, timer or persistence. The mod contributes three zinc items, four recipes
attached to vanilla furnace bench tags, and one small Lua module.

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
   feeds the case-stock stage (`docs/AMMUNITION_DESIGN.md`), which is held to
   the same invariants.

The engine consumes inputs and creates outputs; mod Lua never moves an item in
this stage, so a crash cannot half-apply a recipe on our side.

## 7. Quality

Deferred to cartridge-case manufacturing (owner decision).
`Base.BrassIngot` stays a plain vanilla item with no mod ModData. `OnCreate`
receives the created items if a later stage wants to mark them.

## 8. Code

| File | Content |
|---|---|
| `media/scripts/AC_Recipes.txt` | the four furnace `craftRecipe` blocks (and the two case-stock ones) |
| `media/scripts/AC_Items.txt` | zinc ore / scrap / ingot |
| `media/lua/shared/AC_Materials.lua` | item ids, `UNITS`, `RECIPES` mirror, `VANILLA_RECIPES` (for the loop check), `checkConservation`, `getExpectedTime`, the `OnCreate` callbacks, `applySkillRequirements` |
| `media/lua/shared/AC_Compat.lua` | probes for the metallurgy item ids, each recipe script, its callback and its requirement |
| `media/lua/client/AC_GeologyDebug.lua` | Spawn Metallurgy Kit, Inspect Station Recipes |
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

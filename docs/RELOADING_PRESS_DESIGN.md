# Reloading press: research and design

Status: **DESIGNED. The station is not built.** The press *recipes* are
prepared in the calibre model and switched off; nothing of the press is in
the game's scripts.

Vanilla facts were read on 2026-10-02 from the installed Build 42.20.4
scripts, Lua and `projectzomboid.jar` (paths relative to the install root).
Each is marked:

- **FILE** read in an installed script or Lua file
- **JAR** read from the jar with `javap`
- **INFERRED** a conclusion from those, not itself read
- **WORKSHOP CLUE** seen in an installed Workshop mod; a hint, never proof

## 1. What the press must be

```text
handloading:   AnySurfaceCraft   + the calibre's die set    slow
press:         Reloading Press   + the SAME die set         faster
```

- The press does **not** replace die sets. Every press recipe keeps the
  calibre's die set, the item the hand recipe keeps.
- The press does **not** save material. Same inputs, same outputs, same XP.
- A quality bonus may come later; nothing may depend on it.
- Batches come from vanilla's own batch crafting, not from the press.

## 2. How vanilla defines a crafting station

### 2.1 A station is a script entity

FILE `media/scripts/generated/entities/blacksmith/workstations/entity_grindstone.txt`
(complete, one face shown):

```text
module Base
{
    entity Grindstone
    {
        component UiConfig   { xuiSkin = default, entityStyle = ES_Grindstone, uiEnabled = true, }
        component CraftBench { Recipes = Grindstone, }
        component SpriteConfig
        {
            face S { layer { row = crafted_01_120, } }
            ...
        }
        component CraftRecipe
        {
            timedAction = BuildLowHammer,
            time = 50,
            category = Blacksmithing,
            Tooltip = Tooltip_craft_grindstoneDesc,
            inputs
            {
                item 1 tags[base:hammer] mode:keep flags[Prop1;MayDegradeVeryLight],
                item 4 [Base.Plank],
                item 4 [Base.Nails],
                item 1 [Base.StoneWheel],
            }
        }
    }
}
```

and its UI skin, FILE
`media/scripts/entities/blacksmith/workstations/entity_grindstone_xuiSkin.txt`:

```text
xuiSkin default { entity ES_Grindstone { LuaWindowClass = ISEntityWindow, DisplayName = Grindstone, Icon = Build_Grindstone, } }
```

- `component CraftBench { Recipes = <tags> }` is what makes it a station.
  FILE: 35 entities under `generated/entities` have a `CraftBench`; none has
  a plain `CraftLogic`. Manual stations are `CraftBench` only.
- `component CraftRecipe` inside the entity is its **build** recipe. JAR
  `CraftRecipeComponentScript#load` tags it `EntityRecipe`;
  `BuildLogic#getAllBuildableRecipes` lists recipes with that tag.
- A station need not be buildable. FILE `entity_keyduplicator.txt`:
  `Key_Duplicator` has `isThumpable = false`, no build recipe, and exists as
  the moveable item `Base.Mov_KeyDuplicator`
  (`WorldObjectSprite = industry_04_16`).

Unpowered vanilla stations and their `Recipes =` values (FILE, each
`entity_*.txt`): `Grindstone`; `HandPress`; `PotteryBench`; `PotteryWheel`;
`PrimitiveForge` / `PrimitiveForge;Forge` / `PrimitiveForge;Forge;AdvancedForge`;
the three furnaces likewise; `KilnSmall`, `KilnLarge`, `DomeKiln;WoodCharcoal`;
`AnySurfaceCraft;ChoppingBlock`; `Stone_Quern`; `SpinningWheel`; `Weaving`;
`ChurnBucket`; the fibre and leather stations; `KeyDuplicator`; `MetalBandsaw`.

### 2.2 The closest vanilla precedent: the hand press and its molds

FILE `media/scripts/generated/entities/pottery/cratRecipes/craftrecipe_handpress.txt`:

```text
craftRecipe PressClayBrick
{
    time = 50,
    timedAction = UseHandPress,
    Tags = HandPress,
    xpAward = Pottery:5,
    category = Pottery,
    inputs
    {
        item 1 [Base.Clay],
        item 1 [Base.WoodenBrickMold] mode:keep,
    }
    outputs
    {
        item 1 Base.ClayBrickUnfired,
    }
}
```

A press station, a recipe that only it offers, and a **kept tool that decides
what comes out** (the mold). That is the press-plus-die-set pattern exactly.
`UseHandPress` is a vanilla timed action (FILE `generated/timedactions.txt`).

### 2.3 Recipe tags are free strings

- JAR `CraftRecipe#Load`: the `Tags` value is split on `;`, trimmed and
  stored in `ArrayList<String> categoryTags`. Nothing validates it.
- JAR `zombie.scripting.objects.CraftRecipeTag` is an enum of vanilla's tags
  (`AnySurfaceCraft`, `Forge`, `HandPress`, `InHandCraft`, `EntityRecipe`…),
  but parsing does not go through it, and it is not one of the Lua-extensible
  registries.
- JAR `TaggedObjectManager#registerObject`: every tag string met is
  registered, lower-cased. `CraftBenchScript` passes its `Recipes` string to
  `CraftRecipeManager.FormatAndRegisterRecipeTagsQuery`; matching is any-of
  (`;` separates wanted tags, `-` starts a blacklist).
- JAR `CraftRecipe#requiresSpecificWorkstation`: true unless the recipe has
  one of `InHandCraft`, `AnySurfaceCraft`, `EntityRecipe`, `Outdoors`.
  `BaseCraftingLogic#hasRequiredWorkstation` then requires the open bench's
  recipe list to contain the recipe.
- INFERRED: a mod can introduce a new tag from script alone, by writing it in
  a recipe's `Tags` and in an entity's `CraftBench { Recipes = … }`. It
  should be letters and digits only (`-` and `;` mean something to the tag
  query; `:` was not traced).
- WORKSHOP CLUE (a 42.19 mod, not proof for 42.20.4): an installed ammunition
  mod does exactly this, `component CraftBench { Recipes = AmmoReloadingBench, }`
  with recipes tagged `AmmoReloadingBench` and no Lua registration.

### 2.4 Sprites are the hard constraint

JAR `SpriteConfigManager#parseEntityScript`:

- each `row =` name must already exist as a sprite, else the entity script is
  an error (`"Sprite '…' does not exist"`);
- a sprite may belong to **one** entity; a second claim is an error
  (`"Sprite '…' is duplicate"`);
- either error sets `hasLoadErrors`, and JAR `IsoWorld#init` then refuses to
  load the world: *"World loading could not proceed, there are script load
  errors."*
- claiming a sprite marks the sprite itself (`EntityScriptName`,
  `IsoFlagType.EntityScript`), and JAR
  `GameEntityFactory#CreateIsoEntityFromCellLoading` creates the entity for
  any loaded object with that flag. INFERRED: claiming a sprite that the map
  already uses turns every such object on the map into the station.

So a press entity needs sprites that exist and that no vanilla entity (and no
other mod) claims: either new art shipped as a `.pack` and `.tiles` (WORKSHOP
CLUE: declared in `mod.info` as `pack=` and `tiledef=`), or vanilla sprites
that are unclaimed today. Unclaimed candidates, from the tile properties in
`media/newtiledefinitions.tiles` (artwork not viewed):

| Sprites | Tile name | Notes |
|---|---|---|
| `industry_04_20..23` | Grinder Bench | tabletop, moveable (`Base.Mov_BenchGrinder`); **placed on the map** |
| `crafted_05_0..3` | Press Crude Hand | moveable; the S face is two tiles |
| `crafted_02_0..3` | Workbench | not moveable |

`crafted_01_72/73` (Press Hand) and `industry_04_16..19` (Key Duplicator) are
claimed by vanilla entities and unusable.

### 2.5 Placement, pickup, persistence

- Build: FILE `media/lua/client/Entity/ISUI/BuildRecipe/ISBuildPanel.lua`
  lists `getAllBuildableRecipes()` and creates an `ISBuildIsoEntity`; FILE
  `media/lua/server/BuildingObjects/ISBuildIsoEntity.lua` creates the
  `IsoThumpable`, calls `GameEntityFactory.CreateIsoObjectEntity`, adds it to
  the square and transmits it.
- Use: FILE `media/lua/client/Context/World/ISContextEntity.lua` adds the
  context option when the entity's UI is enabled and opens the entity window,
  which embeds the same hand-craft panel as surface crafting.
- Pickup and re-placing depend on the sprite's tile properties (`IsMoveAble`,
  `CustomItem`); FILE `media/lua/shared/Moveables/ISMoveableSpriteProps.lua`
  moves the components with `GameEntityFactory.TransferComponents`.
- Persistence is the engine's: JAR `IsoObject#save` / `#load` save and load
  the entity with the object; `CraftBench` has its own `save` / `load`. No
  ModData bookkeeping is needed.

### 2.6 Speed and batches

- JAR `CraftRecipe#getTime(IsoGameCharacter)`: `time`, minus
  `(level − requirement) × (time / 20)` with integer division. FILE
  `ISHandcraftAction.lua`: the action lasts `getTime(character) × 5`.
  **There is no station speed modifier**; JAR `CraftBench` holds only its
  recipe query and fluid / energy channels.
- INFERRED: "faster at the press" therefore means a **second recipe** with
  the press's tag and a smaller `time`. A recipe tagged
  `AnySurfaceCraft;<press>` would show in both places at the same speed.
- A recipe shorter than 20 gets no skill speed-up at all (`time / 20` is 0).
- Batch crafting is per recipe (`AllowBatchCraft`, default true) and works
  the same at a bench: FILE `ISEntityUI.lua` `HandcraftStartMultiple` queues
  one action per unit.
- FILE `ISHandcraftWindow.lua`: the hand window queries
  `"InHandCraft;AnySurfaceCraft"`, so a press-only recipe is not listed there.

## 3. What this mod already has: the placed analyzer

The Laboratory Analyzer (`AC_LaboratoryAnalyzerObject`,
`AC_LaboratoryAnalyzer`) is a hand-made world object: an `ISBuildingObject`
cursor creates an `IsoThumpable` with a vanilla sprite, the mod flags it in
its ModData, keeps all state there, repairs it, and has its own pick-up timed
action. It claims no sprite as an entity, so it cannot collide with anything,
but it is not a `CraftBench`: the crafting UI does not know it.

That architecture suits an object with **its own state machine** (a sample, a
timer, power). A press has none: it only has to be "the place where these
recipes run", which is precisely what a `CraftBench` entity is.

## 4. Options

| | A. Press as a tool item at any surface | B. Placed entity with its own `CraftBench` tag | C. Reuse a vanilla station's tag |
|---|---|---|---|
| What it is | `AmmoMaking.ReloadingPress`, a heavy `mode:keep` input of faster `AnySurfaceCraft` recipes | script `entity` with `CraftBench { Recipes = AmmoMakingReloadingPress }`, parallel recipes with that tag | press recipes tagged `HandPress` (or another vanilla tag), made at the vanilla station |
| Implementation | one item, one recipe set; all generated | one entity script, one skin entry, sprites, a build recipe or a moveable item, the recipe set | the recipe set only |
| Runtime risk | lowest: everything is a pattern the mod already uses | **highest**: a wrong or contested sprite stops the world from loading; pickup round-trip and the build menu are unverified | low: vanilla's own station |
| Recipe integration | same generator; shows in the surface crafting list beside the hand recipes (two entries per step) | same generator; shows only at the press | same generator; mixed into the clay and oil press list |
| Save persistence | none needed (an item) | engine-side, with the object | engine-side, vanilla's |
| Future multiplayer | vanilla recipe authority, nothing custom | vanilla entity and recipe authority, nothing custom | same as B |
| UI consistency | crafting list grows; "press" is an inventory item, which reads oddly | the vanilla station experience: walk up, open, craft | odd: ammunition at a pottery press |
| Batch crafting | vanilla's | vanilla's | vanilla's |
| Upgrade path | a second, better item | better stations as further tags, as the forges do (`PrimitiveForge;Forge`) | none of its own |
| Feels like a press | no | yes | partly |

## 5. Decision

**B, a placed `CraftBench` entity with its own tag and a parallel, generated
set of faster recipes.** It is the vanilla pattern (§2.1, §2.2), the engine
persists and syncs it, and it leaves the die sets and the material untouched.
C is rejected: no vanilla tag fits, and reusing one puts ammunition in
another station's list. A stays the fallback if B's runtime checks fail: it
needs only an item and the same recipes with `AnySurfaceCraft`.

**It is not implemented in this pass**, for one reason: §2.4. The entity
cannot exist without sprites, and each way of getting them is a decision that
only the game can check and that fails by refusing to load the world:

- new art is the only collision-free choice and is not something this pass
  can produce or look at;
- an unclaimed vanilla sprite works only until vanilla or another mod claims
  it, and a map-placed one would turn existing map objects into presses.

That is exactly the "uncertain world-object engine behaviour" case, so the
world object waits for a session that can run the game.

## 6. What is prepared

In `AC_Calibres.lua`, tested and switched off:

- `AC_Calibres.PRESS`: `enabled = false`, `benchTag =
  "AmmoMakingReloadingPress"`, `timedAction = "UseHandPress"`,
  `timeDivisor = 2`, `minimumTime = 20`, the steps that have a press version
  (case, bullet, assembly; the die set is forged, not pressed).
- `AC_Calibres.buildPressRecipes(calibre)`: each hand recipe of those steps
  with the press tag and timed action, half the time, and **only** the hammer
  line removed. Inputs, the kept die set, outputs, level, XP and quality
  effect are the hand recipe's own.
- `AC_Calibres.validatePress()`: the tag is letters and digits, the divisor a
  whole number, and no press recipe drops below 20. The compatibility check
  reports a problem with it as a WARNING.
- `AC_Calibres.buildRecipes()` appends the press recipes only when
  `PRESS.enabled`; with it off, the recipe script, callbacks, names and
  compatibility lines are exactly as before.

Press times with the divisor 2 (hand → press): pistol and shell case and
projectile 80 → 40, assembly 40 → 20; rifle case 160 → 80, bullet 120 → 60,
assembly 80 → 40.

The tests assert, for every calibre and step: same material in and out, same
output count, same level and XP, the calibre's own die set kept, no hammer,
no other calibre's item, faster than by hand and never below 20; that the
live recipe list and the generated script contain nothing of the press; and
that switching it on adds exactly three recipes per calibre.

## 7. Building the first prototype (next session with the game)

1. Sprites: ship a tile sheet (`pack=` / `tiledef=` in `mod.info`), or pick an
   unclaimed vanilla set and accept its risk.
2. `media/scripts/entities/AC_ReloadingPress.txt`: `entity
   AmmoMaking_ReloadingPress` with `UiConfig`, `CraftBench { Recipes =
   AmmoMakingReloadingPress, }`, `SpriteConfig`, and a build `CraftRecipe`
   (steel bar stock and a few hand tools; a vanilla `SkillRequired`, because
   the Ammo Making perk is registered from Lua after scripts are parsed). Its
   `xuiSkin` entry with a display name and icon.
3. `AC_Calibres.PRESS.enabled = true`; `lua5.1 tests/write_recipes.lua`; 27
   recipe names in `Recipes.json` ("… (Press)"); the entity in the
   compatibility check.
4. In game: see §9.

Later, and independent of the above: a `toolBonus` for cases formed at the
press (`AC_CaseQuality.onCasesFormed` already takes one; a press recipe would
name a second effect), and better presses as further tags.

## 8. Multiplayer

Nothing custom is planned: the entity, its persistence and the recipes are
vanilla systems with vanilla authority. The one thing to check is the XP
grant in `OnCreate`, which is the same open point as for every other recipe
of the mod (`DEVELOPMENT.md`).

## 9. REQUIRES FUTURE IN-GAME VERIFICATION

None of the following can be established offline:

- a mod entity with a new `CraftBench` tag loads on 42.20.4, opens the
  entity window and lists exactly the press recipes;
- the chosen sprites exist, are unclaimed, and sit correctly; claiming them
  does not alter map objects;
- the build recipe appears in the build menu, or the moveable item places the
  station; pickup and re-placing keep the `CraftBench`;
- a press recipe keeps the die set and takes the material of the hand recipe;
- `UseHandPress` animates acceptably at the press;
- a recipe time of 20 feels right and the skill speed-up applies;
- the crafting UI's tag filter copes with a custom tag (JAR
  `BaseCraftingLogic#filterAndSortRecipeList` calls
  `CraftRecipeTag.fromValue`, which throws for an unknown value; whether that
  path is reached for custom tags was not determined).

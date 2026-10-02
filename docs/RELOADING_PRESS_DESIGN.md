# Reloading press: research and design

Status: **DESIGNED. The station is not built.** The press *recipes* are
prepared in the calibre model and switched off; nothing of the press is in
the game's scripts. A second sprite survey (2026-10-02, §2.4) confirmed that
no vanilla sprite can be shown to be a safe placeholder, so the world object
still waits for art and a session with the game.

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

JAR `SpriteConfigManager#parseEntityScript`, and what surrounds it:

- **A sprite may belong to one entity.** The sprites of every parsed entity
  go into `HashSet<IsoSprite> registeredScriptedSprites`; a second entity
  naming one throws `"Sprite '…' is duplicate. entity script: …"`. The
  exception is caught, `hasLoadErrors` is set, and JAR `IsoWorld#init` ends
  with `if (… || SpriteConfigManager.HasLoadErrors()) throw new
  WorldDictionaryException("World loading could not proceed, there are
  script load errors.")`. That operand is unconditional: **no world loads**,
  in debug or not, while two active scripts claim one sprite. FILE: no two
  vanilla entities share a `row` sprite.
- **A name that does not exist is not an error** (corrected on 2026-10-02;
  this document used to say it was). The method does contain `"Sprite '…'
  does not exist"`, but it tests `IsoSpriteManager.instance.getSprite(name)
  == null`, and JAR `IsoSpriteManager#getSprite(String)` is `namedMap
  .containsKey(n) ? namedMap.get(n) : AddSprite(n)`: an unknown name is
  created on the spot, with no tile properties and whatever texture
  `Texture.getSharedTexture(name)` finds, possibly none. INFERRED: a typo in
  a sprite name yields an invisible, property-less station, not a refusal
  to load.
- **Claiming marks the sprite itself**: property `EntityScriptName` and flag
  `IsoFlagType.EntityScript`. JAR `CellLoader#AddObject` /
  `#AddSpecialObject` call `GameEntityFactory.CreateIsoEntityFromCellLoading`
  for map objects; a sprite with that flag gets the claiming entity's
  components. INFERRED: claiming a sprite the map uses turns newly loaded
  map objects with that sprite into the station. For a sprite that also has
  `IsMoveAble` + `CustomItem` the item path is taken instead, with a warning.
- **No tile property is required by the engine.** FILE
  `ISBuildIsoEntity.lua` only reads them to derive behaviour
  (`BlocksPlacement`, `solid`, `solidtrans`, `IsStackable`); vanilla's own
  `crafted_02_40` (Stone Quern) gets `solidtrans` from
  `lua/shared/Util/CustomTileProps.lua` at `OnGameStart`.
- Order of loading, JAR `IsoWorld#init`: vanilla tile definitions, then
  `ZomboidFileSystem.loadModTileDefs()`, then
  `ScriptManager.PostTileDefinitions()`, which parses the entities. A mod's
  own tile sheet is known before its entity is parsed.

Vanilla candidates, from `media/newtiledefinitions.tiles`, the entity
scripts, the texture packs and the map (`*.lotheader`; 4,065 cells scanned).
Artwork was not viewed.

| Sprites | Tile name | Claimed by a vanilla entity | Map cells that use it | Tiles per face | Notes |
|---|---|---|---|---|---|
| `crafted_01_72`, `_73` | Hand Press | **yes**, `Hand_Press` | 7 / 4 | 1 | unusable: a second claim stops the world loading |
| `industry_04_16..19` | Key Duplicator | **yes**, `Key_Duplicator` | 1–8 | 1 | unusable |
| `crafted_05_0..3` | Crude Hand Press | no | 2–5 | **2** | `IsMoveAble`, `solidtrans`; the closest by name |
| `crafted_02_0..3` | Workbench | no | 9–10 | **2** | not moveable |
| `industry_04_20..23` | Bench Grinder | no | 1–8 | 1 | tabletop; `CustomItem = Base.Mov_BenchGrinder`, so map objects take the item path |
| `crafted_04_96..103` | Branch Workbench | no | 1 | **2** | `container = toolcabinet` |
| `location_business_machinery_01_16..23` | Wood Top Workbench | no | 19–120 | **2** | the commonest; `IsTable` |
| `construction_01_6`, `_7`, `_14`, `_15` | Mortar Grinder | no | 3–64 | 1 | `Material = SmallMetalPlates` |
| `location_community_medical_01_64`, `_65` | Tool Bench | no | 6–7 | 1 | two faces only |
| `crafted_03_120..123` | Grindstone | no | 0 | 1 | tile definition exists, **no texture found in any pack** |

Three things the table shows:

1. **Every unclaimed candidate that has a texture is placed on the vanilla
   map.** Not one is both drawable and absent from the map, so claiming any
   of them changes existing map objects.
2. The two that read as a press or a bench by name are **two tiles wide** on
   every face; a single-tile press has no vanilla sprite to borrow.
3. An unclaimed sprite is only unclaimed today. A vanilla update or another
   mod that claims the same one turns a working setup into "no world
   loads".

WORKSHOP CLUE (installed mods, hints only): every installed mod that adds a
station ships its own tile sheet, declared in `mod.info` as `pack=` and
`tiledef=<name> <number>` (a 42.19 ammunition mod's reloading bench, with
`component CraftBench { Recipes = AmmoReloadingBench, }`; a propane cabinet;
tents). One mod claims hundreds of unclaimed vanilla sprites for decorative
buildables, never for a station. No installed mod claims any candidate
above.

The survey was repeated on 2026-10-02 against the same build with the same
result; `tools/pz_compat.py` now reports, after any game update, a tile the
mod uses that has become claimed by an entity or turned into a moveable.

**Verdict: no safe placeholder sprite can be proven from the installed
files.** A vanilla sprite fails on point 1 (map side effects, unverifiable
offline) and point 3 (a hard failure when someone else claims it). The only
collision-free choice is a sprite name of the mod's own, with its own tile
sheet and pack, and that is art plus an in-game check.

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

### 4.1 A portable press in the meantime? Evaluated, and rejected

With the placed press waiting for art, the obvious shortcut is option A as
an intermediate tier: `AmmoMaking.PortableReloadingPress`, a kept tool in
faster `AnySurfaceCraft` recipes that take the same die sets. Three ways to
go, compared:

| | 1. Hand loading only until the placed press exists | 2. A portable press item now | 3. A press kit: a tool now, the build ingredient of the station later |
|---|---|---|---|
| Gameplay now | none new | 15 % to 22 % of a batch's station time saved (`AMMUNITION_DESIGN.md` 9.1) | the same |
| Code | nothing | small: the generator exists; the bench tag becomes `AnySurfaceCraft` and one kept line is added | the same, plus the station's build recipe later |
| Recipe list | 51 manufacturing recipes | **78**: every case, projectile and assembly step twice in the same surface list, told apart only by a suffix | the same until the station exists, then back to one list per place |
| What the item is afterwards | – | either a second, permanent tier (27 recipes for ever, and a number to balance against the station) or an item whose recipes disappear | an item that stops working as a tool the day the station arrives: a tool the player has been using becomes a crate of parts |
| Migration | none | items in saves outlive their recipes unless the tier is kept | no orphan item, but a change of meaning mid-save |
| Unverified engine behaviour added | none | a heavy kept tool: whether it must be carried or may stand nearby, and how 27 more surface recipes read in the crafting window | the same |
| Art | none | an icon (a vanilla one can stand in) | the same |

**Decision: 1.** The time saved is real but modest, and the press's only
advantage is time. Against that: the surface crafting list grows by half
with near-duplicates, the item's meaning has to change or a second tier has
to be carried for ever, and 27 more recipes would be added before a single
ammunition recipe has been seen in game. That is transitional clutter for a
convenience.

It stays cheap to reverse. Everything a tool-based press needs is already
generated and tested (`buildPressRecipes`: same material, same die set,
same XP, the hammer removed); turning it into option 2 is the bench tag and
one kept input line. If the placed station fails its in-game checks, that
is the fallback, as section 5 already says.

## 5. Decision

**B, a placed `CraftBench` entity with its own tag and a parallel, generated
set of faster recipes.** It is the vanilla pattern (§2.1, §2.2), the engine
persists and syncs it, and it leaves the die sets and the material untouched.
C is rejected: no vanilla tag fits, and reusing one puts ammunition in
another station's list. A stays the fallback if B's runtime checks fail: it
needs only an item and the same recipes with `AnySurfaceCraft`.

**It is not implemented**, for one reason: §2.4. The entity cannot exist
without sprites, and no way of getting them can be shown to be safe from the
files:

- new art is the only collision-free choice, and is not something an
  offline pass can produce or look at;
- every drawable unclaimed vanilla sprite is on the map, so claiming it
  alters existing map objects in a way only the game can show, and stops the
  world loading the day vanilla or another mod claims it too.

That is the "uncertain world-object engine behaviour" case, so the world
object waits for a session that can run the game. `PRESS.enabled` stays
`false`; nothing of the press is in the scripts.

## 6. What is prepared

In `AC_Calibres.lua`, tested and switched off:

- `AC_Calibres.PRESS`: `enabled = false`, `benchTag =
  "AmmoMakingReloadingPress"`, `timedAction = "UseHandPress"`,
  `timePercent = 60`, `minimumTime = 20`, the steps that have a press
  version (case, bullet, assembly; the die set is forged, not pressed),
  `nameSuffix = " (Press)"`.
- `AC_Calibres.buildPressRecipes(calibre)`: each hand recipe of those steps
  with the press tag and timed action, 60 % of the time, and **only** the
  hammer line removed. Inputs, the kept die set, outputs, level, XP and
  quality effect are the hand recipe's own.
- `AC_Calibres.validatePress()`: the tag is letters and digits, the
  percentage a whole number from 50 to 90, every step one the press can do,
  and no press recipe below a time of 20. The compatibility check reports a
  problem with it as a WARNING.
- `AC_Calibres.buildRecipes()` appends the press recipes only when
  `PRESS.enabled`; with it off, the recipe script, callbacks, names and
  compatibility lines are exactly as before.

All nine rounds are covered: 27 press recipes (three per calibre), each made
from the live hand recipe, so a calibre added later gets its press recipes
with no further work.

### 6.1 The press's advantage: time, and only time

| | By hand | At the press |
|---|---|---|
| Material in, material out | the recipe's | the same |
| Die set | kept | the same die set, kept |
| Output count | the recipe's | the same: no bonus round |
| Ammo Making level and XP per craft | the recipe's | the same |
| Hammer | needed, wears very lightly | not needed |
| Time | the recipe's | **60 %** |
| Case quality | rolled from skill | the same roll; no bonus |

Times, hand → press: pistol and shell case and projectile 80 → 48, assembly
40 → 24; rifle case 160 → 96, bullet 120 → 72, assembly 80 → 48.

Why 60 % and not the 50 % first pencilled in. Time is the press's whole
advantage, and time is also the rate at which a recipe pays XP. At 50 % the
steps the press covers (about half of a career's XP in the simulation)
would pay twice as fast, and the pistol assembly would sit
exactly on the 20 floor below which the engine's skill speed-up stops
working. At 60 % the press is two fifths faster, every step keeps its
speed-up (24 / 20 is still 1 per level), and there is room to tune in either
direction: `timePercent` may be set anywhere from 50 to 90 and
`validatePress()` refuses anything else. Batches and ergonomics are the
better things to add later; a material or quality bonus would make the
press mandatory rather than convenient, and is not planned.

**With skill the advantage narrows a little, and that was checked.** The
engine shortens a recipe by `time / 20`, whole division, per level above its
requirement (JAR `CraftRecipe#getTime`, no lower bound). A hand time of 80
loses 4 per level; its press time of 48 loses 2, not 2.4. So the press's
share of the hand time rises from 60 % at the unlock level to at most
68.2 % at level 10 (a 9mm case: 30 against 44). The rifle steps start
higher up the ladder and stay below 66 %. No step ever
comes out equal to, or slower than, its hand recipe, and no time reaches
zero. Tuning each step separately would buy two or three points and cost a
table of per-step numbers; one percentage is kept.

**What the press is worth over a whole batch** is in the generated work
table of `AMMUNITION_DESIGN.md` 9.1: furnace, forge, primers and powder are
untouched, so the press saves 15 % to 22 % of a batch's station time (least
for shells, whose hull is quick to form by hand) and raises the XP earned
per unit of station time by about a quarter. It is a convenience.

The tests assert, for every calibre and step: same material in and out, same
output count, same level and XP, the calibre's own die set kept, no hammer,
no other calibre's item, exactly the configured share of the hand time and
never below 20; that the live recipe list and the generated script contain
nothing of the press; that switching it on adds exactly three recipes per
calibre; and that each press recipe's name can be derived from its hand
recipe's and collides with nothing.

## 7. Building the first prototype (next session with the game)

1. **Sprites.** Ship a tile sheet: a `.tiles` definition and a `.pack`,
   declared in `mod.info` (`pack=<name>`, `tiledef=<name> <number>`), with
   sprite names of the mod's own (`ammomaking_press_01_0` …). One tile per
   face is enough (`face S`, `face E`). Tile properties worth setting, from
   the vanilla stations: `BlocksPlacement`, `solidtrans`, and for pickup
   `IsMoveAble`, `PickUpWeight`, `CustomName`.
2. **The entity**, `media/scripts/entities/AC_ReloadingPress.txt`. A draft,
   following `Hand_Press` field for field; **it is not in the mod**:

   ```text
   module Base
   {
       entity AmmoMaking_ReloadingPress
       {
           component UiConfig
           {
               xuiSkin = default,
               entityStyle = ES_AmmoMaking_ReloadingPress,
               uiEnabled = true,
           }
           component CraftBench
           {
               Recipes = AmmoMakingReloadingPress,
           }
           component SpriteConfig
           {
               health = 100,
               skillBaseHealth = 20,
               face S { layer { row = <the mod's sprite, south>, } }
               face E { layer { row = <the mod's sprite, east>, } }
           }
           component CraftRecipe
           {
               timedAction = BuildWallHammer,
               time = 100,
               category = Blacksmithing,
               SkillRequired = MetalWelding:2,
               xpAward = MetalWelding:10,
               inputs
               {
                   item 1 tags[base:hammer] mode:keep flags[Prop1;MayDegradeVeryLight],
                   item 2 [Base.SteelBarHalf],
                   item 4 [Base.Plank],
                   item 8 [Base.Nails],
               }
           }
       }

       xuiSkin default
       {
           entity ES_AmmoMaking_ReloadingPress
           {
               LuaWindowClass = ISEntityWindow,
               DisplayName = Reloading Press,
               Icon = Build_Handpress,
               components
               {
                   CraftLogic
                   {
                       LuaPanelClass = ISCraftDefaultPanel,
                       DisplayName = Press,
                       Icon = Build_Handpress,
                   }
               }
           }
       }
   }
   ```

   The build recipe's skill has to be a vanilla one: the Ammo Making perk is
   registered from Lua after scripts are parsed, and the engine drops an
   unknown skill name. The inputs and the skill are a first guess to be
   balanced; `Base.SteelBarHalf` is in vanilla's metalwork loot. Every key
   above is one JAR `CraftRecipe#Load`, `SpriteConfigScript#load` and
   `CraftBenchScript#load` accept.
3. `AC_Calibres.PRESS.enabled = true`; `lua5.1 tests/write_recipes.lua`; 27
   recipe names in `Recipes.json` (each hand name with " (Press)"); the
   entity in the compatibility check.
4. In game: see §9.

Later, and independent of the above: a `toolBonus` for cases formed at the
press (`AC_CaseQuality.onCasesFormed` already takes one; a press recipe would
name a second effect), and better presses as further tags.

### 7.1 Art specification

For whoever draws the press. Every figure is read from the installed
42.20.4 files; nothing here has been seen in game with a mod tile.

| | Specification | Source |
|---|---|---|
| Footprint | **one tile**. The vanilla Hand Press and Key Duplicator are one tile per face; the two-tile vanilla benches are the wrong shape for a bench-top press | FILE entity scripts, `newtiledefinitions.tiles.txt` |
| Orientations | **two faces: S and E**, as vanilla's `Hand_Press` (`crafted_01_72` S, `crafted_01_73` E). N and W are optional; the entity script takes `face N` / `face W` if they are drawn | FILE `entity_handpress.txt` |
| Canvas per face | **128 x 256 px** at the game's 2x scale (every tile in `Tiles2x.pack` has that full size); a 64 x 128 version for the 1x pack is optional | `Tiles2x.pack` entries, `fullW`, `fullH` |
| The drawing inside it | bottom-anchored on the floor diamond. Vanilla's hand press occupies 110 x 154 px at offset (4, 94) for S and 103 x 141 at (18, 107) for E; a reloading press on a stand should fill about the same box | `Tiles2x.pack` entry of `crafted_01_72`, `_73` |
| Projection and light | the game's 2:1 isometric projection; the floor diamond of a tile is 128 x 64 px at 2x; light from the upper left, as vanilla furniture | vanilla tiles |
| Style | a single-stage bench press on a short wooden stand: cast frame, a long lever, a ram, a die in the top. Muted colours and a dark outline, to sit beside `crafted_01` (the hand-made workshop set) | – |
| Interaction point | none to define: a `CraftBench` entity is used from any adjacent square (`ISContextEntity`) | FILE |
| Tileset | one sheet, **8 columns**, as every vanilla sheet (`size = 8,N`); name `ammomaking_press_01` | FILE `.tiles.txt`: `size = 8,16` |
| Sprite names | `<tileset>_<index>`, index counting across then down from 0: `ammomaking_press_01_0` (S), `ammomaking_press_01_1` (E) | FILE |
| Tile properties | as vanilla's Hand Press: `BlocksPlacement`, `solidtrans`, `Facing = S` / `E`, `CustomName = Press`, `GroupName = Reloading`, `IsMoveAble`, `PickUpWeight = 400` (40 weight; vanilla's own is 400). `solidtrans` blocks movement and lets light and sight through | FILE `// crafted_01_72` |
| Surface | none (`IsTable` / `Surface` not set): nothing is placed on a press | FILE: the Hand Press sets neither |
| Files | `media/ammomaking_press.tiles` (binary: magic `tdef`, version 1) and `media/texturepacks/AmmoMakingPress.pack` (binary: magic `PZPK`, version 1, a PNG page with one entry per sprite) | read from `newtiledefinitions.tiles` and `Tiles2x.pack`; both formats parsed by a script of this pass |
| `mod.info` | `pack=AmmoMakingPress` and `tiledef=ammomaking_press <number>`; the number must be from 100 to 8189 and **not used by another loaded mod's tile sheet** | JAR `ChooseGameInfo`: the range check's constants |
| Bench tag | `AmmoMakingReloadingPress` (`AC_Calibres.PRESS.benchTag`), on the entity's `CraftBench { Recipes = ... }` | section 6 |
| Icon | `Build_Handpress` can stand in for the entity's window icon; a 32 x 32 icon of its own is optional | FILE `scripts/xui/defaultskin/x_entity_hand_press.txt` |

What cannot be specified from files and has to be looked at in game: how
the sprite sits on the tile (the offsets), whether the lever reads at the
game's zoom levels, and the choice of the tile-definition number.

## 8. Multiplayer

Nothing custom is planned: the entity, its persistence and the recipes are
vanilla systems with vanilla authority. The one thing to check is the XP
grant in `OnCreate`, which is the same open point as for every other recipe
of the mod (`DEVELOPMENT.md`).

## 9. REQUIRES FUTURE IN-GAME VERIFICATION

None of the following can be established offline:

- a mod entity with a new `CraftBench` tag loads on 42.20.4, opens the
  entity window and lists exactly the press recipes;
- the mod's tile sheet loads (`pack=`, `tiledef=`), its sprites are drawn
  and sit correctly;
- the build recipe appears in the build menu, or the moveable item places the
  station; pickup and re-placing keep the `CraftBench`;
- a press recipe keeps the die set and takes the material of the hand recipe;
- `UseHandPress` animates acceptably at the press;
- press times of 24 to 96 feel right and the skill speed-up applies;
- the crafting UI's tag filter copes with a custom tag. JAR
  `BaseCraftingLogic#filterAndSortRecipeList` calls
  `CraftRecipeTag.fromValue` only in the `FilterMode.Tags` branch, entered
  when the search text starts with `$`, and passes it the lower-cased
  registered tags; `fromValue` compares with the CamelCase ids and throws
  otherwise. INFERRED: that path would throw for vanilla tags too, so it is
  not a hazard of a mod tag in particular, but it has not been seen;
- an unknown sprite name does not stop the world loading and shows as an
  invisible station (§2.4), so a typo in the tile sheet's names is noticed;
- claiming the mod's own sprites alters no map object.

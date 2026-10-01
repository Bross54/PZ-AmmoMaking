# Vanilla Build 42 metallurgy: M0 research (verified)

Status: **M0 complete on 2026-10-02.** Every line below was read directly from
the installed game at `E:\SteamLibrary\steamapps\common\ProjectZomboid`
(Build 42.20.4, `projectzomboid.jar` dated 2026-09-03), replacing the earlier
wiki-based pass. Nothing here was observed in a running game; what only a
running game can show is listed in §10.

## Evidence levels

| Level | Meaning |
|---|---|
| **FILE** | Read from an installed script, Lua or translation file. Path given, relative to `media/`. |
| **JAR** | Read from `projectzomboid.jar` with `javap -p -c`. Class and method given. |
| **CLUE** | Installed Workshop mods. Used only to see what other mods do, never as proof. |

## 1. The answer in one table

| Metal | Ore step (vanilla) | Next step (vanilla) | Ingot (vanilla) |
|---|---|---|---|
| Copper | `SmeltCopperOre`: 1 `Base.CopperOre` + 4 charcoal → 10 `Base.CopperScrap`, bench tag `PrimitiveFurnace`, no tool, no skill, no XP | `Forge_Small_Copper_Sheet` (1 scrap → 1 small sheet), `Forge_Copper_Sheet` (4 scrap → 1 sheet) at `PrimitiveForge` | `Base.CopperIngot` exists; **no recipe produces or consumes it** |
| Iron | `ExtractIronBloom`: 1 ore + 8 charcoal → 1 bloom (`PrimitiveFurnace`) | bloom → 12 chunks at the forge; chunks/scrap are smelted into a drainable `CeramicCrucible_Iron`, then `CastIronIngot`: 12 crucible uses + 12 charcoal + tongs (keep) + ingot mold (keep) → 1 `Base.IronIngot` (`Furnace`) | `Base.IronIngot` |
| Gold, silver | no ore; scrap is forged into sheets at `PrimitiveForge`; bars are only split, never cast | — | `GoldBar`, `SilverBar` |
| Zinc | **nothing**: `grep -ri zinc media/scripts` returns no file | — | — |
| Brass | `Base.BrassIngot` and `Base.BrassScrap` exist; **no recipe produces or consumes either**. `BrassScrap` is loot (`ProceduralDistributions.lua`, `Distribution_BinJunk.lua`) and the `OnBreak.BrassScrap` result of two weapons | — | `Base.BrassIngot` |

Sources: `scripts/generated/entities/blacksmith/craftRecipes/recipes_blacksmith_furnaces_i.txt`,
`recipes_blacksmith_furnace_ii.txt`, `recipes_blacksmith_other_metals.txt`;
`scripts/generated/items/normal.txt`, `drainable.txt`, `weapon.txt` (FILE).

Consequences, all implemented (see `METALLURGY_DESIGN.md`):

1. Zinc mirrors copper: ore → furnace → 10 scrap.
2. Vanilla copper is not overridden. The mod adds the missing last step for
   both metals, scrap → ingot.
3. `Base.BrassIngot` is reused; there is no `AmmoMaking.BrassIngot`.
4. No ore preparation: vanilla feeds the 40-weight chunk straight into the
   furnace.

One correction to the earlier pass: copper ore **is** obtainable in vanilla.
`lua/shared/TimedActions/ISPickAxeGroundCoverItem.lua` drops `Base.CopperOre`
(one for `copperOreMedium`, two for `copperOreLarge`) when a ground-cover ore
boulder is broken with a pickaxe, with Masonry XP, and
`lua/server/WorldGen/features/ore/copper_ore.lua` places those boulders as
world-generation veins. The mod's mining loop is an additional source, not the
only one.

## 2. Item scripts (FILE: `scripts/generated/items/normal.txt`)

```text
item CopperOre   { Weight = 40.0, Icon = CopperOre, StaticModel = CopperOre, WorldStaticModel = CopperOre,
                   Tags = base:hasmetal;base:heavyitem;base:copperore;base:coppersource,
                   RequiresEquippedBothHands = true }
item IronOre     { Weight = 40.0, Icon = IronOre, StaticModel = IronOre, WorldStaticModel = IronOre,
                   Tags = base:hasmetal;base:heavyitem;base:ironore;base:ironsource,
                   RequiresEquippedBothHands = true }
item CopperScrap { Weight = 0.5, Icon = Copper_Scrap, WorldStaticModel = CopperScrap, Tags = base:hasmetal }
item AluminumScrap { Weight = 0.5, Icon = AluminumScrap, WorldStaticModel = AluminumScrap,
                   Tags = base:hasmetal;base:scrapaluminum }
item BrassScrap  { Weight = 0.5, Icon = BrassScrap, WorldStaticModel = BrassScrap, Tags = base:hasmetal }
item CopperIngot { Weight = 6.0, Icon = Ingot_Copper, StaticModel = CopperIngot, WorldStaticModel = CopperIngot,
                   Tags = base:hasmetal;base:ingot }
item IronIngot   { Weight = 6.0, Icon = Ingot_Iron,   StaticModel = IronIngot,   WorldStaticModel = IronIngot,
                   Tags = base:hasmetal;base:ingot }
item BrassIngot  { Weight = 5.0, Icon = Ingot_Brass,  StaticModel = BrassIngot,  WorldStaticModel = BrassIngot,
                   Tags = base:hasmetal;base:ingot }
item SilverBar   { Weight = 8.0, Icon = Ingot_Silver, StaticModel = SilverBar,   WorldStaticModel = SilverBar }
item CeramicCrucible { Weight = 5.0, component FluidContainer { ContainerName = Crucible, Capacity = 3.0 } }
item ClayIngotMold   { Weight = 0.3, Tags = base:destructible;base:breakonsmithing,
                       Tooltip = Tooltip_item_BreakOnSmithing }
item IronIngotMold, SteelIngotMold { Weight = 6.0 }            (no tags: they do not break)
item Charcoal, CharcoalCrafted, Coke { Tags = base:charcoal;base:isfirefuel }
item Tongs            { Tags = base:tongs;... }
item CrudeWoodenTongs, KitchenTongs { Tags = base:crudetongs;base:breakonsmithing;... }
```

All have `DisplayCategory = Material` and `ItemType = base:normal`. Vanilla
items carry no `DisplayName`; their names come from
`lua/shared/Translate/EN/ItemName.json` with the key `"Base.CopperIngot"`.
`Item.Load` still parses `DisplayName` (JAR: `zombie.scripting.objects.Item`),
and `Translator.getItemNameFromFullType` falls back to the script's display
name when the JSON has no entry (JAR), so a mod item may use either.

Tags are registry ids (`zombie.scripting.objects.ItemTag`, `Registries.ITEM_TAG`).
A mod item may reference the vanilla `base:` tags. New tags would have to be
registered from a mod's `media/registries.lua`, which `ModRegistries.init()`
runs before scripts load (JAR). The mod defines no new tags, so no zinc
equivalent of `base:copperore` / `base:coppersource` exists; no vanilla recipe
or Lua reads those two tags.

## 3. Stations (FILE: `scripts/generated/entities/blacksmith/workstations/`)

| Entity | File | `component CraftBench { Recipes = … }` |
|---|---|---|
| `Base.Primitive_Furnace` | `entity_furnace_i.txt` | `PrimitiveFurnace` |
| `Base.Smelting_Furnace` (Simple Furnace) | `entity_furnace_ii.txt` | `PrimitiveFurnace;Furnace` |
| `Base.Blast_Furnace` (Advanced Furnace) | `entity_furnace_iii.txt` | `PrimitiveFurnace;Furnace;AdvancedFurnace` |
| Primitive / Simple / Advanced Forge | `entity_forge_i/ii/iii.txt` | `PrimitiveForge` / `PrimitiveForge;Forge` / `PrimitiveForge;Forge;AdvancedForge` |

- **Tiers are cumulative**: a higher furnace also hosts the lower tags.
- A recipe attaches to a station only through its `Tags` line. The valid tag
  names are the `CraftRecipeTag` enum (JAR), which includes
  `PRIMITIVE_FURNACE`, `FURNACE`, `ADVANCED_FURNACE`, `PRIMITIVE_FORGE`,
  `FORGE`, `ADVANCED_FORGE`.
- **There is no lit, fuel, heat or temperature state.** The furnace entities
  have exactly four components: `UiConfig`, `CraftBench`, `SpriteConfig`,
  `CraftRecipe` (the build recipe). No `Resources`, no fuel field. Charcoal is
  an ordinary consumed recipe input (`item N tags[base:charcoal]`). Only the
  two glass recipes also take `tags[base:startfire]`; no metal recipe does.

## 4. The vanilla furnace recipes the mod copies (FILE)

```text
craftRecipe SmeltCopperOre                      craftRecipe CastIronIngot
{                                               {
    time = 200,                                     time = 200,
    Tags = PrimitiveFurnace,                        Tags = Furnace,
    category = Blacksmithing,                       category = Blacksmithing,
    inputs                                          inputs
    {                                               {
        item 4 tags[base:charcoal],                     item 12 [Base.CeramicCrucible_Iron;Base.CeramicCrucibleSmall_Iron],
        item 1 [Base.CopperOre],                        item 1 tags[base:crudetongs;base:tongs] mode:keep flags[MayDegradeLight],
    }                                                   item 12 tags[base:charcoal],
    outputs                                             item 1 [Base.ClayIngotMold;Base.IronIngotMold;Base.SteelIngotMold] mode:keep,
    {                                               }
        item 10 Base.CopperScrap,                   outputs
    }                                               {
}                                                       item 1 Base.IronIngot,
                                                    }
                                                }

craftRecipe ExtractIronFromSmallItem   (the "empty crucible as a kept tool" pattern)
{
    time = 200, Tags = PrimitiveFurnace, category = Blacksmithing,
    inputs
    {
        item 1 [Base.CeramicCrucible] mode:keep flags[IsEmpty],
        item 1 tags[base:crudetongs;base:tongs] mode:keep flags[MayDegradeLight],
        item 1 tags[base:charcoal],
        item 1 tags[base:smeltableironsmall] mode:destroy flags[ItemCount;AllowDestroyedItem],
    }
    outputs { item 1 Base.IronChunk, }
}
```

Facts taken from all 36 vanilla furnace recipes (7 `PrimitiveFurnace`, 12
`Furnace`, 17 `AdvancedFurnace`):

- Every furnace recipe has `time = 200`, `category = Blacksmithing` (glass:
  `Glassmaking`, `time = 20`), no `timedAction`, no `SkillRequired`, no
  `xpAward`, no `NeedToBeLearn`. Vanilla smelting is ungated and awards no XP.
- Ore smelting sits on `PrimitiveFurnace`; all casting sits on `Furnace`
  (iron) or `AdvancedFurnace` (steel).
- Tools are `mode:keep`; tongs carry `flags[MayDegradeLight]`; molds are kept
  with no flags.
- The crucible appears two ways: as a kept empty tool
  (`[Base.CeramicCrucible] mode:keep flags[IsEmpty]`), and as the
  iron/steel-only drainable `CeramicCrucible_Iron` / `_Steel`
  (`UseDelta = 0.05`, filled by the Java `RecipeCodeOnCreate.smeltIronOrSteel*`).
  There is no crucible-with-copper item, so the drainable convention cannot be
  reused for other metals without adding three items and a Lua refill
  callback. The mod uses the kept-empty-crucible form.
- Kept items tagged `base:breakonsmithing` (clay molds, crude and kitchen
  tongs) are destroyed when the recipe `isSmithing()`, which is true when the
  recipe involves the Blacksmith perk **or** its category is `Blacksmithing`
  (JAR: `CraftRecipeData`, `CraftRecipe.isSmithing`). The mod's recipes use
  the same category, so they behave like vanilla casting.

## 5. craftRecipe fields (FILE survey of all 921 vanilla recipes; JAR `CraftRecipe.Load`)

Used by vanilla, with counts: `time` 921, `Tags` 921, `category` 888,
`timedAction` 874, `xpAward` 560, `SkillRequired` 458, `NeedToBeLearn` 385,
`AutoLearnAll` 160, `OnCreate` 144, `AutoLearnAny` 126, `AllowBatchCraft` 112,
`MetaRecipe` 72, `Tooltip` 38, `OnTest` 20, `Icon` 4, `ResearchSkillLevel` 2.
`Load` also accepts `OnStart`, `OnUpdate`, `OnFailed`, `OnAddToMenu`,
`CanWalk`, `ResearchAll`, `ResearchAny`, `recipeGroup`.

- Input lines: `item N [Base.A;Base.B]`, `item N tags[base:x;base:y]`,
  `mode:keep` / `mode:destroy`, `flags[...]`. Output lines: `item N Base.X`.
- All 1004 module declarations in the vanilla scripts are `module Base`. `ScriptBucketCollection.getScript`
  (JAR) resolves a name without a dot in module `Base` only.
- Recipe display name: `Translator.getRecipeName(<recipe id>)` (JAR), keys in
  `Translate/EN/Recipes.json` without a module prefix
  (`"SmeltCopperOre": "Smelt Copper Ore"`).
- **Time and skill are linked by the engine** (JAR `CraftRecipe.getTime(character)`,
  used by `ISHandcraftAction:getDuration()` as `getTime(character) * 5`):
  `time - (highestRelevantLevel - highestRequirement) * (time / 20)`, i.e. 5 %
  faster per level above the requirement. "Relevant" skills are the recipe's
  required skills, then its XP-award skills.
- CLUE: of 312 craftRecipe files in installed Workshop mods, 298 are in
  `module Base`; several add recipes with `Furnace` / `Forge` bench tags from
  their own files. None uses a custom perk in `SkillRequired` or `xpAward`.

## 6. Custom perk in a recipe script: does not work as registered today (JAR)

`SkillRequired`, `xpAward`, `AutoLearn*` resolve names with
`PerkFactory.Perks.FromString`, a lookup in `PerkFactory.PerkById`. An unknown
name logs `Unknown skill "%s" in recipe "%s"` and **the entry is dropped**; the
recipe still loads.

Load order in `GameWindow.initShared`: `PerkFactory.init` → `CustomPerks.init`
/ `initLua` (reads `media/perks.txt` from mods) → `ModRegistries.init`
(`media/registries.lua`) → `ScriptManager.Load`. Mod Lua
(`LuaManager.LoadDirBase`) runs later. The mod registers its perk from
`shared/AC_AmmoMakingSkill.lua`, so at script-parse time `AmmoMaking` is
unknown and `xpAward = AmmoMaking:5` would be silently discarded.

Two routes exist. The mod takes the second because it leaves the perk
registration that is confirmed working in game untouched:

1. Move the perk to `media/perks.txt` (`CustomPerks`), after which script
   fields work. Changes a confirmed system; not done.
2. Keep the Lua perk. Award XP from the recipe's `OnCreate`, and add the
   requirement after Lua has loaded with the public
   `CraftRecipe.addRequiredSkill(Perk, int)` (JAR), which also makes the
   engine's own time scaling use the Ammo Making level.

## 7. OnCreate (JAR + FILE)

- Script value is a global function path: `OnCreate = RecipeCodeOnCreate.x`
  (a Java class exposed to Lua, 146 uses), `Fishing.onCreateFish`,
  `BuildRecipeCode.barricade` (Lua tables). `CraftRecipeData.initLuaFunctions`
  resolves it with `LuaManager.getFunctionObject` when the recipe is first
  used, long after mod Lua has loaded.
- Call: `luaCallOnCreate(character)` → `protectedCallVoid(func, craftRecipeData, character)`.
  Signature **`(craftRecipeData, character)`**.
- Called from `lua/shared/Entity/TimedActions/ISHandcraftAction.lua`
  `performRecipe()`, once per completed craft, after the outputs were added
  and before the consumed items are processed. `complete()` runs
  `performRecipe()` on the server in multiplayer.
- `craftRecipeData:getAllCreatedItems()`, `getAllConsumedItems()`,
  `getAllKeepInputItems()`, `getRecipe()` exist.
- Side effect to know about: when a craft creates exactly **one** item,
  `performRecipe()` writes the consumed items' full types and counts into that
  item's ModData. Vanilla does this for its own ingots too.

## 8. What this settles

| Question from the design | Answer |
|---|---|
| Ore preparation | None. Follow vanilla: ore straight into the furnace. |
| Furnace tags | Ore smelting `PrimitiveFurnace`; casting and alloying `Furnace`. |
| Lit / fuel state | Does not exist. Charcoal is an input. |
| Crucible | Kept empty tool. No per-metal crucible items. |
| Mold | Kept; clay breaks through the vanilla `breakonsmithing` rule. |
| Timed action | None, as vanilla furnace recipes. |
| Skill fields in script | Not usable for the Lua-registered perk; see §6. |
| Time lever | Vanilla's own, once the requirement is attached. |
| Quality | Deferred. `OnCreate` + ModData is available when wanted. |
| Module | Recipes in `module Base` with an `AmmoMaking_` id prefix, like vanilla and most mods; items stay in `module AmmoMaking`. |

## 9. Loop check (FILE)

Every vanilla recipe that mentions the metals involved:

| Item | Produced by | Consumed by |
|---|---|---|
| `Base.CopperOre` | pickaxe on ore boulders (Lua), the mod's mining | `SmeltCopperOre` |
| `Base.CopperScrap` | `SmeltCopperOre` (10), `Scrap_Small_Copper` (1), `Scrap_Large_Copper` (4) | `Forge_Small_Copper_Sheet`, `Forge_Copper_Sheet` |
| `Base.CopperIngot` | nothing | nothing |
| `Base.BrassIngot` | nothing | nothing |
| `Base.BrassScrap` | loot, `OnBreak` | nothing |

No vanilla recipe turns an ingot, a sheet or brass back into scrap, so the
mod's scrap → ingot → brass chain cannot be closed into a loop by vanilla.

## 10. REQUIRES FUTURE IN-GAME VERIFICATION

Offline evidence is strong for all of these; none has been seen running.

- The four mod recipes appear in the crafting UI of a Simple Furnace (and
  "Smelt Zinc Ore" at a Primitive Furnace), consume and produce as written.
- `OnCreate = AC_Materials.on…` resolves and the XP line is logged.
- `CraftRecipe:addRequiredSkill` is callable from Lua and the recipe then
  shows an Ammo Making requirement of 0 and gets faster with level.
- `Recipes.json` and `ItemName.json` in the mod's `common/` translation folder
  are loaded.
- The vanilla world models and icons reused for zinc look acceptable.
- Clay molds and crude tongs break as they do for vanilla casting.

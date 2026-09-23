# Vanilla Build 42 metallurgy: M0 research

Status: M0 partially completed from accessible sources on 2026-09-23. Nothing
below has been checked against an installed Build 42.20 copy of the game.
Section 9 lists the PowerShell commands that finish M0 locally.

## Evidence levels used here

| Level | Meaning |
|---|---|
| **CONFIRMED** | Directly supported by Build 42.20 game or script evidence in hand. In this pass that is only this repository itself. |
| **STRONG INDICATION** | Supported by more than one Build 42 source, including PZwiki pages that quote the vanilla script block verbatim with its source path and "Retrieved: Build 42.20.0". A single local grep promotes each of these to CONFIRMED. |
| **UNVERIFIED** | Not established by any source found; must be checked against the local installation. |

Sources were reached through a text proxy because the wiki itself blocks this
environment. Page versions are noted where the wiki states them, since several
station pages were last revised for 42.12.3.

## 1. Answer to the most important question

**Does vanilla already provide ore → furnace → ingot?** Not directly.

The vanilla pattern for the two ores that exist is **ore → furnace → scrap or
bloom**, then further steps at a forge. There is no vanilla recipe that turns
copper ore, copper scrap, or anything else into `Base.CopperIngot`. The ingot
item exists in the scripts but nothing crafts it or uses it.

| Metal | Ore step (vanilla) | Next step (vanilla) | Ingot (vanilla) | Level |
|---|---|---|---|---|
| Copper | `Base.CopperOre` ×1 + charcoal-tag ×4 → `Base.CopperScrap` ×10 at the Primitive Furnace, recipe "Smelt Copper Ore", no tool, no skill, 0 XP | `Base.CopperScrap` ×4 (or 4 small sheets) + charcoal ×1 + hammer + tongs → Copper Sheet at the Primitive Forge; `CopperScrap` ×1 (or 10 electrical wire) → Small Copper Sheet | `Base.CopperIngot` exists (Weight 6.0, tags `base:hasmetal;base:ingot`), **no recipe produces or consumes it** | STRONG INDICATION |
| Iron | `Base.IronOre` ×1 + charcoal ×8 → `Base.IronBloom` ×1 at the Primitive Furnace | bloom + charcoal ×18 + hammer + tongs → Iron Chunk ×12 at the Primitive Forge; chunks and scrap are melted into a crucible ("Crucible with Iron", counted in units) and cast with an ingot mold: "Cast Iron Ingot" = crucible with 12 units of iron + charcoal ×12 + tongs (keep) + Ceramic / Iron / Steel Ingot Mold, at the Simple Furnace → `Base.IronIngot` ×1 | `Base.IronIngot` (Weight 6.0, tags `base:hasmetal;base:ingot`) | STRONG INDICATION |
| Gold, silver | No ore. Gold and silver scrap (tags `goldscrap`, `silverscrap`) is melted at a furnace; `Base.GoldBar` (16.0) and `Base.SilverBar` (8.0, icon `Ingot_Silver`) are the bar items; "Split Gold Bar" at the Primitive Forge makes `Base.SmallGoldBar` | — | as left | STRONG INDICATION |
| Zinc | **Nothing.** No zinc ore, scrap or ingot page exists on the wiki; the only "Make Zinc Ingot" recipe found anywhere is Hydrocraft for Build 41 (item `HCZincingot`) | — | — | STRONG INDICATION |
| Brass | **`Base.BrassIngot` and `Base.BrassScrap` exist in `normal.txt` (42.20.0)** with no recipe producing or consuming either | — | `Base.BrassIngot` Weight 5.0, icon `Ingot_Brass`, tags `base:hasmetal;base:ingot`; `Base.BrassScrap` Weight 0.5, icon `BrassScrap`, tags `base:hasmetal` | STRONG INDICATION |

Consequences for AmmoMaking:

1. **Imitate the copper pattern for zinc**: `AmmoMaking.ZincOre` → furnace →
   `AmmoMaking.ZincScrap` ×10, mirroring "Smelt Copper Ore" exactly.
2. **Do not override vanilla copper.** Leave "Smelt Copper Ore" alone. Add
   the missing last step for both metals: scrap → ingot, using vanilla's own
   casting convention (charcoal, crucible, tongs, ingot mold at a furnace).
3. **Use `Base.BrassIngot`.** Do not create `AmmoMaking.BrassIngot`. Vanilla
   reserved the item; the mod supplies the recipe. `Base.BrassScrap` is the
   natural recycling output later.
4. Copper ore is not obtainable in vanilla outside debug (community sources,
   STRONG INDICATION). The mod's mining loop is therefore the only supply, which
   is what the design wants.

## 2. Item scripts (verbatim quotes, PZwiki, `media/scripts/normal.txt`, Retrieved 42.20.0)

All STRONG INDICATION until grepped locally.

```text
item CopperOre
{
    DisplayCategory = Material,
    ItemType = base:normal,
    Weight = 40.0,
    Icon = CopperOre,
    StaticModel = CopperOre,
    WorldStaticModel = CopperOre,
    Tags = base:hasmetal;base:heavyitem;base:copperore;base:coppersource,
    RequiresEquippedBothHands = true,
}

item CopperScrap
{
    DisplayCategory = Material,
    ItemType = base:normal,
    Weight = 0.5,
    Icon = Copper_Scrap,
    WorldStaticModel = CopperScrap,
    Tags = base:hasmetal,
}

item CopperIngot
{
    DisplayCategory = Material,
    ItemType = base:normal,
    Weight = 6.0,
    Icon = Ingot_Copper,
    StaticModel = CopperIngot,
    WorldStaticModel = CopperIngot,
    Tags = base:hasmetal;base:ingot,
}

item BrassIngot
{
    DisplayCategory = Material,
    ItemType = base:normal,
    Weight = 5.0,
    Icon = Ingot_Brass,
    StaticModel = BrassIngot,
    WorldStaticModel = BrassIngot,
    Tags = base:hasmetal;base:ingot,
}

item BrassScrap
{
    DisplayCategory = Material,
    ItemType = base:normal,
    Weight = 0.5,
    Icon = BrassScrap,
    WorldStaticModel = BrassScrap,
    Tags = base:hasmetal,
}

item IronOre        -- Weight 40.0, Tags = base:hasmetal;base:heavyitem;base:ironore;base:ironsource, RequiresEquippedBothHands = true
item IronBloom      -- Weight 20.0, Tags = base:hasmetal;base:heavyitem;base:ironsource, RequiresEquippedBothHands = true
item IronIngot      -- Weight 6.0,  Icon = Ingot_Iron,   Tags = base:hasmetal;base:ingot
item GoldBar        -- Weight 16.0, Icon = Ingot_Gold,   Tags = base:ignorezombiedensity;base:hasmetal
item SmallGoldBar   -- Weight 2.0,  Icon = Ingot_Gold
item SilverBar      -- Weight 8.0,  Icon = Ingot_Silver, Tags = base:ignorezombiedensity;base:hasmetal
item SmallCopperSheet -- Weight 0.5, Icon = Sheet_Copper_Small, MetalValue = 20.0
item CeramicCrucible  -- Weight 5.0, Icon = Ceramic_Crucible_Fired, component FluidContainer { ContainerName = Crucible, Capacity = 3.0, ... }
item ClayIngotMold    -- Weight 0.3, Icon = CeramicCast_Bar_Fired, Tags = base:destructible;base:breakonsmithing, Tooltip = Tooltip_item_BreakOnSmithing
```

Tag facts worth copying for zinc: ores carry `base:heavyitem`, a
`base:<metal>ore` tag and a `base:<metal>source` tag, and
`RequiresEquippedBothHands = true`; ingots carry `base:ingot`; every metal item
carries `base:hasmetal`.

The charcoal tag (`charcoal`) is satisfied by `Base.CharcoalCrafted` (Wood
Charcoal), `Base.Coke` and `Base.Charcoal` (PZwiki tag page, revised for
42.20.0). Vanilla furnace recipes take charcoal as an ordinary consumed input.

## 3. Stations

| Station | Sprites (wiki) | Built from | Notes | Level |
|---|---|---|---|---|
| Primitive Furnace | `crafted_01_112`, `crafted_01_113` | Clay ×6, Stone ×4, concrete-tag bucket ×1; needs Magazine: Iron Age Blacksmithing | hosts "Smelt Copper Ore", "Extract Iron Bloom", "Smelt Iron From … Item" (crucible + tongs as tools) | STRONG INDICATION (page revised 42.12.3) |
| Simple Furnace ("Furnace") | `crafted_01_16`, `crafted_01_33` | Stone Block ×40, concrete ×1 (+ Medieval Blacksmithing magazine per guides) | adds casting: "Cast Iron Bar", "Cast Iron Ingot", "Cast Blacksmith Anvil", "Melt Glass" | STRONG INDICATION |
| Advanced Furnace | `crafted_02_11`, `crafted_02_9`, `crafted_03_8`, `crafted_03_10`, `crafted_02_17`, `crafted_02_18` | as Simple + Large Bellows | adds steel (coke + limestone) | STRONG INDICATION |
| Primitive / Simple / Advanced Forge | `crafted_01_61`, `_20`, `_21`, `_62` for primitive | stone + anvil + concrete; simple/advanced need a Blacksmith Anvil (cast at a Simple Furnace) | forging, not smelting; copper sheets are made here | STRONG INDICATION |
| Charcoal Burning Pile / Barrel, Kilns, Pottery, Grindstone, Hand Press | — | — | full vanilla workstation list: Advanced Forge, Advanced Furnace, Advanced Kiln, Charcoal Burning Barrel, Charcoal Burning Pile, Dome Kiln, Grindstone, Hand Press, Pottery Bench, Pottery Wheel, Primitive Forge, Primitive Furnace, Primitive Kiln, Simple Forge, Simple Furnace | STRONG INDICATION |

Wiki tables show every furnace recipe with **Skills: none, XP: 0**. Vanilla
smelting is not gated on Blacksmithing and awards no Blacksmithing XP. Forging
recipes show "Blacksmithing 0" and are researchable.

**Entity ids and CraftBench tags of the furnace tiers: UNVERIFIED.** The wiki
does not print the entity scripts. See §5 and §9.

**Whether a furnace must be lit: UNVERIFIED.** No source found describes a
lighting step; guides talk about charcoal being consumed by recipes, and the
recipe tables list charcoal as an input. The Charcoal Burning Pile is "left
click to open its UI", i.e. it is a crafting UI, not a fire. The
`component Resources` block exists on entities but its documentation is empty.

## 4. The craftRecipe block (PZ API Documentation 42.20.4 and PZwiki)

STRONG INDICATION for everything in this section (two independent modding
sources, the API docs versioned 42.20.4).

- A recipe is `module X { craftRecipe <ID> { … } }`. The ID may not contain
  spaces. `inputs` is required.
- Display name: entry `"<ID>": "Name"` in `Recipes.json` under
  `media/lua/shared/Translate/<LANG>/`. No module prefix in the key. Tooltip:
  `Tooltip = <key>` with the key in `Tooltip.json`. Category:
  `category = X` with `"IGUI_CraftingCategories_X"` in `IG_UI.json`. (This is
  the same JSON translation layout the mod already uses for `IG_UI.json`.)
- Parameters: `time` (integer, default 50, unit unspecified, "refer to vanilla
  recipes"), `timedAction` (a `timedAction` script block, for animation, sound,
  calories), `Tags` (required; at least one crafting-bench tag), `category`,
  `SkillRequired = Skill:level[;…]`, `xpAward = Skill:xp[;…]`,
  `AutoLearnAll` / `AutoLearnAny = Skill:level`, `NeedToBeLearn`,
  `ResearchSkillLevel` / `ResearchAll` / `ResearchAny`, `AllowBatchCraft`
  (default true; shows a batch slider), `CanWalk`, `MetaRecipe`, `Icon`,
  `OnCreate`, `OnTest`, `OnFailed`, `OnUpdate`, `OnAddToMenu`.
- Skills: "You can find the available skills in PerkFactory.Perks.
  Alternatively, you can also use modded skills defined by your mod or other
  mods." → `SkillRequired = AmmoMaking:n` and `xpAward = AmmoMaking:x` should
  work with the perk registered in `AC_AmmoMakingSkill.lua`. Still UNVERIFIED
  in game.
- Inputs: `item <n> [Base.A;Base.B]`, `item <n> tags[tagA;tagB]`,
  `mode:keep` for tools (default `destroy`), `flags[...]` such as
  `MayDegradeLight`, `Prop1`, `Prop2`, `AllowDestroyedItem`. Every line ends
  with a comma; no comma after the closing brace.
- Outputs: `item <n> Base.X,` or `item <n> mapper:<id>`.
- Fluids: `-fluid 0.2 [Water;TaintedWater]` and `+fluid 0.2 Coffee` inside
  `inputs`; the wiki flags this page as possibly outdated.
- Tags list (crafting benches, from the wiki page revised 42.20.2):
  `AnySurfaceCraft`, `InHandCraft`, `CanBeDoneFromFloor`, `CoffeeMachine`,
  `Forge`, `Furnace`, `Grindstone`, `HandPress`, `Heckling`, `KeyDuplicator`,
  `KilnLarge`, `KilnSmall`, `PotteryBench`, `PotteryWheel`, `Rippling`,
  `Scutching`, `StandingDrillPress`, `Toaster`. Activity tags include
  `Smithing`. Other tags: `CanAlwaysBeResearched`, `CanBeDoneInDark`,
  `RightClickOnly`. "The crafting bench tag is mandatory for the recipe to be
  recognized."
- Station attachment: "A crafting bench tag can be created by adding a
  `component CraftBench` to an entity script, which can then be used in this
  tags parameter." The `CraftBench` component's `Recipes` parameter is "the tag
  name for this crafting bench". So a mod recipe attaches to vanilla furnaces
  by carrying the furnace's bench tag; the recipe file does not name the
  station. `Furnace` is the tag the wiki lists. **Which tag each tier
  declares, and whether tiers use extra tags, is UNVERIFIED** (§9, command 5).
- Modifying vanilla recipes from Lua is limited (wiki: "very limited … often
  requires tricks"). Not needed: the mod only adds recipes.

Vanilla example the mod should model its recipes on (PZ API docs):

```text
craftRecipe SawLogs
{
    timedAction = SawLogs,
    Time = 230,
    Tags = InHandCraft;CanBeDoneFromFloor,
    category = Carpentry,
    xpAward = Woodwork:5,
    inputs
    {
        item 1 [Base.Log] flags[Prop2],
        item 1 tags[Saw] mode:keep flags[MayDegradeLight;Prop1],
    }
    outputs
    {
        item 3 Base.Plank,
    }
}
```

## 5. Callbacks and ModData on outputs

- `OnCreate = <GlobalTable.function>` is called when the recipe finishes with
  `(craftRecipeData, character)`. `craftRecipeData:getAllConsumedItems()` and
  `craftRecipeData:getAllCreatedItems()` return the item lists; the vanilla
  example (`media/lua/server/recipecode.lua`, retrieved 42.5.1) sets fields on
  the created item and calls `result:syncItemFields()`, then adds an item with
  `sendAddItemToContainer`. STRONG INDICATION (API docs 42.20.4 + wiki).
- The wiki notes that in 42.10.0 the OnCreate parameter "was changed from a
  single thumpable object to a table" for **entity build** recipes; the item
  recipe signature above is the one the 42.20.4 API docs show. UNVERIFIED which
  applies to a `module` recipe on 42.20; command 8 below finds vanilla
  examples.
- Vanilla puts its OnCreate functions in `media/lua/server/recipecode.lua`,
  which means they run where the crafting completes. Whether that is the
  server in multiplayer and whether ModData written there replicates to the
  client: UNVERIFIED.
- Setting ModData on a created item is ordinary Lua (`item:getModData()`), so
  brass quality via OnCreate is **feasible**; reliability across inventory
  grouping and multiplayer is UNVERIFIED. Given the owner's decision, brass
  quality stays deferred unless commands 8 and 9 make this trivial.

## 6. What this settles for the design

| Question | Answer | Level |
|---|---|---|
| Ore preparation (crushing) | Not needed. Vanilla's preparation is the furnace itself: ore → scrap. The 40-weight chunk is carried two-handed to the furnace, exactly as iron ore is. | STRONG INDICATION |
| Copper path | Keep vanilla "Smelt Copper Ore" (ore → 10 scrap). Add "Cast Copper Ingot": scrap ×10 + charcoal + crucible (keep) + ingot mold (keep) + tongs (keep) → `Base.CopperIngot` ×1, `Tags = Furnace`. | design |
| Zinc path | `AmmoMaking.ZincOre` (copy CopperOre: 40.0, heavyitem, both hands, tags `zincore;zincsource`) → "Smelt Zinc Ore" (charcoal ×4) → `AmmoMaking.ZincScrap` ×10 (copy CopperScrap) → "Cast Zinc Ingot" → `AmmoMaking.ZincIngot` (copy CopperIngot: 6.0, `hasmetal;ingot`). | design |
| Brass | 7 `Base.CopperIngot` + 3 `AmmoMaking.ZincIngot` + charcoal + crucible + mold + tongs → 10 `Base.BrassIngot`. Reuse the vanilla item. | design |
| Station | Vanilla furnace via bench tag; tier tag(s) from command 5. | UNVERIFIED which tag |
| Skill | `SkillRequired = AmmoMaking:…`, `xpAward = AmmoMaking:…`. Vanilla smelting has no Blacksmith gate, so none is added. | STRONG INDICATION |
| Quality | Deferred; OnCreate exists if wanted later. | — |
| Multiplayer | Nothing custom persists. | — |

Conservation check with vanilla numbers: 1 ore (40.0) → 10 scrap (5.0 total)
→ 1 ingot (6.0). One chunk, one ingot. Vanilla's own copper branch (4 scrap →
1 sheet) never returns scrap from an ingot, so no loop exists.

## 7. Weight recommendation for zinc (from §2)

| Item | Now | Recommended |
|---|---|---|
| `AmmoMaking.ZincOre` | 0.5 | 40.0, `RequiresEquippedBothHands = true`, `Tags = base:hasmetal;base:heavyitem;base:zincore;base:zincsource` |
| `AmmoMaking.ZincScrap` (new) | — | 0.5, `Tags = base:hasmetal` |
| `AmmoMaking.ZincIngot` | 1.0 | 6.0, `Tags = base:hasmetal;base:ingot`, icon `Ingot_Silver` until a zinc icon exists |
| `AmmoMaking.BrassIngot` (planned) | — | **removed**: use `Base.BrassIngot` |

`base:` prefixed tags are how 42.20.0 writes them; whether a mod item may use
the `base:` prefix or must write `Tags = hasmetal;ingot` is UNVERIFIED
(command 2 shows both forms if both exist).

## 8. Open items that only the local files answer

| # | Item | Why it matters |
|---|---|---|
| U1 | Entity ids of Primitive / Simple / Advanced Furnace and their `component CraftBench { Recipes = … }` tag names | decides the `Tags` line of every mod recipe and whether "Cast" recipes should require the Simple tier like vanilla casting |
| U2 | Whether any recipe or entity field expresses "must be lit / fuelled" | decides whether the player has to do anything besides having charcoal |
| U3 | Exact `craftRecipe` blocks of "Smelt Copper Ore", "Extract Iron Bloom", "Cast Iron Ingot", "Forge Copper Sheet" | the mod's recipes copy their field set, `time`, `timedAction`, tags and tool flags verbatim |
| U4 | How "Crucible with Iron … units" is represented (fluid, drainable, separate item) | decides whether zinc/brass casting can reuse the crucible-with-metal convention or must consume scrap directly |
| U5 | The `timedAction` block names vanilla smelting uses | reuse for animation and sound |
| U6 | `OnCreate` signature and location on 42.20 for module recipes, and one vanilla example that sets item data | brass quality later, and any "AmmoMaking XP from Lua" fallback |
| U7 | Whether `SkillRequired` / `xpAward` accept `AmmoMaking` | otherwise gate nothing and award XP via OnCreate |
| U8 | Tag prefix form for mod items (`base:` or bare) | zinc item tags |
| U9 | Translation file names for recipes and tooltips on 42.20 (`Recipes.json`, `Tooltip.json`) | mod translation files |
| U10 | Whether copper ore appears in any loot or foraging table | confirms mining is the only source |

## 9. Local verification commands (PowerShell)

Run in PowerShell from any folder. Each command is independent. Output goes to
`$env:USERPROFILE\Desktop\pz_metallurgy\` so it can be pasted back here.

```powershell
$pz  = "E:\SteamLibrary\steamapps\common\ProjectZomboid"
$out = "$env:USERPROFILE\Desktop\pz_metallurgy"
New-Item -ItemType Directory -Force -Path $out | Out-Null
$scripts = Join-Path $pz "media\scripts"
$lua     = Join-Path $pz "media\lua"
Get-Content (Join-Path $pz "steam_appid.txt") -ErrorAction SilentlyContinue
Get-ChildItem $pz -Filter "*.txt" | Where-Object Name -match "version|build" | ForEach-Object { $_.FullName; Get-Content $_.FullName }
```

1. Items: copper ore, copper scrap, copper ingot, brass, zinc (should be absent), molds, crucible.

```powershell
Get-ChildItem $scripts -Recurse -Include *.txt |
  Select-String -Pattern '^\s*item\s+(CopperOre|CopperScrap|CopperIngot|BrassIngot|BrassScrap|IronOre|IronBloom|IronIngot|GoldBar|SilverBar|CeramicCrucible|ClayIngotMold|IronIngotMold|SteelIngotMold|Charcoal|CharcoalCrafted|Coke)\b' -Context 0,14 |
  Tee-Object -FilePath "$out\1_items.txt"
Get-ChildItem $scripts -Recurse -Include *.txt | Select-String -Pattern 'Zinc' -CaseSensitive:$false | Tee-Object -FilePath "$out\1b_zinc.txt"
```

2. Every place the copper, brass and ingot items or tags are referenced (recipes that consume or produce them; tag prefix form).

```powershell
Get-ChildItem $scripts -Recurse -Include *.txt |
  Select-String -Pattern 'CopperOre|CopperScrap|CopperIngot|BrassIngot|BrassScrap|copperore|coppersource|base:ingot|\bingot\b' -Context 3,3 |
  Tee-Object -FilePath "$out\2_copper_brass_refs.txt"
```

3. Furnace recipes: every craftRecipe whose tags mention a furnace or forge, with the whole block.

```powershell
Get-ChildItem $scripts -Recurse -Include *.txt |
  Select-String -Pattern 'craftRecipe\s+(SmeltCopperOre|ExtractIronBloom|CastIronIngot|CastIronBar|ForgeCopperSheet|SmeltIron\w*|Smelt\w*|Cast\w*|Melt\w*)' -Context 0,40 |
  Tee-Object -FilePath "$out\3_furnace_recipes.txt"
Get-ChildItem $scripts -Recurse -Include *.txt |
  Select-String -Pattern '^\s*[Tt]ags\s*=\s*.*(Furnace|Forge|Kiln)' -Context 25,0 |
  Tee-Object -FilePath "$out\3b_recipes_by_bench_tag.txt"
```

4. Gold, silver, iron processing recipes (pattern reference for zinc).

```powershell
Get-ChildItem $scripts -Recurse -Include *.txt |
  Select-String -Pattern 'goldscrap|silverscrap|GoldBar|SilverBar|IronBloom|IronChunk|ironsource' -Context 20,20 |
  Tee-Object -FilePath "$out\4_gold_silver_iron.txt"
```

5. Station entities: ids, CraftBench tags per tier, fuel or lit fields, sprite names.

```powershell
Get-ChildItem $scripts -Recurse -Include *.txt |
  Select-String -Pattern '^\s*entity\s+\S*(Furnace|Forge|Kiln|Charcoal)\S*' -Context 0,80 |
  Tee-Object -FilePath "$out\5_station_entities.txt"
Get-ChildItem $scripts -Recurse -Include *.txt |
  Select-String -Pattern 'component\s+CraftBench' -Context 3,8 |
  Tee-Object -FilePath "$out\5b_craftbench_tags.txt"
Get-ChildItem $scripts -Recurse -Include *.txt |
  Select-String -Pattern 'crafted_01_112|crafted_01_16\b|crafted_02_11\b' -Context 30,10 |
  Tee-Object -FilePath "$out\5c_furnace_by_sprite.txt"
```

6. Fuel, heat and lit requirements anywhere in scripts or Lua.

```powershell
Get-ChildItem $scripts -Recurse -Include *.txt |
  Select-String -Pattern 'IsLit|isLit|Lit\s*=|Fuel|fuel|Heat|heat|Temperature|component\s+Resources|component\s+Energy|energy' |
  Where-Object { $_.Path -match 'entit|workstation|furnace|forge|kiln' } |
  Tee-Object -FilePath "$out\6_fuel_heat_scripts.txt"
Get-ChildItem $lua -Recurse -Include *.lua |
  Select-String -Pattern 'Furnace|Forge' |
  Where-Object { $_.Line -match 'lit|Lit|fuel|Fuel|burn|Burn|heat|Heat' } |
  Tee-Object -FilePath "$out\6b_fuel_heat_lua.txt"
```

7. craftRecipe syntax survey: every distinct field name used by vanilla recipes, plus skill and XP lines.

```powershell
Get-ChildItem $scripts -Recurse -Include *.txt |
  Select-String -Pattern '^\s*(time|Time|timedAction|Tags|tags|category|SkillRequired|skillRequired|xpAward|XpAward|AutoLearnAll|AutoLearnAny|NeedToBeLearn|needTobeLearn|AllowBatchCraft|OnCreate|OnTest|OnFailed|OnUpdate|OnAddToMenu|Tooltip|MetaRecipe|ResearchSkillLevel)\s*=' |
  ForEach-Object { ($_.Line -replace '^\s*','') -replace '\s*=.*$','' } |
  Group-Object | Sort-Object Count -Descending | Format-Table Count,Name -AutoSize |
  Tee-Object -FilePath "$out\7_craftrecipe_fields.txt"
Get-ChildItem $scripts -Recurse -Include *.txt |
  Select-String -Pattern '^\s*(SkillRequired|xpAward)\s*=.*Blacksmith' -Context 12,0 |
  Select-Object -First 5 | Tee-Object -FilePath "$out\7b_skill_xp_examples.txt"
```

8. Creation callbacks: every OnCreate used by a module recipe and the Lua functions behind them.

```powershell
Get-ChildItem $scripts -Recurse -Include *.txt |
  Select-String -Pattern '^\s*OnCreate\s*=' -Context 6,0 |
  Tee-Object -FilePath "$out\8_oncreate_recipes.txt"
Get-ChildItem $lua -Recurse -Include *.lua |
  Select-String -Pattern 'function\s+Recipe\.OnCreate\.|getAllCreatedItems|getAllConsumedItems|craftRecipeData' -Context 2,12 |
  Tee-Object -FilePath "$out\8b_oncreate_lua.txt"
Get-ChildItem $lua -Recurse -Include *.lua |
  Select-String -Pattern 'getModData\(\)' |
  Where-Object { $_.Path -match 'recipecode' } |
  Tee-Object -FilePath "$out\8c_oncreate_moddata.txt"
```

9. Multiplayer side of crafting: where recipe completion and item creation run.

```powershell
Get-ChildItem $lua -Recurse -Include *.lua |
  Select-String -Pattern 'isClient\(\)|isServer\(\)|sendClientCommand|sendServerCommand' |
  Where-Object { $_.Path -match 'recipe|Craft|craft' } |
  Tee-Object -FilePath "$out\9_crafting_multiplayer.txt"
```

10. Translation conventions for recipe names, tooltips and categories.

```powershell
Get-ChildItem (Join-Path $lua "shared\Translate\EN") -Recurse -File |
  Select-Object Name, Length | Tee-Object -FilePath "$out\10_translate_files.txt"
Get-ChildItem (Join-Path $lua "shared\Translate\EN") -Recurse -Include *.json,*.txt |
  Select-String -Pattern 'SmeltCopperOre|ExtractIronBloom|CastIronIngot|IGUI_CraftingCategories_' |
  Tee-Object -FilePath "$out\10b_recipe_translations.txt"
```

11. Timed actions used by smelting recipes.

```powershell
Get-ChildItem $scripts -Recurse -Include *.txt |
  Select-String -Pattern '^\s*timedAction\s*=' -Context 0,0 |
  Where-Object { $_.Line -match 'Smelt|Forge|Cast|Melt|Furnace' } |
  Tee-Object -FilePath "$out\11_timed_actions.txt"
Get-ChildItem $scripts -Recurse -Include *.txt |
  Select-String -Pattern '^\s*timedAction\s+\S*(Smelt|Forge|Cast|Melt|Furnace)\S*' -Context 0,15 |
  Tee-Object -FilePath "$out\11b_timed_action_blocks.txt"
```

12. Copper ore in loot or foraging distributions.

```powershell
Get-ChildItem $lua -Recurse -Include *.lua |
  Select-String -Pattern 'CopperOre' |
  Tee-Object -FilePath "$out\12_copperore_distributions.txt"
```

13. One-shot bundle of the raw script files most likely to hold everything above, for reading in full.

```powershell
Get-ChildItem $scripts -Recurse -Include *.txt |
  Where-Object { $_.Name -match 'blacksmith|smith|metal|furnace|forge|entit|workstation|normal' } |
  Select-Object FullName, Length | Tee-Object -FilePath "$out\13_candidate_files.txt"
```

When the outputs are back, fill the table in §8 and update `METALLURGY_DESIGN.md` §3.

## 10. Sources

- PZwiki pages (retrieved through a text proxy on 2026-09-23): Copper Ore,
  Copper Scrap, Copper Ingot, Brass Ingot, Brass Scrap, Iron Ore, Iron Bloom,
  Iron Chunk, Iron Ingot, Workable Iron, Gold Ingot, Small Gold Ingot, Silver
  Ingot, Copper Sheet - Small, Crucible, Large Ceramic Crucible, Ceramic Ingot
  Mold, Charcoal, charcoal (tag), Primitive Furnace, Simple Furnace, Advanced
  Furnace, Primitive Forge, Charcoal Burning Pile, Category:Workstations,
  Blacksmithing, craftRecipe (scripts), OnCreate (craftRecipe), Tags
  (craftRecipe), inputs (scripts), outputs (scripts), Fluids (craftRecipe),
  fluid (scripts).
- PZ API Documentation 42.20.4 (pz-wiki-modding.github.io/PZ-API-Docs):
  craftRecipe, entity, component CraftBench, component Resources.
- Community guides used only for corroboration of station tiers and materials:
  pzfans.com metalworking overhaul (states 42.20.4), build42guide.wiki
  blacksmithing, gamers.wiki steel feedstock guide (states 42.20.2).
- undeniable.info "Make Zinc Ingot": Hydrocraft, Build 41 (used only to rule
  zinc out of vanilla).
- The Indie Stone translations repository (`master` branch `ItemName_EN.txt`,
  `Recipes_EN.txt`): contains no copper, zinc or brass item names, so that
  branch is not the Build 42 branch and was not used as evidence.

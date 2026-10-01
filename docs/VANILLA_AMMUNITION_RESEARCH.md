# Vanilla Build 42 ammunition: research for component manufacturing

Status: read on 2026-10-02 from the installed game at
`E:\SteamLibrary\steamapps\common\ProjectZomboid` (Build 42.20.4). Paths are
relative to `media/`. Nothing here was observed in a running game.

Evidence levels as in `VANILLA_METALLURGY_RESEARCH.md`: **FILE** (installed
script / Lua / translation), **JAR** (`projectzomboid.jar`, `javap -p -c`).

"None" below means the item ids in `scripts/generated/items/*.txt`, every
script file, `lua/` and `Translate/EN/ItemName.json` were searched for the
words listed and nothing matched.

## 1. Finished ammunition

FILE: `scripts/generated/items/normal.txt`, `weapon.txt`.

| Round | Name | Weight | `count` | Box / carton | Weapon `AmmoType` |
|---|---|---|---|---|---|
| `Base.Bullets9mm` | 9x19mm Round | 0.02 | 5 | `Bullets9mmBox` (50) / `Bullets9mmCarton` | `base:bullets_9mm` |
| `Base.Bullets45` | .45 ACP Round | 0.025 | 5 | `Bullets45Box` (50) | `base:bullets_45` |
| `Base.Bullets38` | .38 Special Round | 0.015 | 5 | `Bullets38Box` (50) | `base:bullets_38` |
| `Base.Bullets357` | .357 Magnum Round | 0.02 | 5 | `Bullets357Box` (50) | `base:bullets_357` |
| `Base.Bullets44` | .44 Magnum Round | 0.03 | 3 | `Bullets44Box` (20) | `base:bullets_44` |
| `Base.308Bullets` | 7.62x51mm Round | 0.04 | 5 | `308Box` (20) | `base:bullets_308` |
| `Base.556Bullets` | 5.56x45mm Round | 0.035 | 5 | `556Box` (20) | `base:bullets_556` |
| `Base.3030Bullets` | .30-30 Round | 0.05 | 5 | `3030Box` (20) | `base:bullets_3030` |
| `Base.ShotgunShells` | 12g Round | 0.06 | 6 | `ShotgunShellsBox` (25) | `base:shotgun_shells` |

- All: `DisplayCategory = Ammo`, `ItemType = base:normal`, `Tags = base:ammo`,
  `MetalValue = 1.0`. **One item is one cartridge.** A box is a separate item
  that `OpenBoxOfBullets50` turns into 50 loose rounds.
- The 9 mm pistol: `item Pistol { AmmoType = base:bullets_9mm, MagazineType =
  Base.9mmClip, AmmoBox = Base.Bullets9mmBox }`; `item 9mmClip { AmmoType =
  base:bullets_9mm, MaxAmmo = 15 }`. `AmmoType` is a registry id
  (`Registries.AMMO_TYPE`, JAR), so a mod calibre would need
  `media/registries.lua`. Producing the vanilla round avoids all of that.
- **The `count` field does not multiply recipe outputs.** The classes that
  both use the item script and call a `getCount` are `ItemContainer`,
  `ItemPickerJava`, `IsoGridSquare`, `IsoTrap`, `ItemUser`, `InventoryItem`
  and a few non-inventory ones; none is in the crafting packages
  (`CraftRecipeData`, `OutputScript`, `CraftRecipe` do not reference it) (JAR).
  It is why loot and `inventory:AddItem("Base.Bullets9mm")` give five rounds;
  `item 1 Base.Bullets9mm` in a recipe gives one. This matches
  `OpenBoxOfBullets50`, which outputs `item 50` for a 50-round box.

## 1a. Pistol calibres and the firearms that use them

FILE: `scripts/generated/items/weapon.txt`, `normal.txt`,
`Translate/EN/ItemName.json`; extracted with a script over every `item` block
that has an `AmmoType`, re-run on 2026-10-02.

| Calibre | Round | Weight | `count` | Box (rounds) | Firearms (`AmmoType`) | Magazine | Capacity | Damage |
|---|---|---|---|---|---|---|---|---|
| 9 mm | `Base.Bullets9mm` | 0.02 | 5 | `Bullets9mmBox` (50) | `Base.Pistol` (M9 Pistol) | `Base.9mmClip` | 15 | 0.6–1.0 |
| .38 Special | `Base.Bullets38` | 0.015 | 5 | `Bullets38Box` (50) | `Base.Revolver_Short` (SN38 Revolver) | none | 5 | 0.5–0.8 |
| .45 ACP | `Base.Bullets45` | 0.025 | 5 | `Bullets45Box` (50) | `Base.Pistol2` (M1911 Pistol), `Base.TrapperCarbine` | `Base.45Clip` (both) | 7 | 0.9–1.2, 1.0–1.4 |
| .357 Magnum | `Base.Bullets357` | 0.02 | 5 | `Bullets357Box` (50) | `Base.Revolver` (Patrol Revolver), `Base.L92_Carbine` | none | 6, 10 | 0.95–1.4, 1.0–1.6 |
| .44 Magnum | `Base.Bullets44` | 0.03 | 3 | `Bullets44Box` (20) | `Base.Pistol3` (B-F Pistol), `Base.Revolver_Long` (Magnum) | `Base.44Clip` (pistol only) | 8, 6 | 1.0–1.6 |

- Every round: `DisplayCategory = Ammo`, `ItemType = base:normal`,
  `Tags = base:ammo`, `MetalValue = 1.0`, and a carton item
  (`…Carton`, opened by `OpenCarton12`). **One item is one cartridge** for
  all five; `count` (5, or 3 for .44) is a loot / `AddItem` multiplier only
  (§1).
- `AmmoType` values are the ten constants of `zombie.scripting.objects.AmmoType`
  (JAR): `bullets_9mm`, `bullets_38`, `bullets_45`, `bullets_357`,
  `bullets_44`, `bullets_308`, `bullets_556`, `bullets_3030`,
  `shotgun_shells`, `cap_gun_cap`. Each maps to its round through
  `AmmoType.getItemKey()`.
- **Magazines** (`Tags = base:pistolmagazine`): `9mmClip` (15), `45Clip` (7,
  `GunType = Base.Pistol2;Base.TrapperCarbine`), `44Clip` (8). They are
  filled from loose rounds; there is nothing calibre-specific beyond
  `AmmoType` and `MaxAmmo`.
- **Revolvers and the lever carbine** have no `MagazineType`; rounds go in
  one at a time. Revolvers carry `ManuallyRemoveSpentRounds = true`, which is
  an unloading animation step, not an item: no casing is produced.
- .357 firearms do **not** accept .38 Special: a firearm has exactly one
  `AmmoType`.
- **Loading turns items into a number.**
  `lua/shared/TimedActions/ISReloadWeaponAction.lua` looks the round up by
  `ammoType:getItemKey()`, removes the items and calls
  `gun:setCurrentAmmoCount(gun:getCurrentAmmoCount() + 1)`; magazines are
  filled the same way (`ISInventoryPaneContextMenu.transferBullets`). A
  firearm or magazine holds a count, not items, so **any ModData on a round
  is gone once it is loaded.** This settles the earlier open question
  without the game: per-round quality cannot reach the moment of firing
  through item ModData.

## 2. Ammunition recipes

FILE: `scripts/generated/recipes/recipes_ammunition.txt` (the whole file).

| Recipe | What it does |
|---|---|
| `GatherGunpowder` | 1 `tags[base:ammo] mode:destroy` + pliers (kept) → `item 1 Base.GunPowder flags[HasOneUse]`. `AnySurfaceCraft`, `timedAction = Making`, `time = 30`, `category = Packing` |
| `OpenBoxOfBullets50` / `20`, `OpenBoxOfShotgunShells` | box → loose rounds |
| `place_ammo_in_box` | loose rounds → box |

**No vanilla recipe makes a round**, and dismantling one yields exactly one
use of gunpowder and nothing else.

## 3. Cartridge components

| Component | Vanilla | Searched for |
|---|---|---|
| Cartridge case | **none** | casing, case (as ammunition), shell, hull, brass |
| Spent brass | **none**; firing leaves no item. "casing" occurs in Lua only in `ISRackFirearm.lua` / `ISReloadWeaponAction.lua`, not as an item | casing, spent |
| Primer | **none** | primer, percussion, cap, detonator, blasting, fulminate |
| Bullet / projectile | **none**. `Base.SteelSlug` is a steel bar offcut (`base:steelmaterial`), `Base.Slug` an animal | bullet, slug, projectile, pellet, shot |
| Lead | **none** as a material. `Base.LeadPipe` is a weapon and no recipe takes it apart | lead, sinker, weight |
| Propellant | `Base.GunPowder` (§4) | powder, propellant |

The "Reloading" perk and the Reloading books are about loading firearms faster,
not handloading.

## 4. Gunpowder and its ingredients

FILE: `items/drainable.txt`, `recipes/recipes_traps.txt`,
`lua/shared/Foraging/Categories/Trash.lua`.

- `Base.GunPowder`: `ItemType = base:drainable`, `UseDelta = 0.1` (10 uses),
  Weight 0.5, icon `GunpowderJar`. Sources: `GatherGunpowder`, and foraging
  (it is listed in the Trash foraging category). It is in no loot
  distribution.
- Consumers: `MakePipeBomb` (`item 20 [Base.GunPowder]`), `MakeFirecracker`
  (`item 1 [Base.GunPowder]`).
- **An input line of a drainable counts uses, not items** (JAR:
  `InputScript.isUsesPartialItem`: true for `ItemType.DRAINABLE` unless the
  line is `mode:keep`, `mode:destroy` or carries `flags[ItemCount]`). So
  `item 1 [Base.GunPowder]` is one use, the amount one dismantled round gives.
- A drainable output is a full item unless it carries `flags[HasOneUse]` or
  `HasNoUses` (JAR: `OutputFlag`).

Raw materials a powder recipe could use:

| Resource | Vanilla | Notes |
|---|---|---|
| Charcoal | `Base.Charcoal` (loot), `Base.CharcoalCrafted` (made at the charcoal pit / burner, so renewable), `Base.Coke`; all `base:charcoal` | already the fuel of every furnace recipe |
| Sulfur | **none** | sulfur, sulphur |
| Nitrate | **no item by that name** (nitrate, saltpeter, potassium, niter). The nearest vanilla things: `Base.Fertilizer` (`base:drainable`, `UseDelta = 0.125` = 8 uses, tag `base:fertilizer`, 18 distribution entries) and `Base.Coldpack`, which vanilla itself uses as the reactive ingredient of `MakeSmokeBomb` | |
| Other chemistry | fluids `Bleach`, `Acid`, `RubbingAlcohol`, `CleaningLiquid`; `Base.CompostBag`; animal dung items. No chemistry station, no chemistry recipes | |
| Grinding tool | `Base.MortarPestle`, `Base.CeramicMortarandPestle` (craftable pottery), both `base:mortarpestle`. Used kept in `MakeAerosolBomb` (`flags[MayDegradeLight]`), the gas-mask filter recipes (with charcoal) and the poultices | |
| Measuring | `Base.Calipers`, `Base.Funnel`, `Mov_ScaleMedical` (furniture). No recipe uses a scale | |

So vanilla has two of black powder's three ingredients in gameplay form
(charcoal, and fertilizer as the nitrate stand-in), a grinding tool, and no
sulfur.

## 5. Explosives (how vanilla abstracts energetic materials)

FILE: `recipes/recipes_traps.txt`. All `NeedToBeLearn = true`, no skill.

| Recipe | Energetic input |
|---|---|
| `MakePipeBomb` | 20 uses of `Base.GunPowder` |
| `MakeFirecracker` | 1 use of `Base.GunPowder` |
| `MakeAerosolBomb` | `Base.Sparklers` + aluminium, mortar and pestle kept |
| `MakeSmokeBomb` | `Base.Coldpack` + newspaper |
| `MakeFlameBomb` | 1.0 petrol |

Vanilla's convention is a household item standing in for a chemical, ground
or mixed with simple tools on a surface. A primer or powder recipe in that
style fits the game; a chemistry simulation would not.

## 6. Primer-like items

| Item | Definition | Availability |
|---|---|---|
| `Base.CapGunCap` | toy cap, Weight 0.005, icon `SnapCap`, `DisplayCategory = Memento`. Ammunition of the toy cap guns (`AmmoType = base:cap_gun_cap`) | loose and as `Base.CapGunCapBox` (100 caps, `OpenBox100`) in two toy-themed distribution lists |
| `Base.Matches`, `Base.Matchbox` | drainables, 10 and 50 uses, `base:startfire` | 42 and 25 distribution entries: common |
| `Base.MagnesiumShavings`, `Base.Sparklers` | fire tinder; aerosol bomb ingredient | loot |

Toy caps are an impact-sensitive charge in a cup, which is what a primer is;
match heads are the other classic improvised priming compound. Both are real
loot, neither requires dismantling ammunition.

## 7. Metal-forming conventions to copy

Hot, at a forge (`entities/blacksmith/craftRecipes/`):

```text
craftRecipe Forge_Small_Metalworking_Punch_Set      (the template for a small tool set)
{
    time = 300, SkillRequired = Blacksmith:5, NeedToBeLearn = true,
    timedAction = HammerMetalStanding, xpAward = Blacksmith:45,
    Tags = Forge, category = Tools,
    inputs
    {
        item 2 tags[base:charcoal],
        item 2 [Base.SteelBarQuarter],
        item 1 tags[base:ballpeenhammer] mode:keep flags[MayDegradeLight],
        item 1 tags[base:metalworkingpliers;base:tongs] mode:keep flags[MayDegradeLight],
        item 1 tags[base:whetstone;base:file] mode:keep flags[MayDegradeLight],
    }
    outputs { item 1 Base.SmallPunchSet, }
}
```

`Base.SmallPunchSet`: `DisplayCategory = Tool`, Weight 1.0, icon
`Punches_Forged`, models `MetalworkingPunch` / `SmallMetalworkingPunches`,
`ConditionMax = 8`. `Base.SteelBarQuarter` (0.5) comes from vanilla bar-stock
recipes. `Forge_Copper_Sheet` (sheets) is quoted in the previous version of
this file and in `AC_Recipes.txt`.

Cold, on any surface: `Tags = AnySurfaceCraft`, `category = Metalworking`,
tools `tags[base:metalworkingpunch;base:smallpunch] mode:keep
flags[MayDegradeLight]` and `tags[base:hammer] mode:keep
flags[MayDegradeVeryLight]`, `timedAction = MakingHammer_Surface`
(`NailSpikeWeapon`); `timedAction = Making` for hand assembly
(`GatherGunpowder`, `MakeFirecracker`).

Crafting categories that exist (`IGUI_CraftingCategories_*`): Assembly, Armor,
Blade, Blacksmithing, Carpentry, Carving, Cooking, Cookware, Electrical,
Farming, Fishing, Furniture, Glassmaking, Knapping, Masonry, Medical,
Metalworking, Miscellaneous, Outdoors, Packing, Pottery, Repair, Tailoring,
Tools, Weaponry, Welding. There is no ammunition category.

Stations: `StandingDrillPress`, `MetalBandsaw`, `Grindstone` exist as bench
tags; `HandPress` is a pottery brick press. **Vanilla has no reloading press,
die or bench**, so `AnySurfaceCraft` with a hand tool is the available
convention.

## 8. Callbacks

`craftRecipeData:getAllCreatedItems()` and `getAllConsumedItems()` exist with
no-argument overloads returning `ArrayList<InventoryItem>` (JAR). Vanilla Lua
calls `getAllConsumedItems()` on the recipe data in
`ISHandcraftAction:performRecipe`, right after `luaCallOnCreate` and before
`processDestroyAndUsedItems`, so consumed items are still readable inside
`OnCreate`. `performRecipe` itself writes ModData onto a single crafted
output, so ModData on crafted items is something vanilla does.

## 9. Consequences for the design

1. Cases, primers and bullets must be mod items; powder is vanilla's item.
2. The product is the vanilla round, one item per cartridge.
3. No lead exists: the first bullet is copper, from metal the mod already
   mines. No lead geology.
4. Primer: brass cup plus a loot priming charge (toy caps or match heads).
5. Powder: charcoal plus fertilizer, ground with a mortar and pestle, into
   vanilla `Base.GunPowder`. No sulfur item is invented.
6. One use of gunpowder per pistol round, the same amount vanilla returns
   when a round is dismantled, so dismantle-and-reassemble can never gain
   powder.
7. Tools: a die set per calibre, forged like vanilla's small punch set.

## 9a. Powder charges

`InputScript` reads an item line's amount back as a whole number of items or
uses (`getIntAmount`, JAR), and vanilla never writes a fractional one (the
only decimal forms in the scripts are whole values such as `item 5.0`). A charge
is therefore a whole number of uses of `Base.GunPowder`: one for a standard
pistol round, more for a magnum. No custom powder item is needed.

Batch crafting: `CraftRecipe.allowBatchCraft` is initialised to `true` in the
constructor (JAR) and 111 of 921 vanilla recipes turn it off, so every mod
recipe gets vanilla's batch slider without a field.

## 10. REQUIRES FUTURE IN-GAME VERIFICATION

- A recipe output of `item 1 Base.Bullets9mm` yields one round (JAR evidence
  says so).
- A recipe line `item 1 [Base.GunPowder]` takes one use from a jar, and
  `item 2 [Base.Fertilizer]` two uses from a bag.
- `item 20 [Base.Matches;Base.Matchbox]` draws uses across several items.
- The hammering and `Making` animations suit the component recipes.

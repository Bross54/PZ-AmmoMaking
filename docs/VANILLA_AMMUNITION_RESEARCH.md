# Vanilla Build 42 ammunition: research for component manufacturing

Status: read on 2026-10-02 from the installed game at
`E:\SteamLibrary\steamapps\common\ProjectZomboid` (Build 42.20.4). Paths are
relative to `media/`. Nothing here was observed in a running game.

Evidence levels as in `VANILLA_METALLURGY_RESEARCH.md`: **FILE** (installed
script / Lua / translation), **JAR** (`projectzomboid.jar`).

## 1. What vanilla has

### Finished ammunition (FILE: `scripts/generated/items/normal.txt`)

| Item | Name | Weight | `count` | Weapon `AmmoType` |
|---|---|---|---|---|
| `Base.Bullets9mm` | 9x19mm Round | 0.02 | 5 | `base:bullets_9mm` |
| `Base.Bullets45` | .45 ACP Round | 0.025 | 5 | `base:bullets_45` |
| `Base.Bullets38` | .38 Special Round | 0.015 | 5 | `base:bullets_38` |
| `Base.Bullets357` | .357 Magnum Round | 0.02 | 5 | `base:bullets_357` |
| `Base.Bullets44` | .44 Magnum Round | 0.03 | 3 | `base:bullets_44` |
| `Base.308Bullets` | 7.62x51mm Round | 0.04 | 5 | `base:bullets_308` |
| `Base.556Bullets` | 5.56x45mm Round | 0.035 | 5 | `base:bullets_556` |
| `Base.3030Bullets` | .30-30 Round | 0.05 | 5 | `base:bullets_3030` |
| `Base.ShotgunShells` | 12g Round | 0.06 | 6 | `base:shotgun_shells` |

All are `DisplayCategory = Ammo`, `ItemType = base:normal`, `Tags = base:ammo`
(shells also `base:shotgunshell`), `MetalValue = 1.0`. Each has a box and a
carton item. Weapons name their ammunition through `AmmoType = base:bullets_…`,
a registry id (`Registries.AMMO_TYPE`, JAR); a new calibre would have to be
registered from `media/registries.lua`. **The mod should produce the vanilla
round items**, so every vanilla firearm accepts them unchanged.

### Recipes (FILE: `scripts/generated/recipes/recipes_ammunition.txt`, the whole file)

| Recipe | What it does |
|---|---|
| `GatherGunpowder` | 1 `tags[base:ammo]` + pliers (kept) → `Base.GunPowder` with one use. `AnySurfaceCraft`, `timedAction = Making`, `time = 30` |
| `OpenBoxOfBullets50` / `20`, `OpenBoxOfShotgunShells` | box → loose rounds |
| `place_ammo_in_box` | loose rounds → box |

That is all. **Vanilla has no recipe that makes a round.**

### Components

| Component | Vanilla | Evidence |
|---|---|---|
| Powder | `Base.GunPowder`: `ItemType = base:drainable`, `UseDelta = 0.1` (10 uses), Weight 0.5, icon `GunpowderJar` | `items/drainable.txt` |
| Powder consumers | `MakePipeBomb` (`item 20 [Base.GunPowder]` = 20 uses), `MakeFirecracker` (1 use) | `recipes/recipes_traps.txt` |
| Cartridge case | **none**. No item, tag or translation contains "casing" or an empty case | grep of `scripts/`, `ItemName.json` |
| Spent brass | **none**. Firing leaves no item; "casing" appears in Lua only in `ISRackFirearm.lua` / `ISReloadWeaponAction.lua`, not as an item id | grep of `lua/` |
| Primer | **none** | grep |
| Bullet / projectile | **none** | grep |
| Lead | **none** as a material (`Base.LeadPipe` is a weapon) | grep |
| Brass | `Base.BrassIngot`, `Base.BrassScrap`; no vanilla recipe consumes them | metallurgy research §9 |

So of the four cartridge components, vanilla provides one (powder, and only by
dismantling existing rounds). Cases, primers and projectiles are the mod's to
define.

## 2. Metal-forming conventions the component recipes can copy (FILE)

Vanilla shapes non-ferrous metal in two ways.

**Hot, at a forge** (`entities/blacksmith/craftRecipes/recipes_blacksmith_other_metals.txt`):

```text
craftRecipe Forge_Copper_Sheet
{
    time = 200,
    SkillRequired = Blacksmith:0,
    timedAction = HammerMetalStanding,
    Tags = PrimitiveForge,
    category = Blacksmithing,
    inputs
    {
        item 1 tags[base:charcoal],
        item 4 [Base.CopperScrap;Base.SmallCopperSheet],
        item 1 tags[base:hammer;base:clubhammer] mode:keep flags[Prop1;MayDegradeLight],
        item 1 tags[base:tongs;base:metalworkingpliers] mode:keep flags[Prop2;MayDegradeLight],
    }
    outputs { item 1 Base.CopperSheet, }
}
```

`Forge_Small_Copper_Sheet` is the same with 1 scrap → 1 `Base.SmallCopperSheet`
(Weight 0.5, icon `Sheet_Copper_Small`, world model `SmallCopperSheet`).
`Forge_Gold_Sheets` turns one small bar into 4 sheets. Products are then made
from sheets (`Forge_Cup`: 1 small sheet → 1 cup, `Forge` tag, Blacksmith 3).

**Cold, on any surface** (`recipes/recipes_metalWelding_Armor.txt`,
`recipes_improvised_weapons.txt`, `recipes_blacksmith_other_metals.txt`):

```text
Tags = AnySurfaceCraft, category = Metalworking
item 1 tags[base:metalworkingpunch;base:drillmetal] mode:keep flags[MayDegradeLight],
item 1 tags[base:hammer] mode:keep flags[MayDegradeVeryLight],
item 1 tags[base:sheetmetalsnips;base:metalsaw] mode:keep flags[MayDegradeLight],
```

`timedAction = MakingHammer_Surface` is what vanilla uses for hammer work on a
surface (`NailSpikeWeapon`, with the hammer line above); `SawSmallItemMetal`
for sawing a sheet into small sheets (`time = 100`).

Tool items: `Base.MetalworkingPunch` (`base:metalworkingpunch`),
`Base.SmallPunchSet` (`base:smallpunch`), `Base.Hammer`, `Base.BallPeenHammer`,
`Base.SmithingHammer` (all `base:hammer`), `Base.Tongs`.

Other stations that exist and may matter later: `StandingDrillPress`,
`MetalBandsaw`, `Grindstone` bench tags. `HandPress` is a pottery brick press,
not a reloading press. **Vanilla has no press, die or reloading bench.**

## 3. What this means for the design

1. Cases, primers and projectiles need mod items. Powder is vanilla's.
2. The assembled product should be the vanilla round item of the calibre.
3. Brass can be brought to a workable form with vanilla stations and tools
   only: forge it into small sheets, punch cups from the sheets cold.
4. Turning a cup into a case of a specific calibre needs dies and some kind
   of press, neither of which vanilla has. That is the first step that
   requires new tools or a station, and so an owner decision.
5. A recipe may consume a number of uses of a drainable (`item 20
   [Base.GunPowder]`), which is how a powder charge can be expressed later.
6. Vanilla firearms eject no brass, so reloading spent cases needs a hook
   into firing; that is far from the first milestone.

## 4. REQUIRES FUTURE IN-GAME VERIFICATION

- What the item field `count` does when a recipe outputs a round (whether
  `item 1 Base.Bullets9mm` yields 1 or 5). To be checked before the assembly
  stage; nothing in the first milestone outputs ammunition.
- That `MakingHammer_Surface` looks right for punching.

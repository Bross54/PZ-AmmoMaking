# Ammunition components: from brass to cartridges

Status: **milestone C1 (brass stock and case cups) is implemented,
offline-verified only. C2 onward is design.** Nothing in this document has
been run in the game.

Vanilla facts used here are in `docs/VANILLA_AMMUNITION_RESEARCH.md`.

## 1. Goal and scope

Continue the chain after `Base.BrassIngot`:

```text
brass ingot → case → + primer + powder + bullet → cartridge → inspection
```

This is a component chain, not a reloading simulator. Each milestone adds the
fewest items and recipes that make one more component real, on vanilla
stations wherever vanilla has one.

Rules carried over from metallurgy:

- vanilla items, stations, tools and recipe patterns first;
- the finished product is the **vanilla round** (`Base.Bullets9mm`, …), so
  vanilla firearms need no change;
- Ammo Making is the only skill; it changes time and later quality, never the
  amount of metal;
- every recipe is mirrored in `AC_Materials.RECIPES` and covered by the
  conservation tests;
- no custom world object until a step cannot be done without one.

## 2. The minimum useful chain

| # | Milestone | Station (vanilla unless noted) | New items | Status |
|---|---|---|---|---|
| C1 | Brass ingot → small brass sheets → case cups | Primitive Forge; any surface | `SmallBrassSheet`, `BrassCaseCup` | **implemented** |
| C2 | Cup → empty case of one calibre (9 mm first) | needs dies and a press: **owner decision** (§5) | one case item per calibre, dies | design |
| C3 | Bullet (projectile) | furnace casting with a bullet mold | bullet per calibre, a bullet mold, a lead source or copper bullets | design |
| C4 | Primer | — | primer item; chemistry is out of scope, so likely loot / dismantling first | design |
| C5 | Assembly: case + primer + powder + bullet → vanilla round | the C2 press | none | design |
| C6 | Quality: `casingQuality` etc. onto the assembled round | Lua on `OnCreate` | none | design; the `AmmoQuality` prototype already defines the fields |

Powder is `Base.GunPowder` (vanilla, 10 uses per jar; a recipe can consume a
number of uses). Its only vanilla source is dismantling rounds, so a powder
source is an open question for C5, not for C1–C3.

C1 is the only part that needs nothing new from the engine or the owner:
vanilla forge, vanilla hand tools, two items.

## 3. C1 as implemented

```text
Base.BrassIngot
      │ Forge Small Brass Sheets
      │ 1 ingot + 1 charcoal; hammer and tongs kept
      ▼ Primitive Forge (or better)
10 AmmoMaking.SmallBrassSheet
      │ Punch Brass Case Cups
      │ 1 small sheet; metalworking punch and hammer kept
      ▼ any surface
2 AmmoMaking.BrassCaseCup          (20 cups per ingot)
```

| Recipe id (display name) | Tags | Consumed | Kept | Output | XP |
|---|---|---|---|---|---|
| `AmmoMaking_ForgeSmallBrassSheets` (Forge Small Brass Sheets) | `PrimitiveForge`, `timedAction = HammerMetalStanding`, `category = Blacksmithing`, `time = 200` | 1 `Base.BrassIngot`, 1 charcoal | `tags[base:hammer;base:clubhammer]`, `tags[base:tongs;base:metalworkingpliers]` | 10 `AmmoMaking.SmallBrassSheet` | 5 |
| `AmmoMaking_PunchBrassCaseCups` (Punch Brass Case Cups) | `AnySurfaceCraft`, `timedAction = MakingHammer_Surface`, `category = Metalworking`, `time = 100` | 1 `AmmoMaking.SmallBrassSheet` | `tags[base:metalworkingpunch;base:smallpunch]`, `tags[base:hammer]` | 2 `AmmoMaking.BrassCaseCup` | 1 |

Vanilla templates: the first is `Forge_Copper_Sheet` (same tags, tools, flags,
timed action, charcoal; `SkillRequired = Blacksmith:0` left out); the second
uses the cold-work tool lines of the scrap-armour recipes and the timed action
and hammer line of `NailSpikeWeapon`.

| Item | Copies | Definition |
|---|---|---|
| `AmmoMaking.SmallBrassSheet` | `Base.SmallCopperSheet` | Weight 0.5, `base:hasmetal`; icon `Sheet_Copper_Small`, world model `SmallCopperSheet` (placeholders) |
| `AmmoMaking.BrassCaseCup` | — | Weight 0.05, `base:hasmetal`; icon and world model `BrassScrap` (placeholders). One cup becomes one case in C2; it is calibre-neutral |

Metal accounting (`AC_Materials.UNITS`, 100 units per ingot): small sheet 10,
cup 5. Both recipes come out even: 100 → 10 × 10, 10 → 2 × 5.

The cup is deliberately not a case. A case has a calibre, a primer pocket and
a quality; a cup has none of them, so C1 needs no metadata and no decision
about calibres.

**Balance, not tuned:** 20 cups per ingot means ten ore make 200 cases. By
mass a real ingot would make far more; the number is one line in the script
and its mirror.

Skill: the same two mechanisms as metallurgy. XP from `OnCreate`; the Ammo
Making requirement (level 0) attached at boot so the engine's time scaling
uses the skill.

## 4. C2–C6 in outline

**C2, cases.** `AmmoMaking.Case9mm` first; the mod's test cartridge and
quality prototype are already 9 mm. One recipe: 1 cup → 1 case, kept die set,
at a press. Case quality is rolled here from the Ammo Making level and written
to the case's ModData in `OnCreate` (`craftRecipeData:getAllCreatedItems()`,
confirmed in the jar). Further calibres are one item, one die set and one
recipe each, added only when the assembly stage can use them.

**C3, bullets.** Vanilla has no lead. Two conservative options: cast copper
bullets from `Base.CopperScrap` with a bullet mold at a furnace (uses only
metals the mod already has), or add lead as a third ore. The first needs no
new geology and is recommended for the first version.

**C4, primers.** Making primer compound is chemistry the game has no
conventions for. First version: primers are found, or recovered by
dismantling vanilla rounds with a mod recipe next to vanilla
`GatherGunpowder`.

**C5, assembly.** One recipe per calibre: case + primer + bullet + powder
uses → the vanilla round. Check first what the item field `count` does to a
recipe output (research §4).

**C6, quality.** The assembled round gets the `AmmoQuality` fields from its
case, bullet and the assembler's level. Only here does brass quality matter,
as decided for metallurgy.

## 5. Decisions needed from the project owner before C2

These change the gameplay architecture, so they are not decided here.

1. **The press.** Options: (a) a hand-held die set and hammer on any surface,
   no station, crude and slow; (b) a new craftable *entity* with a
   `CraftBench` component and its own bench tag, the way vanilla defines its
   stations in script (needs a tag registered through `registries.lua`, a
   sprite and a build recipe); (c) reuse a vanilla bench tag such as
   `StandingDrillPress`. Recommendation: (a) for the first cases, (b) later as
   the quality tier above it.
2. **Calibres.** 9 mm only at first, or all nine vanilla calibres.
3. **Bullet metal.** Copper bullets or a lead ore.
4. **Primer and powder sources.**
5. **Cups per ingot.**

## 6. Multiplayer

Same as metallurgy: vanilla crafting carries it; XP must move to the server
call; the requirement must be attached on both sides. C2's case quality in
ModData is written where `OnCreate` runs, which is the server in multiplayer.

## 7. REQUIRES FUTURE IN-GAME VERIFICATION (C1)

- "Forge Small Brass Sheets" appears at a forge and "Punch Brass Case Cups"
  in the crafting menu at a surface; both consume and produce as written and
  keep their tools.
- The hammering animations look right.
- XP lines appear; the requirement shows as Ammo Making 0.
- Placeholder icons and models are acceptable.

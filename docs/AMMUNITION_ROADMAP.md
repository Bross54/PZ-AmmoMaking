# Ammunition: groundwork for the next stages

Status: **RESEARCH AND DESIGN ONLY. Nothing in this document is
implemented.** It records what the installed Build 42.20.4 files say about
ammo boxes, loot, magazines and recycling, and what follows for this mod.

Vanilla facts were read on 2026-10-02 (paths relative to `media/`), marked
**FILE** (read in a script or Lua file), **JAR** (read from
`projectzomboid.jar`), **INFERRED**, or **WORKSHOP CLUE** (an installed
Workshop mod; a hint, not proof).

## 1. Ammo boxes: nothing to build

FILE `scripts/generated/recipes/recipes_ammunition.txt`, the one packing
recipe, verbatim:

```text
craftRecipe place_ammo_in_box
{
    timedAction = PlaceAmmoInBox,
    time = 15,
    category = Packing,
    Tags = InHandCraft,
    inputs
    {
        item 20 [Base.Bullets44;Base.308Bullets;25:Base.ShotgunShells;Base.556Bullets;50:Base.Bullets9mm;50:Base.Bullets45;50:Base.Bullets38;50:Base.Bullets357;Base.3030Bullets] mappers[ammoType] flags[AllowFavorite;InheritFavorite;IsExclusive],
    }
    outputs
    {
        item 1 mapper:ammoType,
    }
    itemMapper ammoType
    {
        Base.Bullets44Box = Base.Bullets44,
        ...
    }
}
```

| Round | Box | Rounds per box | Carton (12 boxes) |
|---|---|---|---|
| `Base.Bullets9mm`, `Bullets38`, `Bullets45`, `Bullets357` | `…Box` | 50 | `…Carton` |
| `Base.Bullets44`, `556Bullets`, `3030Bullets`, `308Bullets` | `Bullets44Box`, `556Box`, `3030Box`, `308Box` | 20 | `…Carton` |
| `Base.ShotgunShells` | `ShotgunShellsBox` | 25 | `ShotgunShellsCarton` |

- The recipe has one input line: the rounds. No empty box item, no tool, no
  material, no skill. It matches by item type.
- INFERRED: a handloaded round **is** the vanilla item, so the nine rounds
  this mod makes can already be boxed and cartoned
  (`Place12BoxesInCarton`, `recipes_packing.txt`) with no mod work.
- A box holds a count. A boxed handloaded round loses its casing-quality
  record, exactly as a loaded one does (`AC_CaseQuality`): opening a box
  creates fresh items (`OpenBoxOfBullets50`: `item 50 mapper:ammoTypes`).

**Decision: no box recipes and no box items.** Adding "Box Handloaded Rounds"
would duplicate a vanilla recipe that already accepts them. The only thing
worth doing is saying so in the inspection text, which already states that
the record stays with the loose round.

REQUIRES FUTURE IN-GAME VERIFICATION: that `place_ammo_in_box` accepts
rounds carrying mod ModData, and what `IsExclusive` does with a mixed stack.

## 2. Loot for die sets

### 2.1 How vanilla loot is defined

- FILE `lua/server/Items/ProceduralDistributions.lua`:
  `ProceduralDistributions.list.<Name> = { rolls = N, items = { "Item",
  weight, … }, junk = { … } }`.
- FILE `lua/server/Items/Distributions.lua`: rooms map containers to those
  lists (`procList = { { name = "GunStoreAmmunition", min = 0, max = 99,
  weightChance = 100 }, … }`).
- FILE `lua/server/Items/SuburbsDistributions.lua`: merge helpers and the
  `OnPreDistributionMerge` / `OnPostDistributionMerge` hooks. JAR
  `IsoWorld`: those fire just before `ItemPickerJava.Parse()`.
- JAR `ItemPickerJava`: item ids resolve through `ScriptManager.FindItem`;
  an unknown id is logged and skipped.
- Vanilla Lua contains no example of a mod adding to a list. WORKSHOP CLUE:
  `table.insert(ProceduralDistributions.list["X"].items, "Mod.Item")` then
  `table.insert(…, weight)` at file load, after
  `require "Items/ProceduralDistributions"`.

Weights seen in the same file: ammo boxes 10–20 and cartons 1 in
`GunStoreAmmunition`; `"SmallPunchSet", 8` and `"MetalworkingPunch", 8` in
tool lists, 1–4 in others; reloading books 10 / 8 / 6 / 4 / 2 in
`GunStoreLiterature`; very rare tools 0.01–0.1.

**Three lists are dead.** `GunStoreCounter`, `GunStoreDisplayCase` and
`GunStoreShelf` exist with `-- DEPRECATED` and no items, and
`Distributions.lua` references none of them: inserting there spawns nothing.

### 2.2 Should die sets be loot?

Today a die set is only crafted: two steel bar quarters at a forge, at Ammo
Making 1 to 3. That makes the forge a hard requirement for all ammunition.

| Option | For | Against |
|---|---|---|
| A. Crafted only (today) | one obtainable path, fully in the mod's own chain; nothing to balance against loot | a player with brass and no forge can make nothing |
| **B. Crafted, and rare loot** (proposed) | a die set found in a gun store or a hunter's garage is a reason to start handloading that calibre; the forge stays the reliable path | needs a distribution file and in-game tuning |
| C. Loot only | scarcity | breaks the "genuine raw-material loop": progress would depend on luck |

Proposed for B, to be tuned in game:

| List | Referenced by `Distributions.lua` | Die sets | Weight each |
|---|---|---|---|
| `GunStoreAccessories` | 2 containers | all nine | 1 |
| `GarageFirearms` | 2 | 9mm, .38 Special, .308, 12 Gauge (the common hunting and home calibres) | 0.5 |
| `Hunter` | 10 | .308, .30-30, 12 Gauge | 0.5 |
| `ArmyStorageAmmunition` | 3 | 5.56, 9mm | 0.5 |

The die-set list would come from `AC_Calibres.LIST` (each calibre's `dieSet`),
with the per-list selection as a small table next to it, so a new calibre
needs one line. Primers and components would **not** be loot: they are the
mod's manufacturing content.

Not implemented because nothing about it can be validated offline: whether
the insert runs before the parse on this build, how the weights feel against
`rolls` and the sandbox loot settings, and whether a list is actually used
by a container (`MetalWorkerTools`, for instance, is defined but not named
in `Distributions.lua`).

## 3. Magazines and firearms: no integration needed, none possible cheaply

- FILE `scripts/generated/items/weapon.txt`: a firearm names `AmmoType`,
  `AmmoBox`, `MaxAmmo` and, when it has one, `MagazineType`; a magazine item
  names `AmmoType`, `MaxAmmo` and `GunType`.
- FILE `lua/shared/TimedActions/ISLoadBulletsInMagazine.lua`:
  `RemoveOneOf(itemKey, true)` then `setCurrentAmmoCount(count + 1)`.
  `ISReloadWeaponAction.lua`: `getInventory():Remove(bullet)` then
  `setCurrentAmmoCount(count + 1)`. `ISEjectMagazine.lua` makes a **new**
  magazine item (`instanceItem(self.gun:getMagazineType())`) and copies the
  count onto it; `ISUnloadBulletsFromMagazine.lua` makes a new round item.
- JAR `InventoryItem`: the only ammunition state on an item is `ammoType`,
  `maxAmmo`, `currentAmmoCount`.

So handloaded rounds work in every vanilla firearm and magazine as they are,
and **nothing per round survives** a magazine or a firearm; even ModData on
the magazine is lost when it is ejected. A quality effect on firing would
need its own carrier (a per-firearm or per-magazine tally maintained by
wrapping those four timed actions), which is firearm-mechanics work and stays
out of scope. This is the reason no misfire, jam or damage effect exists.

## 4. Recycling and spent cases

What vanilla offers (FILE unless marked):

- Firing spawns nothing: `ISReloadWeaponAction.lua` resets
  `setSpentRoundCount(0)` and plays `ShellFallSound`. There is no spent
  casing, hull, primer or bullet item anywhere in the item scripts or
  `ItemName.json`.
- `GatherGunpowder` (pliers kept, `item 1 tags[base:ammo] mode:destroy`)
  returns `item 1 Base.GunPowder flags[HasOneUse]`: one use, whatever the
  round. No vanilla recipe returns metal from a round.
- `Base.BrassScrap` exists, is loot, and **no recipe uses it**.
  `Base.GunPowder` is in no procedural loot list (foraging only).

Economics, in the mod's units (one round holds 6 to 17 brass, 5 or 10 copper):

| Recycling path | Would return | Verdict |
|---|---|---|
| Spent case from firing | the case, 5–15 brass | needs a hook on firing and a new item per calibre; the single largest design step left, and it changes what a firearm does |
| Pull a round apart (a mod version of `GatherGunpowder`) | case + bullet + primer + powder | must return **at most** what assembly consumed, one use of powder only if vanilla's own recipe is not also usable on the same round; otherwise it is a duplication loop |
| Melt cases and brass scrap back to ingots | 10 cases of 5 brass → half an ingot | simple, conservative, and gives `Base.BrassScrap` (already in `AC_Materials.UNITS`, unused) a purpose |

Rules any recycling recipe must obey, all already checkable by
`AC_Materials.checkConservation` and the metal-flow graph test:

1. No recipe returns more of any material than the consumed item holds.
2. A loss on the way back (for example nine tenths) is allowed; a gain never.
3. The graph may gain a cycle (case → brass → case), so the "no loop returns
   to an item" test becomes "every loop loses material", and XP on a
   recycling recipe must be zero or the loop farms XP.

## 5. Order of work

```text
1. Reloading press            the station entity and sprites; recipes are prepared
                              (RELOADING_PRESS_DESIGN.md)
2. Die sets as rare loot      one distribution file, tuned in game (§2)
3. Brass recycling            melt cases and Base.BrassScrap back to ingots, with a
                              loss and no XP (§4)
4. Spent cases                a firing hook and a spent-case item per calibre;
                              resize and reprime instead of forming from cups
5. Quality that matters       a carrier on the firearm or magazine (§3), then
                              misfires and jams on vanilla's own jam mechanic
```

Steps 1 to 3 touch no firearm code. Steps 4 and 5 do, and are the point at
which the architecture changes; each needs a decision from the project owner
before it starts.

Not on the list, deliberately: lead and its geology, shell variants
(vanilla puts the pellet count on the gun), primer and powder chemistry,
multiplayer authority (its own stage: `MULTIPLAYER_MINING.md`).

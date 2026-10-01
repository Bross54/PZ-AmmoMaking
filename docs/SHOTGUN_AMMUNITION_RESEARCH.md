# Shotgun shells: research, decisions and the first chain

Status: **IMPLEMENTED, offline-verified only.** One shell, the vanilla 12 gauge
round, is made through the same calibre model as the cartridges. Nothing here
has been run in the game; §6 lists what only the game can confirm.

Vanilla facts were read on 2026-10-02 from the installed Build 42.20.4
scripts, Lua and jar (paths relative to `media/`). Each fact is marked:

- **FILE** read in an installed script or Lua file
- **JAR** read from `projectzomboid.jar` with `javap`
- **DECISION** a design choice of this mod

## 1. What vanilla has

### 1.1 The shell (FILE: `scripts/generated/items/normal.txt`)

| Item | Name | Fields |
|---|---|---|
| `Base.ShotgunShells` | 12g Round | `DisplayCategory = Ammo`, `ItemType = base:normal`, Weight 0.06, `count = 6`, `Tags = base:ammo;base:shotgunshell`, `MetalValue = 1.0`, icon `ShotgunAmmo`, world model `ShotGunShells` |
| `Base.ShotgunShellsBox` | Box of 12g Rounds | `OpenBoxOfShotgunShells` → 25 shells; `place_ammo_in_box` packs 25 back |
| `Base.ShotgunShellsCarton` | Carton of 12g Rounds | `OpenCarton12` → 12 boxes |

**There is exactly one shell.** Vanilla does not distinguish buckshot,
birdshot or slugs as ammunition: no item, tag or translation for any of them
exists. One item is one shell; `count = 6` is the loot / `AddItem`
multiplier, as for every other round.

### 1.2 The shotguns (FILE: `scripts/generated/items/weapon.txt`)

| Firearm | Capacity | Loading | `ProjectileSpread` | Damage |
|---|---|---|---|---|
| `Base.Shotgun` | 5 | internal, `RackAfterShoot = true` | 1.0 | 1.5–2.2 |
| `Base.ShotgunSawnoff` | 5 | internal, rack | 1.5 | 1.3–2.0 |
| `Base.JS3T_Shotgun` | 7 | internal, rack | 1.0 | 1.5–2.2 |
| `Base.DoubleBarrelShotgun` | 2 | `InsertAllBulletsReload = true`, no rack | 0.6 | 1.5–2.2 |
| `Base.DoubleBarrelShotgunSawnoff` | 2 | as above | 2.0 | 1.2–1.8 |

All five: `AmmoType = base:shotgun_shells`, `AmmoBox = Base.ShotgunShellsBox`,
no magazine, and **`Projectilecount = 9`** (every other firearm has 1). The
nine pellets and their spread are properties of the gun, not of the
shell: a handloaded `Base.ShotgunShells` behaves as buckshot whatever is put
in it. `Base.ChokeTubeFull` and `Base.ChokeTubeImproved` are weapon parts.

### 1.3 Loading and handling

- FILE `lua/shared/TimedActions/ISReloadWeaponAction.lua`: shells are loaded
  one at a time through the same action as every other round: found by
  `ammoType:getItemKey()`, removed, count incremented. The file's only
  shotgun branch (`gun:getAmmoType() == AmmoType.SHOTGUN_SHELLS`) selects the
  faster-reload check for a shells bandolier. As with all ammunition,
  per-shell ModData does not survive loading.
- `ShellFallSound` is a sound; firing produces no hull item.
- FILE `lua/server/Items/AcceptItemFunction.lua`: shells bandoliers accept
  items tagged `ItemTag.SHOTGUN_SHELL`, bullet bandoliers accept `AMMO`
  without it. A handloaded vanilla shell item fits these unchanged.
- FILE `scripts/generated/recipes/recipes_ammunition.txt`: `GatherGunpowder`
  takes `item 1 tags[base:ammo] mode:destroy` with pliers kept and returns
  `item 1 Base.GunPowder flags[HasOneUse]`, so a shell can be taken apart for
  one use of gunpowder, like any round. `place_ammo_in_box` lists
  `25:Base.ShotgunShells`, so 25 handloaded shells can be boxed.
- Shells are loot (`lua/server/Items/Distributions.lua`,
  `ProceduralDistributions.lua`) and can be foraged.

### 1.4 Components and materials

Searched item ids, scripts, Lua and `ItemName.json` for: hull, wad, shot,
pellet, buckshot, birdshot, slug, bearing, BB, cardboard, wax, felt, plastic
tube / pipe, PVC, lead.

| Component | Vanilla (FILE) |
|---|---|
| Hull (plastic, paper or brass) | **none** |
| Shotshell primer | **none** |
| Shot, pellets, slugs | **none**. `Base.SteelSlug` is a bar offcut, `Base.Slug` an animal; there are no ball bearings or BBs |
| Lead | **none** |
| Wad | **none** as such |
| Plastic stock (sheet, tube) | **none**. Plastic exists only as finished things: `PlasticCup`, `Plasticbag`, cutlery, `PlasticTray` |
| Cardboard, wax | **none** as items (`Mov_CardboardBox` is furniture; `Base.Candle` is a light source) |

What does exist and could serve:

| Role | Vanilla items |
|---|---|
| Wadding | `Base.CottonBalls` (`base:normal`, 0.1, loot, boxed as `CottonBallsBox`), `Base.RippedSheets` (`base:normal`, 0.1, made from any clothing), `Base.PaperNapkins2` (a drainable), `Base.ToiletPaper`, `Base.SheetPaper2`, `Base.Cork` |
| Shot metal | `Base.CopperScrap` (the mod's own chain), `Base.IronPiece` / `Base.SteelPiece`, `Base.Nails` |
| Hull metal | brass, through the mod's case cups |

### 1.5 How vanilla consumes a rag in a recipe

`Base.RippedSheets` has `ReplaceOnUse = Base.RippedSheetsDirty`. Vanilla
recipes that use one up write the line with `mode:destroy` or
`flags[DontReplace]`:

```text
item 1 [Base.RippedSheets;Base.DenimStrips;Base.LeatherStrips] mode:destroy,
    (entities/blacksmith/craftRecipes/recipes_blacksmith_blades.txt)
item 10 [Base.RippedSheets;Base.CottonBalls],
    (recipes/recipes_carpentry.txt, the hunting trophy)
```

JAR: `ItemApplyMode` has exactly `Normal`, `Keep`, `Destroy`;
`InputScript.Load` parses the word `destroy`;
`CraftRecipeData.processDestroyAndUsedItems` and
`CraftRecipeManager.consumesEntireItem` read `isDestroy()`, the `DontReplace`
flag and `InventoryItem.getReplaceOnUse()` together. So `mode:destroy` is
the established way to consume the rag without a dirty rag coming back.

## 2. Decisions

The four choices the first research left open were taken conservatively, as
the pass instructions asked ("gameplay consistency wins").

### 2.1 Architecture: one more calibre, not a second model (DECISION)

A shell is a cartridge with one more part. Mapping it onto the existing
model:

| Shell part | Calibre field | New? |
|---|---|---|
| hull | `case` (drawn from `cupsPerCase` cups, quality rolled) | no |
| shot charge | `bullet` (swaged from copper scrap, `bulletsPerScrap`) | no |
| primer | `primerFamily` | no |
| powder | `powderUses` | no |
| die set | `dieSet` | no |
| **wad** | **`wads`** | **yes, one whole number** |

Four of five parts map one to one, and every generic system (recipe
generation, units, conservation, cross-calibre isolation, case quality, debug
kits, compatibility lines, the 100-round chain test) works on a shell without
knowing it is one. A separate `AC_ShellTypes.lua` would have duplicated all of
that for the sake of one input line, so shells were **not** given their own
model. What was added, each with a consumer:

- `AC_Calibres.CLASSES.shotgun`: the class defaults (three cups, one charge
  per scrap, three powder, one wad, round at level 4, pistol times).
- `class.primerClass`: which class's primer families a class takes. Only the
  shotgun class sets it (`"pistol"`). Consumer: the validator's class rule.
- `calibre.wads` (default 0) and `AC_Calibres.WAD.items`. Consumers:
  `buildCalibreRecipes` (one more assembly line), `validate`, the debug kit,
  the compatibility check.
- `destroy = true` on a mirror input, rendered as `mode:destroy`.

The hull and shot charge have their own item ids
(`AmmoMaking.Hull12Gauge`, `AmmoMaking.ShotCharge12Gauge`); the model already
allowed explicit ids. Recipe ids keep the generic pattern
(`AmmoMaking_FormCase12Gauge`, `AmmoMaking_SwageBullets12Gauge`); the player
sees the translated names ("Form 12 Gauge Brass Hull", "Swage 12 Gauge Copper
Shot Charge").

### 2.2 Hull: all brass (DECISION)

| Option | For | Against |
|---|---|---|
| **A. All-brass hull from case cups** (chosen) | all-brass shotshells are real and still made; uses the existing brass chain and the existing case code path, including quality; no new material | not what a 1993 shop shell looks like |
| B. Paper hull: paper tube, glue, a brass head from one cup | period-correct | two more items and recipes, glue as a consumed drainable, and still needs the brass head |
| C. Plastic hull | modern | vanilla has no plastic stock material at all; would need an invented resource |

Three cups per hull: a 12 gauge brass hull holds about as much brass as a
.308 case.

### 2.3 Shot: copper, one scrap per charge (DECISION)

| Option | For | Against |
|---|---|---|
| **A. Copper shot from `Base.CopperScrap`** (chosen) | the mod's own mined metal, already tracked; copper and copper-plated shot are real; consistent with copper bullets | none in game terms |
| B. Steel shot from `Base.IronPiece` / `Base.SteelPiece` | steel shot is real and vanilla has the item | a new tracked material and a vanilla smithing dependency for a single use |
| C. Lead | most realistic | does not exist in vanilla; ruled out as for bullets |

The shot is one item per shell, a measured **shot charge**, not loose pellets:
pellet count is the gun's property in vanilla, and one item keeps the assembly
recipe to whole numbers. The earlier draft proposed two scrap per charge,
which needed a new field (`scrapPerSwage`). One whole scrap, the cost of a
.45 or .308 bullet, needs no new field and keeps the shell from being the
most copper-hungry round by a factor of two; the units are gameplay units,
not grains.

### 2.4 Wad (DECISION)

One piece of wadding per shell:
`item 1 [Base.RippedSheets;Base.CottonBalls] mode:destroy`. Both are plain
`base:normal` items, so the line has no drainable in it (the first draft also
listed `Base.PaperNapkins2`, which is a drainable and was dropped for that
reason). The wad is an untracked input, like charcoal: obtainable everywhere
(ripped sheets come from any clothing) and it gives the shell one ingredient
cartridges do not have.

### 2.5 Primer: the large pistol primer (DECISION)

A real shotshell takes its own primer (the 209). A fifth family would have
been one more item and two more recipes, sized and made exactly like the
large pistol primer. All-brass hulls are in fact primed with large pistol
primers, so the shell reuses `LargePistol`. The model rule "a calibre takes a
primer family of its own class" is kept and made explicit for this one case:
the shotgun class names `primerClass = "pistol"`. A rifle or pistol calibre
still cannot borrow another class's family, and the validator rejects a shell
that names a rifle family.

### 2.6 Powder, level, time (DECISION)

- Powder: 3 uses, the .44 Magnum charge (a 12 gauge charge is about 22 grains).
- Level: round at 4, die set and hull at 2, shot charge at 3. Shells are
  common, short-range ammunition; they sit with the larger pistol calibres,
  below rifles.
- Times: pistol times; the hull is a straight-walled case.
- XP: hull 2 (three cups, like the .44 and rifle cases), assembly 3 (like the
  other level-4 rounds).

## 3. What is implemented

```text
3 brass case cups ── Form 12 Gauge Brass Hull (die set, hammer) ──► 1 hull (quality rolled)
1 Base.CopperScrap ── Swage 12 Gauge Copper Shot Charge (die set, hammer) ──► 1 shot charge
small brass sheet + priming charge ──► 5 large pistol primers          (existing recipe)
hull + large pistol primer + shot charge + 3 uses of gunpowder + 1 wad
        ── Assemble 12 Gauge Shell (die set) ──► 1 Base.ShotgunShells
```

| Recipe | Level | XP | time |
|---|---|---|---|
| `AmmoMaking_ForgeDieSet12Gauge` | 2 | 10 | 300 |
| `AmmoMaking_FormCase12Gauge` | 2 | 2 | 80 |
| `AmmoMaking_SwageBullets12Gauge` | 3 | 1 | 80 |
| `AmmoMaking_AssembleRound12Gauge` | 4 | 3 | 40 |

Per shell: brass 15 + 2 = 17, copper 10, powder 3, priming compound 4, one
wad. Per 100 shells: 17 brass ingots, 100 copper scrap, 200 toy caps, 60 uses
of fertilizer, 100 wads; 27 ore.

Items: `AmmoMaking.DieSet12Gauge`, `AmmoMaking.Hull12Gauge`,
`AmmoMaking.ShotCharge12Gauge`. The output is the vanilla shell, so all five
shotguns, the box and the bandoliers work unchanged.

## 4. Offline verification (MOCK-VERIFIED)

The shell runs through every generic calibre test, and has its own:

- the pinned matrix row; the shell's tier (brass of a .308, charge and primer
  of a .44 Magnum, pistol times, level between the standard pistol rounds and
  the rifles);
- validator mutations: a shell with a rifle primer, without a wad, with half
  a wad, in a .308 case, loaded with a .44 bullet, made with the 9mm die set,
  below its primer's level; a pistol round that outputs shells; removing or
  corrupting `primerClass`;
- the 100-shell chain from 17 ingots to exactly 100 `Base.ShotgunShells` with
  nothing left over, including the hundred wads;
- no shell without a wad on the mirror inventory;
- the generated script contains exactly one `mode:destroy` line, the wad;
- the career simulation makes shells at level 4, before the first rifle round.

These prove the Lua model, the generated script text and the arithmetic. They
do not prove the engine's behaviour.

## 5. Not built

Buckshot / birdshot / slug variants (vanilla has one shell item and puts the
pellet count on the gun, so a variant would need a new ammunition item and
firearm changes), paper or plastic hulls, steel or lead shot, a shotshell
primer family, recovering fired hulls (vanilla ejects none).

## 6. REQUIRES FUTURE IN-GAME VERIFICATION

Beyond the general list in `AMMUNITION_DESIGN.md` §13:

- `item 1 [Base.RippedSheets;Base.CottonBalls] mode:destroy` takes one of
  either and hands back no `Base.RippedSheetsDirty`.
- `item 3 [AmmoMaking.BrassCaseCup]` forms one hull.
- One assembly craft yields one `Base.ShotgunShells` (not six: the item's
  `count` must not multiply a recipe output, as for the other rounds).
- A handloaded shell loads into all five shotguns, fits the shells bandolier,
  packs into `Base.ShotgunShellsBox` and fires nine pellets like a vanilla
  shell.
- The hull receives a quality in `OnCreate`; the shell inherits it.
- Placeholder icons: the hull looks like a loaded shell, the shot charge like
  a bullet.

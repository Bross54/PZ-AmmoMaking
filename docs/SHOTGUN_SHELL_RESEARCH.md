# Shotgun shells: research and design for the next stage

Status: **research and design only. Nothing in this document is
implemented.** Vanilla facts were read on 2026-10-02 from the installed Build
42.20.4 scripts, Lua and jar (paths relative to `media/`).

## 1. What vanilla has (FILE)

### The shell

| Item | Name | Fields |
|---|---|---|
| `Base.ShotgunShells` | 12g Round | `DisplayCategory = Ammo`, `ItemType = base:normal`, Weight 0.06, `count = 6`, `Tags = base:ammo;base:shotgunshell`, `MetalValue = 1.0`, icon `ShotgunAmmo`, world model `ShotGunShells` |
| `Base.ShotgunShellsBox` | Box of 12g Rounds | `OpenBoxOfShotgunShells` → 25 shells; `place_ammo_in_box` packs 25 back |
| `Base.ShotgunShellsCarton` | Carton of 12g Rounds | `OpenCarton12` → 12 boxes |

**There is exactly one shell.** Vanilla does not distinguish buckshot,
birdshot or slugs as ammunition; no item, tag or translation for any of them
exists. One item is one shell; `count = 6` is the loot / `AddItem`
multiplier, as for every other round.

### The shotguns (`scripts/generated/items/weapon.txt`)

| Firearm | Capacity | Loading | `ProjectileSpread` | Damage |
|---|---|---|---|---|
| `Base.Shotgun` | 5 | internal, `RackAfterShoot = true` | 1.0 | 1.5–2.2 |
| `Base.ShotgunSawnoff` | 5 | internal, rack | 1.5 | 1.3–2.0 |
| `Base.JS3T_Shotgun` | 7 | internal, rack | 1.0 | 1.5–2.2 |
| `Base.DoubleBarrelShotgun` | 2 | `InsertAllBulletsReload = true`, no rack | 0.6 | 1.5–2.2 |
| `Base.DoubleBarrelShotgunSawnoff` | 2 | as above | 2.0 | 1.2–1.8 |

All five: `AmmoType = base:shotgun_shells`, `AmmoBox = Base.ShotgunShellsBox`,
no magazine, and **`Projectilecount = 9`** (every other firearm has 1). The
nine pellets and their spread are properties of the gun, not of the shell: a
handloaded `Base.ShotgunShells` behaves as buckshot whatever is put in it.
`Base.ChokeTubeFull` and `Base.ChokeTubeImproved` are weapon parts.

### Loading and handling

- Shells are loaded one at a time through the same `ISReloadWeaponAction`
  as every other round: found by `ammoType:getItemKey()`, removed, count
  incremented. The file's only shotgun branch
  (`gun:getAmmoType() == AmmoType.SHOTGUN_SHELLS`) selects the faster-reload
  check for a shells bandolier. So, as with all ammunition, per-shell
  ModData does not survive loading.
- `ShellFallSound` is a sound; firing produces no hull item.
- `lua/server/Items/AcceptItemFunction.lua`: shells bandoliers
  (`AmmoStrap_Shells`) accept items tagged `ItemTag.SHOTGUN_SHELL`, bullet
  bandoliers accept `AMMO` without it. A handloaded vanilla shell item fits
  these unchanged.
- `GatherGunpowder` takes `tags[base:ammo]`, so a shell can be taken apart
  for one use of gunpowder, like any round.
- Shells can be foraged (`Foraging/Categories/Ammo.lua`).

### Components and materials

Searched item ids, scripts, Lua and `ItemName.json` for: hull, wad, shot,
pellet, buckshot, birdshot, slug, bearing, BB, cardboard, wax, felt, plastic
tube / pipe, PVC, lead.

| Component | Vanilla |
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
| Wadding | `Base.CottonBalls` (0.1, loot, boxed as `CottonBallsBox`), `Base.RippedSheets` (0.1, made from any clothing), `Base.PaperNapkins2`, `Base.ToiletPaper`, `Base.SheetPaper2`, `Base.Cork` |
| Shot metal | `Base.CopperScrap` (the mod's own chain), `Base.IronPiece` / `Base.SteelPiece` (0.1, `base:metalpiece`), `Base.Nails` |
| Sealing | `Base.Glue`, `Base.Woodglue` (`base:glue`), `Base.Scotchtape`, `Base.DuctTape` (`base:tape`) |
| Hull metal | brass, through the mod's case cups |

## 2. Design

### 2.1 The shape of the chain

A shell is the same four things as a cartridge (case, primer, projectile,
powder) plus a wad:

```text
brass case cups ── Form 12 Gauge Brass Hull (die set) ──► hull (quality rolled)
Base.CopperScrap ── Swage 12 Gauge Shot Charge (die set) ──► one charge of copper buckshot
small brass sheet + priming charge ──► shotshell primers
hull + primer + shot charge + wad + powder ── Assemble 12 Gauge Shell (die set) ──► 1 Base.ShotgunShells
```

It fits the calibre model as one more entry. The output is the vanilla shell,
so all five shotguns, the box and the bandoliers work unchanged.

### 2.2 Hull: brass

| Option | For | Against |
|---|---|---|
| **A. All-brass hull from case cups** (recommended) | all-brass shotshells are real and still made; uses the existing brass chain and the existing case code path, including quality; no new material | not what a 1993 shop shell looks like |
| B. Paper hull: paper tube, glue, a brass head from one cup | period-correct | two more items and recipes, glue as a consumed drainable, and still needs the brass head |
| C. Plastic hull | modern | vanilla has no plastic stock material at all; would need an invented resource |

A is the only option that needs nothing new. Suggested `cupsPerCase = 3`
(a 12-gauge brass hull holds about as much brass as a .308 case).

### 2.3 Shot: copper

Vanilla's shotguns fire nine pellets per shell, i.e. buckshot. Nine 00 pellets
weigh about twice a .45 bullet.

| Option | For | Against |
|---|---|---|
| **A. Copper shot from `Base.CopperScrap`** (recommended) | the mod's own mined metal, already tracked; copper and copper-plated shot are real; consistent with copper bullets | costs more copper than any bullet |
| B. Steel shot from `Base.IronPiece` / `Base.SteelPiece` | steel shot is real and vanilla has the item | a new tracked material and a vanilla smithing dependency for a single use |
| C. Lead | most realistic | does not exist in vanilla; ruled out for the same reason as for bullets |

The shot is one item per shell, a measured **shot charge**, not loose pellets:
pellet count is the gun's property in vanilla, and one item keeps the
assembly recipe to whole numbers.

### 2.4 Wad

One piece of wadding per shell, taken from what vanilla already has:
`[Base.CottonBalls;Base.RippedSheets;Base.PaperNapkins2]`. It is an untracked
input, like charcoal: cheap, obtainable everywhere (ripped sheets come from
any clothing), and it gives the shell one ingredient cartridges do not have.

### 2.5 Primer

Real shotshells take their own primer (the 209), which is larger than a
pistol or rifle primer. A fifth family, `Shotshell`, made exactly like the
other four from a small brass sheet and a priming charge, sized like the
large primers (brass 2, compound 4, 5 per sheet). All-brass hulls can in
reality take large pistol primers, but the model ties a primer family to one
class of calibre, and keeping that rule is worth one item.

### 2.6 Powder, level, time

- Powder: 3 uses, the same as .44 Magnum (a 12-gauge charge is about 22
  grains).
- Level: round at 4, tools at 2, shot at 3. Shells are common, short-range
  ammunition; they belong with the larger pistol calibres, below rifles.
- Times: pistol times; the hull is a straight-walled case.

### 2.7 Per shell, and per 100 shells

Brass 15 + 2 = 17, copper 20, powder 3, compound 4, one wad. A hundred
shells: 17 brass ingots, 200 copper scrap, 200 toy caps, 60 uses of
fertilizer, 100 wads; about 37 ore. That makes the shell the most
metal-hungry round in the mod, which is right for nine projectiles a shot.

## 3. What the calibre model needs

Shells are mostly data, with three small, real extensions. None is built.

| Need | Change | Consumer |
|---|---|---|
| A third class | `AC_Calibres.CLASSES.shotgun`, and `class = "shotgun"` on the `Shotshell` primer family | `define`, the validator's class rule |
| More than one scrap per projectile | today `bulletsPerScrap` is "N bullets from 1 scrap"; the shot charge needs "1 charge from 2 scrap". A second field, `scrapPerSwage` (default 1), with the unit rule `10 × scrapPerSwage / bulletsPerScrap` whole | `buildCalibreRecipes`, `buildUnits`, `validate` |
| An extra, untracked assembly input | `assemblyExtras = { { count = 1, items = { … } } }` on the definition, appended to the assembly inputs | `buildCalibreRecipes`; conservation ignores it, as it ignores charcoal |

Everything else is already generic: the recipe generator, the 100-round chain
test, cross-calibre isolation, the validator's item-sharing rules, case
quality (a hull is the calibre's "case"), debug kits, compatibility lines.
Item ids would follow the existing pattern (`Case12Gauge`, `Bullet12Gauge`,
`DieSet12Gauge`) with display names "Brass 12 Gauge Hull", "12 Gauge Copper
Shot Charge", "12 Gauge Handloading Die Set".

## 4. Why it is not implemented in this pass

Shotgun shells were explicitly out of scope for the rifle pass, and four
choices are the project owner's, because each changes what a shell costs or
looks like rather than how the code works:

1. Hull material: brass (§2.2 A) or paper with a brass head (B).
2. Shot metal: copper (§2.3 A) or vanilla steel pieces (B).
3. A separate shotshell primer family, or reuse of the large pistol primer.
4. Level and cost: round at 4 with the numbers of §2.6–2.7, or something
   else.

With those answered, the stage is one model commit (the three extensions,
with their validator rules and tests) and one data commit (class, family,
definition, three items, a primer item, names, regenerated script).

## 5. REQUIRES FUTURE IN-GAME VERIFICATION

Nothing here is implemented. When it is, beyond the general list in
`AMMUNITION_DESIGN.md` §13:

- A recipe input that mixes item types as alternatives
  (`item 1 [Base.CottonBalls;Base.RippedSheets;Base.PaperNapkins2]`, one of
  them a drainable) behaves as one unit of any of them.
- A handloaded `Base.ShotgunShells` loads into all five shotguns, fits the
  shells bandolier and fires nine pellets like a vanilla shell.

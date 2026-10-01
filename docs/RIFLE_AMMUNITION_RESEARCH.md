# Rifle ammunition: research, decisions and what was built

Status: **IMPLEMENTED on 2026-10-02, offline-verified only.** The three
vanilla rifle calibres are part of the calibre model
(`docs/AMMUNITION_DESIGN.md` has the combined matrix, recipes and balance).
This document keeps the vanilla evidence and records how each open question
of the research was decided. Nothing here has been run in the game
(REQUIRES FUTURE IN-GAME VERIFICATION, §9).

Vanilla facts were read from the installed Build 42.20.4 scripts
(`media/scripts/generated/items/weapon.txt`, `normal.txt`), Lua and jar.

## 0. Decisions taken

| Question (section) | Decision | Where it lives |
|---|---|---|
| Primer families (§3) | Two new families, `SmallRifle` (5.56) and `LargeRifle` (.308, .30-30), with their own items; never interchangeable with pistol primers | `AC_Calibres.PRIMERS`, `class = "rifle"` |
| Powder scale (§4) | Compressed: 5.56 3, .30-30 4, .308 5 whole uses of vanilla gunpowder | `powderUses` |
| Case brass, bullets (§5) | Cups 2 / 2 / 3; bullets per scrap 2 / 1 / 1; copper-only | `cupsPerCase`, `bulletsPerScrap` |
| Press or hand (§6) | **By hand**, with the same kind of die set as pistols. No quality penalty: round quality has no combat effect, so rifles differ by level, time, material and powder instead. No press object | `AC_Calibres.CLASSES.rifle` |
| Levels (§7) | All three rounds at level 5; level 6 would have been a grind wall (57 ore to level 5, 105 to level 6 in the simulated career) | `assembleLevel` |

## 1. Vanilla rifle calibres (FILE)

| Calibre | Round | Weight | `count` | Box (rounds) | Firearms | Magazine | Capacity | Damage |
|---|---|---|---|---|---|---|---|---|
| 5.56x45mm | `Base.556Bullets` | 0.035 | 5 | `Base.556Box` (20) | `Base.AssaultRifle`, `Base.JS14_Rifle`, `Base.VarmintRifle` | `Base.556Clip` (30), `Base.JS14_Clip` (20), none | 30, 20, 5 | 1.0–1.6 |
| 7.62x51mm (.308) | `Base.308Bullets` | 0.04 | 5 | `Base.308Box` (20) | `Base.HuntingRifle`, `Base.MSR7T_Rifle`, `Base.AssaultRifle2` | none, none, `Base.M14Clip` (20) | 4, 4, 20 | 1.2–2.0 |
| .30-30 | `Base.3030Bullets` | 0.05 | 5 | `Base.3030Box` (20) | `Base.L94_Rifle` | none | 6 | 1.2–2.0 |

`AmmoType`: `base:bullets_556`, `base:bullets_308`, `base:bullets_3030`. As
with pistols, one item is one cartridge, firearms hold a count, and every
round has a box and a carton. Two long guns already fire pistol rounds and
are covered by the pistol stage: `Base.L92_Carbine` (.357 Magnum) and
`Base.TrapperCarbine` (.45 ACP). The remaining vanilla ammunition is
`Base.ShotgunShells` (12 gauge), which is a different component set (hull,
wad, shot) and its own later stage.

Nothing rifle-specific exists as a component: no rifle case, primer, bullet
or powder item.

## 1a. Verification pass (FILE, re-extracted for the rifle stage)

Every row of §1 was re-read from the item blocks; additional facts:

| Item | Fields |
|---|---|
| `Base.556Bullets` | `DisplayCategory = Ammo`, `ItemType = base:normal`, Weight 0.035, `count = 5`, `Tags = base:ammo`, `MetalValue = 1.0`, icon `RifleAmmo308loose`, world model `RifleAmmo` |
| `Base.308Bullets` | same, Weight 0.04 |
| `Base.3030Bullets` | same, Weight 0.05 |
| `Base.556Box`, `Base.308Box`, `Base.3030Box` | `DoubleClickRecipe = OpenBoxOfBullets20`: 20 rounds each (`item 20 mapper:ammoTypes`); `place_ammo_in_box` packs 20 back |
| `Base.556Carton`, `Base.308Carton`, `Base.3030Carton` | `OpenCarton12`: 12 boxes |
| `Base.556Clip` | "M16 Magazine", `AmmoType = base:bullets_556`, `MaxAmmo = 30`, `GunType = Base.AssaultRifle`, `Tags = base:hasmetal;base:riflemagazine` |
| `Base.JS14_Clip` | "JS-14 Magazine", 5.56, `MaxAmmo = 20`, `GunType = Base.JS14_Rifle` |
| `Base.M14Clip` | "M1A Magazine", `AmmoType = base:bullets_308`, `MaxAmmo = 20`, `GunType = Base.AssaultRifle2` |

Firearms (display name; magazine or internal; capacity):

| Calibre | Firearm | Loading |
|---|---|---|
| 5.56 | `Base.AssaultRifle` (M16 Assault Rifle) | magazine `556Clip`, 30; `FireModePossibilities = Auto/Single` |
| 5.56 | `Base.JS14_Rifle` (JS-14 Rifle) | magazine `JS14_Clip`, 20 |
| 5.56 | `Base.VarmintRifle` (MSR700 Rifle) | internal, 5, `RackAfterShoot = true` |
| .308 | `Base.HuntingRifle` (MSR788 Rifle) | internal, 4, `RackAfterShoot = true` |
| .308 | `Base.MSR7T_Rifle` (MSR7T Tactical Rifle) | internal, 4, `RackAfterShoot = true` |
| .308 | `Base.AssaultRifle2` (M1A Rifle) | magazine `M14Clip`, 20 |
| .30-30 | `Base.L94_Rifle` (L94 Rifle) | internal, 6, `RackAfterShoot = true` |

- **One item is one cartridge**, as for pistols: the box recipes move 20
  items, and `count = 5` is the loot / `AddItem` multiplier that no crafting
  class reads (ammunition research §1).
- **Loading semantics are the pistol ones.** Rifles go through the same
  `ISReloadWeaponAction` / `transferBullets` code: the round is found by
  `ammoType:getItemKey()`, removed, and the firearm or magazine count is
  incremented. No rifle-specific branch exists; the only calibre-specific
  branch in that file is for `AmmoType.SHOTGUN_SHELLS`.
- **Dismantling**: vanilla `GatherGunpowder` takes `tags[base:ammo]`, which
  all three rifle rounds carry, and returns one use of `Base.GunPowder`
  whatever the round. A rifle round that takes several uses to make
  therefore returns less than went in; it can never return more.
- **No rifle-specific ammunition logic** exists in Lua. The three rounds
  appear only in loot distributions and in the foraging category
  `lua/shared/Foraging/Categories/Ammo.lua`, which lists all nine vanilla
  rounds (so loose ammunition, like gunpowder, can be foraged).
- Rifles have no `AmmoPerShoot` or `ProjectileCount` override: one round per
  shot.
- For the later failure stage: vanilla firearms already have a jam mechanic
  (`JamGunChance` in the item script; `isJammed`, `setJammed`, `checkUnJam`
  used by `ISRackFirearm.lua`). It lives on the firearm, which is where a
  handloading effect would have to be carried, since rounds become a count.

## 2. What the pistol architecture already covered

Adding a rifle calibre is the same data as a pistol calibre: a `LIST` entry,
three items, names, a regenerated script. The model's knobs (`cupsPerCase`,
`bulletsPerScrap`, `powderUses`, `primerFamily`, `assembleLevel`) applied
unchanged, the validator and every generic test picked the new entries up,
and case quality needed no change. The only addition was `class`, which
supplies rifle defaults and ties a calibre to primer families of its own
class.

The sections below are the research as written before implementation, kept
for the reasoning; §0 says what was chosen.

## 3. Primer families

Real practice: 5.56 takes small rifle primers; .308 and .30-30 take large
rifle primers. Rifle primers are the same sizes as pistol primers with a
thicker cup and a hotter charge.

| Option | Items | For | Against |
|---|---|---|---|
| A. Two new families, `SmallRifle` and `LargeRifle` | 2 items, 4 generated recipes | matches reality; lets rifle primers cost more compound and unlock later | two more items that look like the pistol ones |
| B. Reuse the pistol families | none | nothing to add; small/large already means size | a 5.56 round would take the same primer as a 9 mm |

Recommendation, **adopted**: **A**, with the rifle primer holding the same brass as its
pistol size and half as much compound again (3 and 6 units against 2 and 4).
The family model, the generated primer recipes and the conservation checks
already handle it; it is two `PRIMERS` entries. Note that 3 units of compound
is not a whole number of toy caps (2 units each) for an odd count, so
`perSheet` must stay even: 10 small rifle primers take 15 caps or 30 match
uses, 5 large take the same. The validator already rejects a combination that
does not divide.

## 4. Powder scaling

Real charges, relative to a 5-grain standard pistol charge: 5.56 about 25 gr
(5×), .30-30 about 32 gr (6×), .308 about 45 gr (9×).

Taken literally that is 9 uses, nearly a whole jar, per .308 round: 100
rounds would need 90 mixes, 180 uses of fertilizer (more than 22 bags) and
180 charcoal. That is not a workable game economy, and it would make powder,
not metal, the only thing that matters.

| Option | 5.56 | .30-30 | .308 | Fertilizer per 100 rounds of .308 |
|---|---|---|---|---|
| Literal | 5 | 6 | 9 | 180 uses |
| Compressed (recommended) | 3 | 4 | 5 | 100 uses |
| Compressed, with a rifle-powder mix that yields more | 3 | 4 | 5 | fewer, but needs a second powder recipe |

Recommendation, **adopted**: **compressed**, keeping the rule that no rifle round takes
less than the largest pistol charge (.44 Magnum, 3). Charges stay whole uses
of vanilla `Base.GunPowder`; no rifle-powder item. If rifle ammunition then
still feels powder-starved, the lever is the mix yield (one line in
`AC_Calibres.POWDER`), not a new item.

## 5. Case brass and projectile copper

Relative to 9 mm (case about 60 gr, bullet 115 gr):

| Calibre | Case brass | Suggested `cupsPerCase` | Bullet | Suggested `bulletsPerScrap` |
|---|---|---|---|---|
| 5.56 | ~95 gr (1.6×) | 2 | 55–62 gr (0.5×) | 2 (5 units; the unit system has nothing smaller) |
| .30-30 | ~135 gr (2.3×) | 2 | 150–170 gr (1.4×) | 1 (10 units) |
| .308 | ~175 gr (2.9×) | 3 | 150 gr (1.3×) | 1 (10 units) |

**Are copper-only rifle bullets reasonable?** Yes, more so than for pistols.
Solid copper ("monolithic") rifle bullets are a real, common hunting bullet,
and a jacketed bullet's jacket is copper alloy anyway. Vanilla still has no
lead, so the reasoning that chose copper for pistols holds. No lead geology
is needed for rifles.

The one place the unit system pinches is the 5.56 bullet: at half the mass of
a 9 mm bullet it would be 2.5 units, which is not whole. Either it costs the
same copper as a pistol bullet (suggested), or the scrap unit is refined
first. The first is simpler and errs on the side of costing more.

## 6. Should a reloading press become mandatory?

Pistol cases are straight-walled; drawing one from a cup with a hand die and
a hammer is a believable abstraction. Rifle cases are bottlenecked and longer,
and full-length forming them by hand is not. This is the first place where
the hand die set stops being plausible, and it is the natural introduction
of the press.

| Option | Effect |
|---|---|
| A. Rifle cases need the press; pistol calibres stay hand-loadable | the press arrives with a reason; needs the press designed first (a bench tag registered through `registries.lua`, an entity with `CraftBench`, a sprite, a build recipe) |
| B. Rifle calibres by hand at a quality penalty, press later removes it | no new station now; uses the existing `toolBonus` hook with a negative value; rifles available earlier |
| C. Rifle calibres by hand, no penalty | simplest; least believable |

Recommendation at the time: B first, then A's press as the tier above it.

**Decided by the project owner: by hand, without the penalty** (closest to
option C, with the differentiation moved elsewhere). A quality penalty would
balance nothing while round quality has no combat effect, so rifles are
separated from pistols by a higher level, about twice the craft time, larger
material and powder requirements and their own primer families. The press
remains the later upgrade tier and takes the same die sets.

## 7. Progression

The pistol ladder ends at level 5, reached after about 63 ore in the
simulated career. Level 6 costs 5775 XP (about 110 ore at the current rate),
level 7 10275.

Rifle rounds therefore cannot simply continue the ladder at 6, 7, 8 without
becoming a grind wall. Options:

1. Rifle rounds at levels 5 and 6, with rifle crafts worth more XP (a rifle
   round holds two to three times the material of a 9 mm round).
2. Rifles share levels 4 and 5 with the larger pistol calibres and are gated
   by materials and the press instead.
3. Revisit the perk's XP thresholds. They are part of the perk registration
   that is confirmed working in game, so this is the most invasive option.

Recommendation at the time: 1, after re-running the career simulation.

**Outcome:** the simulation was extended to rifles. Level 5 takes 57 ore,
level 6 takes 105. All three rifle rounds were placed at level 5, with
slightly more XP per rifle craft (cases 2–3, rounds 4–5); the first rifle
round is assembled after 73 ore and about 500 pistol rounds. The perk's XP
thresholds were not touched.

## 8. What was built

- `AmmoMaking.SmallRiflePrimer`, `AmmoMaking.LargeRiflePrimer` and four
  generated primer recipes (15 toy caps or 30 match uses per sheet).
- Per calibre: `DieSet556NATO` / `Case556NATO` / `Bullet556NATO`,
  `DieSet3030Win` / …, `DieSet308Win` / …, and four generated recipes each.
- Assembly outputs `Base.556Bullets`, `Base.3030Bullets`, `Base.308Bullets`.
- The 100-round chain, cross-calibre isolation, primer-family, validation
  and mutation tests run for the rifle calibres through the same generic
  code as the pistols.

Shotgun shells come next and are researched in
`docs/SHOTGUN_AMMUNITION_RESEARCH.md`: they need a hull, shot and wad, none of
which the brass-case model describes.

## 9. REQUIRES FUTURE IN-GAME VERIFICATION

- The twelve rifle recipes and four rifle primer recipes appear and work as
  written (see `AMMUNITION_DESIGN.md` §13 for the full list).
- Multi-use powder inputs: `item 3`, `item 4`, `item 5 [Base.GunPowder]`
  take that many uses from a jar, and continue into a second jar when one
  runs out.
- `item 3 [AmmoMaking.BrassCaseCup]` takes three cups for a .308 case.
- `item 15 [Base.CapGunCap]` and `item 30 [Base.Matches;Base.Matchbox]` for
  rifle primers.
- Handloaded rifle rounds load into `556Clip`, `JS14_Clip`, `M14Clip` and
  the internal magazines and fire like vanilla rounds.
- Rifle recipes are unavailable below level 5 and their parts below their
  levels.

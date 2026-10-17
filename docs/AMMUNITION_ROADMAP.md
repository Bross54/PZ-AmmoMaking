# Ammunition roadmap

Where the mod stands at 0.11.0 (in development), and what is left. *Implemented* means Lua and data checked offline (the suite, the
installed game's files, the jar); it never means seen in game. What the
running game has to confirm is one ordered session:
`docs/INGAME_VALIDATION.md`.

## 1. Status

Three states, and only three:

- **IMPLEMENTED**: written and tested offline; part of a normal game.
- **IMPLEMENTED, REQUIRES IN-GAME VERIFICATION, OFF BY DEFAULT**: written
  and tested offline behind a switch of `AC_Features.lua`.
- **VISUAL PLACEHOLDER**: works with borrowed or programmer art; needs
  final art (`docs/ART_HANDOFF.md`).

Every implemented system still needs its in-game pass; the first state
does not claim one. What has been **seen in game** (42.20.4) is sampling
with a shovel, mining with a pickaxe, depletion, exhaustion and cancelling.

| Area | State | Switch | Where |
|---|---|---|---|
| Ammo Making skill, levels 0 to 10 | IMPLEMENTED | | `AMMUNITION_DESIGN.md` 9.0 |
| Skill books (five volumes, vanilla's reading) | IMPLEMENTED; own icons, VISUAL PLACEHOLDER (vanilla book model) | | `AMMUNITION_DESIGN.md` 9.2, `LOOT_AND_RECYCLING.md` 1.4 |
| Recipe magazines | not built: the engine cannot teach an Ammo Making recipe | | `AMMUNITION_DESIGN.md` 9.2 |
| Geology, sampling, field and advanced assay | IMPLEMENTED | | `DEVELOPMENT.md` |
| Laboratory analyzer (placed, powered) | IMPLEMENTED; VISUAL PLACEHOLDER (a vanilla tile) | | `DEVELOPMENT.md` |
| Assay kits and analyzer obtainable | IMPLEMENTED (three recipes from vanilla items) | | `DEVELOPMENT.md`, *Item and recipe audit* |
| Mining, depletion | IMPLEMENTED | | `DEVELOPMENT.md` |
| Metallurgy, case stock | IMPLEMENTED | | `METALLURGY_DESIGN.md` |
| Nine calibres: die sets, cases, bullets, primers, powder, assembly | IMPLEMENTED; own icons, VISUAL PLACEHOLDER (vanilla world models) | | `AMMUNITION_DESIGN.md` |
| Die sets as loot | IMPLEMENTED | | `LOOT_AND_RECYCLING.md` 1 |
| Die set wear (condition, worn by the engine while crafting) | IMPLEMENTED | | `AMMUNITION_DESIGN.md` 7 |
| Component loot (powder, primers, brass) | IMPLEMENTED | | `LOOT_AND_RECYCLING.md` 4 |
| Brass recycling | IMPLEMENTED | | `LOOT_AND_RECYCLING.md` 2 |
| Copper recycling | not built, on purpose | | `LOOT_AND_RECYCLING.md` 2.5 |
| Lead and cast bullets (pistol calibres, buckshot; lead melted from vanilla junk; two moulds, forged or found) | IMPLEMENTED; own icons, VISUAL PLACEHOLDER (vanilla world models) | | `METALLURGY_DESIGN.md` 12, `AMMUNITION_DESIGN.md` 6.1 |
| Lead ore and geology | not built, on purpose: it would change the sampling and assays seen in game | | `METALLURGY_DESIGN.md` 12.5 |
| 12 gauge shell variants (buckshot, birdshot, slug) | not built: not buildable without replacing vanilla firearms | | `SHOTGUN_AMMUNITION_RESEARCH.md` 5.1 |
| Ammo boxes | nothing to build: vanilla boxes handloaded rounds | | `LOOT_AND_RECYCLING.md` 3 |
| Inspection: case, round, magazine, firearm | IMPLEMENTED | | `AC_AmmoInspection.lua` |
| Save data: schema, repairs, versions, upgrade runner | IMPLEMENTED | | `DEVELOPMENT.md`, `AC_SaveData.lua` |
| Multiplayer guards | IMPLEMENTED (everything authoritative is refused on a client unless the server authority is on) | | `MULTIPLAYER_DESIGN.md` 2.1 |
| **Multiplayer server authority** (sampling, assays, analyzer, mining performed by the server) | IMPLEMENTED, REQUIRES IN-GAME VERIFICATION (dedicated server and client), OFF BY DEFAULT; single player proven unchanged offline | sandbox option | `MULTIPLAYER_DESIGN.md` 6 |
| **Reloading press** | IMPLEMENTED, REQUIRES IN-GAME VERIFICATION, OFF BY DEFAULT; VISUAL PLACEHOLDER | add-on mod `AmmoMakingPress` | `RELOADING_PRESS_DESIGN.md` |
| **Spent cases** | IMPLEMENTED, REQUIRES IN-GAME VERIFICATION, OFF BY DEFAULT | add-on mod `AmmoMakingSpentCases` | `SPENT_CASE_RESEARCH.md` |
| **Quality tracking through magazines and firearms** | IMPLEMENTED, REQUIRES IN-GAME VERIFICATION, OFF BY DEFAULT | sandbox option | `AMMO_QUALITY_RUNTIME_DESIGN.md` 9 |
| **Quality effects at the shot** | IMPLEMENTED, LOCKED OFF (no switch in this version) | none | `AMMO_QUALITY_RUNTIME_DESIGN.md` 9.4 |
| Feature switches, placeholder registry | IMPLEMENTED | | `AC_Features.lua`, `AC_Visuals.lua` |
| Balance options for server owners (ore per tile, die-set and component loot, Ammo Making XP) | IMPLEMENTED (multipliers, default 1: nothing changes unless set) | sandbox options | `BALANCE_OPTIONS.md` |
| Debug tree, compatibility check | IMPLEMENTED | `-debug` | `DEVELOPMENT.md` |
| Game-update check | IMPLEMENTED | | `tools/pz_compat.py` |
| Inventory icons, mod list posters, Workshop preview | IMPLEMENTED: the mod's own pixel art (`art/icons/make_icons.py`, `art/workshop/make_workshop_art.py`) | | `ART_HANDOFF.md` 2 |
| Release packaging (three mod folders, one archive, a Workshop item folder with `preview.png`) | IMPLEMENTED; nothing published | | `tools/build_release.py`, `WORKSHOP_DESCRIPTION.md` |
| Black powder and primers from raw materials | out of scope: vanilla has no sulfur, saltpetre or priming compound; gunpowder stays charcoal and fertilizer | | `AMMUNITION_DESIGN.md` 12, `VANILLA_AMMUNITION_RESEARCH.md` |

Numbers: the main mod has 55 items, 74 recipes (67 manufacturing, 16 of
them for lead; 3 for the geology equipment, 3 scrapping, 1 recast) and 55
loot entries (22 die sets, 9 components, 20 skill books, 4 bullet moulds)
in 10 vanilla lists. The press add-on has 27 recipes;
the spent-cases add-on 9 items and 12 recipes (3 scrapping, 9 resizing).

## 2. What the research settled

Kept here in one line each; the evidence is in the documents named above.

- **Shell variants.** One shell item, one `AmmoType` per gun, pellets
  and damage on the gun: a slug or birdshot load cannot be a different
  round without replacing the vanilla shotguns.
- **Boxes.** `place_ammo_in_box` takes the nine rounds by item type, with no
  box item, tool or `OnCreate`. A handloaded round is the vanilla item. The
  casing-quality record is lost at boxing.
- **Loot.** A container is filled from **one** of the lists it names, chosen
  per room; how often a list is used depends on its neighbours.
- **Magazines and firearms.** A round becomes a count when loaded; a
  magazine item is destroyed on insert and a new one made on eject; nothing
  vanilla carries ModData between round, magazine and gun. The tally is
  therefore carried by observation: vanilla's own counts before and after
  each step.
- **Firing.** The round is taken in Lua, in vanilla's
  `OnWeaponSwingHitPoint` handler. A mod listener runs after vanilla's.
- **Mixed loads.** A tally cannot say which round is next. It changes by
  deterministic proportion, and any effect has to be linear in quality or
  read the load's mean, or mixing and unmixing would launder bad rounds.
- **Spent cases.** Any policy that turns fired factory rounds into
  *reloadable* brass competes with the mine, so the rate is bounded by it:
  scrap at a quarter, or resize two spent cases into one usable case (no
  XP, one level after forming, a lower casing quality). At two for one a
  resized case scrapped returns exactly what the spent cases would, and
  even with every case found half of all cases loaded are newly formed
  (`SPENT_CASE_RESEARCH.md` 8).
- **Press.** Time is its only advantage: 60 % of the hand time at the level
  a recipe unlocks, at most 68 % at level 10. A portable press was weighed
  and rejected.
- **XP.** No sequence of crafting and recycling earns more than a stock of
  material is worth. Recycling and spent cases give none.
- **Switches.** Scripts cannot be hidden from Lua once loaded, so anything
  with items, recipes, an entity or a tile sheet is switched by being a
  mod of its own; Lua-only behaviour by a sandbox option.

## 3. What is left

### 3.1 In-game verification (the next step)

`docs/INGAME_VALIDATION.md`: 22 sections in session order, each with
steps, the expected result, the console lines and a pass/fail field.
Sections 1 to 17 are the normal game; 18 to 20 the three switched
systems; 21 saves; 22 the log.

The order matters: the chain from ore to a fired round first (nothing
else matters until it has been seen), then the press (new tile sheet and
entity: the one thing that could stop a world from loading, which is why
it is an add-on), then the two systems that touch firearm code.

The multiplayer server authority needs a session of its own, on a
dedicated server with two clients, after the single-player session: its
steps are in *After the session*. Nothing in single player depends on it.

### 3.2 Final art

The inventory icons, the press's window icon, the three mods' posters
(`poster=poster.png`, 256 x 256 in each `42/`) and the Workshop
`preview.png` are the mod's own (`art/icons/make_icons.py`,
`art/workshop/make_workshop_art.py`). Every other visual (world models,
the analyzer's placed sprite, the press's tiles) is a placeholder.
`docs/PLACEHOLDER_ASSETS.md` lists each one and where it is set;
`docs/ART_HANDOFF.md` says what to draw. How the posters look in the mod
list is REQUIRES FUTURE IN-GAME VERIFICATION.

### 3.3 Balancing, from play

All central tunables; none needs code. Four of them a server owner can
also scale from the sandbox page, without editing Lua (`BALANCE_OPTIONS.md`):
ore per tile, die-set loot, component loot and Ammo Making XP. Their
defaults are 1, so the numbers below are what play uses until one is set.
Recycling yield is deliberately not an option (`BALANCE_OPTIONS.md` 1.1).

| What | Where |
|---|---|
| Ore per tile by grade | `AC_Deposits.CONFIG.reserveByGrade`; sandbox multiplier |
| Loot weights (die sets, components) | `AC_Loot.lua`; sandbox multipliers |
| Skill book loot; the books' multipliers | `AC_Loot.BOOKS`, the game's own skill book loot setting; `AC_SkillBooks.VOLUMES` |
| What the kits and the analyzer cost | `AC_Materials.EQUIPMENT_RECIPES` |
| Recipe levels, times, XP per calibre | `AC_Calibres.lua` |
| The press's time advantage and build cost | `AC_Calibres.PRESS` |
| How long a die set lasts | `AC_Calibres.DIE_WEAR` (and the die set items in `AC_Items.txt`) |
| Spent cases found per hundred shots; scrap return; resizing rate, level and quality | sandbox option; `AC_Recycling.SPENT`; `AC_SpentCases.RESIZE` (the rate is capped by `validateResize`) |
| Recycling yield (half) | `AC_Recycling.lua` |
| The largest extra jam chance, once effects are unlocked | `AC_QualityEffects.CONFIG` |

### 3.4 After verification: switches to move

| Feature | When | Change |
|---|---|---|
| Reloading press | seen loading, building and crafting | state `experimental` to `stable`; optionally fold the add-on into the main mod |
| Spent cases | seen for one gun of each class | state to `stable`; stays an add-on (it adds items) |
| Quality tracking | seen staying in step across save and load | state to `stable`; default stays a sandbox choice |
| Quality effects | only on tracking seen to stay in step, and a decision that quality should matter at the shot | state `disabled` to `experimental` |
| Multiplayer server authority | the steps of `INGAME_VALIDATION.md`, *After the session*, passed on a dedicated server with two clients | state to `stable`; the default stays off until a server owner has run it |

## 4. Optional, not planned

Nothing here is needed for a first release.

- ~~Multiplayer authority~~ (server-side sampling, assays, analyzer,
  mining): **built** behind an experimental sandbox option
  (`MULTIPLAYER_DESIGN.md` 6). Still open there: the firearm features
  (spent cases, quality tracking) on a server, and a check on a real
  server.
- ~~Reloading fired brass~~: **built** in the spent-cases add-on, two
  spent cases into one usable case (`SPENT_CASE_RESEARCH.md` 8).
- Copper recycling: low value, see `LOOT_AND_RECYCLING.md` 2.5.
- More calibres: every vanilla round with a firearm is covered. A new one
  is a `define{}` entry and three items.
- Lead ore and its geology (lead comes from vanilla junk instead,
  `METALLURGY_DESIGN.md` 12.5); cast rifle bullets (gas checks, hardened
  alloy); a press version of the cast assembly.
- Shell variants (buckshot, birdshot, slug): **not buildable without
  replacing vanilla firearms**. Vanilla has one 12 gauge item, each gun
  names one `AmmoType`, a loaded shell is only a count, and pellets,
  spread and damage are read from the gun (`SHOTGUN_AMMUNITION_RESEARCH.md`
  5.1). It would take new or replaced shotgun scripts per load, or a
  run-time rewrite of the gun before each shot with a per-shell queue,
  which multiplayer does not synchronise. Pinned by a test against the
  engine snapshot.
- Out of scope, not merely unplanned: black powder and primers from raw
  materials. Vanilla has no sulfur, saltpetre or priming compound item, and
  none is invented; gunpowder stays charcoal and fertilizer, primers toy
  caps or match heads.
- Better presses as further bench tags; batch recipes.
- Component depth (match-grade cases, case trimming). Tooling wear is
  built for die sets; the bullet moulds still last for ever.
- Recipe magazines: would need the recipes rewritten from Lua, which
  `REFERENCE_IMPLEMENTATIONS.md` 7 already declines (`AMMUNITION_DESIGN.md`
  9.2).

After every game update: `python tools/pz_compat.py --install "<game>"`.

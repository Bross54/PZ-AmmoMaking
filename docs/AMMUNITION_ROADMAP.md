# Ammunition roadmap

Where the mod stands after the code-complete pass of 2026-10-03, and what
is left. *Implemented* means Lua and data checked offline (the suite, the
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
| Geology, sampling, field and advanced assay | IMPLEMENTED | | `DEVELOPMENT.md` |
| Laboratory analyzer (placed, powered) | IMPLEMENTED; VISUAL PLACEHOLDER (a vanilla tile) | | `DEVELOPMENT.md` |
| Assay kits and analyzer obtainable | IMPLEMENTED (three recipes from vanilla items) | | `DEVELOPMENT.md`, *Item and recipe audit* |
| Mining, depletion | IMPLEMENTED | | `DEVELOPMENT.md` |
| Metallurgy, case stock | IMPLEMENTED | | `METALLURGY_DESIGN.md` |
| Nine calibres: die sets, cases, bullets, primers, powder, assembly | IMPLEMENTED; VISUAL PLACEHOLDER (vanilla icons) | | `AMMUNITION_DESIGN.md` |
| Die sets as loot | IMPLEMENTED | | `LOOT_AND_RECYCLING.md` 1 |
| Component loot (powder, primers, brass) | IMPLEMENTED | | `LOOT_AND_RECYCLING.md` 4 |
| Brass recycling | IMPLEMENTED | | `LOOT_AND_RECYCLING.md` 2 |
| Copper recycling | not built, on purpose | | `LOOT_AND_RECYCLING.md` 2.5 |
| Ammo boxes | nothing to build: vanilla boxes handloaded rounds | | `LOOT_AND_RECYCLING.md` 3 |
| Inspection: case, round, magazine, firearm | IMPLEMENTED | | `AC_AmmoInspection.lua` |
| Save data: schema, repairs, versions, upgrade runner | IMPLEMENTED | | `DEVELOPMENT.md`, `AC_SaveData.lua` |
| Multiplayer guards | IMPLEMENTED (everything authoritative is refused on a client) | | `MULTIPLAYER_DESIGN.md` 2.1 |
| Multiplayer authority | designed, not built; optional | | `MULTIPLAYER_DESIGN.md` |
| **Reloading press** | IMPLEMENTED, REQUIRES IN-GAME VERIFICATION, OFF BY DEFAULT; VISUAL PLACEHOLDER | add-on mod `AmmoMakingPress` | `RELOADING_PRESS_DESIGN.md` |
| **Spent cases** | IMPLEMENTED, REQUIRES IN-GAME VERIFICATION, OFF BY DEFAULT | add-on mod `AmmoMakingSpentCases` | `SPENT_CASE_RESEARCH.md` |
| **Quality tracking through magazines and firearms** | IMPLEMENTED, REQUIRES IN-GAME VERIFICATION, OFF BY DEFAULT | sandbox option | `AMMO_QUALITY_RUNTIME_DESIGN.md` 9 |
| **Quality effects at the shot** | IMPLEMENTED, LOCKED OFF (no switch in this version) | none | `AMMO_QUALITY_RUNTIME_DESIGN.md` 9.4 |
| Feature switches, placeholder registry | IMPLEMENTED | | `AC_Features.lua`, `AC_Visuals.lua` |
| Debug tree, compatibility check | IMPLEMENTED | `-debug` | `DEVELOPMENT.md` |
| Game-update check | IMPLEMENTED | | `tools/pz_compat.py` |
| Release packaging | IMPLEMENTED; nothing published | | `tools/build_release.py`, `WORKSHOP_DESCRIPTION.md` |

Numbers: the main mod has 41 items, 58 recipes (51 manufacturing, 3 for
the geology equipment, 3 scrapping, 1 recast) and 31 loot entries (22 die
sets, 9 components) in 6 vanilla lists. The press add-on has 27 recipes;
the spent-cases add-on 9 items and 3 recipes.

## 2. What the research settled

Kept here in one line each; the evidence is in the documents named above.

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
  *reloadable* brass competes with the mine. The policy built gives scrap
  only, at a quarter.
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

### 3.2 Final art

Every visual is a placeholder. `docs/PLACEHOLDER_ASSETS.md` lists each one
and where it is set; `docs/ART_HANDOFF.md` says what to draw. Also
missing: a `poster=` image and a Workshop `preview.png`.

### 3.3 Balancing, from play

All central tunables; none needs code.

| What | Where |
|---|---|
| Loot weights (die sets, components) | `AC_Loot.lua` |
| What the kits and the analyzer cost | `AC_Materials.EQUIPMENT_RECIPES` |
| Recipe levels, times, XP per calibre | `AC_Calibres.lua` |
| The press's time advantage and build cost | `AC_Calibres.PRESS` |
| Spent cases found per hundred shots; scrap return | sandbox option; `AC_Recycling.SPENT` |
| Recycling yield (half) | `AC_Recycling.lua` |
| The largest extra jam chance, once effects are unlocked | `AC_QualityEffects.CONFIG` |

### 3.4 After verification: switches to move

| Feature | When | Change |
|---|---|---|
| Reloading press | seen loading, building and crafting | state `experimental` to `stable`; optionally fold the add-on into the main mod |
| Spent cases | seen for one gun of each class | state to `stable`; stays an add-on (it adds items) |
| Quality tracking | seen staying in step across save and load | state to `stable`; default stays a sandbox choice |
| Quality effects | only on tracking seen to stay in step, and a decision that quality should matter at the shot | state `disabled` to `experimental` |

## 4. Optional, not planned

Nothing here is needed for a first release.

- Multiplayer authority (server-side sampling, assays, analyzer, mining):
  designed in `MULTIPLAYER_DESIGN.md`.
- Reloading fired brass (resizing a spent case into a usable one): needs
  a decision on its cost against the mine (`SPENT_CASE_RESEARCH.md` 4).
- Copper recycling: low value, see `LOOT_AND_RECYCLING.md` 2.5.
- More calibres: every vanilla round with a firearm is covered. A new one
  is a `define{}` entry and three items.
- Lead and its geology; jacketed and cast bullets; shell variants.
- Primer and powder chemistry beyond the present stand-ins.
- Better presses as further bench tags; batch recipes.
- Component depth (match-grade cases, case trimming, tooling wear).
- Skill books.

After every game update: `python tools/pz_compat.py --install "<game>"`.

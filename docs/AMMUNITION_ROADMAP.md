# Ammunition roadmap

Where the mod stands after the second pass of 2026-10-02, and what comes
next. Everything marked *implemented* is Lua and data checked offline only;
what the running game has to confirm is collected in each document's
`REQUIRES FUTURE IN-GAME VERIFICATION` section and summarised in
`DEVELOPMENT.md`.

## 1. Status

| Area | Status | Where |
|---|---|---|
| Geology, sampling, assay, analyzer, mining | implemented; sampling and mining seen working in game | `DEVELOPMENT.md` |
| Metallurgy, case stock | implemented | `METALLURGY_DESIGN.md` |
| Nine calibres: cases, bullets, primers, powder, assembly | implemented | `AMMUNITION_DESIGN.md` |
| Die sets as rare loot | implemented; **availability now worked out per room, and one outlier removed** | `LOOT_AND_RECYCLING.md` 1 |
| Brass recycling | implemented; **a source of brass is now data** | `LOOT_AND_RECYCLING.md` 2 |
| Ammo boxes | nothing to build: vanilla boxes handloaded rounds | `LOOT_AND_RECYCLING.md` 3 |
| Component loot | deliberately none | `LOOT_AND_RECYCLING.md` 4 |
| Save data | schema, fuzz, range repairs; **a version strategy and an upgrade runner** | `DEVELOPMENT.md`, `AC_SaveData.lua` |
| Reloading press | recipes prepared and switched off; **placeholder art, a tile sheet and the entity script prepared beside the mod**; waits for a session with the game | `RELOADING_PRESS_DESIGN.md`, `art/reloading_press/` |
| Spent cases | researched; **five policies costed, one recommended**; not implemented | `SPENT_CASE_RESEARCH.md` |
| Quality that affects firing | **the tally is written as pure arithmetic and wired to nothing**; no effect exists | `AMMO_QUALITY_RUNTIME_DESIGN.md` |
| Multiplayer | **authority map and design**; nothing implemented | `MULTIPLAYER_DESIGN.md`, `MULTIPLAYER_MINING.md` |
| Game-update check | **`tools/pz_compat.py`** | `DEVELOPMENT.md` |
| Release | **`tools/build_release.py`, version 0.9.0, changelog, Workshop text**; nothing published | `CHANGELOG.md`, `WORKSHOP_DESCRIPTION.md` |

Numbers: 41 mod items, 55 recipes (51 manufacturing, 3 scrapping, 1 recast),
22 loot entries in 4 vanilla lists.

## 2. What the research settled

Kept here in one line each; the evidence is in the documents named above.

- **Boxes.** `place_ammo_in_box` takes the nine rounds by item type, with no
  box item, tool or `OnCreate`. A handloaded round is the vanilla item. The
  casing-quality record is lost at boxing, as at loading.
- **Loot.** A container is filled from **one** of the lists it names, chosen
  per room; how often a list is used depends on its neighbours. A gun store
  holds a die set about one time in twelve; an army surplus store would
  have held one on average through the accessories list, and no longer
  gets any.
- **Magazines and firearms.** A round becomes a count when loaded; a
  magazine item is destroyed on insert and a new one made on eject; nothing
  vanilla carries ModData between round, magazine and gun.
- **Firing.** The round is taken in Lua, in vanilla's
  `OnWeaponSwingHitPoint` handler. Live rounds (the count plus a chambered
  round) fall by one at the shot for every firearm class; the bare count
  does not. A mod listener runs after vanilla's.
- **Mixed loads.** A tally cannot say which round is next. It changes by
  deterministic proportion, and any future effect has to be linear in
  quality or read the load's mean, or mixing and unmixing would launder bad
  rounds.
- **Spent cases.** Any policy that turns fired factory rounds into brass
  competes with the mine. Recovering only the player's own rounds needs the
  tally, and nothing else does.
- **Press.** Time is its only advantage: 60 % of the hand time at the level
  a recipe unlocks, at most 68 % at level 10, 15 % to 23 % of a whole
  batch. A portable press was weighed and rejected.
- **XP.** No sequence of crafting and recycling earns more than a stock of
  material is worth: a value exists for every consumable that every recipe
  pays its XP out of.
- **Engine probes.** `getSprite()` never returns nil; a sprite's id tells a
  defined tile from one made on the spot.

## 3. What comes next, by what it is waiting for

### READY WITHOUT GAME TEST

| Task | Notes |
|---|---|
| Copper recycling (bullets and shot back to scrap) | a second entry in `AC_Recycling.getSources()` with its own loss; the XP-potential test says at once whether it opens a loop |
| More calibres or shell variants | one `define{}` entry and three items each |
| Recipes or loot for the assay kits and the analyzer | the four items with no source in normal play; needs a decision on what they cost |
| A second tier of press recipes, batch sizes | data in `AC_Calibres.PRESS`; a decision first (below) |

### READY BUT REQUIRES RUNTIME VALIDATION

Written, or one switch away, and unproven until seen in game.

| Task | What has to be seen |
|---|---|
| **The whole ammunition chain** | one round of each class made from ore and fired: every recipe at its station, the level gates, XP lines, case quality on the items. Nothing after this matters until it has been seen |
| Die-set loot | the log line and the game-start check; a die set in a gun-store display case or a gun locker |
| Brass recycling | the four recipes; a mixed input line filled from several components; the debug material ledger before and after |
| Boxing handloaded rounds | `place_ammo_in_box` offered for rounds carrying ModData |
| The analyzer sprite probe | `OK: analyzer world sprite` now rests on the sprite's id |
| **Reloading press** | the steps in `art/reloading_press/README.md`: the tile sheet loads and is drawn, the entity builds and lists the press recipes |
| `mod.info` | the version shown, `versionMin=42.20.0` accepted |
| The release folder | `release/AmmoMaking/` loads as the repository's `mod/AmmoMaking` does |

### BLOCKED ON SOMETHING ELSE

| Task | Blocked on |
|---|---|
| **Quality tally wired to firearms** | a session with the game: wrapping seven vanilla functions cannot be proven offline. The arithmetic, its repair rules and the mapping to each vanilla step are done |
| **Spent cases** | the tally (the recommended policy needs to know which rounds are the player's), then the decision below |
| Multiplayer authority | its own stage; the design exists |
| Final press art | optional: the placeholder is enough to test with |
| A `poster=` image and a Workshop `preview.png` | art |

### BLOCKED ON A GAMEPLAY DECISION

Each needs the project owner to choose before any code is right.

| Task | The decision | Recommendation on file |
|---|---|---|
| **Spent cases** | which fired rounds leave brass, how much, and what resizing costs | none until the tally is wired; then the player's own rounds only, three cases back from four (`SPENT_CASE_RESEARCH.md` 4.1) |
| **Quality effects, misfires, jams** | whether quality should matter at the shot, and through what | vanilla's own jam chance, linear in the load's mean quality (`AMMO_QUALITY_RUNTIME_DESIGN.md` 5, 7.1) |
| Rare component loot | whether primers or cups may be found | no (`LOOT_AND_RECYCLING.md` 4) |
| Press advantage beyond time | a quality bonus or batch size would make the press mandatory | time only |
| Recycling yield | half is the highest safe figure | keep |
| How generous a gun store is | one die set in twelve stores today | decide after playing |
| A source for the assay kits and the analyzer | recipe, loot, or both | – |

### FUTURE / OPTIONAL

- Lead and its geology; jacketed and cast bullets.
- Primer and powder chemistry beyond the present stand-ins.
- Better presses as further bench tags, as the forges do.
- Progression polish: a use for levels 6 and above (nothing requires them).
- An inspection tool for a magazine or firearm, once the tally is wired.
- Component depth (match-grade cases, improved primers, case trimming,
  tooling wear): only where a tier has a gameplay role of its own. None is
  designed; each would be a decision first.

## 4. Order of work proposed

```text
1. In-game validation        the ammunition chain from ore to a fired round; loot; recycling; boxing
2. Reloading press           switch on with the prepared sheet and entity; verify; keep or revert
3. Quality tally, wired      wrap vanilla's reload functions around the existing arithmetic; verify it
                             stays in step across save and load, one gun of each class
4. Spent cases               decision, then data and the hook, off by default
5. Quality effects           decision; only on a tally seen to stay in step
6. Multiplayer authority     its own stage
```

Steps 1 and 2 touch no firearm code. Steps 3 to 5 do, and 4 and 5 begin
with a decision, not with code. After every game update:
`python tools/pz_compat.py --install "<game>"`.

# Changelog

The version is the `modversion=` line of `mod/AmmoMaking/42/mod.info`; that
line is the only place it is written. `tools/build_release.py` reads it and
refuses to package a version that has no entry here.

Versions below 1.0 are development versions: recipes, balance, item names
and save data may still change. **No version has been published.** The
entries before 0.9.0 are the project's milestones, numbered in retrospect.

"Seen in game" means the developer saw it work in Project Zomboid 42.20.4.
Everything else is checked offline only (data, Lua logic, and the installed
game's files); what the running game has to confirm is listed in
`docs/DEVELOPMENT.md`, *REQUIRES IN-GAME VERIFICATION*.

## 0.10.0 (in development) Code complete, behind switches

Everything that could be written without the game is written. What is new
at the shot or in the world is **off by default**; a game with only *Ammo
Making* ticked differs from 0.9.0 by a little loot, two menu entries and
the multiplayer guards. Nothing in this entry has been seen in game; the
session that checks it is `docs/INGAME_VALIDATION.md`.

- **Feature switches** (`AC_Features.lua`): each optional system is
  stable, experimental or disabled, and says why it is on or off in the
  game-start check. A feature that is off adds no recipe, no menu entry
  and no hook.
- **Reloading Press, as an add-on mod** (`Ammo Making: Reloading Press
  (experimental)`): a placed station built from a hammer, steel bars,
  planks and nails. 27 recipes: the case, projectile and assembly steps of
  all nine calibres with the same die sets, inputs, output and XP as by
  hand, in less time. Placeholder sprites. Off unless the add-on is
  ticked.
- **Spent cases, as an add-on mod** (`Ammo Making: Spent Cases
  (experimental)`): every round fired may leave a spent case of its
  calibre, half of them found (a sandbox option, 0 to 100). Self-loaders
  drop it at the shot, pump, bolt and lever guns at the rack, revolvers
  and break-actions at the reload. A spent case cannot be reloaded: it
  scraps to brass at a quarter of its brass, with no XP. Single player.
  Stands down beside Hot Brass.
- **Ammunition quality in magazines and firearms** (sandbox option, off):
  the casing quality of handloaded rounds follows them through loading,
  inserting, ejecting, racking, firing and unloading, as a count and a
  sum on the magazine or firearm. It observes vanilla's own counts around
  seven vanilla reload functions and never changes what they do; any
  doubt resolves to factory rounds. Single player. It has no effect on
  firing.
- **Quality effects at the shot**: written (a small extra jam chance,
  linear in the load's mean quality, through vanilla's own jam state) and
  **locked off**: no setting switches it on in this version.
- **Inspect Loaded Ammunition** on a magazine or firearm, and a debug
  entry that lists every load carried.
- **Component loot**: gunpowder, primers, brass scrap and small brass
  sheets, a little, in gun stores, hunting stores and metalwork crates.
  Never cases, bullets, rounds or die sets beyond what 0.8.0 added.
- **Multiplayer**: digging a sample, both portable assays and using the
  analyzer are now refused on a multiplayer client and shown as disabled
  options that say why, as mining and analyzer placement already were.
  Nothing is synchronised; multiplayer stays unsupported.
- **Progression**: what each level from 0 to 10 gives, as a generated
  table. No recipe was invented to fill the upper levels.
- **Placeholder visuals** in one place (`AC_Visuals.lua`), marked
  `PLACEHOLDER_VISUAL`, listed in `docs/PLACEHOLDER_ASSETS.md`.
- **Debug tree**: Stations and Diagnostics (compatibility check, feature
  flags, save schema, placeholder visuals).
- **Game-update check**: body digests of the vanilla firearm functions
  the mod wraps, so a rewritten function is reported, not only a renamed
  one.
- **Release**: one archive with the three mod folders; an add-on that
  ships Lua, or a tile sheet that does not match its sources, is refused.
- **Documents**: `INGAME_VALIDATION.md`, `ART_HANDOFF.md`,
  `PLACEHOLDER_ASSETS.md`, `REFERENCE_IMPLEMENTATIONS.md`.

## 0.9.0 (2026-10-03) Foundations, tooling, equipment recipes

Three new recipes, one loot change and one fix. Otherwise foundations,
tooling and hardening.

- **The assay kits and the laboratory analyzer can be made.** Three
  recipes at any surface, from vanilla items (a magnifying glass or loupe,
  tweezers, paper; a calculator and electronics scrap; sheet metal, a car
  battery charger and electronics for the analyzer). The two kits weigh
  what their parts do: 0.7 and 1.2 instead of 1.0 and 1.5. Until now all three came only
  from the debug menu, and with them mining, which needs an assayed
  sample: no zinc, so no brass beyond the trace of brass scrap vanilla
  leaves in bins. No XP for making them. Not crafted in game yet.

- **Quality tally**: the arithmetic for carrying ammunition quality in a
  magazine or firearm (`AC_QualityTally`), as pure functions that nothing
  calls yet. No firearm code is touched and firing is unchanged.
- **Game-update check**: `tools/pz_compat.py` compares an installed game
  with everything the mod relies on and reports PASS, WARNING or BREAKING.
- **Test mock fidelity**: mocked engine objects now refuse a call the real
  42.20.4 engine would refuse (wrong argument count or type).
- **Test generator fixed**: the seeded "random" runs of the suite used a
  generator whose arithmetic overflows Lua's numbers; every seed ended in
  the same loop of 10,466 values. Replaced by an exact one. Every
  invariant still holds under it.
- **Release packaging**: `tools/build_release.py`, this changelog, a version
  in `mod.info`, `versionMin=42.20.0`.
- **Reloading press, prepared beside the mod**: placeholder sprites, a
  builder for the game's tile-sheet formats (verified by writing vanilla's
  own files back byte for byte), the sheet and the station script. Not in
  the mod; the press stays off.
- **Loot**: gun-store die sets moved from the accessories list to the
  magazine-and-ammunition list. Same odds in a gun store; army surplus
  stores, which would have held about one die set each, hold none.
- **Fixed**: the game-start check of the analyzer's sprite could never
  fail (the engine's `getSprite` never returns nil). It now does its job.
- **Save data**: a layout version on the depletion store, an upgrade
  runner, and a save written by a later version is never reset (and
  yields no ore while its records cannot be read).
- **Brass recycling**: sources of brass are data (one today).
- **Debug**: a material ledger of the carried inventory, and a kit with
  the parts for the three equipment recipes.
- **Economy tables**: all nine calibres, four loadouts, craft counts, hand
  and press time.
- Research and design, no code: spent-case policies in numbers, the
  firearm matrix, mixed-ammunition semantics, the multiplayer authority
  map, a portable press (rejected), press art specification.

## 0.8.0 (2026-10-02) Loot, recycling, save safety

- Die sets as rare loot in four vanilla loot lists.
- Brass recycling: unwanted brass components to brass scrap at half the
  brass and no XP; brass scrap recast into ingots.
- Vanilla ammo boxes confirmed to take handloaded rounds; the mod adds no
  box recipe.
- Save data: a schema of every stored key; damaged or hand-edited values
  are read back within their range (kit uses, analyzer timer, qualities).
- Reloading press recipes prepared in the model and switched off.

## 0.7.0 (2026-10-02) Shotgun shells

- 12 gauge: brass hull, shot charge, wad, large pistol primer, assembly
  into the vanilla shell.

## 0.6.0 (2026-10-02) Rifle ammunition

- 5.56, .30-30 and .308: cases, bullets, die sets, small and large rifle
  primers, assembly into the vanilla rounds.

## 0.5.0 (2026-10-02) Pistol ammunition

- 9mm, .38 Special, .45 ACP, .357 Magnum and .44 Magnum from a data-driven
  calibre model: die sets, cases with a rolled quality, copper bullets,
  small and large pistol primers, gunpowder from charcoal and fertilizer.
- Inspection of empty cases and loose handloaded rounds.

## 0.4.0 (2026-10-02) Metallurgy and case stock

- Zinc smelting, copper and zinc ingot casting and 7 + 3 brass alloying on
  the vanilla furnaces; small brass sheets at the forge; brass case cups.
- Ammo Making level requirement and XP on the mod's recipes.

## 0.3.0 (2026-09-23) Placed laboratory analyzer, mining hardening

- The laboratory analyzer as a placed, powered world object: place, start,
  cancel, collect, pick up; state repair.
- Mining fixes after the first in-game test on 42.20.4 (**seen in game**:
  the mining action, its animation, zinc ore on the ground, depletion,
  exhaustion, cancelling).
- Compatibility self-check at game start; one debug tree; translations.

## 0.2.0 (2026-09-23) Mining

- Pickaxe extraction inside an assayed 3x3 area, finite per-tile reserves,
  persistent depletion, XP and tool wear.
- Offline test harness.

## 0.1.0 (2026-08-14) Geology and assays

- Ammo Making skill; procedural per-save geology for copper and zinc;
  geological samples; field, advanced and laboratory assays.
- Ammunition quality and inspection prototype (test cartridge).

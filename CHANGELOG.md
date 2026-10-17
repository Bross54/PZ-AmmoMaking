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

## 0.11.0 (in development) Own art, books, lead, resizing, balance options, server authority

What was added after 0.10.0. A game with only *Ammo Making* ticked gains
skill books, lead and cast bullets, the mod's own icons and posters, and a
sandbox page whose defaults change nothing; everything else new is in an
add-on or behind an experimental switch that is off. Nothing in this entry
has been seen in game; the session that checks it is
`docs/INGAME_VALIDATION.md`.

- **Build 42.21**: the game updated to 42.21.0 on 2026-10-17; the
  compatibility tool found nothing that breaks (a new vanilla tag, loot
  lists refreshed), and every mod.info now asks for 42.21.0, the build it
  was checked against.
- **Compatibility with six gun mods**: an add-on per gun mod, each
  requiring it, for 38 calibres in all (`docs/GUN_MOD_COMPATIBILITY.md`):
  Vanilla Firearms Expansion, Rain's Firearms (and Expanded),
  GaelGunStore, Real Firearms and Modern Firearms System, besides the
  7.62x39 of Vanilla Weapons Plus. Packs whose round ids mean different
  calibres (`Base.762Bullets` is 7.62x39 in VFE, 7.62x51 in Rain's) are
  `incompatible=` with each other. Rimfire is left out. Names in all 27
  languages, derived from each language's own names
  (`tools/derive_addon_translations.py`).
- **Hot Brass bridge** (*Ammo Making: Hot Brass Casings*): the casings Hot
  Brass ejects are resized at the die set like the mod's spent cases.
- **A warning beside Modern Firearms System**, whose `Base.Bullets38` is a
  6.8mm round: the .38 Special recipes make it.
- **Debug calibre kits** list the calibres of the add-ons in the game.
- **7.62x39 add-on** (*Ammo Making: 7.62x39 (experimental)*, requires
  Vanilla Weapons Plus - Gunworks Edition): the AK-47's round
  (`Base.762Bullets`) handloaded like the vanilla rifle rounds, with its
  die set, case, copper and gas-checked cast bullets, every mould and
  treatment. The calibre is an extension (`AC_Calibres.EXTENSIONS`): its
  items and recipes are generated into the add-on, and the vanilla
  calibres, the press, the spent cases and loot are untouched.
- **Poor handloads jam more often**: the firing effect, written and locked
  until now, is an experimental sandbox option, off by default and only
  with quality tracking on.
- **Three more balance options** (default 1, nothing changes unless set):
  the finishing bonus, the die set regrinding loss, the extra jam chance.
- **Broken die sets and iron moulds smelt back** to steel and iron at the
  vanilla furnaces, like the small punch set and the file.
- **Metal names inside sentences** follow the language: German keeps
  "Kupfer" (a translation key per metal, lowercase where it had been).
- **Annealing cases** with a blowtorch: five empty cases and one use of a
  vanilla blowtorch, +3 case quality once, no XP. *Inspect Ammunition*
  says when a case was annealed or a cast bullet lubed.
- **Debug kits** for the new systems: a casting kit (every mould of every
  material, lead, candle, copper for gas checks), a mould materials kit
  (stone, clay, sand, chisel, knife) and a treatment kit (blowtorch, steel
  wool, file).
- **Player guide** in the README: which mould, tool care, finishing.
- **Machine translations** of all three mods into 27 of the game's
  languages (AR, CA, CH, CN, CS, DA, DE, ES, ES_CL, ES_MX, FI, FR, HU, ID,
  IT, JP, KO, NL, NO, PL, PT, PTBR, RO, RU, TH, TR, UA; AR, ES_CL and ES_MX
  share one Latin American Spanish text; AR, ES, PT and NO write .45 Auto
  as the game does there). Vanilla's own words are reused
  for vanilla things. Machine-made, for native speakers to correct; the
  generated English files (the add-ons' recipe names) are not regenerated
  into them.
- **Rifles cast lead, with a gas check**: a rifle bullet mould (forged, or
  of stone, clay or sand), cast bullets for the 5.56, .30-30 and .308, and
  *Punch Copper Gas Checks* (ten from a copper scrap). The rifle's cast
  assembly takes a gas check; its cast bullets roll 10 lower than a
  pistol's. The rifle mould is found among a hunter's things.
- **Candle-wax lube** for cast bullets: five bullets and ten uses of a
  candle, +5 quality once, no XP.
- **Regrinding a worn die set** with a file or whetstone, broken ones too:
  each regrind lowers the condition it can reach by 2 (8, 6, 4, 2), so a
  die set still wears out. No XP.
- **Iron bullet moulds wear** as slowly as die sets (some 900 casts).
- **Spent cases cleaned with steel wool** (Spent Cases add-on): five cases
  and one use of steel wool; a case resized from clean ones rolls -5
  instead of -10.
- **Seven more own icons**: the stone, clay, fired-clay and sand moulds,
  the rifle mould, the gas check and the cast rifle bullet.
- **Die sets wear out**, as vanilla's small punch set does: condition 10,
  shown on the item, and each completed case, swaging or assembly (by hand,
  at the press or resizing) has a small chance of costing a point; Ammo
  Making and Maintenance make it rarer. A die set lasts about 900 to 1,100
  crafts, some 360 to 440 copper pistol rounds; a worn-out one is refused by
  its recipes and is forged or found again (`docs/AMMUNITION_DESIGN.md` 7).
  The engine does the wearing; a die set from an older save is a full one.
- **Bullet moulds of stone, clay and sand**, for casting without a forge:
  a stone mould carved from a stone block with a hammer and chisel (wears,
  some 300 casts), a clay mould shaped from dug clay and fired in a kiln
  (breaks after one cast, as vanilla's clay moulds do) and a sand mould
  rammed from a dug sandbag with a clay binder (used up by its cast). How a
  mould is made decides the bullet's quality: iron +0, stone -5, clay -10,
  sand -20 on the roll. Cast bullets now carry a quality, a round with cast
  bullets averages its case and its bullet, and *Inspect Ammunition* shows
  cast bullets ("Bullet quality") and labels a round's record "Round
  quality". 8 items, 26 recipes; XP, levels and metal are the iron cast's
  (`docs/METALLURGY_DESIGN.md` 12.8).
- **The mod's own art.** 36 original inventory icons drawn by
  `art/icons/make_icons.py`: the main mod's items, the spent cases (a
  tarnished drawing of their own) and the press's 48 x 48 window icon.
  A poster for each of the three mods (`poster=poster.png` in each
  `mod.info`, 256 x 256 in `42/`) and the Workshop `preview.png`, drawn by
  `art/workshop/make_workshop_art.py`. No vanilla or third-party pixel;
  world models and the press's tile art are still placeholders.
- **The analyzer takes a radio receiver** as its signal part, as an
  alternative to an amplifier; ten electronics scrap keep its parts at its
  12 kg.
- **Balance options for server owners** (sandbox page *Ammo Making*):
  ore per deposit tile (x0.5 to x3), die sets as loot (x0 to x2),
  reloading stock as loot (x0 to x2) and an Ammo Making XP multiplier
  that the game applies like its own per-skill ones (used when the global
  XP multiplier is off). All default to 1: nothing changes unless they are
  set. The loot multipliers are applied once the save's options are
  loaded, and only to containers filled from then on. Recycling yield is
  not an option, on purpose (`docs/BALANCE_OPTIONS.md`).
- **Skill books**: five volumes, *Ammo Making I* to *V*, with the game's
  own levels (two each), pages and the multipliers it gives its Aiming and
  Reloading books (1.5 to 8). Entered in vanilla's reading table from a
  server file and again at game and server start; found, never made, in
  a gun store's shelves and, rarely, bookstores, libraries and a
  survivalist's things, scaled by the game's own skill book loot setting.
  Own icons; the Reloading books' model.
- **Lead and cast bullets** (`docs/METALLURGY_DESIGN.md` 12): lead is
  melted at any furnace from vanilla's Lead Pipe (two lead scrap) and Jig
  Lures (one from five), with no XP; a pistol bullet mould and a buckshot
  mould are forged from iron bar quarters or found beside the die sets;
  cast bullets and lead shot for the five pistol calibres and the shell
  are cast at a Primitive Furnace and assembled into the same vanilla
  rounds, at the copper recipes' levels, XP and times. Lead replaces only the bullet's copper; the brass, and so the
  zinc, still comes from the mine. 16 recipes, 9 items; no lead ore
  (geology is unchanged).
- **Resizing fired brass** (in the Spent Cases add-on): *Resize Spent
  ... Case*, one recipe per calibre, takes two spent cases and keeps the
  calibre's die set and a hammer, and makes one usable case of the
  calibre. No XP, the forming recipe's time, one level after forming, and
  a casing quality one band below a formed case's. Two for one is the
  most the economy allows: a resized case scrapped returns no more than
  the spent cases would, and even with every case found half of all cases
  loaded are newly formed (`docs/SPENT_CASE_RESEARCH.md` 8). The spent
  cases debug kit now holds every die set.
- **Multiplayer server authority** (sandbox option, off, experimental,
  never run on a server; `docs/MULTIPLAYER_DESIGN.md` 6): with it on, a
  multiplayer client asks and the server checks and performs digging,
  both assays, the analyzer (place, start, cancel, collect, pick up) and
  mining. The three timed actions use Build 42's own mechanism (a
  `complete()` the engine runs on the server; the files moved from
  `client/` to `shared/`); the menu clicks are client commands. The server
  checks distance (2 tiles), the tool in hand, that every item named is
  the requester's own, whole coordinates on a loaded square, the metal,
  and one request of each kind per player and second; items, item fields,
  XP (`addXp`), the analyzer's ModData and the depletion store are sent
  back with vanilla's calls. Two players cannot both take the last ore or
  collect one sample. **Single player is unchanged**: a test replays a
  whole session against the files as they were seen working in game
  (`tests/sp_reference/`) and compares every message, item, XP grant and
  console line. Spent cases and quality tracking stay single player.
- **Game-update check**: the snapshot also records each firearm's pellets
  per shot; the drift tool's self-test checks the one icon still borrowed.
- **Release**: the builder checks each mod's poster (named, shipped, 256 x
  256) and the Workshop preview, and writes a Workshop item folder
  (`release/Workshop/AmmoMaking/`: `preview.png` beside `Contents/mods/`).
- **Researched, not built** (the evidence is in the documents named):
  - *Recipe magazines*: a learned recipe still needs its level, and an
    auto-learn line cannot name a skill registered from Lua
    (`docs/AMMUNITION_DESIGN.md` 9.2).
  - *12 gauge shell variants* (buckshot, birdshot, slug): vanilla has one
    12 gauge item, each shotgun names one ammo type, a loaded shell is only
    a count and the pellets, spread and damage are the gun's. A variant
    would mean replacing the vanilla shotguns
    (`docs/SHOTGUN_AMMUNITION_RESEARCH.md` 5.1); a test pins the evidence.
- **Out of scope**: black powder and primers from raw materials (sulfur,
  saltpetre, priming compound). Vanilla has no such items; gunpowder stays
  charcoal and fertilizer, primers stay toy caps or match heads.

## 0.10.0 (2026-10-03) Code complete, behind switches

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

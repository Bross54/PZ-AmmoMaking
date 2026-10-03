# Ammo Making

> **Current target:** Project Zomboid Build 42.20 Stable  
> **Status:** 🚧 Work in Progress  
> **Development:** 🤖 Built with AI assistance

---

# 🤖 AI Disclosure

This project is being developed with significant assistance from AI tools, primarily **ChatGPT by OpenAI**.

AI assistance is used throughout development for:

- code generation
- code iteration and refactoring
- debugging and troubleshooting
- Project Zomboid Lua experimentation
- system architecture
- gameplay system design
- documentation
- development planning
- research assistance

AI-generated suggestions and code are **not treated as automatically correct**.

Features are actively tested in Project Zomboid, while gameplay direction, implementation decisions and final changes are reviewed and tested by the project author.

Because the project is under active development, AI-assisted code may contain bugs, incorrect assumptions or compatibility issues.

Bug reports, testing feedback and technical suggestions are welcome.

---

# About

**Ammo Making** is an advanced ammunition manufacturing, geology, mining and metallurgy mod for **Project Zomboid Build 42**.

The goal of the mod is to turn ammunition production into a complete progression system rather than a simple crafting recipe.

Players will be able to survey the world for raw materials, analyze geological samples, mine finite ore deposits, process metals, manufacture ammunition components and eventually produce different types and qualities of ammunition.

---

# Overview

Ammo Making is designed around a complete production chain:

```text
Geological Surveying
        ↓
Ore Deposits
        ↓
Mining
        ↓
Copper + Zinc
        ↓
Smelting
        ↓
Brass Production
        ↓
Case / Projectile Manufacturing
        ↓
Primers + Powder
        ↓
Cartridge Assembly
        ↓
Inspection
        ↓
Finished Ammunition
```

The mod aims to make ammunition production expensive, technical and rewarding while still fitting naturally into Project Zomboid's survival gameplay.

---

# Current Features

## Ammo Making Skill

A new **Ammo Making** crafting skill with 10 progression levels.

The skill is intended to affect:

- ammunition manufacturing
- component quality
- inspection ability
- advanced ammunition recipes
- manufacturing reliability
- access to more complex production methods

The skill is integrated into the Build 42 perk system.

---

## Procedural Geology

Copper and zinc are distributed throughout the world using deterministic procedural geology.

Each save receives its own geology layout.

The same save always generates the same geology after restarting the game.

Current geology supports:

- procedural copper concentration
- procedural zinc concentration
- large-scale ore regions
- smaller local variations
- concentration grades
- deterministic per-save geology seeds
- 3×3 geological survey areas

Ore distribution is calculated procedurally instead of storing geology information for every tile in the world.

---

## Geological Sampling

Players can collect geological samples from valid outdoor terrain using a shovel.

Samples represent a **3×3 area** around the sampling location.

Sampling currently supports:

- natural ground
- dirt
- grass
- farmland / plowed terrain
- sand
- gravel

Sampling is blocked on:

- indoor floors (any square inside a room)
- constructed flooring
- roads
- asphalt
- water
- upper floors and basements

Sampling and mining share one terrain rule (`AC_Geology.isSurveyableSquare`), so they always agree.

---

# Geological Assay System

Geological samples can be analyzed using several levels of equipment.

## Making the equipment

All three are put together at any surface from vanilla items. None of
them is found ready-made, and making one earns no Ammo Making XP: a kit
pays per assay.

| Equipment | Ammo Making level | Takes |
|---|---|---|
| Field Assay Kit (20 assays) | 0 | a magnifying glass or a loupe, tweezers (bought or forged), 5 sheets of paper |
| Advanced Field Assay Kit (10 assays) | 1 | the same, a calculator and 2 electronics scrap |
| Laboratory Assay Analyzer | 2 | 4 sheet metal, a car battery charger, 8 electronics scrap, 3 electric wire, an amplifier, a light bulb, 6 screws; a screwdriver is kept |

The kit parts are ordinary household and office loot. The analyzer's
amplifier is the scarce part: electricians' and engineers' tool stores,
or a speaker taken apart with a screwdriver (a vanilla recipe). The
amplifier and the bulb must not be broken.

These recipes are new and have not been crafted in the game yet; the
amounts are a first guess and easy to change (`AC_Materials.EQUIPMENT_RECIPES`).

## Field Assay Kit

Provides a basic geological grade.

Example:

```text
Copper: Moderate
Zinc: Poor
```

Designed for quick exploration and approximate deposit identification.

---

## Advanced Field Assay Kit

Provides a more accurate estimate of ore concentration.

Results are displayed as an estimated percentage range.

Example:

```text
Copper: 42% - 62%
Zinc: 8% - 28%
```

---

## Laboratory Assay Analyzer

A placeable powered laboratory machine used for high-accuracy geological analysis.

Features:

- placeable world object: right-click the analyzer item → **Place Laboratory Assay Analyzer**, then pick a tile with the vanilla placement cursor
- persistent machine state, stored on the placed object
- one sample at a time
- requires electricity: a generator, or utility-grid power when the analyzer stands inside a building (the same rule vanilla Build 42 uses for its appliances)
- processing pauses when electricity is unavailable
- approximately 24 in-game hours per analysis
- processing survives save/reload
- a running assay can be cancelled; the sample comes back exactly as it went in, with no XP
- **an analyzer that is processing a sample or holding a finished result cannot be picked up**: cancel the assay or collect the sample first (Pick Up is shown disabled with the reason)
- picking up takes a short timed action next to the analyzer
- laboratory results use approximately ±2% instrument tolerance

Analyzers simply dropped on the floor (the original behaviour) still work, so samples stored in them in existing saves are not lost. Their pickup is vanilla's and cannot be blocked; if a dropped analyzer is picked up mid-assay and later placed, the assay moves onto the placed analyzer.

Example result:

```text
Laboratory Assay

Copper: 67%
Grade: Good

Zinc: 14%
Grade: Trace

Instrument Tolerance: +/-2%
```

The Laboratory Assay Analyzer currently uses a temporary vanilla Project Zomboid world sprite while final visuals are still in development.

---

# Ammunition Quality System

Ammo Making includes an ammunition quality framework intended to support player-manufactured cartridges.

A cartridge can track separate quality values for:

- casing
- primer
- projectile
- assembly
- powder load
- reload count
- overall quality
- failure chance
- catastrophic failure chance

Current testing supports quality states such as:

```text
Perfect
Good
Poor
Dangerous
Overloaded
```

Ammunition inspection becomes more informative depending on the player's Ammo Making skill.

Higher skill levels reveal more detailed information about cartridge quality and potential problems.

---

# Materials

## Copper and brass

Ammo Making uses Project Zomboid's own Build 42 items and never duplicates them:

```text
Base.CopperOre
Base.CopperScrap
Base.CopperIngot
Base.BrassIngot
Base.BrassScrap   (what brass recycling hands back)
```

## Zinc

Vanilla Build 42 has no zinc, so the mod adds it, copying the vanilla copper items:

```text
AmmoMaking.ZincOre     40.0, two-handed, like Base.CopperOre
AmmoMaking.ZincScrap   0.5, like Base.CopperScrap
AmmoMaking.ZincIngot   6.0, like Base.CopperIngot
```

The zinc items use vanilla icons and models as placeholders.

---

# Metallurgy

Metallurgy extends the vanilla Build 42 furnaces. There is no custom furnace, fuel, heat or timer: the mod adds recipes to the vanilla Primitive and Simple Furnace crafting menus.

```text
Base.CopperOre                       AmmoMaking.ZincOre
      │ vanilla "Smelt Copper Ore"         │ "Smelt Zinc Ore"
      │ 4 charcoal, Primitive Furnace      │ 4 charcoal, Primitive Furnace
      ▼                                    ▼
10 Base.CopperScrap                  10 AmmoMaking.ZincScrap
      │ "Cast Copper Ingot"                │ "Cast Zinc Ingot"
      │ 10 scrap + 4 charcoal              │ 10 scrap + 4 charcoal
      ▼ Simple Furnace                     ▼ Simple Furnace
Base.CopperIngot                     AmmoMaking.ZincIngot
      └────────────────┬───────────────────┘
                       ▼ "Cast Cartridge Brass", Simple Furnace
                         7 copper ingots + 3 zinc ingots + 10 charcoal
                10 Base.BrassIngot
```

- casting needs an empty ceramic crucible, tongs and an ingot mold; all three are kept (a clay mold breaks, as it does for vanilla casting)
- one ore is one ingot of metal; ten ore make ten brass ingots, with nothing created or lost on the way
- vanilla "Smelt Copper Ore" is used as it is
- Ammo Making XP per completed craft; crafting gets 5 % faster per Ammo Making level through the game's own recipe timing
- no Blacksmithing requirement, like vanilla smelting
- brass quality is not tracked yet; it becomes relevant when cartridge cases are made

**Not yet tested in game.** The recipes were written from the installed Build 42.20.4 files and are covered by the offline tests; see `docs/METALLURGY_DESIGN.md`.

---

# Ore Extraction (first version)

Geology now feeds a finite, per-tile deposit system. A pickaxe alone is not enough to mine.

Gameplay loop:

```text
Dig geological sample (shovel, 3×3 area)
        ↓
Assay the sample (field / advanced / laboratory)
        ↓
Carry the assayed sample to the site
        ↓
Right-click ground inside the sampled 3×3 area with a pickaxe equipped
        ↓
"Mine Copper Ore" / "Mine Zinc Ore"
        ↓
Ore is dropped on the mined tile
```

Rules:

- mining is only offered for metals the assay reports above `None`
- the assay only decides what the player **knows**; the ore actually extracted always comes from the tile's true geology
- each tile has a deterministic reserve derived from its concentration grade (`Poor`/`Moderate` 1, `Good` 2, `Rich` 3, `Very Rich` 4, `Trace` 0)
- each extraction removes one unit and drops one ore (`Base.CopperOre` or `AmmoMaking.ZincOre`)
- depletion is persistent; only worked tiles are stored in save data (global ModData)
- a tile is only shown as exhausted after someone has worked it
- same terrain rules as sampling: outdoor natural ground, ground level only, never water, never inside a building
- dropping the assayed sample, unequipping the pickaxe or breaking it cancels a running extraction
- Ammo Making level reduces extraction time (up to 40% at level 10)
- Ammo Making XP is granted per extracted ore and per completed assay
- accepted tools: `Base.PickAxe`, `Base.PickAxeForged`

Invariants (enforced in code, asserted by the offline tests):

- one completed mining action gives at most one ore, one reserve decrement, one XP grant and one pickaxe wear roll
- an interrupted or invalidated action gives none of those
- only a real extraction writes depletion to the save; menus and lookups never do
- the assay decides what may be attempted, the true geology decides what exists
- outside `-debug`, no label or message shows exact concentrations or reserve counts

Current limitations:

- **the mining loop has passed a first in-game test on Build 42.20.4**; save/reload persistence of depletion is still unverified (see `docs/DEVELOPMENT.md`, *Real-game validation*)
- multiplayer mining is intentionally disabled: a multiplayer client sees a disabled "Mine Ore" option (design in `docs/MULTIPLAYER_MINING.md`)
- the pickaxe action uses the vanilla `DigPickAxe` animation (confirmed in game) and the `Shoveling` sound as a placeholder

Offline checks (no game required):

```text
lua5.1 tests/run_tests.lua
```

`tests/mock_pz.lua` mocks the Project Zomboid API; `tests/run_tests.lua` loads every mod file and runs 92,000+ checks over geology, reserves, depletion, persistence, terrain, prospecting, the timed actions, menus, assays, the laboratory analyzer (state machine, pick-up rule, cancel, malformed data), metallurgy, case stock and ammunition components (the generated recipe script against its Lua mirror, the nine rounds (five pistol calibres, three rifle calibres and the 12 gauge shell) and four primer families, cross-calibre isolation, material conservation from ore to finished rounds, case quality and inspection, level requirements, a simulated XP career, the press recipes, the generated balance tables), translation keys, debug gating, startup cost and the compatibility check. It cannot verify vanilla item ids, animations, sounds or engine behaviour; the placed analyzer's engine side (placement cursor, world object, saving) is mocked and still needs the in-game test.

Developer notes: `docs/DEVELOPMENT.md` (module map, constants, invariants, timed-action conventions, debug tools, what still needs the game). Metallurgy: `docs/METALLURGY_DESIGN.md` (the implemented furnace recipes, items, skill and conservation rules) and `docs/VANILLA_METALLURGY_RESEARCH.md` (what vanilla Build 42.20.4 provides, read from the installed files and jar).

---

# Planned Mining Machine

A large **3×3 mining machine** is planned for extracting ore from discovered deposits.

Current design goals include:

- must be placed above suitable deposits
- powered directly by gasoline
- requires an engine
- mechanical components
- drill / mining components
- component wear
- fuel consumption
- mining output based on local geology
- finite resource extraction

The machine will not simply generate random ore independently of the geology system.

---

# Ammunition Manufacturing

Vanilla Build 42 has finished rounds and gunpowder, and nothing else: no cartridge cases, primers, bullets or lead, and no recipe that makes a round. Ammo Making adds the components and assembles them into the **vanilla round items**, so vanilla firearms and magazines work unchanged. No recipe in the chain needs finished ammunition.

```text
Base.BrassIngot
      │ Forge Small Brass Sheets (vanilla Primitive Forge)
      ▼
10 small brass sheets ──────────────► Make Small Pistol Primers
      │ Punch Brass Case Cups            1 sheet + 10 toy caps (or 20 match uses) → 10 primers
      ▼
2 brass case cups per sheet
      │ Form 9mm Case (9mm Handloading Die Set + hammer)
      ▼
Empty 9mm Case  (its quality is rolled here)

Base.CopperScrap ── Swage 9mm Copper Bullets ──► 2 bullets
2 charcoal + 2 uses of fertilizer ── Mix Gunpowder (mortar and pestle) ──► 1 jar of vanilla Base.GunPowder (10 charges)

case + primer + bullet + 1 charge ── Assemble 9mm Round ──► 1 Base.Bullets9mm
```

- **Calibres**: all five vanilla pistol calibres (9mm, .38 Special, .45 ACP, .357 Magnum, .44 Magnum), all three vanilla rifle calibres (5.56, .30-30, .308) and the vanilla 12 gauge shell; table below. A calibre is one data entry; no code names one, and pistol rounds, rifle rounds and the shell share one model. Each has its own case, bullet and die set, and nothing of one calibre fits another.
- **12 gauge shells**: a brass hull drawn from three case cups, a charge of copper shot swaged from one copper scrap, a large pistol primer, three charges of gunpowder and a wad of ripped sheet or cotton, assembled into the vanilla `Base.ShotgunShells`. Vanilla has a single shell and puts the nine pellets on the gun, so there are no buckshot or slug variants.
- **Die set**: one forged tool per calibre (two steel bar quarters at a Simple Forge), kept by every recipe of that calibre. Rifles are loaded by hand with the same kind of die set; they take about twice as long. A reloading press is designed as the faster tier above it and will take the same die sets (`docs/RELOADING_PRESS_DESIGN.md`); its recipes, a tile sheet with placeholder art and its station script are prepared and switched off, and none of it is in the mod yet.
- **Bullets are copper**: vanilla has no lead, and copper is already mined.
- **Primers** come in four families (small and large pistol, small and large rifle), all made the same way from a small brass sheet and toy cap-gun caps or match heads. A large primer holds twice the material of a small one; a rifle primer takes half as much priming charge again and is never interchangeable with a pistol primer. **Gunpowder** is charcoal and fertilizer. Vanilla has no sulfur or nitrate item and none is invented.
- **Case quality**: 1–100, rolled when a case is formed from the maker's Ammo Making level with a random spread, stored on the case and passed on to the assembled round. It never changes how much material a recipe uses. Nothing reads it in combat yet.
- **Inspection**: right-click an empty case, or a loose round you loaded yourself, and choose *Inspect Ammunition* to see its calibre and case quality (a label from level 1, the number from level 5). Factory rounds have nothing to inspect. The record stays with the loose round: a magazine or firearm keeps only a count.
- **Progression**: metallurgy and case stock from level 0; 9mm and .38 Special rounds at level 3, .45 ACP, .357 Magnum and 12 gauge shells at 4, .44 Magnum and the three rifle rounds at 5, each calibre's die set, cases and bullets one or two levels earlier. In a simulated career level 3 comes after about 19 ore, level 4 after 29, level 5 after 54, and the first rifle round after 70 ore and some 390 pistol rounds and shells. Nothing requires level 6.
- **Material balance**: larger calibres cost more through whole-number knobs: cups of brass per case, projectiles per copper scrap, charges of gunpowder and, for a shell, a wad.
- **Boxes**: handloaded rounds are the vanilla items, so vanilla's own *place ammo in box* recipe already packs them, 50, 20 or 25 to a box. The mod adds no box recipe. A box keeps only a count, so a round's case-quality record does not survive boxing.
- **Die sets as loot**: besides forging one, a die set can be found, rarely: in a gun store's display case (any calibre), a garage gun locker (handgun dies) or among a hunter's things (rifle and shotgun dies). 9mm and .38 Special are the common ones, the magnums and .45 less so, rifle and shotgun dies rare. At default loot settings about one gun store in twelve holds a die set; military lockers are the likeliest place for handgun dies. Finding one opens nothing early: the Ammo Making levels are on the recipes. No component is loot.
- **Brass recycling**: case cups, small brass sheets and empty cases or hulls you no longer want can be hammered into vanilla brass scrap on any surface, and ten brass scrap cast back into a brass ingot at a furnace. **Half of the brass is lost** and recycling gives **no Ammo Making XP**. Finished rounds, primers and bullets cannot be scrapped (vanilla already takes a round apart for its powder).

<!-- CALIBRE TABLE: generated by tests/write_recipes.lua from AC_Calibres.lua. Do not edit. -->

| Round | Type | Vanilla item | Primer | Cups per case | Projectiles per scrap | Powder charges | Wads | Round at level | Ore per 100 rounds |
|---|---|---|---|---|---|---|---|---|---|
| 9mm | pistol | `Base.Bullets9mm` | small pistol | 1 | 2 | 1 | 0 | 3 | 11 |
| .38 Special | pistol | `Base.Bullets38` | small pistol | 1 | 2 | 1 | 0 | 3 | 11 |
| .45 ACP | pistol | `Base.Bullets45` | large pistol | 1 | 1 | 1 | 0 | 4 | 17 |
| .357 Magnum | pistol | `Base.Bullets357` | small pistol | 1 | 2 | 2 | 0 | 4 | 11 |
| .44 Magnum | pistol | `Base.Bullets44` | large pistol | 2 | 1 | 3 | 0 | 5 | 22 |
| 5.56 | rifle | `Base.556Bullets` | small rifle | 2 | 2 | 3 | 0 | 5 | 16 |
| .30-30 | rifle | `Base.3030Bullets` | large rifle | 2 | 1 | 4 | 0 | 5 | 22 |
| .308 | rifle | `Base.308Bullets` | large rifle | 3 | 1 | 5 | 0 | 5 | 27 |
| 12 Gauge | shotgun | `Base.ShotgunShells` | large pistol | 3 | 1 | 3 | 1 | 4 | 27 |

<!-- END CALIBRE TABLE -->

Rifle powder is a compressed scale: a literal .308 charge would be nearly a whole jar per round.

All balance values are tunable. They live in one file, `AC_Calibres.lua`; the table above, the recipe script and the full balance tables of `docs/AMMUNITION_DESIGN.md` are generated from it.

**Not yet tested in game.** Everything is written from the installed Build 42.20.4 files and covered by the offline tests. Design, balance and the list of what needs a game run: `docs/AMMUNITION_DESIGN.md`; vanilla research: `docs/VANILLA_AMMUNITION_RESEARCH.md`, `docs/RIFLE_AMMUNITION_RESEARCH.md`, `docs/SHOTGUN_AMMUNITION_RESEARCH.md`.

---

# Planned Metallurgy Extensions

The first metallurgy stage (ore to brass on the vanilla furnaces) is implemented; see *Metallurgy* above. Still planned:

- brass quality, decided when cartridge cases are made
- more than one brass composition
- balance of charcoal, time and XP

---

# Planned Ammunition Manufacturing

The component chain above is the foundation. Still planned:

- the reloading press station (designed in `docs/RELOADING_PRESS_DESIGN.md`; its recipes are prepared and 40 % faster than by hand, the world object needs a tile sheet of its own and an in-game pass)
- spent cases: researched, not built, and waiting for a decision on what fired factory rounds should leave behind (`docs/SPENT_CASE_RESEARCH.md`)
- a way for round quality to reach the shot: designed, not built (`docs/AMMO_QUALITY_RUNTIME_DESIGN.md`)
- bullet and primer quality, powder load, and their effect on reliability

What is ready, what needs the game and what needs a decision: `docs/AMMUNITION_ROADMAP.md`.

---

# Planned Ammunition Types

The mod is intended to eventually support several ammunition variants.

Examples include:

- FMJ
- Hollow Point
- Soft Point
- armor-oriented ammunition variants
- shotgun shells
- multiple shotgun load types
- specialty ammunition

Some advanced ammunition will require higher Ammo Making skill levels and specialized equipment.

---

# Ammunition Failures

Poorly manufactured ammunition will not simply have worse stats.

Planned failures include:

- misfires
- unreliable ignition
- feeding problems
- excessive weapon wear
- case failures
- dangerous cartridges
- catastrophic ammunition failures

The intention is to make manufacturing quality genuinely important.

---

# Reloading

Future versions are planned to support spent ammunition components.

Possible systems include:

- recovering spent brass
- recovering shotgun hulls
- casing inspection
- casing degradation
- reload count
- damaged cases
- resizing
- cleaning
- reusing suitable components

Repeatedly reloading the same casing may gradually reduce its reliability.

---

# Design Goals

Ammo Making is being built around several principles.

## No Infinite Resource Machines

Mining should depend on actual geological deposits.

## Persistent World Systems

Deposits, machines and processing should survive save/reload.

## Player Progression

Advanced manufacturing should require knowledge, equipment and skill.

## Risk vs Reward

Poor manufacturing decisions should have meaningful consequences.

## Project Zomboid Integration

Where possible, Ammo Making uses existing Build 42 systems, materials, animations and world mechanics rather than replacing them.

---

# Development Status

The mod is currently in active development.

## Working systems

Implemented and covered by the offline tests; each still needs its in-game pass on Build 42.20.

- **Ammo Making skill**: custom perk with 10 levels, XP from assays and extraction, level descriptions
- **Geology**: deterministic per-save copper and zinc concentrations, grades, 3x3 surveys, terrain rules (natural outdoor ground only, never indoors or on water)
- **Geological samples**: shovel timed action, sample item carrying its hidden true geology
- **Field and advanced assays**: limited-use kits, measurement error, grade or range results, XP once per assay
- **Laboratory analyzer**: placeable powered world object, 24 processed hours, pauses without power, ±2 % result, cancel, no pickup while occupied
- **Mining / extraction**: pickaxe timed action inside a sampled 3x3, ore dropped on the tile, XP and tool wear
- **Metallurgy**: zinc smelting, copper and zinc ingot casting and 7 + 3 brass alloying as recipes on the vanilla furnaces; XP and craft time tied to Ammo Making (**not yet run in game**)
- **Case stock**: brass ingots forged into small brass sheets at the vanilla forge, sheets punched into brass case cups on any surface (**not yet run in game**)
- **Ammunition components**: die sets, cases with a rolled quality, copper bullets, four primer families, gunpowder from charcoal and fertilizer, and assembly into the vanilla rounds of all five pistol and all three rifle calibres and the vanilla 12 gauge shell; calibres defined and validated as data (**not yet run in game**)
- **Component inspection**: calibre and case quality of an empty case or a loose handloaded round, read-only (**not yet run in game**)
- **Die-set loot**: each calibre's die set in four vanilla loot lists, rare, added when the world loads (**not yet run in game**)
- **Brass recycling**: unwanted brass components to vanilla brass scrap at half the brass and no XP, and scrap back to ingots (**not yet run in game**)
- **Save-data safety**: every stored value is read back within its range; a damaged or hand-edited save cannot give a kit extra uses, stall the analyzer or put a broken number on screen. The depletion store carries a layout version, and a save written by a later version of the mod is read without being reset
- **Component loot**: a little gunpowder, primers, brass scrap and small brass sheet in gun stores, hunting stores and metalwork crates; never cases, bullets or rounds (**not yet run in game**)
- **Feature switches**: every optional system is stable, experimental or disabled in `AC_Features.lua`; one that is off adds no recipe, no menu entry and no hook, and the game-start check says which are on and why
- **Multiplayer guards**: sampling, assays, the analyzer and mining are refused on a multiplayer client and say so
- **Depletion**: finite per-tile reserves from geology, persistent extracted counts, only worked tiles stored
- **Ammo quality prototype**: per-cartridge component qualities, powder load, reload count, failure chances
- **Inspection prototype**: skill-gated inspection panel for the test cartridge
- **Debug tools** (`-debug` only): one "Ammo Making Debug" tree (Geology, Analyzer, Metallurgy, Ammunition, Stations, Diagnostics) for inspecting, resetting and spawning, with a material ledger to check in game that a craft neither creates nor loses metal
- **Compatibility self-check**: every Build 42 assumption probed at game start; problems and a per-class summary in the console, every line in `-debug` mode
- **Localization**: every player-facing string has an `IGUI_AmmoMaking_*` key with an English fallback

## Experimental systems (off by default)

Written, tested offline, and **never run in the game**. Each is switched on
separately; with all of them off the mod behaves as described above.
`docs/INGAME_VALIDATION.md`, sections 18 to 20, is the session that checks
them.

| System | Switch | What it does |
|---|---|---|
| **Reloading Press** | the add-on mod *Ammo Making: Reloading Press (experimental)* | a placed station; the case, projectile and assembly steps of all nine calibres, same die sets and material, less time. Placeholder sprites |
| **Spent cases** | the add-on mod *Ammo Making: Spent Cases (experimental)*; sandbox option for how many are found | fired rounds leave spent brass that can only be scrapped, at a quarter of its brass and no XP. Single player. Stands down beside Hot Brass |
| **Quality tracking** | sandbox option *Track ammunition quality in magazines and firearms* | the casing quality of handloaded rounds survives loading and unloading, and can be inspected on a magazine or firearm. Single player. No effect on firing |
| **Quality effects at the shot** | none: locked off in this version | a small extra jam chance for poor handloads, through vanilla's own jam state. Written; waits for the tracking to be seen working |

An add-on is a mod folder of its own beside `AmmoMaking`, holding only
scripts, translations and (for the press) a tile sheet. All logic is in the
main mod. If a world does not load with an add-on ticked, untick it: the
main mod has no tile sheet or entity of its own.

## Current limitations

- **Mining passed a first in-game test on Build 42.20.4** (start, completion, `DigPickAxe` animation, zinc ore on the ground, depletion, exhaustion, cancel by walking away). Save/reload persistence, `Base.CopperOre`, water detection, built floors and the sound are still marked *REQUIRES IN-GAME VERIFICATION* in `docs/DEVELOPMENT.md`.
- **Multiplayer mining is intentionally disabled.** A multiplayer client gets a disabled option and no extraction. The server-authoritative design is in `docs/MULTIPLAYER_MINING.md`.
- **Metallurgy has not been run in game yet.** The furnace recipes are written from the installed 42.20.4 files and pass the offline tests; whether they appear at the furnace, award XP and speed up with skill is listed under *REQUIRES FUTURE IN-GAME VERIFICATION* in `docs/METALLURGY_DESIGN.md`.
- **The ammunition chain has not been run in game yet**, and its level gates depend on a requirement attached from Lua at boot; see *REQUIRES FUTURE IN-GAME VERIFICATION* in `docs/AMMUNITION_DESIGN.md`.
- **Round quality is stored and shown, and changes nothing at the shot.** Vanilla turns loaded rounds into a count; the experimental quality tracking carries the casing quality across that as a tally (off by default). A box of ammunition keeps no record at all.
- **Die-set loot and brass recycling have not been run in game yet.** The loot weights are deliberately small and untuned; toy caps and fertilizer are plain vanilla loot (toy caps exist in one Wild West location, so match heads are the practical priming charge). See `docs/LOOT_AND_RECYCLING.md`.
- **The reloading press is an experimental add-on with placeholder art.** No vanilla sprite can be borrowed safely (a sprite claimed twice stops every world from loading), so the station has a tile sheet of its own. Whether the game loads and draws it can only be checked in the game.
- **Spent cases are an experimental add-on, and cannot be reloaded.** They are scrap brass at a loss; reloading fired brass is not built (`docs/SPENT_CASE_RESEARCH.md`).
- **Multiplayer is not supported.** Every action that changes the world or an item outside a recipe (sampling, assays, the analyzer, mining) is refused on a client; nothing is synchronised. The authority map and the design are in `docs/MULTIPLAYER_DESIGN.md`.
- **Ammo quality does not affect firearms.** The effect code exists and is locked off.
- **All visuals are placeholders**: vanilla icons and models, a vanilla tile for the analyzer, programmer art for the press (`docs/PLACEHOLDER_ASSETS.md`, `docs/ART_HANDOFF.md`).
- **The recipes for the assay kits and the laboratory analyzer have not been crafted in game yet.** They are what makes the chain playable without the debug menu, so they are the first thing to try. They are never loot.
- **The placed laboratory analyzer needs its in-game pass**: placement, pickup, the sprite and saving its state are engine behaviour the offline tests only mock. `-debug` has Inspect Analyzer State and Complete Analyzer Job to test it without waiting 24 hours (see `docs/DEVELOPMENT.md`).
- **Placing and picking up the analyzer is single-player only for now.** Multiplayer clients get disabled options; the laboratory itself has no server-side synchronisation yet.
- Laboratory processing time is only accounted for when the analyzer is interacted with, using the power state at that moment. Analyzers dropped on the floor (the original behaviour) can still be picked up mid-assay through vanilla.
- The pickaxe action reuses the shovel sound.

## Development loop

Current:

```text
geology (deterministic per save)
        ↓
geological sample (shovel, 3x3)
        ↓
assay (field / advanced / laboratory)
        ↓
mining (pickaxe, inside the sampled 3x3)
        ↓
ore on the ground, reserve depleted
        ↓
vanilla furnace: ore → scrap → copper / zinc ingots
        ↓
vanilla furnace: 7 copper + 3 zinc → 10 brass ingots
        ↓
vanilla forge: brass ingot → 10 small brass sheets
        ↓
any surface, punch + hammer: small sheet → 2 brass case cups
        ↓
die set: cup → case (quality), copper scrap → bullets
        ↓
primers (brass + toy caps / match heads), gunpowder (charcoal + fertilizer)
        ↓
assembly → vanilla pistol and rifle rounds and 12 gauge shells (9 rounds)
```

Beside the chain:

```text
die sets: forged, or found as rare loot
unwanted brass components → brass scrap (half the brass) → brass ingots
finished rounds → vanilla boxes and cartons, by vanilla's own recipe
a little gunpowder, primers and brass as loot
```

Behind switches (experimental, off by default):

```text
reloading press: the same steps at a placed station, faster
fired rounds → spent cases → brass scrap (a quarter of the brass)
casing quality carried through magazines and firearms, and inspected there
```

## What is left

The code is complete as far as it can be without the game
(`docs/AMMUNITION_ROADMAP.md`). What remains, in order:

1. **In-game verification**: `docs/INGAME_VALIDATION.md`, one session.
2. **Final art**: `docs/ART_HANDOFF.md`; every visual is a placeholder.
3. **Balancing**, from play: loot weights, recipe costs, the press's time
   advantage, the spent-case rate. All are central tunables.
4. **Runtime bug fixing** from 1.

## Optional, not planned

Multiplayer authority (designed in `docs/MULTIPLAYER_DESIGN.md`), reloading
of fired brass, lead and cast bullets, shell variants, further calibres,
skill books, a mining machine, directional analyzer sprites.

---

# Compatibility

Currently developed for:

**Project Zomboid Build 42.20 Stable**

Compatibility with other Project Zomboid builds is not guaranteed during development.

The project is being developed and tested primarily against Build 42 systems and APIs.

---

# Installation

The mod is currently intended primarily for development and testing.

Clone or download the repository.

Place the `AmmoMaking` mod folder (from `mod/`, or from the archive built by
`python tools/build_release.py`) inside:

```text
C:\Users\<USERNAME>\Zomboid\mods\
```

The resulting installation should look similar to:

```text
Zomboid
└── mods
    └── AmmoMaking
        ├── common
        │   └── media
        │       └── lua
        │           └── shared
        │
        └── 42
            ├── mod.info
            └── media
                ├── scripts
                └── lua
                    ├── client
                    ├── server
                    └── shared
```

Enable **Ammo Making** from the Project Zomboid Mods menu.

The two experimental add-ons, `AmmoMakingPress` and `AmmoMakingSpentCases`,
are folders of their own beside it. Copy them only to test them, and tick
them separately; each requires Ammo Making. Leave them off for a normal
game.

---

# Repository Structure

```text
PZ-AmmoMaking
├── README.md
├── CHANGELOG.md
├── docs
│   ├── DEVELOPMENT.md                    module map, constants, tests, tools, what needs the game
│   ├── AMMUNITION_ROADMAP.md             status and what comes next
│   ├── INGAME_VALIDATION.md              the play session that checks what offline tests cannot
│   ├── ART_HANDOFF.md                    what to draw, and which value each asset replaces
│   ├── PLACEHOLDER_ASSETS.md             generated: every temporary visual and where it is set
│   ├── REFERENCE_IMPLEMENTATIONS.md      patterns read in other mods; nothing copied
│   ├── AMMUNITION_DESIGN.md              the component chain, balance and economy tables
│   ├── METALLURGY_DESIGN.md
│   ├── LOOT_AND_RECYCLING.md
│   ├── RELOADING_PRESS_DESIGN.md
│   ├── SPENT_CASE_RESEARCH.md
│   ├── AMMO_QUALITY_RUNTIME_DESIGN.md
│   ├── MULTIPLAYER_DESIGN.md
│   ├── MULTIPLAYER_MINING.md
│   ├── WORKSHOP_DESCRIPTION.md
│   ├── VANILLA_AMMUNITION_RESEARCH.md
│   ├── VANILLA_METALLURGY_RESEARCH.md
│   ├── RIFLE_AMMUNITION_RESEARCH.md
│   └── SHOTGUN_AMMUNITION_RESEARCH.md
├── tests
│   ├── run_tests.lua                     the offline suite
│   ├── suite_<name>.lua                  one file per feature, loaded by run_tests.lua
│   ├── firearm_model.lua                 vanilla's firearm Lua as a model, for the hook tests
│   ├── render_addons.lua                 generator of the add-ons' scripts and the placeholder table
│   ├── mock_pz.lua                       the mocked game API, checked against engine_snapshot.lua
│   ├── run_mutants.py                    mutation run over the suite
│   ├── render_recipes.lua, render_balance.lua, write_recipes.lua
│   │                                     generators of the recipe script and the documents' tables
│   ├── snapshot_vanilla.lua              writes vanilla_snapshot.lua from an install
│   ├── vanilla_snapshot.lua              generated: loot lists, ammo boxes
│   └── engine_snapshot.lua               generated: items, tags, stations, Java signatures
├── tools
│   ├── pz_compat.py                      does an installed game still match the mod?
│   ├── test_pz_compat.py                 its self-test
│   ├── mod_facts.lua                     what the mod names, from its own model
│   ├── build_release.py                  gates, then a clean folder and archive
│   └── build_tiles.py                    the game's tile-sheet formats
├── art
│   └── reloading_press                   sources of the press's placeholder sprites and tile sheet
│
└── mod
    ├── AmmoMakingPress                   experimental add-on: entity, skin, 27 recipes, tile sheet; no Lua
    ├── AmmoMakingSpentCases              experimental add-on: 9 items, 3 recipes, a sandbox option; no Lua
    └── AmmoMaking
        ├── common
        │   └── media
        │       └── lua
        │           └── shared
        │               └── Translate
        │                   └── EN
        │                       ├── IG_UI.json
        │                       ├── ItemName.json
        │                       └── Recipes.json
        │
        └── 42
            ├── mod.info
            │
            └── media
                ├── sandbox-options.txt
                ├── scripts
                │   ├── AC_Items.txt
                │   └── AC_Recipes.txt     generated
                │
                └── lua
                    ├── client
                    │   ├── AC_AmmoContextMenu.lua
                    │   ├── AC_AmmoInspectionUI.lua
                    │   ├── AC_DigGeologicalSampleAction.lua
                    │   ├── AC_GeologyAssayUI.lua
                    │   ├── AC_GeologyDebug.lua
                    │   ├── AC_GeologySamplingContextMenu.lua
                    │   ├── AC_MineOreAction.lua
                    │   ├── AC_MiningContextMenu.lua
                    │   └── AC_PickUpAnalyzerAction.lua
                    │
                    ├── server
                    │   └── BuildingObjects
                    │       └── AC_LaboratoryAnalyzerObject.lua
                    │
                    └── shared
                        ├── AC_AmmoInspection.lua
                        ├── AC_AmmoMakingSkill.lua
                        ├── AC_AmmoQuality.lua
                        ├── AC_Calibres.lua
                        ├── AC_CaseQuality.lua
                        ├── AC_Compat.lua
                        ├── AC_Deposits.lua
                        ├── AC_Features.lua
                        ├── AC_Geology.lua
                        ├── AC_GeologySampling.lua
                        ├── AC_LaboratoryAnalyzer.lua
                        ├── AC_Loot.lua
                        ├── AC_Materials.lua
                        ├── AC_Mining.lua
                        ├── AC_QualityCarrier.lua
                        ├── AC_QualityEffects.lua
                        ├── AC_QualityTally.lua
                        ├── AC_Recycling.lua
                        ├── AC_SaveData.lua
                        ├── AC_SpentCases.lua
                        ├── AC_Text.lua
                        ├── AC_Visuals.lua
                        └── AC_WorldData.lua
```

`mod/AmmoMaking` is the mod; the two folders beside it are its optional
add-ons. `python tools/build_release.py` packages exactly those three
folders; tests, tools, documents and art sources are never shipped.

---

# Disclaimer

Ammo Making is an unofficial community mod for **Project Zomboid**.

This project is not affiliated with, endorsed by, sponsored by or associated with **The Indie Stone**.

Project Zomboid and The Indie Stone are trademarks of their respective owners.

Parts of this project's code, documentation, design process and development workflow were created with the assistance of AI tools.

---

# Contributing & Feedback

Ammo Making is currently an experimental work-in-progress project.

Bug reports, testing results, balance suggestions and technical feedback are welcome.

When reporting an issue, useful information includes:

- Project Zomboid build number
- whether the issue occurs in a new or existing save
- relevant steps to reproduce the issue
- relevant `console.txt` errors
- screenshots where applicable

---

# Development

Version: see `modversion=` in `mod/AmmoMaking/42/mod.info` and `CHANGELOG.md`.

```text
lua5.1 tests/run_tests.lua                              the offline suite (or through Python's lupa)
python tests/run_mutants.py                             mutation run
python tools/pz_compat.py --install "<game>"            after a game update: PASS / WARNING / BREAKING
python tools/build_release.py --install "<game>"        every gate, then a clean release folder and archive
```

`docs/DEVELOPMENT.md` describes each.

This repository contains active development code.

Systems, recipes, item names, balancing, world-generation logic and save-data structures may change significantly between versions.

Backwards compatibility between development versions is not guaranteed.
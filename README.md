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
Base.BrassScrap   (reserved for later recycling)
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

`tests/mock_pz.lua` mocks the Project Zomboid API; `tests/run_tests.lua` loads every mod file and runs 10,600+ checks over geology, reserves, depletion, persistence, terrain, prospecting, the timed actions, menus, assays, the laboratory analyzer (state machine, pick-up rule, cancel, malformed data), metallurgy, case stock and ammunition components (the generated recipe script against its Lua mirror, the eight pistol and rifle calibres and four primer families, cross-calibre isolation, material conservation from ore to finished rounds, case quality, level requirements, a simulated XP career), translation keys, debug gating and the compatibility check. It cannot verify vanilla item ids, animations, sounds or engine behaviour; the placed analyzer's engine side (placement cursor, world object, saving) is mocked and still needs the in-game test.

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

- **Calibres**: all five vanilla pistol calibres (9mm, .38 Special, .45 ACP, .357 Magnum, .44 Magnum) and all three vanilla rifle calibres (5.56, .30-30, .308); table below. A calibre is one data entry; no code names one, and pistols and rifles share one model. Each has its own case, bullet and die set, and nothing of one calibre fits another.
- **Die set**: one forged tool per calibre (two steel bar quarters at a Simple Forge), kept by every recipe of that calibre. Rifles are loaded by hand with the same kind of die set; they take about twice as long. A reloading press is planned as the faster tier above it and will take the same die sets.
- **Bullets are copper**: vanilla has no lead, and copper is already mined.
- **Primers** come in four families (small and large pistol, small and large rifle), all made the same way from a small brass sheet and toy cap-gun caps or match heads. A large primer holds twice the material of a small one; a rifle primer takes half as much priming charge again and is never interchangeable with a pistol primer. **Gunpowder** is charcoal and fertilizer. Vanilla has no sulfur or nitrate item and none is invented.
- **Case quality**: 1–100, rolled when a case is formed from the maker's Ammo Making level with a random spread, stored on the case and passed on to the assembled round. It never changes how much material a recipe uses. Nothing reads it in combat yet.
- **Progression**: metallurgy and case stock from level 0; 9mm and .38 Special rounds at level 3, .45 ACP and .357 Magnum at 4, .44 Magnum and the three rifle rounds at 5, each calibre's die set, cases and bullets one or two levels earlier. In a simulated career level 3 comes after about 19 ore, level 4 after 29, level 5 after 57, and the first rifle round after 73 ore and some 500 pistol rounds. Nothing requires level 6.
- **Material balance**: larger calibres cost more through three whole-number knobs: cups of brass per case, bullets per copper scrap, and charges of gunpowder.

| Calibre | Type | Vanilla round | Primer | Cups per case | Bullets per scrap | Powder charges | Round at level | Ore per 100 rounds |
|---|---|---|---|---|---|---|---|---|
| 9mm | pistol | `Base.Bullets9mm` | small pistol | 1 | 2 | 1 | 3 | 11 |
| .38 Special | pistol | `Base.Bullets38` | small pistol | 1 | 2 | 1 | 3 | 11 |
| .45 ACP | pistol | `Base.Bullets45` | large pistol | 1 | 1 | 1 | 4 | 17 |
| .357 Magnum | pistol | `Base.Bullets357` | small pistol | 1 | 2 | 2 | 4 | 11 |
| .44 Magnum | pistol | `Base.Bullets44` | large pistol | 2 | 1 | 3 | 5 | 22 |
| 5.56 | rifle | `Base.556Bullets` | small rifle | 2 | 2 | 3 | 5 | 16 |
| .30-30 | rifle | `Base.3030Bullets` | large rifle | 2 | 1 | 4 | 5 | 22 |
| .308 | rifle | `Base.308Bullets` | large rifle | 3 | 1 | 5 | 5 | 27 |

Rifle powder is a compressed scale: a literal .308 charge would be nearly a whole jar per round.

All balance values are tunable and untuned.

**Not yet tested in game.** Everything is written from the installed Build 42.20.4 files and covered by the offline tests. Design, balance and the list of what needs a game run: `docs/AMMUNITION_DESIGN.md`; vanilla research: `docs/VANILLA_AMMUNITION_RESEARCH.md`.

---

# Planned Metallurgy Extensions

The first metallurgy stage (ore to brass on the vanilla furnaces) is implemented; see *Metallurgy* above. Still planned:

- brass quality, decided when cartridge cases are made
- more than one brass composition
- recycling brass scrap
- balance of charcoal, time and XP

---

# Planned Ammunition Manufacturing

The component chain above is the foundation. Still planned:

- shotgun shells (researched in `docs/SHOTGUN_AMMUNITION_RESEARCH.md`)
- a reloading press as a faster, higher-quality tier above the hand die set
- bullet and primer quality, powder load, and their effect on reliability
- recovering and reloading spent cases
- brass recycling

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
- **Ammunition components**: die sets, cases with a rolled quality, copper bullets, four primer families, gunpowder from charcoal and fertilizer, and assembly into the vanilla rounds of all five pistol and all three rifle calibres; calibres defined and validated as data (**not yet run in game**)
- **Depletion**: finite per-tile reserves from geology, persistent extracted counts, only worked tiles stored
- **Ammo quality prototype**: per-cartridge component qualities, powder load, reload count, failure chances
- **Inspection prototype**: skill-gated inspection panel for the test cartridge
- **Debug tools** (`-debug` only): one "Ammo Making Debug" submenu for inspecting, resetting and spawning
- **Compatibility self-check**: one console line per Build 42 assumption at game start
- **Localization**: every player-facing string has an `IGUI_AmmoMaking_*` key with an English fallback

## Current limitations

- **Mining passed a first in-game test on Build 42.20.4** (start, completion, `DigPickAxe` animation, zinc ore on the ground, depletion, exhaustion, cancel by walking away). Save/reload persistence, `Base.CopperOre`, water detection, built floors and the sound are still marked *REQUIRES IN-GAME VERIFICATION* in `docs/DEVELOPMENT.md`.
- **Multiplayer mining is intentionally disabled.** A multiplayer client gets a disabled option and no extraction. The server-authoritative design is in `docs/MULTIPLAYER_MINING.md`.
- **Metallurgy has not been run in game yet.** The furnace recipes are written from the installed 42.20.4 files and pass the offline tests; whether they appear at the furnace, award XP and speed up with skill is listed under *REQUIRES FUTURE IN-GAME VERIFICATION* in `docs/METALLURGY_DESIGN.md`.
- **The ammunition chain has not been run in game yet**, and its level gates depend on a requirement attached from Lua at boot; see *REQUIRES FUTURE IN-GAME VERIFICATION* in `docs/AMMUNITION_DESIGN.md`.
- **Round quality is stored but not used, and cannot reach the gun as it is.** Vanilla turns loaded rounds into a count, so data on a loose round is gone once it is in a magazine or firearm; misfires and wear need a different carrier and are later work.
- **Die sets, toy caps and fertilizer have no dedicated loot tuning.** The die set is crafted; the rest is vanilla loot.
- **Ammo quality is not integrated into firearm failures.** The quality and inspection systems are data and UI prototypes only.
- **Assay kits and the laboratory analyzer have no loot spawns or recipes yet.** Obtaining them currently relies on the debug menu.
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
assembly → vanilla pistol and rifle rounds (8 calibres)
```

Intended next stages (`docs/AMMUNITION_DESIGN.md`):

```text
shotgun shells (docs/SHOTGUN_AMMUNITION_RESEARCH.md)
        ↓
reloading press tier
        ↓
round quality in use: inspection, misfires, wear
        ↓
spent case recovery and reloading
```

## 🚧 In Development

🔄 Final Laboratory Analyzer visuals  
🔄 Laboratory Analyzer directional sprites / visual rotation  
🔄 Mining machine  
🔄 Mining fuel consumption  
🔄 Mining component wear  

## 📋 Planned

⬜ Multiple brass alloys  
⬜ Brass quality  
⬜ Brass recycling  
⬜ Cartridge presses  
⬜ Shotgun shell presses  
⬜ Shotgun ammunition variants  
⬜ Reloading  
⬜ Spent casing recovery  
⬜ Spent shotgun hull recovery  
⬜ Casing degradation  
⬜ Ammunition failures  
⬜ Weapon damage from dangerous ammunition  
⬜ Advanced ammunition types  
⬜ Specialty ammunition  
⬜ Skill books / manuals  
⬜ Sandbox settings  
⬜ Multiplayer support and synchronization  

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

Place the `AmmoMaking` mod folder inside:

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

---

# Repository Structure

The development repository is currently organized approximately as follows:

```text
PZ-AmmoMaking
├── README.md
├── docs
│   ├── AMMUNITION_DESIGN.md
│   ├── DEVELOPMENT.md
│   ├── METALLURGY_DESIGN.md
│   ├── MULTIPLAYER_MINING.md
│   ├── RIFLE_AMMUNITION_RESEARCH.md
│   ├── SHOTGUN_AMMUNITION_RESEARCH.md
│   ├── VANILLA_AMMUNITION_RESEARCH.md
│   └── VANILLA_METALLURGY_RESEARCH.md
├── tests
│   ├── mock_pz.lua
│   ├── render_recipes.lua
│   ├── write_recipes.lua
│   └── run_tests.lua
│
└── mod
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
                ├── scripts
                │   ├── AC_Items.txt
                │   └── AC_Recipes.txt
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
                        ├── AC_Geology.lua
                        ├── AC_GeologySampling.lua
                        ├── AC_LaboratoryAnalyzer.lua
                        ├── AC_Materials.lua
                        ├── AC_Mining.lua
                        ├── AC_Text.lua
                        └── AC_WorldData.lua
```

The repository structure may change as additional systems are implemented.

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

This repository contains active development code.

Systems, recipes, item names, balancing, world-generation logic and save-data structures may change significantly between versions.

Backwards compatibility between development versions is not guaranteed.
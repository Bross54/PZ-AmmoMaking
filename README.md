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

## Copper

Ammo Making uses Project Zomboid's existing Build 42 copper resources where possible.

Examples:

```text
Base.CopperOre
Base.CopperIngot
```

## Zinc

The mod adds zinc as a new manufacturing resource.

Current zinc items:

```text
AmmoMaking.ZincOre
AmmoMaking.ZincIngot
```

Copper and zinc will eventually be combined to create different grades of brass.

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

`tests/mock_pz.lua` mocks the Project Zomboid API; `tests/run_tests.lua` loads every mod file and runs 880+ checks over geology, reserves, depletion, persistence, terrain, prospecting, the timed actions, menus, assays, the laboratory analyzer (state machine, pick-up rule, cancel, malformed data), translation keys, debug gating and the compatibility check. It cannot verify vanilla item ids, animations, sounds or engine behaviour; the placed analyzer's engine side (placement cursor, world object, saving) is mocked and still needs the in-game test.

Developer notes: `docs/DEVELOPMENT.md` (module map, constants, invariants, timed-action conventions, debug tools, what still needs the game). Next stage design: `docs/METALLURGY_DESIGN.md` (ore processing and metallurgy, design only) and `docs/VANILLA_METALLURGY_RESEARCH.md` (what vanilla Build 42 provides, with evidence levels and the local verification commands).

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

# Planned Metallurgy

Mining is only the beginning of the manufacturing chain.

Planned metallurgy includes:

- copper smelting
- zinc smelting
- brass production
- multiple brass compositions
- material purity
- poor-quality alloys
- high-quality alloys
- large furnace equipment
- reusable metal molds
- cheaper clay molds

Material quality will eventually influence ammunition quality.

---

# Planned Ammunition Manufacturing

The long-term goal is to support a complete ammunition production workflow.

## Cartridge Cases

Brass will be formed into cartridge cases using molds and manufacturing equipment.

## Projectiles

Copper and other materials will be used to manufacture projectile components.

## Primers

Primers will require dedicated manufacturing materials and processes.

## Powder

Powder load will influence cartridge performance and safety.

Incorrect powder loads may create dangerous ammunition.

## Cartridge Assembly

Dedicated presses will be used to assemble finished ammunition.

Different machine tiers may affect manufacturing speed and quality.

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
- **Depletion**: finite per-tile reserves from geology, persistent extracted counts, only worked tiles stored
- **Ammo quality prototype**: per-cartridge component qualities, powder load, reload count, failure chances
- **Inspection prototype**: skill-gated inspection panel for the test cartridge
- **Debug tools** (`-debug` only): one "Ammo Making Debug" submenu for inspecting, resetting and spawning
- **Compatibility self-check**: one console line per Build 42 assumption at game start
- **Localization**: every player-facing string has an `IGUI_AmmoMaking_*` key with an English fallback

## Current limitations

- **Mining passed a first in-game test on Build 42.20.4** (start, completion, `DigPickAxe` animation, zinc ore on the ground, depletion, exhaustion, cancel by walking away). Save/reload persistence, `Base.CopperOre`, water detection, built floors and the sound are still marked *REQUIRES IN-GAME VERIFICATION* in `docs/DEVELOPMENT.md`.
- **Multiplayer mining is intentionally disabled.** A multiplayer client gets a disabled option and no extraction. The server-authoritative design is in `docs/MULTIPLAYER_MINING.md`.
- **Metallurgy does not exist yet.** Ore is the end of the chain today; no furnaces, smelting, crushing or brass.
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
```

Intended next stages (not started):

```text
ore processing (crushing / sorting)
        ↓
metallurgy (smelting, alloys, purity)
        ↓
brass and components (cases, projectiles, primers, powder)
        ↓
ammunition (assembly, inspection, failures)
```

## 🚧 In Development

🔄 Final Laboratory Analyzer visuals  
🔄 Laboratory Analyzer directional sprites / visual rotation  
🔄 Mining machine  
🔄 Mining fuel consumption  
🔄 Mining component wear  

## 📋 Planned

⬜ Furnaces  
⬜ Copper smelting  
⬜ Zinc smelting  
⬜ Brass production  
⬜ Multiple brass alloys  
⬜ Material purity  
⬜ Clay molds  
⬜ Metal molds  
⬜ Cartridge case manufacturing  
⬜ Projectile manufacturing  
⬜ Primer manufacturing  
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
│   ├── DEVELOPMENT.md
│   ├── METALLURGY_DESIGN.md
│   ├── MULTIPLAYER_MINING.md
│   └── VANILLA_METALLURGY_RESEARCH.md
├── tests
│   ├── mock_pz.lua
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
        │                       └── IG_UI.json
        │
        └── 42
            ├── mod.info
            │
            └── media
                ├── scripts
                │   └── AC_Items.txt
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
                        ├── AC_Compat.lua
                        ├── AC_Deposits.lua
                        ├── AC_Geology.lua
                        ├── AC_GeologySampling.lua
                        ├── AC_LaboratoryAnalyzer.lua
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
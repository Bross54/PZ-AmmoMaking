# Ammo Making

**Ammo Making** is an advanced ammunition manufacturing, geology, mining and metallurgy mod for **Project Zomboid Build 42**.

The goal of the mod is to turn ammunition production into a complete progression system rather than a simple crafting recipe.

Players will be able to survey the world for raw materials, analyze geological samples, mine finite ore deposits, process metals, manufacture ammunition components and eventually produce different types and qualities of ammunition.

> **Current target:** Project Zomboid Build 42.20 Stable  
> **Status:** Work in Progress

---

## Overview

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

Copper and zinc are distributed through the world using deterministic procedural geology.

Each save receives its own geology layout.

The same save always generates the same deposits after restarting the game.

Geology currently supports:

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

- indoor floors
- constructed flooring
- roads
- asphalt
- upper floors

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

- placeable world object
- persistent machine state
- one sample at a time
- requires electricity
- supports utility-grid electricity
- supports generator electricity
- processing pauses when electricity is unavailable
- approximately 24 in-game hours per analysis
- processing survives save/reload
- sample remains stored inside the analyzer
- analyzer cannot be picked up while occupied
- laboratory results use approximately ±2% instrument tolerance

Example result:

```text
Laboratory Assay

Copper: 67%
Grade: Good

Zinc: 14%
Grade: Trace

Instrument Tolerance: +/-2%
```

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

# Planned Mining System

The geology system will eventually feed into a finite deposit system.

Deposits will have limited reserves rather than producing unlimited resources.

Planned mechanics include:

- finite copper reserves
- finite zinc reserves
- deposit depletion
- concentration affecting mining output
- deterministic initial reserves
- persistent depletion
- only modified deposits stored in save data

This approach is intended to keep the system scalable without storing data for every tile in the game.

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

Planned systems include:

### Cartridge Cases

Brass will be formed into cartridge cases using molds and manufacturing equipment.

### Projectiles

Copper and other materials will be used to manufacture projectile components.

### Primers

Primers will require dedicated manufacturing materials and processes.

### Powder

Powder load will influence cartridge performance and safety.

Incorrect powder loads may create dangerous ammunition.

### Cartridge Assembly

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

Ammo Making is being built around several principles:

### No Infinite Resource Machines

Mining should depend on actual geological deposits.

### Persistent World Systems

Deposits, machines and processing should survive save/reload.

### Player Progression

Advanced manufacturing should require knowledge, equipment and skill.

### Risk vs Reward

Poor manufacturing decisions should have meaningful consequences.

### Project Zomboid Integration

Where possible, Ammo Making uses existing Build 42 systems, materials, animations and world mechanics rather than replacing them.

---

# Development Status

The mod is currently in active development.

### Implemented

- [x] Build 42 mod structure
- [x] Ammo Making skill
- [x] Ammunition quality framework
- [x] Ammunition inspection system
- [x] Deterministic geology seed
- [x] Procedural copper geology
- [x] Procedural zinc geology
- [x] Geological sampling
- [x] Field assay system
- [x] Advanced field assay system
- [x] Laboratory assay system
- [x] Placeable Laboratory Assay Analyzer
- [x] Electrical power requirement
- [x] Processing pause during power loss
- [x] Persistent laboratory processing
- [x] Zinc ore
- [x] Zinc ingot

### In Development

- [ ] Final Laboratory Analyzer visuals
- [ ] Finite ore deposits
- [ ] Deposit depletion
- [ ] Mining machine
- [ ] Mining fuel consumption
- [ ] Mining component wear

### Planned

- [ ] Furnaces
- [ ] Copper smelting
- [ ] Zinc smelting
- [ ] Brass alloys
- [ ] Material purity
- [ ] Cartridge case manufacturing
- [ ] Projectile manufacturing
- [ ] Primer manufacturing
- [ ] Cartridge presses
- [ ] Shotgun shell presses
- [ ] Reloading
- [ ] Spent casing recovery
- [ ] Ammunition failures
- [ ] Advanced ammunition types
- [ ] Skill books / manuals
- [ ] Sandbox settings
- [ ] Multiplayer support and synchronization

---

# Compatibility

Currently developed for:

**Project Zomboid Build 42.20 Stable**

Compatibility with other builds is not guaranteed during development.

---

# Installation

The mod is currently intended for development and testing.

Clone or download the repository and place the `AmmoMaking` mod folder inside:

```text
C:\Users\<USERNAME>\Zomboid\mods\
```

The resulting structure should contain:

```text
Zomboid
└── mods
    └── AmmoMaking
        ├── common
        └── 42
            ├── mod.info
            └── media
```

Enable **Ammo Making** from the Project Zomboid Mods menu.

---

# Repository Structure

```text
AmmoMaking
├── common
│   └── media
│       └── lua
│           └── shared
│               └── Translate
│
└── 42
    ├── mod.info
    │
    └── media
        ├── scripts
        │
        └── lua
            ├── client
            ├── server
            │   └── BuildingObjects
            └── shared
```

---

# Disclaimer

Ammo Making is an unofficial community mod for Project Zomboid.

Project Zomboid and The Indie Stone are trademarks of their respective owners.

---

# Development

This repository contains active development code and systems may change significantly between commits.

Bug reports, testing feedback and development suggestions are welcome.
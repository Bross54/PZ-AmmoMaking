# Ore Processing + Metallurgy: design for the next milestone

Status: **design only. Nothing in this document is implemented.** It is written
against the repository as of the mining loop that still needs in-game
validation, and it must not be started until that loop passes.

Target: Project Zomboid Build 42.20 Stable.

---

## 1. What exists today and what this stage must fit

| Existing piece | What metallurgy inherits from it |
|---|---|
| `Base.CopperOre` dropped by mining, one item per reserve unit; the mod's own comment calls it "a heavy 40-weight chunk" (**REQUIRES VANILLA FILE VERIFICATION**) | Copper enters metallurgy as vanilla chunks. The weight, if true, is the single biggest gameplay fact of this stage: one chunk is a full load. |
| `AmmoMaking.ZincOre` (weight 0.5, icon `IronOre`), `AmmoMaking.ZincIngot` (weight 1.0, icon `Ingot_Silver`) | Zinc is ours to define. Its current weight contradicts the copper chunk model. |
| Geology grades None / Trace / Poor / Moderate / Good / Rich / Very Rich, mapped to 0 / 0 / 1 / 1 / 2 / 3 / 4 reserve units per tile | Grade already expresses richness as **quantity**. Metallurgy must not count it a second time. |
| `AC_Mining.extract()` as the single mutation point, `AC_Deposits` as the single persistent store | The same shape is required here: one shared module owns every state change; menus and actions only call it. |
| `AC_LaboratoryAnalyzer`: a placeable `IsoWorldInventoryObject` whose state lives in the item's ModData, with a lazy timer (`labRemainingHours`, `labLastUpdateAt`) that only advances while powered and is evaluated on interaction | This is the proven world-machine pattern in this project. The furnace copies it instead of inventing a second one. |
| Module-local `CONFIG` tables, `AC_Text.get(key, fallback, ...)`, `AC_Compat` startup probes, the `-debug`-only "Ammo Making Debug" submenu, `tests/mock_pz.lua` + `tests/run_tests.lua` | Every new module follows the same conventions and lands with its tests, its translation keys, its compat probes and its debug entries. |
| `AmmoQuality` prototype with `casingQuality` on the cartridge | The only quality value metallurgy needs to produce is one that can later feed `casingQuality`. |
| Mining is disabled on multiplayer clients via `AC_Mining.isAvailable()` | Metallurgy ships with the same guard from day one. |

Item and recipe conventions: items are declared in `media/scripts/AC_Items.txt`
inside `module AmmoMaking`, `ItemType = base:normal`, vanilla icons. Player text
goes through `IGUI_AmmoMaking_*` keys with English fallbacks.

---

## 2. The first metallurgy loop

Smallest coherent loop, both metals identical in shape:

```text
ore chunk (on the ground where it was mined)
        ↓  crush   (hand tool, timed action, no machine)
crushed ore ×N        light, carriable
        ↓  smelt    (furnace world object, fuel, time)
ingot ×1 per batch
        ↓  alloy    (same furnace, copper + zinc ingots, ratio matters)
brass ingot ×N   or   brass scrap ×N
```

No molten-metal items, no separate crusher machine, no crucible item, no mold
item in the first version. Each of those was considered and rejected below.

### Why crushing exists

Not for realism. If `Base.CopperOre` really weighs 40, a player cannot carry a
mined tile home without a vehicle. Crushing at the mine face turns one immovable
chunk into a few light pieces and is where the player pays with time and tool
wear instead of transport. It also gives the skill its first lever (waste). For
zinc the same step keeps one pipeline instead of two.

If verification shows copper ore is light, crushing loses its transport reason
but keeps the waste/skill reason; it stays, with the step shortened.

### Why no ore crusher machine, crucible or mold now

- A powered crusher adds throughput, not a decision. Later, as an upgrade.
- A crucible is only meaningful if molten metal is an item. It is not.
- A mold would be a one-time purchase with no decision attached. The furnace
  "batch" abstracts casting. A mold can be introduced later when cases need
  their own forming step.

### Step table

| Step | Player action | Tool / machine | Input | Output | Time | Ammo Making XP | Failure | Quality | Persistent state |
|---|---|---|---|---|---|---|---|---|---|
| Crush | Right-click an ore chunk lying on the ground → "Crush ore"; timed action facing the chunk | equipped sledgehammer (full yield) or hammer (slower, slightly lower yield); ids to verify | 1 chunk (`Base.CopperOre` / `AmmoMaking.ZincOre`) | up to 4 crushed ore (`AmmoMaking.CrushedCopperOre` / `AmmoMaking.CrushedZincOre`), skill-dependent | ~ dig duration; skill reduces | small per chunk | none besides interruption (nothing consumed until perform) | none | none |
| Smelt | Place furnace, load fuel, load crushed ore, light, wait, collect | `AmmoMaking.SmeltingFurnace` (world object) | 4 crushed ore of one metal per batch, fuel hours | 1 ingot (`Base.CopperIngot` / `AmmoMaking.ZincIngot`) | hours, config; skill reduces | per ingot collected | batch can lose 1 crushed unit to slag (skill-dependent chance); fuel exhaustion pauses | none carried on ingots | furnace ModData: job, inputs, fuel, remaining hours, last update |
| Alloy | Load 2–10 ingots (copper + zinc), "Melt brass", wait, collect | same furnace, "alloy" job | N copper + M zinc ingots | N+M brass ingots (`AmmoMaking.BrassIngot`) if zinc fraction is within tolerance of 30 %, else N+M brass scrap (`AmmoMaking.BrassScrap`) | hours, config | per batch + per ingot | off-spec batch (player decision), fuel exhaustion | brass ingots carry `brassQuality` 0–100 | same furnace ModData |
| Re-alloy scrap | Load scrap plus correcting ingots | same furnace | K scrap + corrections | (K + corrections − loss) brass or scrap | as alloy | reduced | strictly loses ≥ 1 unit | as alloy | same |

Grind check: a Rich 3x3 (say 9 tiles × 3 units) yields 27 chunks → 27 crush
actions → ~100 crushed → 25 smelt batches → 25 ingots. That is a lot of
interaction for one site. Two levers keep it sane and are config values:
`crushYieldPerChunk` (4) and `crushedPerIngot` (4). Raising the furnace batch to
several ingots at once (capacity 5 batches) keeps the smelt count down. The
numbers are placeholders; the shape is what matters.

---

## 3. Vanilla Build 42 integration research

Nothing below could be checked from this environment (no game files, wiki
blocked). Everything is classified honestly.

### CONFIRMED (from this repository and the engine API the mod already uses)

- `ISBaseTimedAction` timed actions, `IsoWorldInventoryObject` placed items with
  ModData, global `ModData`, `getScriptManager():FindItem`, item scripts in
  `module AmmoMaking { item X { … } }` format. All in use today.
- Vanilla icons `IronOre` and `Ingot_Silver` exist (the mod's zinc items use them
  and the author has seen them in game).

### LIKELY (widely reported for Build 42; must be confirmed in the game files)

- `Base.CopperOre` and `Base.CopperIngot` exist. The mod already targets them and
  the compatibility check reports them at startup.
- `Base.CopperOre` is very heavy (the repository says 40). If true, one chunk is
  a full inventory.
- Build 42 has a blacksmithing / metalworking layer: forge-type world objects,
  charcoal production (kiln / charcoal burning), a `Blacksmith` perk, iron ore
  and ingots, crucibles or molds of some kind, and the new `craftRecipe` script
  format with `inputs` / `outputs` / `time` / `xpAward` and station requirements
  by tag.
- `Base.Charcoal`, `Base.Log`, `Base.Plank`, `Base.Sledgehammer`,
  `Base.Sledgehammer2`, `Base.Hammer` exist as ids.

### REQUIRES IN-GAME / VANILLA FILE VERIFICATION

Run these against the game's `media/scripts` folder before M1 (Windows: use
`findstr /s /i`; Linux/macOS: `grep -ri`):

| Question | What to search |
|---|---|
| Exact ids and weights of copper ore / ingot | `item CopperOre`, `item CopperIngot` |
| Do a crucible, mold, ingot mold, forge, furnace, bloomery, kiln exist as items or buildables, and what tags do they carry | `Crucible`, `Mold`, `Forge`, `Furnace`, `Bloomery`, `Kiln` |
| How vanilla smelts (recipe format, station tag, fuel model, time) | `craftRecipe` blocks mentioning `Ingot`, `Smelt`, `Melt`, `Ore` |
| Charcoal id and how it is produced | `item Charcoal`, `Charcoal` recipes |
| Sledgehammer / hammer ids and tags | `item Sledgehammer`, `Tags` lines with `Hammer` |
| Whether vanilla world stations can be required by a mod recipe (tag or full type) | any `craftRecipe` with a station / `SkillRequired` / `Tags` field |
| Weight of vanilla ingots, to size ours | `item IronIngot`, `item CopperIngot` |

### Reuse decision

- **Reuse vanilla items** for copper ore, copper ingot, fuel (charcoal, logs)
  and the crushing tools.
- **Do not reuse vanilla stations in the first version.** Two reasons: the
  station model (`craftRecipe` at a tagged object) is instant-or-timed inventory
  crafting and cannot express "load, light, wait hours, collect, pause without
  fuel" without engine research this environment cannot do; and the project
  already has a working, tested, persistent machine pattern. M0 records what
  vanilla offers; a later "vanilla station adapter" milestone can let a vanilla
  forge count as a furnace if it turns out to expose enough.
- **Do not reuse vanilla `craftRecipe` for smelting or alloying.** Both need
  world time and machine state. Crushing could be a vanilla recipe, but as a
  world-item timed action it keeps the 40-weight chunk out of the inventory
  entirely, which is the whole point.

---

## 4. Copper strategy

- Ore: `Base.CopperOre`, unchanged, as mining already drops it.
- Ingot: `Base.CopperIngot`, produced by our furnace. No `AmmoMaking.Copper*`
  items. The only reason to ever add one would be a vanilla ingot that cannot
  hold ModData or is consumed by vanilla recipes in a way that breaks our
  conservation rules; neither is expected, and ingots carry no ModData in this
  design anyway.
- Intermediate: `AmmoMaking.CrushedCopperOre`, ours, because vanilla has no such
  item and it must be light.

Implications of a 40-weight chunk, if confirmed:

- Crushing must be possible **on the ground**, without picking the chunk up.
  Design already does this.
- The mining halo/tooltips should not suggest picking ore up. No change needed.
- Vehicles become the alternative to crushing on site. That is a legitimate
  player choice, not a problem.
- If vanilla later smelts copper ore directly at a forge, our crushed path and
  the vanilla path must not both be allowed on the same chunk in a way that
  yields more metal in total. Conservation rule 1 below covers it: our path
  yields at most one ingot-equivalent per chunk; if vanilla yields one ingot per
  chunk directly, the two are equal and no loop exists.

---

## 5. Zinc strategy

Keep the ids: `AmmoMaking.ZincOre`, `AmmoMaking.ZincIngot`. Add
`AmmoMaking.CrushedZincOre`.

Recommended changes (not made yet):

| Item | Now | Recommended | Why |
|---|---|---|---|
| `AmmoMaking.ZincOre` | Weight 0.5 | Same weight as the verified `Base.CopperOre` chunk, or a similar heavy value if copper turns out to be light-ish; icon stays `IronOre` until a zinc icon exists | Both ores go through the same crush step and drop one per reserve unit. A 0.5 zinc chunk next to a 40 copper chunk makes zinc a free resource and copper a punishment. Parity keeps one rule. |
| `AmmoMaking.ZincIngot` | Weight 1.0 | Match the verified `Base.CopperIngot` weight | Ingots are counted, not weighed, in every recipe; matching weights keeps brass batches honest in the inventory. |
| `AmmoMaking.CrushedZincOre` | — | Light (about a quarter of an ingot's weight each), `DisplayCategory = Material` | Carriable output of crushing. |

No "zinc concentrate", "roasted zinc" or similar: zinc smelting is not more
complex than copper in this game. The whole point of parity is one pipeline.

---

## 6. Brass

Decisions, with the reasoning:

| Question | Decision | Reason |
|---|---|---|
| Direct from copper + zinc? | Yes, from **ingots**, in the furnace's "alloy" job | Ingots are the unit players already count. No molten intermediates. |
| Molten metal? | No item. The furnace job *is* the molten phase | An item would exist only to be immediately consumed. |
| Do ratios matter? | **Yes.** Load any N copper + M zinc ingots (2–10 total). Zinc fraction f = M / (N + M). Target 0.30 (cartridge brass). Within `alloyTolerance` → brass ingots; outside → brass scrap | The only real decision in the stage: 7+3 is perfect, 2+1 (33 %) or 5+2 (28.6 %) are acceptable small batches, 3+1 (25 %) or 1+1 (50 %) are mistakes. Small batches are possible early; perfect batches reward planning. |
| Skill affects yield? | **No.** N + M in → N + M out, always | Skill never creates metal. Skill affects **information** (whether the furnace tooltip shows "ratio 28.6 % zinc: good" before you light it), **quality** and **scrap loss on re-alloy**. |
| Wrong ratio → scrap? | Yes. Scrap keeps its ingot count and its zinc fraction in the furnace batch record, then in the scrap items' ModData | The player can fix a batch by re-melting scrap with correcting ingots, at the cost of one unit of loss per re-melt. Nothing is silently deleted, nothing is free. |
| Does brass quality influence cases later? | Yes, that is its only purpose | `brassQuality` 0–100 = closeness to 0.30 scaled by a skill consistency factor. Later `casingQuality` starts from the brass ingot used. |
| Representation | **Ingots** (`AmmoMaking.BrassIngot`) and **scrap** (`AmmoMaking.BrassScrap`) | Sheets, strip, billets and cups belong to case manufacturing, the next stage. Introducing them now would store form factors nobody uses yet. |

Quality formula shape (numbers are config):

```text
closeness  = 1 - |f - 0.30| / alloyTolerance          -- 0..1 inside tolerance
skillTerm  = skillQualityFloor + (1 - skillQualityFloor) * level / 10
brassQuality = round(100 * closeness * skillTerm)     -- stored on each brass ingot
```

Off-spec (closeness < 0) → scrap, no quality.

Because brass ingots carry ModData, they must not be allowed to merge into
stacks that would lose it. Build 42 items with distinct ModData do not merge as
one object, but the inventory UI may group them; `AC_Materials` treats each
ingot as an individual item and never reads a "count" from a stack.

---

## 7. Machines / stations

One new world object. Nothing else.

### `AmmoMaking.SmeltingFurnace` (world object, placed like the analyzer)

| Aspect | Decision |
|---|---|
| Why it exists | Smelting and alloying need hours of world time, fuel, and a place where inputs sit while the player is away. Nothing in the mod does that except the analyzer pattern. |
| Why not vanilla | Unknown whether a vanilla forge exposes a loadable, timed, fuel-gated state to Lua (M0 answers this). Even if it does, the analyzer pattern is already proven and tested in this codebase. |
| Item or world object | Inventory item that becomes an `IsoWorldInventoryObject` when dropped, exactly like `AmmoMaking.LaboratoryAssayAnalyzer`. State lives in the item's ModData so it survives pickup, save and reload. |
| Obtaining | First version: a `craftRecipe` from vanilla materials (bricks / stone / metal sheets, ids from M0) **and** the debug spawn. If the recipe format cannot be verified in time, debug spawn only for the first in-game test. |
| Fuel | Yes, from day one. `fuelHours` in ModData; adding a charcoal / log item adds config hours; a running job consumes hours; at zero the job pauses (same as the analyzer without power). Fuel is the ongoing cost that stops the furnace from being free. |
| Electricity | No. |
| Maintenance | Later. No wear in the first version; a `condition` hook is left in the state machine so it can be added without a save migration. |
| Jobs | `smelt_copper`, `smelt_zinc`, `alloy_brass`. One job at a time. Inputs are consumed into ModData counts when loaded; outputs are created on collect. |
| Capacity | `maxCrushedPerJob` (e.g. 20 = 5 ingots), `maxIngotsPerAlloy` (10). |

Crushing uses no machine: sledgehammer or hammer, timed action on a ground item.

---

## 8. Skill progression

Ammo Making level 0–10. Skill never adds metal. Recommended levers, each a
config value with a linear shape so balancing is one number:

| Lever | Effect of level | Config |
|---|---|---|
| Crush waste | Expected crushed pieces per chunk rise from `crushYieldMin` (3) at level 0 to `crushYieldPerChunk` (4) at level 10, never above 4 | `crushYieldMin`, `crushYieldPerChunk` |
| Crush time | −4 % per level, like mining | `crushTimeReductionPerLevel` |
| Smelt slag loss | Chance that a batch loses one crushed unit: `slagChanceBase` (25 %) → `slagChanceMin` (5 %) at level 10 | both |
| Smelt time | −3 % per level | `smeltTimeReductionPerLevel` |
| Alloy information | Below `alloyInfoLevel` (3) the furnace only says "loaded"; at or above it shows the zinc fraction and "good / off-spec" before lighting | `alloyInfoLevel` |
| Alloy tolerance | Fixed. Skill does not widen what counts as brass | `alloyTolerance` (0.05) |
| Brass quality | `skillQualityFloor` (0.6) → 1.0 at level 10 | `skillQualityFloor` |
| Re-alloy loss | 1 unit per re-melt at any level; skill does not remove it | `reAlloyLoss` |
| XP | crush 2, ingot 5, brass batch 10 + 1 per ingot, scrap batch 3 | `xp*` |

All XP sources consume finite ore, so none can be farmed.

---

## 9. Material conservation

Unit: **1 metal unit (mu) = 1 ingot**. One ore chunk contains at most 1 mu.

Rules, each of which becomes a test:

1. `crush(chunk) ≤ crushYieldPerChunk` pieces, and `crushYieldPerChunk × pieces-per-ingot` = exactly 1 mu. One chunk can never become more than one ingot.
2. `smelt(k pieces)` produces `floor(k / crushedPerIngot)` ingots minus slag; leftover pieces stay loaded. Never rounds up.
3. `alloy(N Cu, M Zn)` produces exactly `N + M` brass **or** exactly `N + M` scrap. Never both, never more.
4. `reAlloy(K scrap + C ingots)` produces `K + C − reAlloyLoss` (≥ 0) brass or scrap. Every cycle loses at least one unit, so any loop terminates.
5. Inputs are consumed **before** any output exists (loading moves items into ModData counts; the job runs on counts; collect creates items). A crash between load and collect loses nothing: the counts persist.
6. Outputs are created **only** by `collect()`, exactly once: `collect()` zeroes the job's output count in the same call that spawns the items, before spawning. If spawning throws mid-way, the remaining count is kept and a second collect finishes it. No double collect.
7. Cancelling a crush action consumes nothing. Interrupting a furnace job is not possible; unloading an unlit furnace returns exactly what was loaded.
8. Future stages inherit the unit: a case consumes a fraction of a brass ingot; a spent case recycles to strictly less. Recycling is the only path from product back to metal, and it is lossy.

An `AC_Materials.ledger()` debug helper can sum every metal-bearing item in the
player's inventory plus loaded furnace counts, in mu, so a tester can watch the
total never rise across a full cycle.

---

## 10. Quality integration (minimum useful model)

| Stage | Carries quality? | Why |
|---|---|---|
| Ore grade | No per-item value | Grade is already expressed as reserve units. |
| Crushed ore | No | Nothing decided here affects the metal. |
| Copper / zinc ingot | No | Vanilla `Base.CopperIngot` should stay plain; zinc mirrors it. Purity would be fake precision. |
| Brass ingot | **Yes**: `brassQuality` 0–100 in ModData | The only place a player decision (ratio, skill) changes the material. |
| Brass scrap | zinc fraction only | Needed to re-alloy correctly. |
| Cartridge case (later) | `casingQuality` seeded from `brassQuality` | Already a field in `AmmoQuality`. |

Everything else in the `AmmoQuality` prototype stays as it is.

---

## 11. Operation → mechanism

| Operation | Mechanism | Why |
|---|---|---|
| Crush ore | Timed action on a world item (chunk on the ground) with a tool in hand | Keeps the heavy chunk out of the inventory; has an animation and interruption like mining; shared logic in one function |
| Place / pick up furnace | Vanilla drop / pick up of the furnace item | Free, proven by the analyzer |
| Load fuel / load ore / load ingots | World-object context menu, immediate | Moving items into counts has no duration worth animating |
| Light / run / pause / complete | Machine processing job on world time, lazily evaluated on interaction | Same as the analyzer; no per-tick code |
| Collect ingots / brass / scrap | World-object context menu, immediate | As analyzer collect |
| Unload unlit furnace | World-object context menu, immediate | Reversibility before commitment |
| Check status / ratio | World-object context menu + halo/tooltip | As analyzer status |

No ordinary crafting recipes for any metallurgy operation in the first version
(only for building the furnace item itself, pending M0).

---

## 12. Multiplayer readiness (design only)

| Concern | Rule in the first (single-player) implementation |
|---|---|
| Authoritative state | All furnace state is in the furnace item's ModData; all mutations are in `AC_Metallurgy.*` functions that take (player, worldObject, …). Menus and actions never touch ModData. |
| Ownership | None. Any player can load / light / collect. Concurrency is serialised later by running the same functions in one server handler. |
| Concurrent use | Each function checks state first and writes in the same call. Collect zeroes before spawning. No two-step client protocol anywhere. |
| Input consumption | Items are removed from the player's inventory and added to counts in one function. |
| Output creation | Only in `collect()`, from counts, once. |
| Timers | World hours with `lastUpdateAt`, evaluated on interaction, exactly like the analyzer. No client tick timers. |
| Cancellation | Crush action: nothing consumed until `perform()`. Furnace: unload only while unlit. |
| Fuel | A count in ModData, consumed by the same lazy update. |
| Guard | `AC_Metallurgy.isAvailable()` = `not isClient()`. Menus show a disabled explanatory option on clients, as mining does. |

Server path later: replace the direct call in the context-menu callbacks and in
`AC_CrushOreAction:perform()` with `sendClientCommand`, run the same shared
functions in an `OnClientCommand` handler, transmit the furnace item's ModData.
Same shape as `docs/MULTIPLAYER_MINING.md`.

---

## 13. Proposed file architecture

```text
shared/AC_Materials.lua      item ids, metal units per item, conversion table,
                             yield / slag / alloy / quality maths as pure functions
                             of (level, rng), the conservation ledger. No world access.
shared/AC_Metallurgy.lua     furnace state machine (initialize, load, fuel, light,
                             updateState, collect, unload, status), crush(), isAvailable().
                             The only writer of furnace ModData and the only creator
                             of metallurgy items.
client/AC_CrushOreAction.lua timed action; perform() calls AC_Metallurgy.crush().
client/AC_MetallurgyContextMenu.lua
                             "Crush ore" on ground chunks; furnace options
                             (load fuel / ore / ingots, light, status, collect, unload).
scripts/AC_Items.txt         + CrushedCopperOre, CrushedZincOre, BrassIngot,
                             BrassScrap, SmeltingFurnace (+ furnace craftRecipe, pending M0)
Translate/EN/IG_UI.json      + IGUI_AmmoMaking_Met_* keys
client/AC_GeologyDebug.lua   + Spawn Metallurgy Kit, Complete Furnace Job,
                             Add Fuel, Show Material Ledger
shared/AC_Compat.lua         + new item ids and tool ids in REQUIRED_ITEMS
tests/run_tests.lua          + metallurgy sections; tests/mock_pz.lua + furnace
                             world-object helper
docs/METALLURGY_DESIGN.md    this file, kept current
```

Two shared modules, two client files. `AC_Materials` is pure so its maths can be
tested exhaustively; `AC_Metallurgy` mirrors `AC_LaboratoryAnalyzer` so the
world-object handling is familiar. Splitting alloying into its own module was
considered and rejected: it is ~100 lines of maths that belongs with the other
conversion rules.

---

## 14. Testing strategy

Offline (extend `tests/run_tests.lua`, all before any in-game run):

- **Conservation:** for every level 0–10 and 1000 seeded RNG runs, crush yield
  ≤ 4, smelt output = floor(pieces / 4) − slag ≥ 0, alloy out = in, re-alloy
  out = in − loss; the ledger never rises across crush → smelt → alloy → scrap →
  re-alloy.
- **Input consumption:** loading removes exactly the items loaded from the
  inventory; over-capacity loads are refused with the inventory untouched; wrong
  material (a shovel, an ingot into a smelt job, crushed ore into an alloy job)
  refused.
- **No duplication:** collect twice → second returns `empty`; item spawn failure
  mid-collect keeps the remaining count; save/reload between load and collect
  preserves counts; Lua reload preserves state.
- **Cancellation:** crush action `stop()` consumes nothing; `isValid()` fails
  when the tool leaves the hands, breaks, or the chunk is gone; unload of an
  unlit furnace returns exactly the loaded items; light is refused without fuel.
- **Timers and fuel:** job advances only while `fuelHours > 0`; pausing and
  resuming across world-hour jumps; fuel reaching zero mid-job pauses at the
  right remaining time.
- **Skill effects:** monotone yield / slag / time / quality across levels; skill
  never increases alloy output; info gate at `alloyInfoLevel`.
- **Brass ratios:** 7+3 perfect, 2+1 and 5+2 accepted, 3+1 and 1+1 scrap, scrap
  keeps its fraction, re-alloy with correct correction becomes brass, quality
  bounds 0–100.
- **Failure paths:** unknown ingot id → `item_creation_failed`, no consumption;
  malformed furnace ModData tolerated; furnace picked up mid-job keeps state.
- **Multiplayer guard:** every mutation refused on a client; menus disabled.
- **Hidden information:** no exact zinc fraction shown below `alloyInfoLevel`.
- **Localization:** no raw keys in any label.
- **Debug gating:** metallurgy debug entries only under `isDebugEnabled()`.

Only in Project Zomboid:

- vanilla ids and weights (copper ore/ingot, charcoal, logs, sledgehammer, hammer)
- crushing animation and sound with a sledgehammer
- placing the furnace as a world item, its sprite, pickup with state
- context menu on a ground chunk (world-object menu hit-testing)
- `craftRecipe` for the furnace, if used
- ModData on ingot items surviving inventory grouping and container transfers
- world-hour timing feel (hours per batch)

---

## 15. Milestones

Each is independently testable and lands with tests, translations, compat
probes and debug entries.

| # | Milestone | Files | Gameplay result | Tests | Depends on | In-game verification |
|---|---|---|---|---|---|---|
| M0 | Vanilla verification | `docs/METALLURGY_DESIGN.md` (fill the table in §3) | none | none | mining loop passed in game | the grep table in §3; note ids, weights, existence of forge / crucible / mold / charcoal, recipe format |
| M1 | Materials and items | `AC_Materials.lua`, `AC_Items.txt`, `IG_UI.json`, `AC_Compat.lua`, tests | items exist and can be spawned; ledger works; zinc weights adjusted per M0 | conservation maths at every level, ledger, ids probed | M0 | debug spawn of every new item; compat lines all OK |
| M2 | Ore crushing | `AC_Metallurgy.lua` (crush only), `AC_CrushOreAction.lua`, `AC_MetallurgyContextMenu.lua` (crush part), debug spawn of tools, tests | mine → crush on the ground → carry crushed ore | yield bounds, tool checks, cancellation, MP guard, hidden info | M1 | menu on a ground chunk, animation, sound, yield feel, sledgehammer id |
| M3 | Furnace and smelting | `AC_Metallurgy.lua` (state machine), context menu (furnace part), items (furnace), debug (complete job, add fuel), tests | crushed ore → ingots with fuel and time | load / fuel / light / pause / collect / unload, save + Lua reload, no double collect, slag, MP guard | M2 | placement, sprite, pickup with state, timing, fuel feel |
| M4 | Brass alloying | `AC_Materials.lua` (alloy maths), `AC_Metallurgy.lua` (alloy job), context menu, items (brass, scrap), tests | copper + zinc ingots → brass or scrap; scrap re-alloy | ratios, quality, info gate, scrap loop terminates, conservation | M3 | ingot ModData survives inventory handling; tooltip readability |
| M5 | Skill, balance and docs | all `CONFIG` tables, README, `docs/DEVELOPMENT.md`, debug ledger | XP and skill levers live; documented constants | monotonicity, XP once per event | M4 | hours-per-batch and yields feel right across a full site |
| M6 (later) | Vanilla station adapter and multiplayer | per M0 findings; `server/` handlers | vanilla forge counts as a furnace if possible; MP | — | M5 | — |

M2 is the first milestone with visible gameplay; M3 is the first that produces
metal; M4 completes the stage.

---

## 16. Risks

- **Copper ore weight unknown.** Drives crushing, zinc parity and transport. M0
  first.
- **Vanilla may already smelt copper.** If a vanilla forge turns `Base.CopperOre`
  into `Base.CopperIngot` directly, our crushed path must yield no more than
  that, and our furnace becomes a convenience, not a necessity. Conservation
  rule 1 holds either way.
- **Ingot ModData vs stacking.** If Build 42 merges items with different ModData
  in some container operations, `brassQuality` could be lost or copied. Test in
  game early in M4; fallback is a small number of discrete quality tiers as
  separate item ids (`BrassIngotPoor` / `BrassIngot` / `BrassIngotFine`).
- **Grind.** 27 chunks per rich site is many crush actions. Batch capacity and
  yield constants are the levers; a powered crusher is the later answer.
- **Furnace as a dropped item** inherits the analyzer's known limits: pickup is
  not blocked while running, and time only advances on interaction. Acceptable
  for the first version, documented.
- **Fuel ids.** If charcoal is not obtainable in vanilla the way we assume, logs
  and planks must be enough fuel on their own.
- **Scope creep** into molds, sheets, cups and cases. They are the next stage,
  not this one.

---

## 17. Decisions requested from the project owner

1. **Ratio-based brass with scrap on failure** (recommended) versus a single
   fixed 7 + 3 recipe. Ratio gives the stage its one real decision; fixed is
   simpler and grind-free.
2. **Fuel from the first version** (recommended) versus a furnace that runs for
   free until a later balance pass.
3. **Zinc ore weight parity with the copper chunk** (recommended) versus keeping
   zinc light and skipping the crush step for zinc.
4. **Furnace as the mod's own world item now** (recommended) versus waiting on
   M0 to see whether a vanilla forge can host the jobs.
5. **Brass quality as a single stored number now** (recommended) versus deferring
   all quality to the case-making stage.

Everything else in this document is an implementation default that can be
changed by editing a config value or a table.

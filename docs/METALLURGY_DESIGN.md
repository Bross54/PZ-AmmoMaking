# Ore Processing + Metallurgy: design for the next milestone

Status: **design only. Nothing in this document is implemented.** It must not
be started until the mining loop passes in-game testing.

Target: Project Zomboid Build 42.20 Stable.

Guiding decision (project owner): **AmmoMaking metallurgy is an extension of
Build 42's own furnace / metalworking system, not a parallel one.** There is no
custom furnace world object, no custom fuel, heat, timer or persistence for
smelting. The mod contributes items, recipes attached to vanilla stations, and
a thin Lua layer for brass quality and skill.

---

## 1. What exists today and what this stage must fit

| Existing piece | What metallurgy inherits from it |
|---|---|
| `Base.CopperOre` dropped by mining, one item per reserve unit; the mod's comment calls it "a heavy 40-weight chunk" (**REQUIRES VANILLA FILE VERIFICATION**) | Copper enters metallurgy as vanilla chunks and should leave it as vanilla `Base.CopperIngot` through a vanilla station. |
| `AmmoMaking.ZincOre` (weight 0.5, icon `IronOre`), `AmmoMaking.ZincIngot` (weight 1.0, icon `Ingot_Silver`) | Zinc is ours to define; it must look and behave like a vanilla ore / ingot pair so vanilla stations treat it the same way. |
| Geology grades → 0 / 0 / 1 / 1 / 2 / 3 / 4 reserve units per tile | Grade already expresses richness as **quantity**. Recipes must not count it again. |
| `AC_Mining.extract()` as the single mutation point; `AC_Deposits` as the single store | Metallurgy should need **no** persistent store of its own. Vanilla crafting already owns station state. |
| `AC_LaboratoryAnalyzer` (custom powered world object with its own lazy timer) | Kept for assays only. **Not** the template for smelting any more: that was the previous design and is withdrawn. |
| Module-local `CONFIG`, `AC_Text.get`, `AC_Compat` probes, `-debug` submenu, `tests/mock_pz.lua` + `tests/run_tests.lua` | New modules follow the same conventions and land with tests, translation keys, compat probes and debug entries. |
| `AmmoQuality` prototype with `casingQuality` | The only quality value metallurgy must produce is one that can later seed `casingQuality`. |
| Mining disabled on multiplayer clients via `AC_Mining.isAvailable()` | Any custom timed action added here ships with the same guard. Vanilla recipes need none. |

Conventions: items in `media/scripts/AC_Items.txt` inside `module AmmoMaking`,
vanilla icons, `IGUI_AmmoMaking_*` translation keys with English fallbacks.

---

## 2. The first metallurgy loop

```text
Base.CopperOre          AmmoMaking.ZincOre
      │                        │
      ▼  (ore preparation only if vanilla convention or the chunk weight requires it, see §6)
      │                        │
      ▼  vanilla furnace recipe (mod-defined craftRecipe at a vanilla station)
Base.CopperIngot        AmmoMaking.ZincIngot
      └──────────┬─────────────┘
                 ▼  vanilla furnace alloy recipe(s) (mod-defined, fixed ratios)
        AmmoMaking.BrassIngot   (brassQuality set by a Lua callback if the
                                 recipe system exposes one, see §7)
```

The player experience is the vanilla one: build or find a furnace, fuel and
light it the vanilla way, open the vanilla crafting UI at the station, pick a
recipe, wait the recipe's time, take the output. The mod adds the recipes and
the zinc / brass items. Nothing about the furnace itself is ours.

### Step table

| Step | Player action | Station / tool | Input | Output | Time | Ammo Making XP | Failure | Quality | Persistent state (ours) |
|---|---|---|---|---|---|---|---|---|---|
| Prepare ore (**conditional**, §6) | vanilla recipe or, only if the chunk cannot be carried, a ground timed action | hammer / sledgehammer (vanilla ids from M0) | 1 ore chunk | prepared ore ×k | recipe time | small | none | none | none |
| Smelt copper | vanilla crafting UI at a lit vanilla furnace | vanilla furnace (ids from M0), vanilla fuel | ore (or prepared ore) | `Base.CopperIngot` | recipe time; skill reduction only if the recipe system supports it | per recipe `xpAward` | vanilla only (unlit, no fuel) | none | none |
| Smelt zinc | same | same | `AmmoMaking.ZincOre` (or prepared) | `AmmoMaking.ZincIngot` | same | same | same | none | none |
| Alloy brass | same, choosing one of the brass recipes | same | N `Base.CopperIngot` + M `AmmoMaking.ZincIngot` in the recipe's fixed ratio | N + M `AmmoMaking.BrassIngot` | same | per recipe | vanilla only | `brassQuality` on each ingot via callback, or discrete tiers (§7) | none |

There is no slag, no fuel accounting, no pause / resume and no collect step of
ours. If vanilla furnaces model any of those, the player gets them for free.

---

## 3. Vanilla Build 42 integration research

Nothing in this section could be checked from this environment (no game files,
wiki blocked). Classification is honest and M0 exists to replace every LIKELY
and VERIFY line with a fact.

### CONFIRMED (this repository and APIs the mod already uses)

- `ISBaseTimedAction`, dropped-item world objects with ModData, global
  `ModData`, `getScriptManager():FindItem`, `module AmmoMaking { item X { … } }`.
- Vanilla icons `IronOre` and `Ingot_Silver` exist.

### LIKELY (widely reported for Build 42; each must be confirmed in the files)

- `Base.CopperOre` and `Base.CopperIngot` exist; copper ore is very heavy.
- Build 42 has a metalworking layer: furnace and forge world objects in more
  than one tier, a `Blacksmith` perk, iron and other ores and ingots, charcoal
  production, crucibles and molds of some kind.
- Recipes use the `craftRecipe` script block with `inputs` / `outputs`, a
  `time`, skill requirement and XP award fields, tags, a category, and a way to
  require a nearby station (by object tag or full type).
- Station objects expose whether they are lit / burning, and vanilla recipes
  that smelt require the lit state.
- `craftRecipe` can name a Lua callback that runs on creation of the output
  (an `OnCreate`-style field), receiving enough context to set ModData on the
  produced items; and a Lua test callback that can veto a recipe.
- Custom perks registered through `PerkFactory` (our `AmmoMaking`) can be used
  in recipe skill / XP fields.
- The Build 42 crafting UI can consume inputs from nearby containers and
  possibly from the floor around the player.
- `Base.Charcoal`, `Base.Log`, `Base.Plank`, `Base.Sledgehammer`,
  `Base.Sledgehammer2`, `Base.Hammer` exist.

### REQUIRES IN-GAME / VANILLA FILE VERIFICATION (this is M0)

Search the game's `media/scripts` folder (Windows: `findstr /s /i /n "TEXT" *.txt`,
Linux/macOS: `grep -rin "TEXT" .`) and read the vanilla Lua under
`media/lua/shared/` and `media/lua/client/` for the crafting UI. Record the
answers in §3 of this file.

| # | Question | What to search / open |
|---|---|---|
| V1 | Exact ids, weights and tags of copper ore and ingot; whether copper ore is even used by a vanilla recipe | `item CopperOre`, `item CopperIngot`, every recipe line mentioning them |
| V2 | Furnace / forge station identifiers per tier (Primitive / Simple / Advanced or whatever vanilla calls them), how they are built, whether they are `IsoObject`s with tags, and which tag or type vanilla recipes require | `Furnace`, `Forge`, `Bloomery`, `Kiln`, `Crucible`; the `Tags` on those objects; buildable / craftable definitions |
| V3 | How vanilla smelting recipes attach to a station: the exact `craftRecipe` field that names a required object (tag or type) and any "must be lit" field | every `craftRecipe` whose outputs contain `Ingot`; note every field name used |
| V4 | How iron, gold, silver or any other metal goes from ore or scrap to ingot: raw ore, or a preparation item (crushed / washed / dust / bloom), which tools, which station tier, how many inputs per ingot, how much time | recipes whose inputs are `*Ore` or `*Scrap` and outputs `*Ingot` |
| V5 | Fuel model: what a furnace burns, how it is lit, whether burn time is tracked by the object, and whether recipes check "lit" | the furnace object definitions and their Lua (`Fireplace`, `Campfire`, `Lit`, `Fuel`) |
| V6 | Complete `craftRecipe` syntax as used by vanilla: `inputs` / `outputs` item lines, `mode`, `flags`, `tags`, `category`, `time`, `SkillRequired`, `xpAward`, `AutoLearnAll`, `needToBeLearn`, `timedAction`, tool inputs that are kept (`mode:keep`) | read three or four vanilla recipe files end to end |
| V7 | Whether a recipe can produce an output that carries ModData, and whether a Lua callback runs on creation of the outputs (field name, argument list, whether it runs on the server in multiplayer) | `OnCreate`, `onCreate`, `OnGiveXP`, `OnTest`, `OnCanPerform`, `Lua` inside `craftRecipe` blocks; the corresponding vanilla Lua functions |
| V8 | Whether a custom perk name is accepted in `SkillRequired` / `xpAward` | any recipe using a non-core perk; the perk-name resolution in Lua / Java if visible |
| V9 | Whether recipe display names are translated via a `CraftRecipe_` / `Recipe_` key convention and in which translation file | `Translate/EN/` files containing recipe names |
| V10 | Whether the crafting UI takes inputs from the floor around the player, and how heavy items are handled | the crafting UI Lua, `ISCraftingUI` / equivalent, search `floor`, `nearby` |
| V11 | Whether any vanilla brass, bronze or other alloy recipe exists (naming, ratios, ingredients) | `Brass`, `Bronze`, `Alloy` |
| V12 | Whether a mod can add recipes to an existing vanilla station without editing vanilla files (recipes referencing the vanilla station tag from `AC_Recipes.txt`) | follows from V3; test in game with one dummy recipe |

M0 is done when every row has an answer with the file path it came from.

---

## 4. Copper strategy

- Ore: `Base.CopperOre`, as mining already drops it. Unchanged.
- Ingot: `Base.CopperIngot`, produced by a mod-defined recipe at the vanilla
  furnace, **or**, if V1/V4 show vanilla already smelts copper ore, by the
  vanilla recipe itself with no mod recipe at all.
- No `AmmoMaking.Copper*` items. The only acceptable reason to add one would be
  a vanilla `Base.CopperIngot` that vanilla recipes turn into something with
  **more** metal than went in; V1 will show whether any such recipe exists.

If the 40 weight holds (V1):

- Whether the player can carry a chunk to a furnace is a vanilla problem with
  vanilla answers (vehicles, furnaces near the site). We do not solve it with a
  custom item unless V10 shows the crafting UI cannot use a chunk lying next to
  the player and V4 shows vanilla has no preparation step. See §6.

---

## 5. Zinc strategy

Keep `AmmoMaking.ZincOre` and `AmmoMaking.ZincIngot`. Recommended changes (not
made yet):

| Item | Now | Recommended | Why |
|---|---|---|---|
| `AmmoMaking.ZincOre` | Weight 0.5 | Copy the verified `Base.CopperOre` weight and any `Tags` vanilla ore carries | Zinc must be "an ore" to the vanilla system in every way copper is, including whatever tag vanilla smelting recipes match on. Parity keeps one rule. |
| `AmmoMaking.ZincIngot` | Weight 1.0 | Copy the verified `Base.CopperIngot` weight and tags | Ingots are counted, not weighed, but vanilla may use ingot tags for later recipes. |
| prepared zinc | — | Only if §6 concludes preparation exists, and then named after the vanilla convention (e.g. if vanilla uses "Crushed X Ore", we add `AmmoMaking.CrushedZincOre`) | Never invent a convention vanilla does not have. |
| `AmmoMaking.BrassIngot` | — | New. Same weight as `Base.CopperIngot`. Icon: a vanilla ingot icon until custom art exists | The stage's product. |
| `AmmoMaking.BrassScrap` | — | **Not in this version.** With fixed-ratio recipes an off-spec batch cannot happen. Scrap returns with case recycling. | Fewer items. |

---

## 6. Ore preparation: only if justified

The previous design kept a crushing step for transport and skill reasons. Under
vanilla-first rules it is decided by M0, in this order:

1. **Vanilla smelts raw ore directly** (V4 shows `*Ore → *Ingot` with no
   intermediate): **no preparation step.** Copper ore goes into the furnace as
   is; zinc ore does the same. Transport of a heavy chunk is the vanilla
   experience.
2. **Vanilla has a preparation convention** (V4 shows crushed / washed / bloom
   items or a tool-and-recipe step before smelting): **follow it exactly**, with
   our zinc items named and tagged after the vanilla pattern, and our recipes
   mirroring the vanilla ones.
3. **Vanilla has neither** and the chunk is too heavy to carry and the crafting
   UI cannot use floor items (V1 + V10): add the **smallest** preparation step:
   a `craftRecipe` "Break up ore" requiring a hammer (`mode:keep`) that turns
   one chunk into k light pieces, and one smelting recipe that takes k pieces.
   Prefer this over a custom timed action. Only if V10 proves the crafting UI
   cannot reach a chunk on the ground does a custom ground timed action come
   back, built exactly like `AC_MineOreAction` with the same multiplayer guard.

Whatever the outcome, one chunk yields at most one ingot-equivalent (§9).

---

## 7. Brass on top of vanilla crafting

Vanilla `craftRecipe` inputs are fixed lists, so "load any N + M and see" is not
expressible without a custom station. The ratio decision is kept as a **choice
of recipe**:

| Recipe (display name) | Inputs | Output | Zinc fraction | Note |
|---|---|---|---|---|
| Cartridge brass, full batch | 7 Cu ingot + 3 Zn ingot | 10 brass | 30.0 % | reference quality |
| Cartridge brass, small batch | 2 Cu + 1 Zn | 3 brass | 33.3 % | early game, lower quality |
| Cartridge brass, medium batch | 5 Cu + 2 Zn | 7 brass | 28.6 % | in between |

Only correct-enough ratios exist as recipes, so a player cannot waste metal by
mistake; the decision is between batch size and quality, and between spending
ingots now or saving for a full batch. Wrong-ratio scrap is dropped from this
version.

Quality, in order of preference depending on V7:

- **V7 confirms a creation callback with access to the output items:** one
  `AmmoMaking.BrassIngot` item; the callback (in `AC_Materials`) sets
  `brassQuality` on each ingot from the recipe's zinc fraction and the player's
  Ammo Making level:

  ```text
  closeness    = 1 - |f - 0.30| / alloyTolerance        (0..1)
  skillTerm    = skillQualityFloor + (1 - skillQualityFloor) * level / 10
  brassQuality = round(100 * closeness * skillTerm)
  ```

  The three recipes pass their fraction to the same callback (by recipe name
  lookup in a table in `AC_Materials`, so no numbers live in the script file).
- **V7 shows no callback but ModData survives on outputs some other way:**
  same, wired through whatever hook exists (documented in M0).
- **V7 shows outputs cannot carry ModData:** discrete tiers as separate items
  (`AmmoMaking.BrassIngotRough`, `AmmoMaking.BrassIngot`,
  `AmmoMaking.BrassIngotFine`), chosen per recipe by `SkillRequired` gating
  (e.g. full batch at level ≥ 4 yields Fine). Quality becomes a per-item
  constant looked up in `AC_Materials`. Cases later read the tier the same way
  they would read the number.

The smallest extension needed in every case is: mod-defined `craftRecipe`
blocks, one Lua table of recipe → fraction, and one callback. No custom station.

---

## 8. Skill progression

Skill never creates metal. With vanilla recipes the available levers are:

| Lever | Mechanism | Config |
|---|---|---|
| Access | `SkillRequired = AmmoMaking:n` on the full-batch brass recipe (and on Fine tier if tiers are used); smelting itself unlocked at level 0 so the loop is reachable early | `brassFullBatchLevel` |
| XP | `xpAward = AmmoMaking:x` per recipe; all inputs are finite ore so XP cannot be farmed | per-recipe values mirrored in `AC_Materials.CONFIG` for tests |
| Quality | `skillQualityFloor` in the callback | `skillQualityFloor`, `alloyTolerance` |
| Time | Only if V6 shows recipe time can depend on skill; otherwise recipe time is fixed and the lever is dropped rather than re-implemented | — |
| Blacksmith interplay | Decision for the owner (§17): require only Ammo Making, or also a vanilla `Blacksmith` level for furnace recipes to match vanilla progression | — |

No yield or slag levers: vanilla recipes are deterministic and we do not add a
scheduler to make them otherwise.

---

## 9. Material conservation

Unit: **1 metal unit = 1 ingot**. One ore chunk contains at most 1 unit.

1. Every mod recipe satisfies `units(out) ≤ units(in)`. A table in
   `AC_Materials` lists every metal-bearing item with its unit value; a test
   walks every recipe the mod defines (read from a Lua mirror of
   `AC_Recipes.txt`, see §14) and checks the inequality.
2. Preparation (if any): 1 chunk → k pieces, smelt takes exactly k pieces → 1
   ingot. Never fewer pieces per ingot than the chunk yields.
3. Alloy recipes: `N + M` in → `N + M` out. Exactly.
4. No mod recipe converts a product back into more metal than it contains.
   Recycling (later stage) is strictly lossy.
5. Vanilla recipes touching `Base.CopperIngot` are out of our control but must
   be listed in M0 (V1) so that a vanilla path cannot combine with ours into a
   loop (e.g. vanilla ingot → N copper wire → our recipe back to ingot).
6. Nothing is consumed by mod Lua outside a recipe; the crafting system does
   the consumption and creation, so a crash cannot half-apply a recipe on our
   side.

A `-debug` ledger (sum of units in inventory and nearby containers) remains a
useful tester tool and needs no persistent state.

---

## 10. Quality integration (minimum useful model)

| Stage | Carries quality? | Why |
|---|---|---|
| Ore | No | Grade is quantity. |
| Prepared ore (if any) | No | Nothing decided. |
| Copper / zinc ingot | No | Vanilla ingot stays plain; zinc mirrors it. |
| Brass ingot | `brassQuality` 0–100 (or a tier item) | The one place a player decision changes the material. |
| Case (later) | `casingQuality` seeded from brass | Field already exists in `AmmoQuality`. |

---

## 11. Operation → mechanism

| Operation | Mechanism | Why |
|---|---|---|
| Build / place / fuel / light furnace | vanilla | Not ours. |
| Prepare ore (if any) | vanilla `craftRecipe` with a kept tool; ground timed action only as last resort (§6) | Prefer the crafting system. |
| Smelt copper / zinc | vanilla `craftRecipe` at the vanilla furnace | The point of the redesign. |
| Alloy brass | vanilla `craftRecipe` at the vanilla furnace | Same. |
| Set brass quality | Lua callback from the recipe, if available | Only custom logic in the loop. |
| Read brass quality | tooltip / inspection later | — |

No custom world objects. No custom scheduler. At most one custom timed action,
and only if M0 forces it.

---

## 12. Multiplayer

Because vanilla crafting is already server-authoritative and synchronised, the
custom persistent state of this stage is **zero**. What remains:

| Concern | Rule |
|---|---|
| Recipe execution, input consumption, output creation, station state, fuel, timers | vanilla; nothing to guard |
| Brass quality callback | M0 must record **where** the callback runs (client, server or both). If server-side, ModData set there is replicated; if client-side, the value must be set in a way vanilla syncs (V7). Until known, the callback must be idempotent and tolerant of running twice. |
| Ore preparation as a custom timed action (only if §6 case 3 ends there) | same guard as mining: disabled on multiplayer clients until a server command exists; it consumes and creates nothing on a client |
| Ledger / debug | client-only, read-only |

Retrofit risk is now limited to one callback and, at worst, one timed action.

---

## 13. Proposed file architecture

```text
scripts/AC_Recipes.txt        craftRecipe blocks: smelt copper (if vanilla lacks it),
                              smelt zinc, brass full / medium / small, optional
                              ore preparation. Fields exactly as V6 documents.
shared/AC_Materials.lua       item ids and units, recipe → zinc-fraction table,
                              brass quality maths (pure), the recipe callback(s),
                              the conservation table, the debug ledger.
client/AC_CrushOreAction.lua  ONLY if §6 case 3 ends in a ground timed action;
                              otherwise this file does not exist.
scripts/AC_Items.txt          + BrassIngot (and tier variants or prepared-ore
                              items only if M0 requires them); zinc weight/tag changes
Translate/EN/IG_UI.json       + item names, recipe display names (key convention from V9)
shared/AC_Compat.lua          + new item ids, vanilla station and tool ids, and a
                              probe that the mod's recipes are known to the script manager
client/AC_GeologyDebug.lua    + Spawn Metallurgy Kit (ores, ingots, hammer),
                              Show Material Ledger
tests/run_tests.lua           + materials / quality / conservation / callback sections
docs/METALLURGY_DESIGN.md     this file; §3 filled in by M0
```

One shared module and one script file are the whole feature. `AC_Metallurgy.lua`
from the previous design is gone with the furnace it managed.

---

## 14. Testing strategy

Offline (extend `tests/run_tests.lua`):

- **Conservation table:** every mod recipe (a Lua mirror of `AC_Recipes.txt`
  kept in `AC_Materials.RECIPES` and asserted equal to the script by a parser
  test, so the two cannot drift) satisfies units(out) ≤ units(in); alloy
  recipes satisfy equality.
- **Brass quality maths:** each recipe's fraction maps to the expected
  closeness; quality is monotone in level, bounded 0–100, and never above 100
  for the 7 + 3 batch at level 10; the tier fallback maps the same inputs to the
  same ordering.
- **Callback:** given a mocked recipe result with three output items, sets
  `brassQuality` on each; running twice is idempotent; unknown recipe name is a
  no-op with a console warning; missing player level defaults to 0.
- **Items:** every id referenced by `AC_Materials` is declared in
  `AC_Items.txt` or is on the vanilla list probed by `AC_Compat` (parser test).
- **Zinc parity:** the mirrored item definitions for zinc ore / ingot carry the
  same weight and tags as the recorded copper values (numbers filled by M0).
- **Ore preparation (only if it exists):** k pieces per chunk, smelt takes k,
  timed action cancellation consumes nothing, multiplayer guard.
- **Hidden information / localization / debug gating:** as for mining.

Only in Project Zomboid:

- everything in §3 V1–V12
- that a mod `craftRecipe` appears in the vanilla crafting UI at the vanilla
  furnace, is gated by "lit", consumes and produces correctly
- that the callback runs and ModData survives inventory grouping and container
  transfers
- that `SkillRequired` / `xpAward` accept the `AmmoMaking` perk
- recipe display names and translation keys
- timing and fuel feel of a full site's worth of ore

---

## 15. Milestones

| # | Milestone | Files | Gameplay result | Tests | Depends on | In-game verification |
|---|---|---|---|---|---|---|
| M0 | Inspect and verify vanilla B42.20 metallurgy | this document (§3 filled in with file paths) | none | none | mining loop passed | answer V1–V12; one throwaway dummy recipe at the vanilla furnace to prove V12 |
| M1 | Zinc and material definitions | `AC_Items.txt`, `AC_Materials.lua` (ids, units, conservation table), `IG_UI.json`, `AC_Compat.lua`, tests | zinc ore / ingot match vanilla ore / ingot weight and tags; brass ingot exists; ledger works | conservation table, parser tests, ids probed | M0 | debug spawn of every item; compat all OK |
| M2 | Ore preparation, only if §6 requires it | `AC_Recipes.txt` (prep recipe) or `AC_CrushOreAction.lua` + menu, items, tests | chunk → pieces | k per chunk, cancellation, MP guard | M1 | recipe visible / action works on a ground chunk |
| M3 | Copper and zinc smelting at the vanilla furnace | `AC_Recipes.txt` (smelt recipes), `AC_Compat.lua` (recipe probe), tests | ore → `Base.CopperIngot` / `AmmoMaking.ZincIngot` at a lit vanilla furnace | recipe mirror = script, conservation | M1 (M2 if it exists) | recipes appear at the furnace, require lit, consume / produce correctly |
| M4 | Brass alloying at the vanilla furnace | `AC_Recipes.txt` (3 brass recipes), `AC_Materials.lua` (fraction table), tests | ingots → brass in three batch sizes | equality conservation, fraction table | M3 | recipes appear, outputs correct |
| M5 | Quality and skill integration | `AC_Materials.lua` (callback, quality maths), items (tier variants if needed), recipes (`SkillRequired`, `xpAward`), tests | brass carries quality; skill gates the full batch; XP awarded | callback tests, monotonicity, idempotence | M4, V7/V8 answers | callback runs, ModData survives, XP shows in the skill panel |
| M6 | Balance, multiplayer and polish | all `CONFIG`, README, `docs/DEVELOPMENT.md`, debug ledger, (server handler only if a custom action exists) | tuned batch sizes and times; documented | XP once per event | M5 | full site run; multiplayer smoke test of a recipe |

M3 is the first milestone that produces metal; M4 completes the stage.

---

## 16. Risks

- **The vanilla station hook may not be moddable from a separate script file**
  (V12). If recipes cannot target the vanilla furnace tag from our file, the
  fallback is to ask what vanilla exposes before considering anything custom;
  the custom furnace is not a fallback here.
- **No creation callback (V7).** Quality degrades to discrete tiers. Acceptable.
- **Custom perk not accepted in recipes (V8).** Fall back to gating by nothing
  and awarding XP from the callback (if it exists) or from an
  `OnCreate`-equivalent; if neither exists, brass gives no Ammo Making XP in the
  first version and the loop still works.
- **Copper ore weight and floor access (V1, V10).** Decides §6. Worst case adds
  one custom timed action, nothing more.
- **Vanilla already smelts copper differently than we assume** (V4). Then we
  simply do not define a copper recipe and follow vanilla for zinc.
- **Grind.** A rich site is many chunks; recipe batch sizes are the lever.
- **Scope creep** into molds, sheets, cups, cases. Next stage.

---

## 17. Decisions requested from the project owner

1. **Brass as three fixed-ratio recipes** (recommended) versus one 7 + 3 recipe
   only. Three gives an early-game path; one is simplest.
2. **Furnace recipes gated on Ammo Making only** (recommended for the first
   version) versus also requiring a vanilla `Blacksmith` level to match vanilla
   metalworking progression.
3. **Brass quality now** (callback if V7 allows, tiers otherwise; recommended)
   versus deferring quality to case making.
4. **If §6 ends in case 3:** a preparation `craftRecipe` (recommended) versus a
   custom ground timed action, given the trade-off that the recipe needs the
   chunk in reach of the crafting UI.

Everything else is an implementation default tied to a config value or to an
M0 answer.

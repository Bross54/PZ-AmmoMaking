# Ore Processing + Metallurgy: design for the next milestone

Status: **design only. Nothing in this document is implemented.** It must not
be started until the mining loop passes in-game testing.

Target: Project Zomboid Build 42.20 Stable.

Guiding decision (project owner): **AmmoMaking metallurgy is an extension of
Build 42's own furnace / metalworking system, not a parallel one.** There is no
custom furnace world object, no custom fuel, heat, timer or persistence for
smelting. The mod contributes items, recipes attached to vanilla stations, and
a thin Lua layer for brass quality and skill.

## M0 status (2026-09-23)

`docs/VANILLA_METALLURGY_RESEARCH.md` holds the partial M0 result from
accessible sources, with evidence levels and the PowerShell commands that
finish it locally. Four findings already change this document (all STRONG
INDICATION, pending the local grep):

1. Vanilla's ore convention is **ore → furnace → scrap**, not ore → ingot:
   `Base.CopperOre` ×1 + charcoal ×4 → `Base.CopperScrap` ×10 at the Primitive
   Furnace. Zinc mirrors this. **No crushing or other preparation step.**
2. **`Base.CopperIngot` has no vanilla recipe.** The mod adds "scrap → ingot"
   casting for copper and zinc, using vanilla's own casting inputs (charcoal,
   crucible, tongs, ingot mold at a furnace).
3. **`Base.BrassIngot` and `Base.BrassScrap` already exist in 42.20.0** with
   no recipes. The mod reuses them; `AmmoMaking.BrassIngot` is dropped.
4. Recipes attach to a vanilla station through the station's crafting-bench
   tag in the recipe's `Tags` line (`Furnace` is the documented tag). Which
   tag each furnace tier declares is still unverified.

Owner decisions applied: first brass recipe is 7 copper + 3 zinc only; Ammo
Making is the only skill in `SkillRequired` / `xpAward` (vanilla smelting has
no Blacksmith gate, so none is added); brass quality is deferred; no
preparation step.

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
Base.CopperOre                       AmmoMaking.ZincOre
      │  vanilla "Smelt Copper Ore"         │  mod "Smelt Zinc Ore" (mirror)
      │  charcoal ×4, Primitive Furnace     │  charcoal ×4, same furnace tag
      ▼                                     ▼
Base.CopperScrap ×10                 AmmoMaking.ZincScrap ×10
      │  mod "Cast Copper Ingot"            │  mod "Cast Zinc Ingot"
      │  scrap ×10 + charcoal + crucible,   │  same inputs
      │  tongs, ingot mold (kept)           │
      ▼                                     ▼
Base.CopperIngot                     AmmoMaking.ZincIngot
      └──────────────┬────────────────────┘
                     ▼  mod "Cast Cartridge Brass": 7 Cu + 3 Zn ingots + charcoal,
                        crucible, tongs, ingot mold (kept), furnace tag
              Base.BrassIngot ×10   (vanilla item, no vanilla recipe)
```

The player experience is the vanilla one: build or find a furnace, fuel and
light it the vanilla way, open the vanilla crafting UI at the station, pick a
recipe, wait the recipe's time, take the output. The mod adds the recipes and
the zinc / brass items. Nothing about the furnace itself is ours.

### Step table

| Step | Player action | Station / tool | Input | Output | Time | Ammo Making XP | Failure | Quality | Persistent state (ours) |
|---|---|---|---|---|---|---|---|---|---|
| Smelt copper ore | vanilla crafting UI at a vanilla furnace; **vanilla recipe, untouched** | Primitive Furnace (or higher), charcoal-tag ×4 | `Base.CopperOre` ×1 | `Base.CopperScrap` ×10 | vanilla | vanilla (0) | vanilla | none | none |
| Smelt zinc ore | same UI; mod recipe mirroring "Smelt Copper Ore" | same | `AmmoMaking.ZincOre` ×1 | `AmmoMaking.ZincScrap` ×10 | copy vanilla | `xpAward = AmmoMaking:n` | vanilla | none | none |
| Cast copper / zinc ingot | same UI; mod recipe modelled on vanilla "Cast Iron Ingot" | furnace tag from M0 (vanilla casts at the Simple Furnace); charcoal, crucible (keep), tongs (keep, may degrade), ingot mold (keep) | scrap ×10 of one metal | `Base.CopperIngot` ×1 / `AmmoMaking.ZincIngot` ×1 | copy vanilla casting time | `AmmoMaking:n` | vanilla | none | none |
| Cast cartridge brass | same UI; mod recipe | same tools | 7 `Base.CopperIngot` + 3 `AmmoMaking.ZincIngot` | `Base.BrassIngot` ×10 | copy vanilla casting time | `AmmoMaking:n` | vanilla | deferred | none |

There is no slag, no fuel accounting, no pause / resume and no collect step of
ours. Charcoal is an ordinary consumed input, as in every vanilla furnace
recipe. Whether a furnace must additionally be lit is unverified (research §3).

---

## 3. Vanilla Build 42 integration research

This section was written before the source research. The current state of
each line, with evidence levels and sources, is in
`docs/VANILLA_METALLURGY_RESEARCH.md`; the local PowerShell commands there
replace every remaining LIKELY / VERIFY line with a fact. The lists below are
kept as the original question set.

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
- Scrap: `Base.CopperScrap`, from the **vanilla** "Smelt Copper Ore" recipe.
  The mod does not redefine or replace that recipe.
- Ingot: `Base.CopperIngot`, from the mod's "Cast Copper Ingot" (scrap ×10 +
  charcoal + crucible + tongs + ingot mold, kept tools). Vanilla has no recipe
  for this item, so the mod is adding, not overriding.
- No `AmmoMaking.Copper*` items. Vanilla's other use of copper scrap (4 scrap
  → 1 copper sheet at a forge) never returns scrap from an ingot, so no loop.

The 40 weight (STRONG INDICATION: `Weight = 40.0`,
`RequiresEquippedBothHands = true`, tag `base:heavyitem`) is the vanilla
experience for iron ore too. The player carries one chunk two-handed to the
furnace, exactly as vanilla intends; the mod adds nothing for transport.

---

## 5. Zinc strategy

Keep `AmmoMaking.ZincOre` and `AmmoMaking.ZincIngot`. Recommended changes (not
made yet):

| Item | Now | Recommended | Why |
|---|---|---|---|
| `AmmoMaking.ZincOre` | Weight 0.5 | Copy `Base.CopperOre`: Weight 40.0, `RequiresEquippedBothHands = true`, `Tags = base:hasmetal;base:heavyitem;base:zincore;base:zincsource` (tag prefix form to confirm locally) | Zinc must be "an ore" to the vanilla system in every way copper is. |
| `AmmoMaking.ZincScrap` | — | New. Copy `Base.CopperScrap`: Weight 0.5, `Tags = base:hasmetal` | The vanilla furnace convention is ore → scrap ×10. |
| `AmmoMaking.ZincIngot` | Weight 1.0 | Copy `Base.CopperIngot`: Weight 6.0, `Tags = base:hasmetal;base:ingot`, icon `Ingot_Silver` until a zinc icon exists | Same unit as every vanilla ingot. |
| `AmmoMaking.BrassIngot` | planned earlier | **Dropped.** Use vanilla `Base.BrassIngot` (Weight 5.0, icon `Ingot_Brass`, tags `base:hasmetal;base:ingot`) | Vanilla reserved the item with no recipe; the mod supplies the recipe. |
| `AmmoMaking.BrassScrap` | planned earlier | **Dropped.** Vanilla `Base.BrassScrap` (0.5) exists for the later recycling stage. | Fewer items, vanilla names. |

---

## 6. Ore preparation: not needed

Resolved by M0 (research §1, §6): vanilla's preparation step **is the
furnace**. Every vanilla ore goes ore → Primitive Furnace → intermediate (copper
scrap, iron bloom), and the 40-weight chunk is carried two-handed like iron
ore. There is no crushing, washing or dust convention to follow, and no reason
to invent one. The previous crushing design and the `AC_CrushOreAction`
fallback are withdrawn.

Whatever the local check finds, one chunk yields at most one ingot-equivalent
(§9): 1 ore → 10 scrap → 1 ingot.

## 7. Brass on top of vanilla crafting

Vanilla `craftRecipe` inputs are fixed lists, so "load any N + M and see" is not
expressible without a custom station. The ratio decision is kept as a **choice
of recipe**:

| Recipe (display name) | Inputs | Output | Zinc fraction | Note |
|---|---|---|---|---|
| Cast Cartridge Brass | 7 `Base.CopperIngot` + 3 `AmmoMaking.ZincIngot` (+ charcoal; crucible, tongs, ingot mold kept) | 10 `Base.BrassIngot` | 30.0 % | **the first and only brass recipe** (owner decision) |
| Cartridge brass, small batch (2 + 1 → 3) and medium batch (5 + 2 → 7) | — | — | 33.3 % / 28.6 % | candidates for a later balance pass, not the first version |

With one fixed recipe a player cannot waste metal by mistake; the only decision
is saving ten ingots for a batch. Wrong-ratio scrap does not exist.

Quality is **deferred** to cartridge-case manufacturing (owner decision). The
mechanism below is recorded for that later stage; nothing of it is built now.
Order of preference depending on V7:

- **V7 confirms a creation callback with access to the output items** (the
  42.20.4 API docs document `OnCreate(craftRecipeData, character)` with
  `getAllCreatedItems()`): the callback (in `AC_Materials`) sets
  `brassQuality` on each `Base.BrassIngot` from the recipe's zinc fraction and
  the player's Ammo Making level:

  ```text
  closeness    = 1 - |f - 0.30| / alloyTolerance        (0..1)
  skillTerm    = skillQualityFloor + (1 - skillQualityFloor) * level / 10
  brassQuality = round(100 * closeness * skillTerm)
  ```

  The three recipes pass their fraction to the same callback (by recipe name
  lookup in a table in `AC_Materials`, so no numbers live in the script file).
- **V7 shows no callback but ModData survives on outputs some other way:**
  same, wired through whatever hook exists (documented in M0).
- **V7 shows outputs cannot carry ModData reliably:** discrete tiers as
  separate mod items around the vanilla one (`AmmoMaking.BrassIngotRough`,
  `Base.BrassIngot`, `AmmoMaking.BrassIngotFine`), chosen per recipe by
  `SkillRequired` gating. Quality becomes a per-item constant looked up in
  `AC_Materials`. Cases later read the tier the same way they would read the
  number.

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
| Blacksmith interplay | **Ammo Making only.** Vanilla furnace recipes show no skill requirement and 0 XP, so requiring Blacksmith would be stricter than vanilla for the same station. | — |

No yield or slag levers: vanilla recipes are deterministic and we do not add a
scheduler to make them otherwise.

---

## 9. Material conservation

Unit: **1 metal unit = 1 ingot**. One ore chunk contains at most 1 unit.

1. Every mod recipe satisfies `units(out) ≤ units(in)`. A table in
   `AC_Materials` lists every metal-bearing item with its unit value; a test
   walks every recipe the mod defines (read from a Lua mirror of
   `AC_Recipes.txt`, see §14) and checks the inequality.
2. 1 ore chunk → 10 scrap (vanilla) and the mod's casting takes exactly 10
   scrap → 1 ingot. Never fewer scrap per ingot than a chunk yields.
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
| Custom timed actions | none in this stage (ore preparation was withdrawn), so nothing needs the mining-style client guard |
| Ledger / debug | client-only, read-only |

Retrofit risk is now limited to one callback and, at worst, one timed action.

---

## 13. Proposed file architecture

```text
scripts/AC_Recipes.txt        craftRecipe blocks: Smelt Zinc Ore, Cast Copper Ingot,
                              Cast Zinc Ingot, Cast Cartridge Brass. Fields copied from
                              the vanilla blocks found by research §9 command 3.
shared/AC_Materials.lua       item ids and units, recipe → zinc-fraction table,
                              brass quality maths (pure), the recipe callback(s),
                              the conservation table, the debug ledger.
scripts/AC_Items.txt          + ZincScrap; ZincOre and ZincIngot weight/tag changes.
                              No brass items (vanilla Base.BrassIngot is used).
Translate/EN/IG_UI.json       + item names, recipe display names (key convention from V9)
shared/AC_Compat.lua          + new item ids, vanilla station and tool ids, and a
                              probe that the mod's recipes are known to the script manager
client/AC_GeologyDebug.lua    + Spawn Metallurgy Kit (ores, ingots, hammer),
                              Show Material Ledger
tests/run_tests.lua           + materials / quality / conservation / callback sections
docs/METALLURGY_DESIGN.md     this file; §3 filled in by M0
```

One shared module and one script file are the whole feature. `AC_Metallurgy.lua`
and `AC_CrushOreAction.lua` from earlier drafts are gone with the mechanisms
they served.

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
- **Scrap arithmetic:** the mirrored zinc recipe yields 10 scrap per ore and
  each casting recipe consumes exactly 10 scrap, matching vanilla copper.
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
| M2 | Ore preparation | **Withdrawn** (research §1): vanilla has no preparation step and the furnace itself turns ore into scrap. Nothing to build. | — | — | — | — |
| M3 | Copper and zinc smelting at the vanilla furnace | `AC_Recipes.txt` ("Smelt Zinc Ore", "Cast Copper Ingot", "Cast Zinc Ingot"), `AC_Compat.lua` (recipe probe), tests | ore → scrap (vanilla + mirror) → `Base.CopperIngot` / `AmmoMaking.ZincIngot` at a vanilla furnace | recipe mirror = script, conservation (10 scrap per ingot) | M1 | recipes appear at the furnace, consume / produce correctly, any lit requirement |
| M4 | Brass alloying at the vanilla furnace | `AC_Recipes.txt` ("Cast Cartridge Brass"), `AC_Materials.lua` (units), tests | 7 Cu + 3 Zn → 10 `Base.BrassIngot` | equality conservation | M3 | recipe appears, output is the vanilla brass item |
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

## 17. Decisions

Decided by the project owner (2026-09-23):

1. First brass recipe: 7 copper + 3 zinc only. Smaller batches are a later
   balance question.
2. Ammo Making is the only skill in `SkillRequired` / `xpAward`; no Blacksmith
   gate, matching vanilla smelting which has none.
3. Brass quality deferred to cartridge-case manufacturing.
4. No ore preparation (vanilla has none).

Still open, and answered by the local M0 commands rather than by the owner:
which furnace tier tag(s) the recipes carry, whether a lit state is required,
and the exact vanilla casting block to copy for time, tools and animation.

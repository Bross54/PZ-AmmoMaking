# Ammunition roadmap

Where the ammunition stage stands after the pass of 2026-10-02, and what
comes next. Everything marked *implemented* is Lua and data checked offline
only; what the running game has to confirm is collected in each document's
`REQUIRES FUTURE IN-GAME VERIFICATION` section and summarised in
`DEVELOPMENT.md`.

## 1. Status

| Area | Status | Where |
|---|---|---|
| Geology, sampling, assay, analyzer, mining | implemented, seen working in game | `DEVELOPMENT.md` |
| Metallurgy, case stock | implemented | `METALLURGY_DESIGN.md` |
| Nine calibres: cases, bullets, primers, powder, assembly | implemented | `AMMUNITION_DESIGN.md` |
| **Die sets as rare loot** | **implemented this pass** | `LOOT_AND_RECYCLING.md` 1 |
| **Brass recycling** | **implemented this pass** | `LOOT_AND_RECYCLING.md` 2 |
| **Ammo boxes** | **nothing to build**: vanilla boxes handloaded rounds; pinned by tests and probed at game start | `LOOT_AND_RECYCLING.md` 3 |
| Component loot | deliberately none | `LOOT_AND_RECYCLING.md` 1.3, 4 |
| **Save data** | **hardened this pass**: schema, fuzz, range repairs | `DEVELOPMENT.md`, `AC_SaveData.lua` |
| Reloading press | designed; recipes prepared and switched off; **blocked on sprites** | `RELOADING_PRESS_DESIGN.md` |
| Spent cases | **researched this pass; not implemented** | `SPENT_CASE_RESEARCH.md` |
| Quality that affects firing | **carrier designed this pass; no effect exists** | `AMMO_QUALITY_RUNTIME_DESIGN.md` |
| Multiplayer | reviewed, nothing implemented | `DEVELOPMENT.md`, `MULTIPLAYER_MINING.md` |

Numbers: 41 mod items, 55 recipes (51 manufacturing, 3 scrapping, 1 recast),
22 loot entries in 4 vanilla lists.

## 2. What the research settled

Kept here in one line each; the evidence is in the documents named above.

- **Boxes.** `place_ammo_in_box` takes the nine rounds by item type, with no
  box item, tool or `OnCreate`. A handloaded round is the vanilla item. The
  casing-quality record is lost at boxing, as at loading.
- **Loot.** Lists are Lua tables parsed once per world load, after
  `OnPreDistributionMerge`; a weight is the percent chance per roll. 184 of
  the 1,420 procedural lists are used by no container, among them three
  gun-store lists and several that look usable.
- **Magazines and firearms.** A round becomes a count when loaded; a
  magazine item is destroyed on insert and a new one made on eject; nothing
  vanilla carries ModData between round, magazine and gun.
- **Firing.** The round is taken in Lua, in vanilla's
  `OnWeaponSwingHitPoint` handler; there is no spent-case item and ejection
  is only a sound. Revolvers keep a spent count that is not saved; pump,
  bolt and lever guns eject at the rack.
- **Brass in the world.** `Base.BrassScrap` is in no live loot list and no
  vanilla recipe uses it; gunpowder is foraged or taken from rounds; toy
  caps exist in one location.
- **Press sprites.** A second claim on a sprite stops every world from
  loading; every drawable unclaimed vanilla candidate is on the map. No
  placeholder is provably safe.

## 3. What comes next, by what it is waiting for

### READY WITHOUT GAME TEST

Work that changes data and Lua the offline suite covers end to end.

| Task | Notes |
|---|---|
| Copper recycling (bullets and shot back to scrap) | needs a loss model that fits two bullets per scrap; `AC_Recycling` groups by content already |
| A debug kit for recycling | a spawn entry in the debug tree, like the other stages' kits |
| Spent-case **data**: `calibre.spentCase`, items, a resizing recipe, the recycling group | all covered by the model tests and generators; do it together with the hook, not before (`SPENT_CASE_RESEARCH.md` 3–4) |
| The quality tally as pure functions (`load`, `takeOne`, `moveAll`, `reconcile`) | testable exactly as `AC_CaseQuality` is; no vanilla function touched (`AMMO_QUALITY_RUNTIME_DESIGN.md` 4) |
| Rare component loot through `AC_Loot` | the mechanism and validation exist; whether to do it is a decision (below) |
| More calibres or shell variants | one `define{}` entry and three items each |

### READY BUT REQUIRES RUNTIME VALIDATION

Written, or one switch away, and unproven until seen in game.

| Task | What has to be seen |
|---|---|
| Die-set loot | the log line and the game-start check; a die set in a gun-store display case; the feel of the weights |
| Brass recycling | the four recipes at a surface and a furnace; a mixed input line filled from several components |
| Boxing handloaded rounds | `place_ammo_in_box` offered for rounds carrying ModData |
| The Ammo Making requirement on recipes | `addRequiredSkill` from Lua, the level shown in the crafting UI (open since the metallurgy stage) |
| Save-data repairs | nothing new to see; they only act on damaged values |
| Reloading press recipes | `PRESS.enabled = true` once the station exists |

### BLOCKED ON SOMETHING ELSE

| Task | Blocked on |
|---|---|
| **Reloading press entity** | **art**: a tile sheet and pack of the mod's own (`RELOADING_PRESS_DESIGN.md` 2.4, 7). The entity script is drafted. |
| Multiplayer authority | its own stage; mining and analyzer placement are disabled for clients until then |

### BLOCKED ON A GAMEPLAY DECISION

Each needs the project owner to choose before any code is right.

| Task | The decision |
|---|---|
| **Spent cases** | Do factory rounds leave reusable brass? All of it or a share? On the ground or in the inventory? What does resizing cost? It changes the brass economy more than anything so far: a looted carton of 9mm is thirty ingots of cases |
| **Quality effects, misfires, jams** | Whether quality should matter at the shot at all, and through what: vanilla's own jam chance is the natural lever. The carrier is designed; no effect is |
| Rare component loot | Whether finding primers or cups should be possible; today the answer is no |
| Press advantage beyond time | A quality bonus or batch size would make the press mandatory rather than convenient |
| Recycling yield | Half is the highest safe figure today; a different XP model would allow more |

### FUTURE / OPTIONAL

- Lead and its geology; jacketed and cast bullets.
- Primer and powder chemistry beyond the present stand-ins.
- Better presses as further bench tags, as the forges do.
- Progression polish: a use for levels 6 and above (nothing requires them).
- An inspection tool for a magazine or firearm, once a quality carrier
  exists.

## 4. Order of work proposed

```text
1. In-game validation of this pass   loot, recycling, boxing, the recipe skill gate
2. Reloading press                   needs a tile sheet; everything else is prepared
3. Spent cases                       decision first, then data, then the hook, off by default
4. Quality tally                     pure functions, then the wrapped vanilla functions
5. Quality effects                   only on a tally seen to stay in step
6. Multiplayer authority             its own stage
```

Steps 1 and 2 touch no firearm code. Steps 3 to 5 do, and each begins with a
decision, not with code.

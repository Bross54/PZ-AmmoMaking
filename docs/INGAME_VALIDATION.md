# In-game validation

One play session, in order, that looks at everything the offline tests
cannot. Nothing below has been run in the game unless it says
**CONFIRMED**; the offline suite proves the logic, not the engine.

How to use it:

- Start the game with `-debug` (Steam: Properties, launch options). The
  debug menu is a right click on the ground: **Ammo Making Debug**.
- Keep `console.txt` open (`%UserProfile%\Zomboid\console.txt`). Every line
  of the mod starts with `[AmmoMaking]`.
- Write `PASS` or `FAIL` in the **Result** field of each section. A FAIL
  needs only the section number and the console lines around it.
- Sections 1 to 17 need only the main mod. Sections 18 to 20 need an
  add-on or a sandbox option; they are marked.
- **If a world does not load, or loads with a red error box at once**:
  untick `Ammo Making: Reloading Press (experimental)` and
  `Ammo Making: Spent Cases (experimental)`,
  start again, and note which one it was. The main mod has no tile sheet
  and no entity of its own; the press add-on has both.

Use a **new** sandbox world for the session, single player. Old saves are
section 21.

---

## 1. Startup

Steps
1. In the mod list, select **Ammo Making**, then each add-on, without
   ticking the add-ons.
2. Enable only **Ammo Making**. Start a new sandbox world.

Expected
- The mod list shows each mod's poster (a dark workbench, the title
  *AMMO MAKING*, the add-ons marked *EXPERIMENTAL*) in the picture square
  beside its description, and version 0.11.0.
- The world loads; no error box (the red counter at the bottom right stays
  at 0).
- The skill panel shows **Ammo Making** at level 0.

Console
- One `... loaded` line per module (`Calibre definitions loaded (9)`,
  `Compatibility check loaded`, `Spent cases loaded`,
  `Quality tracking loaded`, `Debug tools loaded`, ...).
- `[AmmoMaking] Die set loot: 22 entries added, ...`,
  `[AmmoMaking] Component loot: ... entries added, ...`,
  `[AmmoMaking] Skill book loot: 20 entries added, ...` and
  `[AmmoMaking] Bullet mould loot: 5 entries added, ...` with
  `lists missing: 0`.
- `[AmmoMaking] Lead casting loaded (6 castable calibres)`.
- `[AmmoMaking] Skill books: Ammo Making entered in vanilla's reading table (server Lua)`
  once per world load. If it says `(game start)` instead, the server file
  ran before vanilla's table existed: note it, the books still work.
- No line with `WARNING` and no Lua stack trace.
- **Not** present: `Spent cases installed`, `Quality tracking installed`.

Debug shortcut: none.

Result: ____

## 2. Compatibility report

Steps
1. Debug menu, **Diagnostics > Run Compatibility Check**.

Expected / Console
- Every line is `OK:`; the last line is
  `[AmmoMaking] Compatibility check: N ok, 0 warnings, 0 unverified`.
- Five feature lines, all off:
  `feature Reloading Press: off (off)`, `feature Spent Cases: off (off)`,
  `feature Ammunition Quality Tracking: off (off)`,
  `feature Ammunition Quality Firing Effects: off (off)`,
  `feature Multiplayer Server Authority: off (off)`,
  `feature 7.62x39 Handloading (Vanilla Weapons Plus): off (off)`,
  `feature Hot Brass Casings Resized: off (off)`,
  `feature Handloading for Vanilla Firearms Expansion: off (off)`,
  `feature Handloading for Rain's Firearms: off (off)`,
  `feature Handloading for Rain's Firearms Expanded: off (off)`,
  `feature Handloading for GaelGunStore: off (off)`,
  `feature Handloading for Real Firearms: off (off)`,
  `feature Handloading for Modern Firearms System: off (off)` (each on with
  its add-on and its gun mod ticked; with Modern Firearms System also a
  WARNING that its Base.Bullets38 is a 6.8mm round).
- One line per calibre class (`.../... complete`).
- `OK: die set loot (...)` and `OK: component loot (...)`.
- `OK: skill books entered in vanilla's reading table (server Lua)` and
  `OK: skill book loot (20 entries)`; the five book items
  (`OK: AmmoMaking.BookAmmoMaking1` ...) among the item lines.
- `OK: lead casting (9 castable calibres, 3 moulds, no XP for melting)`
  and `OK: bullet mould loot (5 entries)`; `OK: Base.LeadPipe`,
  `OK: Base.JigLure` and `OK: AmmoMaking.LeadScrap` among the item lines.

Any `WARNING` or `UNVERIFIED` line is a finding: copy it whole.

Debug shortcut: **Diagnostics > Print Feature Flags**, **Print Save
Schema**, **Print Placeholder Visuals** should each print a short table
and raise nothing.

Result: ____

## 3. Debug menu

Steps
1. Right click the ground, open **Ammo Making Debug** and each submenu:
   Geology, Analyzer, Metallurgy, Ammunition, Diagnostics.

Expected
- Five submenus (no **Stations**: the press add-on is off). Each opens;
  no entry raises an error when clicked.
- Without `-debug`, the menu is not there at all (check once at the end).

Result: ____

## 4. Geology

Steps
1. Stand on grass outdoors. **Geology > Inspect Current Tile**, then
   **Survey Current Area (3x3)**, then **Show Geology Seed**.
2. Walk 50 tiles and repeat.

Expected
- Copper and zinc percentages and a reserve for each tile; the same tile
  gives the same answer every time; different places differ.
- Indoors, on a road and on water the tile is refused as not natural
  ground.

Console: the tile lines, no error.

Result: ____

## 5. Field assay

Steps
1. **Geology > Spawn Sampling Kit**. Equip the shovel.
2. Right click the grass: **Dig Geological Sample**.
3. Right click the sample: **Analyze with Field Assay Kit**, then **View
   Assay Result**.

Expected
- The shovel animation plays; one **Geological Sample** appears
  (**CONFIRMED** on 42.20.4 with `Base.Shovel`).
- After the assay the sample is a **Tested Geological Sample**; the window
  shows a grade word per metal; the kit's name shows one use less.
- Ammo Making XP rises.

Console: `Started digging geological sample`,
`Geological sample digging completed at x, y`.

Debug shortcut: **Geology > Spawn Assayed Sample (current 3x3)** skips
the digging.

Result: ____

## 6. Advanced assay

Steps
1. Dig a second sample; **Analyze with Advanced Field Assay Kit**.
2. On the first (field-tested) sample: **Re-analyze with Advanced Field
   Assay Kit**.

Expected
- A percentage range per metal and an accuracy line. Re-analysis narrows
  the first sample's result; a sample that already has an equal or better
  assay is refused.

Result: ____

## 7. Analyzer

Steps
1. **Analyzer > Spawn Laboratory Analyzer**. Right click it in the
   inventory: **Place Laboratory Assay Analyzer**; place it indoors in a
   building that has power (or beside a running generator).
2. Right click the placed object: **Start Lab Assay: Sample ...**.
3. **Check Laboratory Progress**. Then **Analyzer > Complete Analyzer Job**
   and **Collect Laboratory Sample**.
4. Start another assay and **Cancel Laboratory Assay**.
5. **Pick Up Laboratory Assay Analyzer** when it is empty; try it once
   while an assay runs.

Expected
- A ghost sprite while placing; the object (a vanilla industrial tile,
  `industry_03_61`: placeholder) stands on the tile and blocks it.
- Without power: "Requires Electricity", and a running assay pauses.
- The collected sample is a **Laboratory Tested Geological Sample** with
  exact percentages and a tolerance line.
- Cancel returns the sample. Pick up is refused while processing or
  ready, and gives exactly one analyzer item otherwise.

Console: `Laboratory Assay Analyzer placed at ...`,
`Laboratory Assay Analyzer picked up at ...`.

Debug shortcut: **Analyzer > Inspect Analyzer State**; **Geology > Inspect
Clicked Tile Objects** shows the sprite and the stored state.

Also once, by hand: **Geology > Spawn Equipment Parts Kit**, then craft
*Assemble Field Assay Kit*, *Assemble Advanced Field Assay Kit* and
*Build Laboratory Assay Analyzer* from the crafting window (the analyzer
keeps the screwdriver; a broken light bulb or amplifier is not accepted).

Result: ____

## 8. Mining

Steps
1. **Geology > Spawn Mining Kit**. Carry an assayed sample of the spot
   (section 5) whose result shows workable ore.
2. Equip the pickaxe. Right click the ground: **Mine Copper Ore (Assay:
   ...)** or **Mine Zinc Ore (...)**.
3. Mine until the option reads **(Exhausted)**. Walk away during one
   attempt.

Expected
- The pickaxe animation plays and the action completes (**CONFIRMED**).
- Zinc ore appears on the ground (**CONFIRMED**); copper ore is vanilla's
  `Base.CopperOre` (not yet seen).
- One result message per extraction, with the remaining reserve and the
  XP; the reserve drops by one (**CONFIRMED**: `remaining 1/2`).
- An exhausted tile gives nothing more (**CONFIRMED**). Walking away
  cancels and gives nothing (**CONFIRMED**).
- The ore can be picked up; zinc ore is heavy.

Console: `Started mining ...`, `Mining: +5 Ammo Making XP (total a -> b)`.

Debug shortcut: **Geology > Reset Depletion: Current Tile** or **Geology > Reset Depletion: 3x3 Area**.

Result: ____

## 9. Save and reload: depletion

Steps
1. After section 8, with one tile exhausted and one partly mined and an
   assay running in the analyzer: quit to the main menu, load the save.

Expected
- The exhausted tile is still exhausted; the partly mined tile shows the
  same remaining count.
- The analyzer still holds its sample and its remaining time.
- The compatibility check prints its summary again for the second load.

Result: ____

## 10. Metallurgy

Steps
1. **Metallurgy > Spawn Metallurgy Kit**. Build or find vanilla's
   furnaces.
2. At a **Primitive Furnace**: *Smelt Zinc Ore*. At a **Simple Furnace**:
   *Cast Zinc Ingot*, *Cast Copper Ingot*.
3. Lead (`docs/METALLURGY_DESIGN.md` 12): take two Lead Pipes and five Jig
   Lures from the vanilla debug item list; break one pipe on a zombie or a
   wall first if you can. At the **Primitive Furnace**, with the crucible
   and tongs: *Melt Lead from Lead Pipe* (once whole, once broken) and
   *Melt Lead from Jig Lures*.

Expected
- Each recipe is listed at its furnace with its name, not a raw id.
- The crucible, tongs and mold are kept; inputs are consumed; one craft
  logs one XP line.
- Zinc scrap and zinc ingot have a name and an icon (placeholders: the
  aluminium scrap and silver ingot icons).
- Lead: two Lead Scrap per pipe, broken or whole; one per five jig lures.
  The crucible and tongs are kept. No Ammo Making XP line for a melt. The
  recipes are listed at a Primitive Furnace (and at the higher furnaces).

Debug shortcut: **Metallurgy > Inspect Station Recipes**, **Print
Material Ledger (inventory)**.

Result: ____

## 11. Brass

Steps
1. At the Simple Furnace: *Cast Cartridge Brass (7 Copper + 3 Zinc)*.
2. **Metallurgy > Spawn Case Stock Kit**. At a forge: *Forge Small Brass
   Sheets*; then *Punch Brass Case Cups*.

Expected
- 10 vanilla brass ingots from 7 copper and 3 zinc.
- Sheets and cups are made in the quantities the recipe window shows; the
  ledger of **Print Material Ledger** adds up before and after (nothing
  gained).

Result: ____

## 12. 9mm

Steps
1. **Ammo Making Debug > Set Ammo Making Level > 5** (the recipes are
   level-gated; 9mm assembly needs 3, rifle and shotgun steps up to 5). **Ammunition > Spawn Calibre Kit > 9mm** and **Spawn
   Primer and Powder Kit**.
2. Craft, in order: *Forge 9mm Handloading Die Set* (forge), *Form 9mm
   Case*, *Swage 9mm Copper Bullets*, *Make Small Pistol Primers*,
   *Assemble 9mm Round*.
3. Right click a case and a finished round: **Inspect Ammunition**.
4. Load the rounds into a 9mm magazine, fire them at a wall.
5. Cast bullets: take two Iron Bar Quarters from the vanilla debug item
   list; at the forge *Forge Pistol Bullet Mould*. With the lead scrap of
   section 10, at the **Primitive Furnace**: *Cast 9mm Lead Bullets*; then
   *Assemble 9mm Round (Cast Bullet)*. Inspect and fire one as in steps 3
   and 4.

Expected
- One round per assembly craft; the die set is kept; powder is taken by
  uses.
- The die set shows a condition (10 of 10 when forged). Over many crafts it
  now and then loses a point (about one craft in 95 at level 5); a die set
  at 0 is broken and its recipes no longer offer it.
- The round is vanilla's 9mm round: it stacks with factory rounds, loads
  into vanilla magazines and fires exactly like one.
- The inspection window opens and shows a case quality; in `-debug` three
  `[debug]` lines follow.
- A recipe above your level is shown but locked.
- The quick way to everything below: **Ammunition > Spawn Casting Kit**,
  **Spawn Mould Materials Kit** and **Spawn Treatment Kit**. Anneal five
  9mm cases (*Anneal 9mm Cases with a Blowtorch*): each gains 3 and
  *Inspect Ammunition* says "Neck annealed with a blowtorch."; lube five
  cast bullets with candle wax: +5 and "Lubed with candle wax.".
- Step 5 with the other moulds (take a Stone Block, Clay and a Sandbag
  from the vanilla debug item list): *Carve Stone Pistol Bullet Mould*
  with a hammer and chisel; *Shape Clay Pistol Bullet Mould*, then *Fire
  Clay Pistol Bullet Mould* at a kiln; *Ram Sand Pistol Bullet Mould*.
  Cast 9mm bullets in each: the stone mould is kept and shows a condition,
  the clay mould is broken after its cast, the sand mould is gone.
  *Inspect Ammunition* on a cast bullet shows "Bullet quality", lower for
  sand than for iron at the same level.
- Step 5: the mould is kept; two cast bullets per lead scrap; the cast
  round is the same vanilla 9mm round (it stacks with the others) and logs
  the same XP as a copper one. No cast recipe exists for the rifle
  calibres.

Debug shortcut: **Ammunition > Verify Ammo Dependencies**, **Print Calibre
Definitions**, **Print Primer Families**, **Inspect Ammo Components
(inventory)**.

Result: ____

## 13. Rifle

Steps
1. The same as section 12 for **.308** (kit: `.308`), with *Make Large
   Rifle Primers*.
2. Fire from a vanilla hunting rifle. Repeat the assembly only for 5.56
   and .30-30 if time allows.

Expected
- As section 12. Rifle recipes need a higher level than pistol ones.

Result: ____

## 14. 12 gauge

Steps
1. Kit `12 Gauge`. Craft *Form 12 Gauge Brass Hull*, *Swage 12 Gauge
   Copper Shot Charge*, *Assemble 12 Gauge Shell*.
2. Fire from a vanilla shotgun.
3. Lead shot: *Forge Buckshot Mould* (forge), *Cast 12 Gauge Lead Shot
   Charge* (Primitive Furnace), *Assemble 12 Gauge Shell (Lead Shot)*.

Expected
- The wad material is consumed; one shell per craft; the shell is
  vanilla's and behaves as one (pellets, boxes, bandolier).
- A shell with lead shot is the same vanilla shell.

Result: ____

## 15. Recycling

Steps
1. **Metallurgy > Spawn Recycling Kit**.
2. At any surface: the three *Scrap ...* recipes. At a furnace: *Cast
   Brass Ingot (Brass Scrap)*.

Expected
- Each scrapping recipe takes a mixed batch (several kinds of cup, sheet
  or case in one craft) and returns brass scrap; fewer units come back
  than went in.
- No Ammo Making XP line for any of the four.

Result: ____

## 16. Loot

Steps
1. With the vanilla debug loot tool (or by visiting): a gun store's
   magazine and ammunition display, a hunting store's lockers, a metalwork
   or blacksmith crate.
2. Skill books (`docs/AMMUNITION_DESIGN.md` 9.2): a gun store's shelves,
   a bookstore, a library. Then, with Ammo Making at level 0, take the five
   volumes from the vanilla debug item list (search `BookAmmoMaking`) and
   right click each one. Read *Ammo Making I* to the end; then mine one ore
   (section 8) and note the XP line.
3. Balance options (`docs/BALANCE_OPTIONS.md`): look at the sandbox page
   *Ammo Making* of a new world. Then start a second new world with *Die
   sets found as loot* 2, *Reloading stock found as loot* 0, *Ore per
   deposit tile* 3, *Ammo Making XP multiplier* 3 and the game's global XP
   multiplier switched off. Repeat step 1 there, mine one Good tile
   (section 8) and craft one recipe that gives XP.

Expected
- Die sets, and now and then a primer box or gunpowder, in gun stores;
  brass scrap or a small brass sheet in metalwork crates. Rare: several
  containers may be needed.
- Rarer still, a bullet mould: either mould in a gun store's ammunition
  case, the pistol mould in a garage gun locker, the buckshot mould among
  a hunter's things. The die-set option scales them too: in the second
  world they turn up about twice as often.
- No cases, bullets or finished handloads anywhere.
- An Ammo Making book now and then, most often on a gun store's shelves;
  rarely in a bookstore, a library or a survivalist's crate. Its icon is a
  hardback with a cartridge on the cover and one to five bands on the spine.
- At level 0: volume I can be read; II to V say the book is too
  complicated (vanilla's own text). The reading window (vanilla's
  literature list) shows the five under skill books. No error box when
  any of them is right clicked.
- After volume I is read: the skill panel shows an XP multiplier for
  Ammo Making (x1.5), and the mining XP line shows 1.5 times the amount in
  the total (`total a -> b`). At level 2 and above volume I is too simple.
- The page shows the four balance options with their labels and tooltips,
  each at 1.
- Second world: no component loot of the mod at all, die sets noticeably
  more often; a Good tile gives 6 ore; the XP line of a craft shows three
  times its amount in the total (`total a -> b`). Vanilla's own loot looks
  as in the first world.
- Containers already filled before an option is changed keep what they
  hold (only if the options can be changed for a running save).

Console (section 1): the three loot lines. Second world only:
`Balance options of this save: ...` and
`Loot multipliers: die sets x2, components x0; ... loot tables read again: true`.

Result: ____

## 17. Ammo boxes

Steps
1. With 50 handloaded 9mm rounds (or a mix with factory rounds): vanilla's
   *place in box* recipe; then open the box again.

Expected
- Vanilla's recipe accepts them. The rounds that come out are ordinary
  rounds: a box keeps no quality record (documented, by design).

Result: ____

---

## 18. Press (add-on: `Ammo Making: Reloading Press (experimental)`)

Steps
1. Quit. Enable the add-on **Ammo Making: Reloading Press (experimental)** for the save
   (or a new world). Load.
2. **Diagnostics > Run Compatibility Check**.
3. **Stations > Spawn Press Build Kit**. Open the build menu, find the
   **Reloading Press**, place it.
4. Use it: craft *Form 9mm Case (Press)*, *Swage 9mm Copper Bullets
   (Press)*, *Assemble 9mm Round (Press)*.
5. Pick the press up with the vanilla furniture tool and place it again.
6. Save, reload.

Expected
- The world loads (if not: untick the add-on; that is the finding).
- `feature Reloading Press: ON (on)` and OK lines for the press entity and
  its two sprites.
- The press is in the build menu with a name and an icon (vanilla's hand
  press icon: placeholder), costs the kit, and appears as a programmer-art
  sprite facing south or east.
- A press recipe looked at elsewhere says "Requires a Reloading Press"
  (not a raw `IGUI_...` key); the placed object is named Reloading Press.
- Its window lists 27 recipes, all `(Press)`. They use the **same** die
  sets and inputs as the hand recipes, give the same output and the same
  XP, and take less time. The hand recipes still work without it.
- The press survives save and reload.

Debug shortcut: **Stations** exists only with the add-on.

Result: ____

## 19. Spent cases (add-on: `Ammo Making: Spent Cases (experimental)`)

Steps
1. Enable **Ammo Making: Spent Cases (experimental)**; in the sandbox options, page
   **Ammo Making**, leave *Spent cases found* at 50. Load.
2. Fire 20 rounds from a pistol; look at the ground.
3. Fire a revolver empty and reload it. Fire a pump shotgun and a bolt
   rifle, racking each time. Fire a double-barrel and open it.
4. **Ammunition > Spawn Spent Cases Kit**; craft the three *Scrap Spent
   ...* recipes.
5. With Ammo Making at level 1, open the crafting window on a surface and
   look for *Resize Spent 9mm Case*; raise Ammo Making to 2 and craft it
   four times, then craft *Resize Spent .308 Case* at level 4. Inspect the
   resized cases, and form four new 9mm cases at the same level to
   compare. Assemble a
   9mm round on the resized case.
6. Set the option to 0 and to 100 in two short tries.

Expected
- `feature Spent Cases: ON (on)`; console
  `[AmmoMaking] Spent cases installed (shot true, rack true, reload true;
  50 % found, placed on the ground)`.
- About half the shots leave a **Spent ... Case** on the shooter's tile:
  at the shot for self-loaders, at the rack for pump, bolt and lever
  guns, at the reload for revolvers and break-actions. Never more cases
  than shots.
- Spent cases cannot be loaded as they are; they scrap at a lower return
  than unused brass, with no XP.
- *Resize Spent 9mm Case* needs Ammo Making 2 (the crafting window names
  the level), takes two spent 9mm cases, keeps the die set and the
  hammer, and makes one **Empty 9mm Case**. No Ammo Making XP. The
  resized case shows a casing quality; over a few of each, resized cases
  come out about 10 (one band) below cases formed at the same level (the
  roll spreads 15 either way). The round assembled on it is an ordinary
  9mm round.
- Firing, racking, reloading and jamming feel exactly as without the
  add-on.
- With Hot Brass enabled as well: `feature Spent Cases: off (conflict
  with HBVCEFb42)` and no case from this mod.

Result: ____

## 20. Quality tally (sandbox option)

Steps
1. Sandbox options, page **Ammo Making**: tick *Track ammunition quality
   in magazines and firearms*. Single player. Load.
2. Load 10 handloaded 9mm rounds and 5 factory rounds into a magazine.
   Right click the magazine: **Inspect Loaded Ammunition**.
3. Insert the magazine, rack, fire 3, eject the magazine, inspect it and
   the pistol.
4. Unload the magazine by hand; inspect a loose round.
5. Repeat briefly with a revolver and a pump shotgun.
6. **Ammunition > Inspect Loads**.

Expected
- `feature Ammunition Quality Tracking: ON (on)`; console
  `[AmmoMaking] Quality tracking installed (7 of 7 reload functions, shot
  true)`.
- The window shows the count loaded, how many are handloaded and their
  average case quality. Counts never exceed what the magazine holds.
- Rounds unloaded again carry a case quality (the average of the load,
  not each round's own).
- Firing is unchanged: the tally has no effect on any shot.
- Any doubt resolves to "Factory rounds": that is the designed fallback,
  not a failure. A stack trace or a changed reload is a failure.
- `feature Ammunition Quality Firing Effects: off (locked)` whatever is
  ticked.

Result: ____

Then, with the same tracking on, switch on *Poor handloads jam more often*
as well (new world, or the sandbox page of a copy): fire a magazine of the
worst handloads you can make (level 0, sand mould): the gun jams a little
more often than with factory rounds and racking clears it; a magazine of
factory rounds never jams more than vanilla does.

**7.62x39 add-on** (only with Vanilla Weapons Plus - Gunworks Edition):
tick *Ammo Making: 7.62x39 (experimental)*; the world loads; **Ammunition >
Spawn Calibre Kit** has no 7.62x39 entry yet, so take the steel bar quarters,
brass and copper from the other kits, forge the 7.62x39 die set, then form,
swage and assemble one round; it is the mod's `Base.762Bullets`,
stacks with found ones and fires in the AK-47.

## 21. Save and reload

Steps
1. Save with: a half-loaded magazine holding handloads, a running assay,
   a placed press, spent cases on the ground, cases and rounds in a
   container. Quit to the menu, load.
2. Then disable both add-ons and the sandbox option and load the same
   save once more.
3. If you have a save from version 0.8 or earlier, load it with this
   version.

Expected
- Everything is as it was left; the magazine's inspection is unchanged.
- With the add-ons off: the world still loads. The press and the spent
  cases are gone or inert (the engine drops items and objects whose
  script is missing); nothing else is affected. **This is the riskiest
  step of the session**: back the save up first.
- An old save loads with no warning; old samples, kits and analyzers
  read as before.

Debug shortcut: **Diagnostics > Print Save Schema**.

Result: ____

## 22. Error log check

Steps
1. Close the game. Search `console.txt` for `[AmmoMaking] WARNING`,
   `ERROR`, `Exception`, `attempted index`, `Tried to call nil` and
   `No implementation found`.
2. Once, start without `-debug`: no **Ammo Making Debug** menu, and the
   compatibility check prints only its summary lines.

Expected
- None of them in a line that mentions the mod or one of its files.

Result: ____

---

## After the session

- All PASS: the systems marked *IMPLEMENTED BUT REQUIRES IN-GAME
  VERIFICATION* in `docs/AMMUNITION_ROADMAP.md` move to confirmed, and the
  list in `docs/DEVELOPMENT.md` (*Real-game validation*) is updated with
  what was seen.
- A FAIL in sections 18 to 20 costs nothing in a normal game: those
  features are off unless switched on.
- Multiplayer is not part of this session: with the sandbox option
  *Multiplayer: the server performs sampling, assays, the analyzer and
  mining* off (the default), every authoritative action is refused on a
  multiplayer client by design (`docs/MULTIPLAYER_DESIGN.md`).

### Multiplayer server authority (a separate session, optional)

Only after the single-player session has passed sections 4 to 9. Needs a
**dedicated server** with *Ammo Making* and two clients (A and B) on it.
Write PASS or FAIL after each step; a FAIL needs the server's and the
client's `console.txt` around it. None of this has been run.

Steps
1. Server sandbox options: tick *Multiplayer: the server performs
   sampling, assays, the analyzer and mining (experimental)*. Start the
   server. Server console: `[AmmoMaking] Server authority installed`.
   Client A joins; its console: `[AmmoMaking] Server authority: this
   client asks the server`. ____
2. A, shovel equipped, on outdoor grass: *Dig Geological Sample*. The
   action runs; A gets one *Geological Sample* and the halo *Geological
   sample collected*. Save and rejoin: the sample is still there. ____
3. A, with a field assay kit: *Analyze with Field Assay Kit* on the
   sample. Halo *Sample analyzed*; *View Assay Result* shows grades; the
   kit's name shows one use less; the skill panel shows the XP. ____
4. A, pickaxe equipped, beside the sampled tile: *Mine ... Ore*. One ore
   on the ground (B sees it too), the halo with the XP. B, with a sample
   of the same tile, mines it until *deposit exhausted*: A's menu then
   shows the tile exhausted without A mining it. ____
5. A places a *Laboratory Assay Analyzer* (powered room). B sees it.
   A starts a lab assay; B's *Check Laboratory Progress* shows it
   processing. Wait the 24 in-game hours (the debug tools act on a
   client's own copy and prove nothing here). A and B click *Collect
   Laboratory Sample* at the same moment:
   exactly one of them gets the sample and the XP, the other is told
   *Laboratory analyzer is empty*. ____
6. A starts and cancels an assay: the sample comes back. A picks the
   analyzer up: it disappears for B, and A holds the item. ____
7. Untick the option on the server and restart it: on A every one of
   those options is shown disabled, with the *not available in
   multiplayer yet* reason. ____

Expected
- No `[AmmoMaking] ERROR` and no Lua stack trace on either side; on the
  server, refusals only as `[AmmoMaking] Server refused ...` lines for
  what was really refused.
- Nothing is created twice: one sample per dig, one ore per extraction,
  one result per assay, one XP grant per action.

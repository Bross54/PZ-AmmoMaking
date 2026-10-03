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
1. Enable only **Ammo Making**. Start a new sandbox world.

Expected
- The world loads; no error box (the red counter at the bottom right stays
  at 0).
- The skill panel shows **Ammo Making** at level 0.

Console
- One `... loaded` line per module (`Calibre definitions loaded (9)`,
  `Compatibility check loaded`, `Spent cases loaded`,
  `Quality tracking loaded`, `Debug tools loaded`, ...).
- `[AmmoMaking] Die set loot: 22 entries added, ...` and
  `[AmmoMaking] Component loot: ... entries added, ...` with
  `lists missing: none` (or an empty list after the colon).
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
- Four feature lines, all off:
  `feature Reloading Press: off (off)`, `feature Spent Cases: off (off)`,
  `feature Ammunition Quality Tracking: off (off)`,
  `feature Ammunition Quality Firing Effects: off (locked)`.
- One line per calibre class (`.../... complete`).
- `OK: die set loot (...)` and `OK: component loot (...)`.

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

Expected
- Each recipe is listed at its furnace with its name, not a raw id.
- The crucible, tongs and mold are kept; inputs are consumed; one craft
  logs one XP line.
- Zinc scrap and zinc ingot have a name and an icon (placeholders: the
  aluminium scrap and silver ingot icons).

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

Expected
- One round per assembly craft; the die set is kept; powder is taken by
  uses.
- The round is vanilla's 9mm round: it stacks with factory rounds, loads
  into vanilla magazines and fires exactly like one.
- The inspection window opens and shows a case quality; in `-debug` three
  `[debug]` lines follow.
- A recipe above your level is shown but locked.

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

Expected
- The wad material is consumed; one shell per craft; the shell is
  vanilla's and behaves as one (pellets, boxes, bandolier).

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

Expected
- Die sets, and now and then a primer box or gunpowder, in gun stores;
  brass scrap or a small brass sheet in metalwork crates. Rare: several
  containers may be needed.
- No cases, bullets or finished handloads anywhere.

Console (section 1): the two loot lines.

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
5. Set the option to 0 and to 100 in two short tries.

Expected
- `feature Spent Cases: ON (on)`; console
  `[AmmoMaking] Spent cases installed (shot true, rack true, reload true;
  50 % found, placed on the ground)`.
- About half the shots leave a **Spent ... Case** on the shooter's tile:
  at the shot for self-loaders, at the rack for pump, bolt and lever
  guns, at the reload for revolvers and break-actions. Never more cases
  than shots.
- Spent cases cannot be reloaded; they only scrap, at a lower return than
  unused brass, with no XP.
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
- Multiplayer is not part of this session: every authoritative action is
  refused on a multiplayer client by design
  (`docs/MULTIPLAYER_DESIGN.md`).

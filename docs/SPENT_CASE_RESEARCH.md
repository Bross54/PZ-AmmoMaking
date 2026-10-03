# Spent cases: research, design and implementation

Status: **IMPLEMENTED AS AN EXPERIMENTAL ADD-ON, NOT YET SEEN IN GAME.**
The add-on mod `AmmoMakingSpentCases` carries nine spent-case items and
their scrapping recipes; `AC_SpentCases.lua` in the main mod is the logic.
Nothing of it exists in a game without the add-on (feature `spentCases`,
`AC_Features.lua`), in multiplayer, or beside another mod that leaves
casings. Sections 1 to 3 are the research the implementation rests on;
section 4 is the economy and the policy that was chosen (4.2); section 7
is what was built.

Facts were read on 2026-10-02 from the installed game and are marked
**FILE** (a vanilla Lua or script file, path under `media/`), **JAR**
(`javap` of `projectzomboid.jar`), or **INFERRED**. Line numbers are those of
42.20.4.

## 1. How a shot consumes a round

All firearm Lua is in `lua/shared/TimedActions/` (`ISReloadWeaponAction`,
`ISRackFirearm`, `ISInsertMagazine`, `ISEjectMagazine`,
`ISLoadBulletsInMagazine`, `ISUnloadBulletsFromMagazine`,
`ISUnloadBulletsFromFirearm`).

### 1.1 The shot

FILE `ISReloadWeaponAction.lua:470-528`, `ISReloadWeaponAction.onShoot(player,
weapon)`, registered at `:542` with `Events.OnWeaponSwingHitPoint.Add`:

```lua
if not weapon:isRanged() then return; end
if getDebug() and player:isUnlimitedAmmo() then return; end
if weapon:haveChamber() then
    weapon:setRoundChambered(false);
    weapon:setSpentRoundChambered(true)
end
if not weapon:isRackAfterShoot() then
    if not weapon:isManuallyRemoveSpentRounds() then
        weapon:setSpentRoundChambered(false)
        if weapon:getShellFallSound() then
            player:getEmitter():playSound(weapon:getShellFallSound())
        end
    end
    if weapon:getCurrentAmmoCount() >= weapon:getAmmoPerShoot() then
        if weapon:haveChamber() then weapon:setRoundChambered(true); end
        if not isClient() then
            weapon:setCurrentAmmoCount(weapon:getCurrentAmmoCount() - weapon:getAmmoPerShoot())
        end
        if (weapon:getJamGunChance() > 0) then weapon:checkJam(player, false) end
    end
end
if weapon:isManuallyRemoveSpentRounds() then
    weapon:setSpentRoundCount(weapon:getSpentRoundCount() + weapon:getAmmoPerShoot())
end
syncHandWeaponFields(player, weapon)
```

- **The round count is decremented in Lua, in this event handler**, for
  guns that feed themselves. JAR `SwipeStatePlayer.OnAnimEvent_
  AttackCollisionCheck`: the only Java-side decrement is for items tagged
  `FAKE_WEAPON`.
- For `RackAfterShoot` guns nothing is decremented at the shot. FILE
  `ISRackFirearm.lua:62-64` (`rackBullet`): the count goes down when the
  action is racked, and that rack is queued by
  `ISReloadWeaponAction.OnPlayerAttackFinished` (`:530-538`).
- INFERRED: rounds in a chambered gun are `getCurrentAmmoCount()` plus one
  if `isRoundChambered()`.

### 1.2 Events around a shot

| Event | Arguments | Fired from | Once per shot? | Melee too? | Dry fire or jam? |
|---|---|---|---|---|---|
| `Hook.Attack` | character, charge, weapon | JAR `IsoLivingCharacter.AttemptAttack` | per attempt | yes | **yes** (`attackHook` `:452-455` plays the empty click) |
| `OnWeaponSwing` | player, weapon | JAR `SwipeStatePlayer.enter` | per swing | yes | INFERRED yes |
| **`OnWeaponSwingHitPoint`** | character, weapon | JAR `CombatManager.attackCollisionCheck` (local player) and JAR `network.fields.hit.Player.attack` (server, aimed firearms, once per shot id) | **yes: it is where vanilla itself takes the round** | yes (hence the `isRanged()` test) | **no**: FILE `AnimSets/player/ranged/firearm/FirearmEmpty.xml` has no `AttackCollisionCheck` event, `FirearmDefault.xml:77` has |
| `OnPlayerAttackFinished` | character, weapon | JAR `SwipeStatePlayer.exit`, only after a collision check | yes | yes | no |
| `OnWeaponHitCharacter` | wielder, target, weapon, damage | JAR `IsoGameCharacter.Hit` | per character hit | yes | never on a miss |

Vanilla Lua listens to these in four places only
(`ISReloadWeaponAction.lua:540-544`, `XpUpdate.lua:385`,
`DamageModelDefinitions.lua:69`, the tutorial).

### 1.3 Spent rounds in vanilla

JAR `HandWeapon`: `getSpentRoundCount` / `setSpentRoundCount` (clamped to
`0..getMaxAmmo()`), `isSpentRoundChambered` / `setSpentRoundChambered`,
`isRoundChambered`, `haveChamber`, `isRackAfterShoot`,
`isManuallyRemoveSpentRounds` (read from the script, no setter),
`isInsertAllBulletsReload`, `getShellFallSound`, `isContainsClip`.

- **They are not saved.** JAR `HandWeapon.save` / `load` write
  `containsClip`, `roundChambered` and `isJammed`; `spentRoundCount` and
  `spentRoundChambered` are touched only by their accessors and reset on
  load. They are networked (JAR `SyncHandWeaponFieldsPacket`).
- **The spent state is cleared in one place**: `ejectSpentRounds()`, with
  the same body in FILE `ISRackFirearm.lua:89-102` and
  `ISReloadWeaponAction.lua:271-284`: if `getSpentRoundCount() > 0` set it to
  0, else if a spent round is chambered clear that, then play the
  shell-fall sound. Called from the two actions' `start()` and
  `serverStart()`. This is the only moment at which "N spent cases leave
  the gun" can be observed, and observing it means wrapping those two
  functions.
- **There is no spent-case item and no ejection hook.** FILE: no item in
  the scripts is a casing, hull or spent shell; the only brass items are
  `BrassIngot`, `BrassScrap`, `Needle_Brass` and `BrassNameplate`. JAR: no
  class or string for a casing or a shell-eject effect. Ejection is a
  **sound**, played from Lua at three places (`ISReloadWeaponAction.lua:505`,
  `:281`, `ISRackFirearm.lua:99`) and, JAR `HandWeapon.checkUnJam`, after a
  cleared jam.

### 1.4 The firearms, by how they eject

FILE `scripts/generated/items/weapon.txt` (`–` = key absent: `haveChamber`
defaults to true, the others to false, JAR `Item.<init>`).

| Firearm | AmmoType | Magazine | MaxAmmo | RackAfterShoot | ManuallyRemoveSpentRounds | HaveChamber |
|---|---|---|---|---|---|---|
| Pistol | 9mm | `9mmClip` | 15 | – | – | – |
| Pistol2 | .45 | `45Clip` | 7 | – | – | – |
| Pistol3 | .44 | `44Clip` | 8 | – | – | – |
| AssaultRifle | 5.56 | `556Clip` | 30 | – | – | – |
| AssaultRifle2 | .308 | `M14Clip` | 20 | – | – | – |
| JS14_Rifle | 5.56 | `JS14_Clip` | 20 | – | – | – |
| TrapperCarbine | .45 | `45Clip` | 7 | – | – | – |
| Revolver | .357 | none | 6 | – | **true** | false |
| Revolver_Long | .44 | none | 6 | – | **true** | false |
| Revolver_Short | .38 | none | 5 | – | **true** | false |
| DoubleBarrelShotgun (and sawn-off) | 12 gauge | none | 2 | false | – | false |
| Shotgun, ShotgunSawnoff, JS3T_Shotgun | 12 gauge | none | 5 / 5 / 7 | **true** | – | – |
| HuntingRifle, MSR7T_Rifle | .308 | none | 4 | **true** | – | – |
| VarmintRifle | 5.56 | none | 5 | **true** | – | – |
| L92_Carbine | .357 | none | 10 | **true** | – | – |
| L94_Rifle | .30-30 | none | 6 | **true** | – | – |

Four behaviours follow from `onShoot`:

| Class | At the shot | The case leaves the gun |
|---|---|---|
| **Self-loading** (pistols, magazine rifles) | spent round chambered and cleared in the same call, shell-fall sound, count − 1 | at the shot |
| **Revolver** | count − 1, `spentRoundCount` + 1, no sound | when the cylinder is opened: `ejectSpentRounds()` at the start of a reload or a rack, all N at once |
| **Double barrel** | no chamber, not manual: shell-fall sound and count − 1 at the shot; `spentRoundCount` stays 0 | at the shot, as far as vanilla is concerned (it does not model breaking the gun open) |
| **Pump, bolt, lever** | spent round stays chambered | at the rack vanilla queues after the shot (`ejectSpentRounds()`), one case |

### 1.5 Client and server

- FILE `ISReloadWeaponAction.lua:514-516`: the count is only decremented
  where `not isClient()`: single player and the server.
- JAR: on a server `OnWeaponSwingHitPoint` is triggered from
  `PlayerHit.attack` for aimed firearms, once per shot id. The rest of
  `onShoot` also runs on the shooter's client.
- JAR `syncHandWeaponFields`: server to owning client only; it carries the
  ammo count, chamber and spent state, and the weapon's ModData.

### 1.6 The matrix: what happens when, by firearm class

Everything a hook would have to follow, in one place. "Count" is
`getCurrentAmmoCount()`; **"live rounds" is the count plus one when
`isRoundChambered()`**, which is what the gun actually holds. FILE and JAR
as above.

| | Self-loading pistol or rifle (magazine) | Revolver | Double barrel | Pump, bolt, lever |
|---|---|---|---|---|
| Rounds live in | a magazine item out of the gun; the gun's count, plus one chambered | the gun's count | the gun's count | the gun's count, plus one chambered |
| Loading | `ISLoadBulletsInMagazine` (round into magazine), `ISInsertMagazine` (magazine item destroyed, count copied) | `ISReloadWeaponAction:loadAmmo`, one round per animation event, or all at once (`isInsertAllBulletsReload`) | the same | the same |
| Chambering (`ISRackFirearm:rackBullet`, `:47-80`) | count − 1, chamber set: live rounds unchanged | no chamber | no chamber | the same as a self-loader, after each shot |
| Racking a gun that has a live round chambered | that round is handed back as a **new item** (`removeBullet`), then the next is chambered: live rounds − 1 | a round is handed back and count − 1 | the same | as a self-loader |
| At the shot (`OnWeaponSwingHitPoint`, vanilla's `onShoot`) | chamber emptied and refilled from the count, count − 1, shell-fall sound | count − 1, spent count + 1, no sound | count − 1, shell-fall sound | chamber emptied and marked spent; count unchanged |
| **Live rounds fall by one** | **at the shot** | **at the shot** | **at the shot** | **at the shot** (the count itself only falls at the rack that follows, queued by `OnPlayerAttackFinished`) |
| The case leaves the gun | at the shot | when the cylinder is opened (`ejectSpentRounds` at the start of a reload or rack): all at once | at the shot, as far as vanilla models it | at that rack (`ejectSpentRounds`) |
| Unloading | `ISEjectMagazine` (new magazine item, count copied), `ISUnloadBulletsFromMagazine`; `ISRackFirearm:removeBullet` for the chambered round | `ISUnloadBulletsFromFirearm` | the same | the same, and `removeBullet` |
| Spent state survives a save | – | **no** (`spentRoundCount` is not saved) | – | **no** (`spentRoundChambered` is not saved) |
| Tally step (`AMMO_QUALITY_RUNTIME_DESIGN.md` 8) | `addHandloaded` per round into the magazine, `merge` at insert, `transfer` at eject, `consume` per shot, `unload` of one at a rack-out | `addHandloaded`, `consume`, `unload` | the same | the same as a revolver, and `unload` of one at a rack-out |

Two things follow for any hook, tally or spent case:

- **A listener on `OnWeaponSwingHitPoint` runs after vanilla's `onShoot`.**
  JAR `zombie.Lua.Event#trigger` walks its callbacks in an `ArrayList`, in
  the order they were added; vanilla's shared Lua registers `onShoot` when
  `ISReloadWeaponAction.lua` loads, before any mod file (INFERRED from the
  loading order of vanilla and mod Lua, not re-read here). So a mod
  listener sees the gun **after** vanilla has taken the round.
- **Live rounds are the thing to follow, not the event and not the bare
  count.** `getCurrentAmmoCount()` alone misleads for a chambered gun: it
  falls when a round moves into the chamber, not when one is fired, so a
  pump gun's count is unchanged at the shot and falls at the rack. Count
  plus chamber falls by exactly one at the shot for every class. A hook
  that compares the live rounds it last recorded with the live rounds it
  sees needs no knowledge of the firearm class at all. That is what
  `AC_QualityTally` is built around (its record carries the number of
  rounds it describes), and it is why the same code serves a revolver and
  a pump gun. The firearm class only matters for **where the spent case
  appears**, which is the table above.
- **A racked-out live round is an unload, not a shot**: vanilla makes a new
  round item (`removeBullet`). A hook that only watches live rounds sees
  one round fewer and nothing else; unless `removeBullet` itself is
  wrapped, that round leaves as a factory round and the record follows by
  `reconcile` (doubt resolves toward factory).

## 2. Design options

One fired round yields at most one case, whatever the gun: the options
differ in **when** and **where** it appears, and in what has to be touched.

| | A. Case on a successful shot | B. Tally on the gun, recover later | C. Only at an unload or eject interaction | D. Nothing until a weapon layer exists |
|---|---|---|---|---|
| Hook | `Events.OnWeaponSwingHitPoint.Add`, purely additive | the same event to count, plus a recovery action of the mod's own | wrap `ISRackFirearm.ejectSpentRounds` and `ISReloadWeaponAction.ejectSpentRounds` | none |
| Vanilla code replaced | none | none | two functions wrapped (call the original, read the state first) | none |
| Count per round | one per event; the event is where vanilla takes the round | one per event | exactly what vanilla says left the gun | – |
| Survives save | the case is an item | tally in weapon ModData persists | vanilla's spent count does **not** persist: cases in a revolver at save time are lost (a loss, never a gain) | – |
| Where the case goes | ground at the shooter, or the inventory | nowhere until recovered | the shooter's inventory (they are in the hand) | – |
| Feels right for | self-loaders, double barrel | nothing: a gun does not keep its brass | revolvers; pump, bolt and lever at the rack | – |
| Cost | a world item per shot unless thinned; hundreds after a fight | a new timed action and menu entry | depends on two vanilla function bodies staying as they are | none |

By firearm class:

| Class | Fits | Why |
|---|---|---|
| Self-loading pistols and rifles | A | the case is thrown clear at the shot; there is no later moment |
| Revolvers | C | the cases stay in the cylinder until it is opened, and vanilla already counts them; A would hand out cases while they are still in the gun |
| Double barrel | A | vanilla treats it as ejecting at the shot; C has no spent count to read |
| Pump, bolt, lever | A or C | one case per shot either way; C puts it at the rack, where the sound is |

**No single model fits every firearm.** The honest design is a small
dispatcher: at `OnWeaponSwingHitPoint`, a self-loader or a double barrel
yields a case at once; a revolver yields nothing then, and its N cases come
out when the cylinder is opened; the rack-after-shot guns can use either.

## 3. What a spent case would be

Designed, not defined in any script:

| Question | Design |
|---|---|
| Item | one per calibre, `AmmoMaking.SpentCase<suffix>` (and `SpentHull12Gauge`), listed in the calibre model as `calibre.spentCase` so no other file names a calibre |
| Brass content | the case's own (`cupUnits * cupsPerCase`); the fired primer cup is discarded, so a spent case holds no more brass than went into the case |
| Back into use | a resizing recipe at the calibre's die set: several spent cases in, fewer cases out (split necks), no XP or the forming XP only; the loss keeps reloading from being free |
| Recycling | joins the scrapping recipe of its brass size in `AC_Recycling`, which already groups by content |
| Quality | a resized case gets a fresh quality roll, a little lower: there is nothing to carry over, because the round in the gun was a count |

## 4. Why it was first left unimplemented, and what changed

(Kept as written in the second pass, because the reasons are why the
feature is an add-on that is off by default. The decision that followed is
in 4.2.)

The pass's rule was to implement only if the hook is source-verified, the
duplication risk is low, no invasive override is needed and the behaviour
can be tested offline. Measured against it:

| Condition | Finding |
|---|---|
| Hook verified in the files | **Yes** for A: `OnWeaponSwingHitPoint` is the event vanilla's own `onShoot` uses to take the round, it does not fire on a dry fire, and `Events.….Add` replaces nothing |
| Duplication risk low | **Not established.** How often the event fires per trigger pull in automatic fire, the listener order against vanilla's handler, and what makes a server fire it for a shot that hits nothing could not be determined from the files |
| No invasive override | Yes for A; **no** for the revolver's correct behaviour (C wraps two vanilla functions) |
| Testable offline | The dispatcher's logic, yes; that a case appears once per shot in the running game, no |

And two things that are not engineering questions:

1. **It changes the economy more than anything added so far.** Every
   vanilla round fired would leave brass. A looted carton of 9mm (600
   rounds) is thirty ingots' worth of cases; mining and smelting would stop
   being the way to brass for anyone with a stock of factory ammunition.
   Whether factory rounds leave reusable cases, whether all are recovered or
   a share, and what resizing costs are decisions for the project owner.
   Section 4.1 puts numbers on five answers and recommends one.
2. **World items.** A case on the ground per shot is hundreds of world
   objects after a fight. Thinning (a recovery chance), or putting cases in
   the inventory, are both gameplay choices.

### 4.1 The economy of each policy, in numbers

Five ways to answer "does a fired round leave reusable brass", each with
what it would do to the brass economy. The parameters are those of the
calculation (`tests/render_balance.lua`, `SPENT_POLICIES`), chosen to show
the range; none is a value of the mod.

| | Policy | Parameters used below |
|---|---|---|
| **A** | Every fired round leaves a clean case | all cases recovered; scrap returns half; one spent case resizes into one case |
| **B** | Factory cases exist but are poor scrap and cannot be reloaded | factory: scrap returns a quarter, no resizing. Handloaded: three cases from four |
| **C** | Only rounds the player made leave a case | factory: nothing. Handloaded: three cases from four, scrap a quarter |
| **D** | Every round leaves a case; half are lost, the rest are dirty | half recovered; three from four resize; scrap a quarter |
| **E** | No spent cases | the mod as it is |

<!-- SPENT CASE POLICY TABLE: generated by tests/write_recipes.lua from the calibre model. Do not edit. -->

Looted factory ammunition as a source of brass, per hundred rounds fired:

| Policy | 100 looted 9mm: cases, ingots if scrapped, ingots' worth if reloaded | 100 looted .308: cases, ingots if scrapped, ingots' worth if reloaded | 100 looted 12 Gauge: cases, ingots if scrapped, ingots' worth if reloaded |
|---|---|---|---|
| **A**: every fired round leaves a clean case | 100, 2.5, 5 | 100, 7.5, 15 | 100, 7.5, 15 |
| **B**: factory cases are poor scrap and cannot be reloaded | 100, 1.3, 0 | 100, 3.8, 0 | 100, 3.8, 0 |
| **C**: only handloaded rounds leave a case | 0, 0, 0 | 0, 0, 0 | 0, 0, 0 |
| **D**: every round leaves a case; half are lost, the rest are dirty | 50, 0.6, 1.9 | 50, 1.9, 5.6 | 50, 1.9, 5.6 |
| **E**: no spent cases | 0, 0, 0 | 0, 0, 0 | 0, 0, 0 |
| **F**: **implemented (add-on)**: every round leaves a case, half are found, scrap only at a quarter | 50, 0.6, 0 | 50, 1.9, 0 | 50, 1.9, 0 |

The player's own rounds, fired and reloaded: what the next hundred cost:

| Policy | the next 100 9mm: cases back, brass ingots still needed (of), ore (of) | the next 100 .308: cases back, brass ingots still needed (of), ore (of) | the next 100 12 Gauge: cases back, brass ingots still needed (of), ore (of) |
|---|---|---|---|
| **A** | 100, 1 (6), 6 (11) | 100, 2 (17), 12 (27) | 100, 2 (17), 12 (27) |
| **B** | 75, 2.3 (6), 7.3 (11) | 75, 5.8 (17), 15.8 (27) | 75, 5.8 (17), 15.8 (27) |
| **C** | 75, 2.3 (6), 7.3 (11) | 75, 5.8 (17), 15.8 (27) | 75, 5.8 (17), 15.8 (27) |
| **D** | 37.5, 4.1 (6), 9.1 (11) | 37.5, 11.4 (17), 21.4 (27) | 37.5, 11.4 (17), 21.4 (27) |
| **E** | 0, 6 (6), 11 (11) | 0, 17 (17), 27 (27) | 0, 17 (17), 27 (27) |
| **F** | 0, 6 (6), 11 (11) | 0, 17 (17), 27 (27) | 0, 17 (17), 27 (27) |

<!-- END SPENT CASE POLICY TABLE -->

Reading it:

- **A makes looted ammunition a brass mine.** A hundred looted .308 fired
  are fifteen ingots' worth of ready cases: more than half of what a
  hundred new .308 need in ore (15 of 27), for no mining, smelting, forging
  or punching. A 50-round box of 9mm is two and a half ingots of cases. Ore,
  the furnace and the forge stop mattering for anyone with a stock of
  factory ammunition, and all three are what the mod is built on.
- **B closes the reloading shortcut and leaves a trickle**: looted rounds
  give scrap only, 1.3 to 3.8 ingots per hundred. That is still brass from
  nothing, on the scale of one or two ore per hundred shots, with a world
  item per shot to pick up.
- **C gives looted ammunition no value at all** and makes the player's own
  brass last: with three cases in four coming back, the next hundred 9mm
  cost 2.3 ingots instead of 6, the next hundred .308 5.8 instead of 17.
  No brass enters the world that was not mined.
- **D** is A at about three eighths strength for looted rounds (half are
  found, three in four of those resize), and a weaker loop for the
  player's own.
- **E** is today.

**C needs to know which rounds are handloaded, and vanilla does not keep
that**: a loaded round is a count (`AMMO_QUALITY_RUNTIME_DESIGN.md` 1).
The quality tally is exactly that knowledge. `AC_QualityTally.consume`
answers, for each shot, "a handloaded round" or "a factory round", without
a random number, and counts exactly as many handloaded shots as handloaded
rounds were loaded. So C is not infeasible, as an earlier version of this
document assumed; it is **blocked on the tally being wired to the
firearms**, which is the in-game-verified step of that design.

A round that has lost its record (boxed, or loaded by a path the tally did
not see) counts as a factory round and leaves nothing. That is the tally's
rule everywhere: doubt resolves toward factory.

**Recommendation, for the project owner to decide:**

1. **E until the tally is wired and seen to stay in step in game.**
2. **Then C**, with a loss at resizing (three from four is the figure
   used here) and a low scrap recovery for spent brass. It is the only
   policy under which brass still has to be mined, and it rewards exactly
   the thing the mod is about: the player's own ammunition.
3. **Not A, at any setting.** B and D differ from it in degree, not in
   kind: any policy that turns factory ammunition into brass competes with
   the mine.

Under C the conservation rule is simple and testable offline: a spent case
holds no more brass than the case that was formed, at most one comes back
per handloaded round fired, and resizing loses some. No loop creates brass.
`AC_Recycling` already takes a second source of brass with its own recovery
as data, and refuses one that returns more than unused components do
(`getSources()`; the suite builds an invented spent source through it).

### 4.2 The policy that was implemented (row F)

The project owner's direction for the third pass: all spent brass may
exist; it recycles at a lower efficiency than unused components; no XP;
no rule that depends on where a round came from, since that does not
survive loading; and firing factory ammunition must not beat mining.

That is neither A (clean, reloadable cases) nor C (handloads only, which
needs the tally wired). It is row **F** of the table above, the one row
that is computed from the mod's own numbers:

| | Value | Where |
|---|---|---|
| Which rounds leave a case | all, factory and handloaded alike | `AC_SpentCases` asks only for the firearm's calibre |
| How many are found | 50 of 100 | `AC_SpentCases.CONFIG.recoveryPercent` |
| What a spent case is | an item of its own, `calibre.spentCase`; **not** a case | `AC_Calibres.define` |
| Loading it again | impossible: no recipe takes it but scrapping | tested: no main, press or assembly recipe names one |
| Scrap recovery | a quarter (40 units in, 1 brass scrap out) | `AC_Recycling.SPENT` |
| XP | none | `AC_Recycling.CONFIG.xp`, shared with clean scrapping |

Half found times a quarter recovered is **one eighth** of a fired case's
brass. A hundred looted 9mm are 0.6 of an ingot, a hundred .308 or shells
1.9. An ore is an ingot: mining a tile beats emptying two boxes of
ammunition into a wall, and the brass of a hundred new rounds is six to
seventeen ingots. Looted ammunition is a trickle, not a mine.

The player's own rounds come back at the same eighth. From any stock of
cases the rounds that can ever be made are bounded by 1 / (1 - 0.25) even
if every case were found, and the suite walks that cycle to exhaustion for
every calibre.

A resizing recipe (spent case back to a loadable case) is deliberately
absent. It would need to know handloads from factory rounds to stay
honest, which is the quality tally's job; it is listed as an optional
future feature.

## 5. The order that was proposed (done except point 4's in-game check)

1. Decide the economy (section 4, point 1) and the recovery rule.
2. Add `calibre.spentCase`, the items, the resizing recipe and the
   recycling group. All of it is covered by the existing model tests,
   conservation checks and generators, with no firearm code.
3. Add the dispatcher on `OnWeaponSwingHitPoint`, guarded by `not
   isClient()`, behind a switch that is off by default, and verify the
   per-shot count in game for one self-loader, one revolver, one pump gun
   and automatic fire.
4. Only then decide whether the revolver deserves the two wrapped
   functions, or a simpler "cases at the shot" rule.

## 6. REQUIRES FUTURE IN-GAME VERIFICATION

- How many times `OnWeaponSwingHitPoint` fires per round in automatic fire.
- That a mod listener on it runs after vanilla's `onShoot` (section 1.6:
  the callback order is read from the jar, the load order is inferred).
- Whether the event reaches the server for a shot that hits nothing.
- Whether `serverStart()` of the reload and rack actions ever runs in single
  player (it decides where a wrapped `ejectSpentRounds` would be called).
- That a revolver's `getSpentRoundCount()` still holds N at the start of
  `ejectSpentRounds()`.

## 7. What is implemented

`AC_SpentCases.lua` (main mod), the add-on `mod/AmmoMakingSpentCases`
(generated items, recipes and names), the source `spent` of
`AC_Recycling`.

| Firearm family | Decided by | When the case is left | How |
|---|---|---|---|
| Self-loading pistols and rifles | neither flag set | at the shot | listener on `OnWeaponSwingHitPoint` |
| Double barrel | neither flag set (no chamber) | at the shot | the same listener |
| Revolvers | `ManuallyRemoveSpentRounds` | when the cylinder is opened, all at once | wrapped `ejectSpentRounds` (reload and rack actions) |
| Pump, bolt and lever guns | `RackAfterShoot` | at the rack that follows the shot | the same wrapper |

No firearm is named: the two script flags vanilla's own `onShoot`
branches on are the adapters. The wrapper reads the spent count, calls
vanilla's function with exactly what it was given, and only then leaves
the cases; its own two steps are `pcall`-guarded and vanilla's is not, so
a failure of the mod cannot break a reload. The cases are created with
the item factory and placed with `IsoGridSquare:AddWorldInventoryItem`,
the two calls mining uses to drop ore (that path has been seen in game),
or put in the inventory (`CONFIG.placement`).

Tested offline against a model of vanilla's seven reload functions
(`tests/firearm_model.lua`, written from the installed 42.20.4 Lua): for
every family one case per round fired and never more, at the moment the
table says; nothing for a dry fire, a melee swing, a racked-out live
round, unlimited debug ammunition or a calibre the mod does not make;
1,600 random actions per family and seed, including a save that loses
vanilla's spent state. The model is the mod's reading of vanilla, not
vanilla.

An installed Workshop mod (Hot Brass, `docs/REFERENCE_IMPLEMENTATIONS.md`)
wraps the same two functions the same way, which is a clue that the
pattern works in Build 42, not proof for this mod. With that mod active
the feature stands down: both would leave a casing.

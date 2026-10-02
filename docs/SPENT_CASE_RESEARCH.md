# Spent cases: research and design

Status: **RESEARCH AND DESIGN ONLY. No spent-case item, hook or recipe
exists.** This document records how Build 42.20.4 fires a firearm, where a
spent case could be recovered, and why nothing was implemented in this
pass.

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

## 4. Why nothing was implemented

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
2. **World items.** A case on the ground per shot is hundreds of world
   objects after a fight. Thinning (a recovery chance), or putting cases in
   the inventory, are both gameplay choices.

So the hook stays unwritten and the items undefined. Defining nine spent-case
items that nothing produces and nothing consumes would add dead data to the
item list and the translation file without bringing the feature closer; the
table in section 3 is what a future pass needs.

## 5. Proposed order for a future pass

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
- Whether a mod listener on it runs before or after vanilla's `onShoot`.
- Whether the event reaches the server for a shot that hits nothing.
- Whether `serverStart()` of the reload and rack actions ever runs in single
  player (it decides where a wrapped `ejectSpentRounds` would be called).
- That a revolver's `getSpentRoundCount()` still holds N at the start of
  `ejectSpentRounds()`.

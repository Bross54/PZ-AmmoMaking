# Ammunition quality at run time: where it could live

Status: **DESIGN ONLY. Nothing here is implemented, and no combat effect
exists or is proposed for this stage.** No misfire, jam or damage change is
part of the mod.

Today a handloaded round carries its casing quality in the loose item's
ModData (`AC_CaseQuality`). The record is lost the moment vanilla turns the
round into a count: at loading and at boxing (`LOOT_AND_RECYCLING.md` 3.1).
This document compares the places a quality could live so that, one day, it
can reach the shot.

Vanilla facts are marked **FILE**, **JAR** or **INFERRED** and were read
from the installed Build 42.20.4. They are set out in full in
`SPENT_CASE_RESEARCH.md`, section 1.

## 1. What vanilla keeps, and where it throws things away

| Fact | Evidence |
|---|---|
| An item's ammunition state is `ammoType`, `maxAmmo`, `currentAmmoCount`. A firearm adds `containsClip`, `roundChambered`, `isJammed` (saved) and the spent state (not saved) | JAR `InventoryItem`, `HandWeapon.save` / `load` |
| An item's ModData is saved, for firearms and magazines alike | JAR `InventoryItem.save`: the table is written when non-empty; `HandWeapon.save` calls it |
| Items never merge: a container holds individual objects; the inventory pane only groups rows by display name | JAR `InventoryItem.CanStack` returns false, `ItemContainer.AddItem`; FILE `ISInventoryPane.lua:2090-2134` |
| Loading a round **removes the round item** and adds one to a counter | FILE `ISLoadBulletsInMagazine.lua:128-131` (`RemoveOneOf(itemKey, true)`), `ISReloadWeaponAction.lua:239-244` |
| Which round is taken is not chosen by ModData | FILE `getSomeType(itemKey, count)`, `RemoveOneOf(itemKey, true)` |
| Unloading **creates new round items** | FILE `ISUnloadBulletsFromMagazine.lua:114-118`, `ISUnloadBulletsFromFirearm.lua:74-85`, `ISRackFirearm.lua:82-87` (`instanceItem(itemKey)`) |
| **Inserting a magazine destroys the magazine item**; the gun keeps a boolean and the count | FILE `ISInsertMagazine.lua:44-48` |
| **Ejecting creates a new magazine item** and copies the count onto it | FILE `ISEjectMagazine.lua:33-42` (`instanceItem(self.gun:getMagazineType())`) |
| On a server, weapon ModData reaches the owning client with every `syncHandWeaponFields`; magazine ModData travels with `syncItemFields` | JAR `SyncHandWeaponFieldsPacket`, `SyncItemFieldsPacket` |
| All of these state changes run where `not isClient()` | FILE, each action |

Two consequences shape everything below:

- **A magazine is not one object through its life.** ModData written on a
  magazine item is gone when the magazine is inserted, and the magazine
  that comes out is a different item. Anything on a magazine has to be
  copied to the gun on insert and back on eject, by the mod.
- **Nothing vanilla moves ModData between round, magazine and gun.** Any
  carrier means wrapping the seven functions where rounds change place.

The touch points:

| Function | What moves | Needed by |
|---|---|---|
| `ISLoadBulletsInMagazine:animEvent` (`:128`) | round → magazine | magazine guns |
| `ISUnloadBulletsFromMagazine:animEvent` (`:113`) | magazine → round | magazine guns |
| `ISInsertMagazine:loadAmmo` (`:42`) | magazine → gun | magazine guns |
| `ISEjectMagazine:unloadAmmo` (`:31`) | gun → magazine | magazine guns |
| `ISReloadWeaponAction:loadAmmo` (`:235`) | round → gun | revolvers, shotguns, tube and internal-magazine rifles |
| `ISUnloadBulletsFromFirearm:animEvent` (`:74`) | gun → round | the same |
| `ISRackFirearm:removeBullet` (`:82`) | chamber → round | every gun that can be racked |
| `Events.OnWeaponSwingHitPoint` | a round is fired | all; additive, no wrap |

## 2. The candidate carriers

### A. ModData on the magazine

The per-magazine record: what the rounds in it are.

- Save: yes. Reload: only if copied to the gun at insert and back at
  eject.
- Fails alone: revolvers, shotguns and internal-magazine rifles have no
  magazine item at all (thirteen of the twenty vanilla firearms).

### B. ModData on the weapon

The per-gun record of what is loaded, chamber included.

- Save: yes. Server to client: carried by vanilla's own sync.
- Works for every firearm. For a magazine gun it is the record while the
  magazine is in, and has to be handed to the magazine item on eject.

### C. A parallel queue, one entry per round

An ordered list beside the count (`{ 82, 82, 71, "factory", … }`), on the
magazine or the weapon; the shot reads the entry on top.

- Exact: each round keeps its own quality through load, fire and unload.
- Needs every touch point to push or pop in step with vanilla's count, in
  the right order (a magazine is last in, first out; a revolver cylinder
  and a tube are not obviously either).
- One missed path, by a vanilla change or another mod's reload action, and
  the list and the count disagree. It then needs a repair rule anyway, and
  the repair rule is option D.
- A partial unload must decide which entries leave.

### D. An aggregate per container

Two numbers beside the count: how many of the loaded rounds are handloaded
and the sum of their qualities (`{ n = 9, q = 702 }`). Factory rounds are
the rest of the count, at a fixed nominal quality.

- Loading a handloaded round: `n + 1`, `q + quality`. A factory round:
  nothing.
- A shot, an unload or a rack-out removes one round "of the mix": the
  share `n / count` says whether it was a handloaded one, and it leaves
  with the mean `q / n`.
- Order does not exist, so no path can get it wrong. If the count and the
  tally ever disagree, clamp `n` to the count and scale `q`: the record
  degrades toward "factory", it never invents quality.
- Loses the individual round: one fine round among poor ones is averaged.

### E. State derived at load time

Nothing stored per round: when a magazine or gun is loaded, a single figure
is fixed (say the mean quality at that moment) and every shot until the
next load uses it, with a deterministic draw from a counter in the same
ModData.

- Cheapest to keep right; it is D with the tally frozen between loads.
- Wrong after a partial unload or a top-up unless recomputed, which makes
  it D again.

## 3. Comparison

| | A. Magazine ModData | B. Weapon ModData | C. Queue per round | D. Aggregate | E. Derived at load |
|---|---|---|---|---|---|
| Survives save and load | yes | yes | yes (a list in ModData) | yes | yes |
| Survives insert and eject | only with a copy in both directions | is the gun's own | only with a copy of the whole list | only with a copy of two numbers | only with a copy |
| Reload (loose rounds) | – | wrap one function | push per round, in order | add per round | recompute |
| Partial magazine unload | n/a | n/a | must choose which entries | remove at the mean | stale |
| Mixing factory and handloaded | – | – | exact | exact in number, averaged in quality | averaged |
| Covers guns without a magazine | **no** | yes | on the weapon | on the weapon | on the weapon |
| Multiplayer later | `syncItemFields` | `syncHandWeaponFields` already carries it | the same, but a list per sync | two numbers per sync | one number |
| Vanilla functions wrapped | 4 | 3 | 7 | 7 | 7 |
| Breaks when a path is missed | record lost | record lost | **list and count diverge** | clamps toward factory | stale until next load |
| Duplication risk | none (no item) | none | a repair that pads the list could invent good rounds | none: the clamp only removes | none |
| Complexity | low, incomplete | low, incomplete | high | moderate | low, weak |

A and B are **places**; C, D and E are **shapes**. The real choice is a
shape, stored on B while the rounds are in a gun and on A while they are in
a loose magazine.

By firearm class:

| Class | Where the record sits | Touch points |
|---|---|---|
| Magazine-fed (7 guns) | the magazine item while it is out, the weapon while it is in; copied at insert and eject. The chambered round belongs to the weapon | all seven |
| Revolvers (3) | the weapon | loose-round reload, unload from firearm, the shot |
| Shotguns and internal-magazine rifles (10) | the weapon | the same three, and the rack (`removeBullet`) for pump, bolt and lever |

## 4. Recommendation

**An aggregate tally (D), kept on the weapon while rounds are in a gun and
on the magazine item while they are in a loose magazine.**

```text
item ModData, key "AmmoMakingLoad" (weapon or magazine)
  v   schema version
  n   handloaded rounds among the loaded ones    0 .. count
  q   sum of their casing qualities              0 .. n * 100
factory rounds = count - n, at a fixed nominal quality
```

Why this one:

- **It cannot be wrong in a way that helps the player.** Every repair
  moves the record toward "factory". A queue that has lost step has to be
  padded or cut, and both are guesses.
- **It is the same code for every firearm.** A revolver and a magazine
  rifle differ only in which item holds the two numbers.
- **It is small enough to verify offline.** The tally is pure arithmetic
  (`load`, `takeOne`, `moveAll`, `reconcile`), testable exactly as
  `AC_CaseQuality` is today, before any vanilla function is wrapped.
- **It fits what the mod records.** The only quality that exists is one
  number per case; there is nothing per round worth an ordered list.
- **Multiplayer has a path.** Two numbers ride on packets vanilla already
  sends, and every change happens where vanilla's own change happens
  (`not isClient()`).

What it gives up: a single fine round is averaged with the rest of the
magazine. If per-shot identity ever matters, the queue can be added on top
with the aggregate as its repair rule.

Rules a future implementation must keep:

1. `0 <= n <= count` and `0 <= q <= n * 100` after every operation; a
   record that breaks them is clamped, never trusted (the save-data rules
   of `DEVELOPMENT.md`).
2. The tally is written only where vanilla writes the count, and only
   after vanilla's own change has happened.
3. Unloading hands back round items whose casing quality is the mean, and
   only for the handloaded share; the rest are plain factory rounds.
4. A wrapped vanilla function calls the original first and never changes
   its arguments or result. If the original's shape is not what was
   expected, the wrapper does nothing and the game-start check says so.
5. No effect on firing is attached until the tally has been seen to stay
   in step in game, across save and load, for one gun of each class.

## 5. What an effect would build on, later

Not designed here, recorded so the carrier is not chosen in the dark:
vanilla already has a jam mechanic (JAR `HandWeapon.checkJam`: a chance from
the script's `JamGunChance`, the sandbox multiplier, condition and skill;
`isJammed` is saved and networked; `ISRackFirearm` clears it). A quality
effect would most plausibly raise that chance for a low mean quality, at the
shot, rather than add a mechanic of its own. That is a later stage and a
gameplay decision.

## 6. REQUIRES FUTURE IN-GAME VERIFICATION

- That ModData written on a firearm survives save and load and reaches the
  client on a server, as the bytecode says.
- That the seven functions can be wrapped by table-field replacement from a
  mod (they are plain fields of global tables in shared Lua).
- The order in which a magazine, a revolver and a tube hand rounds back, if
  a queue is ever wanted.
- That no vanilla path changes `currentAmmoCount` outside the functions
  listed in section 1.

# Multiplayer mining: minimal server-authoritative design

Status: **design only, not implemented.** Mining is intentionally disabled on
multiplayer clients (`AC_Mining.isAvailable()` returns false when `isClient()`),
because the current loop runs entirely on the machine that executes the timed
action: it spawns the ore locally and records depletion in that client's global
ModData, which is neither authoritative nor shared. Two players would each get
the full reserve; a reconnecting player would see every tile as untouched.

Single-player and local split-screen are unaffected.

## Why the current split already helps

`AC_Mining.extract()` is the only function that changes world state in the
mining loop, and it takes plain inputs (player, square, metal, tool). The menus
and the timed action only call it. Making mining server-authoritative means
moving that one call to the server and replacing the local call with a request.

## Client

Unchanged responsibilities:

- context menu: offer "Mine … Ore" using the client's own view of inventory
  (assayed sample carried, pickaxe equipped) and the client's terrain check
- local UI: halo messages, tooltips, job progress on the pickaxe
- timed action: animation, sound, `isValid()` as a cheap early-out

New responsibility, in `AC_MineOreAction:perform()` when `isClient()`:

- send a request instead of calling `extract()`:
  `sendClientCommand(player, "AmmoMaking", "mine", { x = , y = , z = , metal = , pickaxeId = })`
- do nothing else. No ore, no XP, no wear, no ModData write on the client.

## Server

`OnClientCommand("AmmoMaking", "mine", player, args)` in a `server/` file:

1. **Validate** using server-side state only:
   - the player exists and is within reach of `(x, y, z)`
   - the square is mineable (`AC_Geology.isSurveyableSquare`)
   - the pickaxe with `pickaxeId` is in the player's inventory, is an accepted
     type and is usable
   - a covering assayed sample is in the player's inventory
     (`AC_Mining.findProspect` already takes a player and a square)
2. **Calculate the true reserve** from geology and the server's global ModData
   (`AC_Deposits.getRemaining`). The server's ModData is the only copy that
   counts; the geology seed must be derived from the server's world name so
   every machine computes the same reserves.
3. **Atomically decrement.** Check remaining, then record the extraction, in the
   same Lua call. Lua on the server is single-threaded, so a handler that reads
   and writes without yielding cannot be interleaved with another request.
4. **Spawn / award the ore** on the server (`square:AddWorldInventoryItem` on
   the server-side square, which the engine replicates to clients), or add it to
   the player's inventory through the server inventory API.
5. **Apply XP and wear** server-side where the engine supports it, or send the
   amounts back for the client to apply (XP is normally client-authoritative in
   Project Zomboid; wear on an item in the player's inventory needs the item
   synced back).
6. **Synchronise the result:**
   - `ModData.transmit(AC_Deposits.CONFIG.modDataKey)` so clients see the new
     depletion for their menus (or a targeted `sendServerCommand` with the
     tile's new state)
   - `sendServerCommand(player, "AmmoMaking", "mineResult", { ok = , error = , remaining = })`
     so the client can show the halo message it shows today.

`AC_Mining.extract()` can stay almost as it is and simply run on the server; the
guard `isAvailable()` becomes "not a client".

## Two requests for the last unit

Player A and player B both have one unit left on the same tile and both finish
their action in the same tick.

- Both clients send `mine`. The server receives them in some order.
- Handler for A: remaining = 1 → record extraction → remaining = 0 → spawn ore →
  reply ok.
- Handler for B: remaining = 0 → reply `no_ore`, mark worked (already is).

This is correct only because step 3 does the check and the write inside one
uninterrupted handler. The rules that keep it correct:

- never move the "remaining" check to the client (the client's copy can be stale)
- never `yield`, wait or defer between the check and the write
- never decrement on the client "optimistically" and reconcile later
- the reply carries the server's `remaining`, not the client's guess

## Client-side state after the change

The client's own global ModData copy is only a cache for the context menu
(known-exhausted labels). It is refreshed by `ModData.transmit` from the server
and must never be written by mining code on a client.

## Out of scope for the first implementation

- anti-cheat beyond "the server validates every field"
- ore in the requester's inventory instead of on the ground
- rate limiting (a request per completed timed action is already slow)

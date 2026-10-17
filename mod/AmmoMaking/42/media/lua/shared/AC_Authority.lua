-- Ammo Making - multiplayer server authority
-- Project Zomboid Build 42.20
--
-- Single player is not touched by this file. Every function
-- that changes something here returns at once unless the
-- machine is a multiplayer SERVER with the feature
-- "serverAuthority" switched on (AC_Features, a sandbox
-- option, experimental, off by default). The single-player
-- code of sampling, assays, the analyzer and mining runs
-- exactly as before (tests/suite_authority.lua replays it
-- against frozen copies of the files as they were seen
-- working in game).
--
-- The rule (docs/MULTIPLAYER_DESIGN.md): the machine that
-- decides is the machine that changes the state, and that
-- machine is the server. A client asks, shows the answer,
-- and never writes.
--
-- Two ways of asking, both vanilla Build 42:
--
--   timed actions   dig a sample, mine ore, pick up the
--                   analyzer. A Lua timed action that has a
--                   complete() is sent to the server by the
--                   engine (JAR LuaTimedActionNew.<init>:
--                   useCustomRemoteTimedActionSync is false
--                   when the class has "complete"; start()
--                   then calls ActionManager
--                   .createNetTimedAction). The server
--                   rebuilds the action with Type.new(...)
--                   from the action's fields named like the
--                   parameters of new() (JAR NetTimedAction
--                   .set / .parse), waits the action's own
--                   getDuration(), and calls complete() (JAR
--                   NetTimedAction.perform). It never calls
--                   isValid() there (NetTimedAction.isValid
--                   returns false and names no Lua function):
--                   complete() checks everything itself, in
--                   the server* functions below.
--   client commands the assays and the analyzer's start,
--                   cancel and collect, which are menu clicks
--                   with no timed action.
--                   sendClientCommand(player, module, command,
--                   args) arrives in OnClientCommand(module,
--                   command, player, args) on the server
--                   (JAR LuaManager.GlobalObject; FILE
--                   server/ClientCommands.lua).
--
-- Placing the analyzer goes through vanilla's ISBuildAction:
-- the server rebuilds the building object the same way
-- (JAR BuildAction.parse) and calls create() (FILE
-- shared/ActionManager.lua, Actions.build).
--
-- The server answers with sendServerCommand(player, module,
-- "result", reply), which arrives in OnServerCommand(module,
-- command, args) on that player's client (FILE
-- client/ServerCommands.lua). Items it adds, removes or
-- changes go to the client with the calls vanilla's own
-- complete() functions use: sendAddItemToContainer,
-- sendRemoveItemFromContainer, syncItemFields and
-- syncItemModData (FILE shared/TimedActions/*.lua). XP goes
-- through addXp(player, perk, amount), which on a server is
-- GameServer.addXp (JAR LuaManager.GlobalObject.addXp). The
-- depletion store is sent with ModData.transmit(key); a
-- client keeps it with ModData.add (JAR GlobalModDataPacket
-- only fires OnReceiveGlobalModData, it stores nothing).
--
-- REQUIRES FUTURE IN-GAME VERIFICATION (dedicated server and
-- client): all of it. The offline suite simulates a client
-- and a server in one Lua state with a mocked engine; it
-- proves the checks and the order of the calls, not that
-- the engine delivers them.

AC_Authority = AC_Authority or {}


AC_Authority.FEATURE = "serverAuthority"


AC_Authority.MODULE = "AmmoMaking"


AC_Authority.REPLY = "result"


AC_Authority.CONFIG = {

    ------------------------------------------------
    -- REACH
    ------------------------------------------------
    --
    -- How far, in tiles on each axis, the player may
    -- stand from the centre of the tile he works on.
    -- Vanilla's own pickaxe action allows 1.6
    -- (ISPickAxeGroundCoverItem:isValid); the mod's
    -- menus walk the player next to the tile first
    -- (luautils.walkAdj), so 2 leaves room for a
    -- diagonal neighbour and nothing more.
    ------------------------------------------------

    reach = 2,


    ------------------------------------------------
    -- RATE LIMIT
    ------------------------------------------------
    --
    -- One request of each kind per player and second.
    -- A legitimate dig or extraction takes several
    -- seconds; an assay or an analyzer click is one
    -- click. More than that is a flood and is dropped.
    ------------------------------------------------

    minIntervalMs = 1000,


    ------------------------------------------------
    -- COORDINATES
    ------------------------------------------------
    --
    -- Anything a request names is a whole number in
    -- this range, or the request is malformed.
    ------------------------------------------------

    maxCoordinate = 100000,

    minLevel = -32,

    maxLevel = 32,
}


------------------------------------------------
-- STATE (memory only, never saved)
------------------------------------------------

AC_Authority.lastRequestAt = AC_Authority.lastRequestAt or {}


AC_Authority.dropped = AC_Authority.dropped or 0


------------------------------------------------
-- WHO DECIDES
------------------------------------------------

function AC_Authority.isEnabled()

    return
        AC_Features.isEnabled(
            AC_Authority.FEATURE
        )
end


-- A multiplayer client that asks the server instead of
-- refusing. False in single player, always.
function AC_Authority.canRequest()

    if not isClient() then
        return false
    end


    return
        AC_Authority.isEnabled()
end


-- A multiplayer server that performs what clients ask.
-- False in single player, always.
function AC_Authority.decides()

    if not isServer() then
        return false
    end


    return
        AC_Authority.isEnabled()
end


------------------------------------------------
-- VALIDATION
------------------------------------------------

function AC_Authority.isWhole(
    value,
    minimum,
    maximum
)

    if type(value) ~= "number" then
        return false
    end


    ------------------------------------------------
    -- NaN, infinities and fractions are refused.
    ------------------------------------------------

    if value ~= value
        or value ~= math.floor(value)
    then
        return false
    end


    return
        value >= minimum
        and value <= maximum
end


-- The square a request names, or nil and why. Only
-- whole coordinates in range, and only a square the
-- server has loaded.
function AC_Authority.readSquare(
    args
)

    if type(args) ~= "table" then
        return nil, "bad_request"
    end


    local limit =
        AC_Authority.CONFIG.maxCoordinate


    if not AC_Authority.isWhole(args.x, 0, limit)
        or not AC_Authority.isWhole(args.y, 0, limit)
        or not AC_Authority.isWhole(
            args.z,
            AC_Authority.CONFIG.minLevel,
            AC_Authority.CONFIG.maxLevel
        )
    then
        return nil, "bad_request"
    end


    ------------------------------------------------
    -- As vanilla's own server commands look a square
    -- up (FILE server/ClientCommands.lua).
    ------------------------------------------------

    local square =
        getCell():getGridSquare(
            args.x,
            args.y,
            args.z
        )


    if not square then
        return nil, "no_square"
    end


    return square, nil
end


-- Whether the player stands within reach of the square:
-- same level, and at most CONFIG.reach tiles from its
-- centre on each axis. The server's own position of the
-- player counts, never anything the client says.
function AC_Authority.isWithinReach(
    player,
    square,
    limit
)

    if not player
        or not square
    then
        return false
    end


    limit =
        limit
        or AC_Authority.CONFIG.reach


    local x =
        tonumber(player:getX())


    local y =
        tonumber(player:getY())


    local z =
        tonumber(player:getZ())


    if not x
        or not y
        or not z
    then
        return false
    end


    if math.floor(z) ~= square:getZ() then
        return false
    end


    return
        math.abs(x - (square:getX() + 0.5)) <= limit
        and math.abs(y - (square:getY() + 0.5)) <= limit
end


-- An item of the player's own inventory (bags included)
-- by id, or nil. An id the client made up, or one of
-- another player's items, finds nothing.
function AC_Authority.findOwnItem(
    player,
    id
)

    if not player
        or not AC_Authority.isWhole(
            id,
            -2147483648,
            2147483647
        )
    then
        return nil
    end


    return
        player:getInventory():getItemWithIDRecursiv(
            id
        )
end


-- Whether this very item is in the player's inventory.
function AC_Authority.ownsItem(
    player,
    item
)

    if not player
        or not item
    then
        return false
    end


    return
        AC_Authority.findOwnItem(
            player,
            item:getID()
        )
        == item
end


-- Whether the item is in one of the player's hands.
function AC_Authority.holds(
    player,
    item
)

    return
        item ~= nil
        and (
            player:getPrimaryHandItem() == item
            or player:getSecondaryHandItem() == item
        )
end


------------------------------------------------
-- RATE LIMIT
------------------------------------------------

function AC_Authority.now()

    return
        getTimestampMs()
end


function AC_Authority.allow(
    player,
    kind,
    now
)

    local key =
        tostring(player:getOnlineID())
        .. "/"
        .. tostring(kind)


    local last =
        AC_Authority.lastRequestAt[key]


    ------------------------------------------------
    -- A clock that went backwards lets the request
    -- through rather than lock the player out.
    ------------------------------------------------

    if last
        and now >= last
        and now - last < AC_Authority.CONFIG.minIntervalMs
    then

        AC_Authority.dropped =
            AC_Authority.dropped + 1


        return false
    end


    AC_Authority.lastRequestAt[key] =
        now


    return true
end


------------------------------------------------
-- ANSWER
------------------------------------------------
--
-- Every answer is one table of plain values:
--
--   action    what was asked ("mine", "dig", "assay",
--             "pickUp", "labStart", "labCancel",
--             "labCollect")
--   ok        true or false
--   error     the refusal's code, when not ok
--   onlineID  whose answer it is (a client may have
--             split-screen players)
--
-- plus what the client shows (metal, remaining, xp ...).
------------------------------------------------

function AC_Authority.reply(
    player,
    action,
    answer
)

    answer.action =
        action


    answer.ok =
        answer.ok == true


    answer.onlineID =
        player:getOnlineID()


    sendServerCommand(
        player,
        AC_Authority.MODULE,
        AC_Authority.REPLY,
        answer
    )


    if not answer.ok then

        print(
            "[AmmoMaking] Server refused "
            .. tostring(action)
            .. " for "
            .. tostring(player:getUsername())
            .. ": "
            .. tostring(answer.error)
        )
    end


    return answer
end


local function refuse(
    player,
    action,
    errorCode
)

    return
        AC_Authority.reply(
            player,
            action,
            {
                ok = false,
                error = errorCode,
            }
        )
end


-- The checks every server operation starts with. Returns
-- nil when the request may go on, else the refusal
-- already sent.
local function gate(
    player,
    action
)

    if not player then
        return { ok = false, error = "no_player" }
    end


    if not AC_Authority.decides() then

        return
            refuse(
                player,
                action,
                "multiplayer_unsupported"
            )
    end


    if not AC_Authority.allow(
        player,
        action,
        AC_Authority.now()
    ) then

        return
            refuse(
                player,
                action,
                "rate_limited"
            )
    end


    return nil
end


-- After the server changed an item the client holds.
local function syncItem(
    player,
    item
)

    syncItemModData(
        player,
        item
    )


    syncItemFields(
        player,
        item
    )
end


------------------------------------------------
-- MINE (AC_MineOreAction:complete on the server)
------------------------------------------------

function AC_Authority.serverMine(
    player,
    square,
    metal,
    pickaxe
)

    local refused =
        gate(
            player,
            "mine"
        )


    if refused then
        return refused
    end


    ------------------------------------------------
    -- A metal other than the two is refused by
    -- extract() itself (invalid_metal), before it
    -- looks at anything else.
    ------------------------------------------------

    if not square then
        return refuse(player, "mine", "no_square")
    end


    if not AC_Authority.isWithinReach(
        player,
        square
    ) then
        return refuse(player, "mine", "too_far")
    end


    if not AC_Authority.ownsItem(player, pickaxe)
        or not AC_Authority.holds(player, pickaxe)
    then
        return refuse(player, "mine", "no_pickaxe")
    end


    ------------------------------------------------
    -- The extraction itself is the single-player
    -- function, unchanged: on a server isClient() is
    -- false, so it runs. It checks the prospect in
    -- the server's copy of the inventory, and reads
    -- and records the reserve in one call: two
    -- requests for the last unit cannot both get it.
    ------------------------------------------------

    local result,
          errorCode =
        AC_Mining.extract(
            player,
            square,
            metal,
            pickaxe
        )


    ------------------------------------------------
    -- Both outcomes may have written the depletion
    -- store (an extraction, or a tile found empty).
    ------------------------------------------------

    if result
        or errorCode == "no_ore"
    then

        ModData.transmit(
            AC_Deposits.CONFIG.modDataKey
        )
    end


    if not result then

        return
            AC_Authority.reply(
                player,
                "mine",
                {
                    ok = false,
                    error = errorCode,
                    metal = metal,
                }
            )
    end


    syncItem(
        player,
        pickaxe
    )


    return
        AC_Authority.reply(
            player,
            "mine",
            {
                ok = true,
                metal = metal,
                remaining = result.remaining,
                initial = result.initial,
                xp = result.xp,
            }
        )
end


------------------------------------------------
-- DIG (AC_DigGeologicalSampleAction:complete)
------------------------------------------------

function AC_Authority.serverDig(
    player,
    square,
    shovel
)

    local refused =
        gate(
            player,
            "dig"
        )


    if refused then
        return refused
    end


    if not square then
        return refuse(player, "dig", "no_square")
    end


    if not AC_Authority.isWithinReach(
        player,
        square
    ) then
        return refuse(player, "dig", "too_far")
    end


    if not AC_Authority.ownsItem(player, shovel)
        or not AC_GeologySampling.isShovel(shovel)
        or shovel:isBroken()
        or shovel:getCondition() <= 0
    then
        return refuse(player, "dig", "no_shovel")
    end


    local sample,
          errorCode =
        AC_GeologySampling.createSample(
            player,
            square,
            shovel
        )


    if not sample then
        return refuse(player, "dig", errorCode)
    end


    ------------------------------------------------
    -- The sample is complete (hidden geology in its
    -- ModData) before it is sent.
    ------------------------------------------------

    sendAddItemToContainer(
        player:getInventory(),
        sample
    )


    syncItem(
        player,
        shovel
    )


    return
        AC_Authority.reply(
            player,
            "dig",
            {
                ok = true,
            }
        )
end


------------------------------------------------
-- PICK UP THE ANALYZER (AC_PickUpAnalyzerAction)
------------------------------------------------

function AC_Authority.serverPickUp(
    player,
    analyzer
)

    local refused =
        gate(
            player,
            "pickUp"
        )


    if refused then
        return refused
    end


    if not AC_LaboratoryAnalyzer.isPlacedAnalyzerObject(
        analyzer
    ) then
        return refuse(player, "pickUp", "invalid_analyzer")
    end


    if not AC_Authority.isWithinReach(
        player,
        analyzer:getSquare()
    ) then
        return refuse(player, "pickUp", "too_far")
    end


    local item,
          errorCode =
        AC_PickUpAnalyzerAction.pickUp(
            player,
            analyzer
        )


    if not item then
        return refuse(player, "pickUp", errorCode)
    end


    sendAddItemToContainer(
        player:getInventory(),
        item
    )


    return
        AC_Authority.reply(
            player,
            "pickUp",
            {
                ok = true,
            }
        )
end


------------------------------------------------
-- PLACE THE ANALYZER (AC_LaboratoryAnalyzerObject)
------------------------------------------------
--
-- Not a request of its own: vanilla's build action
-- brings the building object to the server. This is
-- the server's extra check before create() builds:
-- the feature must be on and the player next to the
-- square. The item check is create()'s own.
------------------------------------------------

function AC_Authority.mayPlace(
    player,
    square
)

    if not AC_Authority.decides() then
        return false, "multiplayer_unsupported"
    end


    if not AC_Authority.isWithinReach(
        player,
        square
    ) then
        return false, "too_far"
    end


    return true, nil
end


------------------------------------------------
-- CLIENT COMMANDS (server side)
------------------------------------------------

local function findPlacedAnalyzer(
    player,
    args
)

    local square,
          errorCode =
        AC_Authority.readSquare(
            args
        )


    if not square then
        return nil, errorCode
    end


    if not AC_Authority.isWithinReach(
        player,
        square
    ) then
        return nil, "too_far"
    end


    ------------------------------------------------
    -- Placed analyzers only. One dropped on the floor
    -- (an item, from saves before the placed object
    -- existed) keeps its state in the item's ModData,
    -- which no packet here would carry: it stays a
    -- single-player thing.
    ------------------------------------------------

    local objects =
        square:getSpecialObjects()


    for index = 0,
        objects:size() - 1
    do

        local object =
            objects:get(
                index
            )


        if AC_LaboratoryAnalyzer.isPlacedAnalyzerObject(
            object
        ) then
            return object, nil
        end
    end


    return nil, "invalid_analyzer"
end


AC_Authority.COMMANDS = {}


AC_Authority.COMMANDS.assay = function(
    player,
    args
)

    local sample =
        AC_Authority.findOwnItem(
            player,
            args.sampleId
        )


    if not AC_GeologySampling.isSample(
        sample
    ) then
        return { ok = false, error = "invalid_sample" }
    end


    local kit =
        AC_Authority.findOwnItem(
            player,
            args.kitId
        )


    if AC_GeologySampling.getKitRank(kit) <= 0 then
        return { ok = false, error = "invalid_kit" }
    end


    local ok,
          errorCode =
        AC_GeologySampling.analyzeSample(
            sample,
            kit
        )


    if not ok then
        return { ok = false, error = errorCode }
    end


    ------------------------------------------------
    -- The same grant the single-player menu makes
    -- after a successful assay.
    ------------------------------------------------

    local xp =
        AC_GeologySampling.getAssayXP(
            kit
        )


    AmmoMakingSkill.addXP(
        player,
        xp
    )


    syncItem(
        player,
        sample
    )


    syncItem(
        player,
        kit
    )


    return {
        ok = true,
        xp = xp,
    }
end


AC_Authority.COMMANDS.labStart = function(
    player,
    args
)

    local analyzer,
          errorCode =
        findPlacedAnalyzer(
            player,
            args
        )


    if not analyzer then
        return { ok = false, error = errorCode }
    end


    local sample =
        AC_Authority.findOwnItem(
            player,
            args.sampleId
        )


    if not sample then
        return { ok = false, error = "invalid_sample" }
    end


    local container =
        sample:getContainer()


    local started,
          startError =
        AC_LaboratoryAnalyzer.startAssay(
            player,
            analyzer,
            sample
        )


    if not started then
        return { ok = false, error = startError }
    end


    sendRemoveItemFromContainer(
        container,
        sample
    )


    analyzer:transmitModData()


    return {
        ok = true,
        hours = AC_LaboratoryAnalyzer.CONFIG.processingHours,
    }
end


AC_Authority.COMMANDS.labCancel = function(
    player,
    args
)

    local analyzer,
          errorCode =
        findPlacedAnalyzer(
            player,
            args
        )


    if not analyzer then
        return { ok = false, error = errorCode }
    end


    local sample,
          cancelError =
        AC_LaboratoryAnalyzer.cancelAssay(
            player,
            analyzer
        )


    if not sample then
        return { ok = false, error = cancelError }
    end


    sendAddItemToContainer(
        player:getInventory(),
        sample
    )


    analyzer:transmitModData()


    return { ok = true }
end


AC_Authority.COMMANDS.labCollect = function(
    player,
    args
)

    local analyzer,
          errorCode =
        findPlacedAnalyzer(
            player,
            args
        )


    if not analyzer then
        return { ok = false, error = errorCode }
    end


    local sample,
          collectError =
        AC_LaboratoryAnalyzer.collectSample(
            player,
            analyzer
        )


    if not sample then
        return { ok = false, error = collectError }
    end


    sendAddItemToContainer(
        player:getInventory(),
        sample
    )


    analyzer:transmitModData()


    ------------------------------------------------
    -- The only laboratory XP, once, to the one who
    -- collected: the analyzer was emptied in the same
    -- call, so a second request finds it empty.
    ------------------------------------------------

    local xp =
        AmmoMakingSkill.awardXP(
            player,
            AC_LaboratoryAnalyzer.CONFIG.assayXP,
            "Laboratory"
        )


    return {
        ok = true,
        xp = xp,
    }
end


-- OnClientCommand(module, command, player, args), on the
-- server. Returns the answer it sent, or nil when the
-- request was not ours or was dropped.
function AC_Authority.onClientCommand(
    module,
    command,
    player,
    args
)

    if module ~= AC_Authority.MODULE then
        return nil
    end


    local handler =
        AC_Authority.COMMANDS[command]


    if not handler
        or not player
        or not AC_Authority.decides()
    then
        return nil
    end


    ------------------------------------------------
    -- A flood is dropped without an answer: answering
    -- it would only send the flood back.
    ------------------------------------------------

    if not AC_Authority.allow(
        player,
        command,
        AC_Authority.now()
    ) then
        return nil
    end


    if type(args) ~= "table" then
        return refuse(player, command, "bad_request")
    end


    local ran,
          answer =
        pcall(
            handler,
            player,
            args
        )


    if not ran then

        print(
            "[AmmoMaking] ERROR: server command "
            .. tostring(command)
            .. " failed: "
            .. tostring(answer)
        )


        answer = {
            ok = false,
            error = "server_error",
        }
    end


    return
        AC_Authority.reply(
            player,
            command,
            answer
        )
end


------------------------------------------------
-- ASKING (client side)
------------------------------------------------

function AC_Authority.request(
    player,
    command,
    args
)

    if not player
        or not AC_Authority.canRequest()
    then
        return false
    end


    sendClientCommand(
        player,
        AC_Authority.MODULE,
        command,
        args
    )


    return true
end


------------------------------------------------
-- INSTALL (server)
------------------------------------------------
--
-- Nothing is listened to unless this is a server with the
-- feature on. OnServerStarted fires once the dedicated
-- server has loaded its Lua (as for AC_SkillBooks).
-- REQUIRES FUTURE IN-GAME VERIFICATION: that the server's
-- sandbox options are in SandboxVars by then.
------------------------------------------------

function AC_Authority.installServer()

    if AC_Authority.serverInstalled then
        return true
    end


    if not AC_Authority.decides() then
        return nil
    end


    Events.OnClientCommand.Add(
        AC_Authority.onClientCommand
    )


    AC_Authority.serverInstalled =
        true


    print(
        "[AmmoMaking] Server authority installed (multiplayer requests are performed on the server)"
    )


    return true
end


Events.OnServerStarted.Add(
    AC_Authority.installServer
)


------------------------------------------------
-- LOAD MESSAGE
------------------------------------------------

print(
    "[AmmoMaking] Server authority loaded"
)

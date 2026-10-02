-- Ammo Making - Quality tally of loaded ammunition (pure)
-- Project Zomboid Build 42.20
--
-- STATUS: ARITHMETIC ONLY. Nothing in the mod calls this
-- file yet. No firearm, magazine or vanilla function is
-- touched, nothing is stored in a save and no event is
-- listened to. It is the part of the future quality
-- carrier (docs/AMMO_QUALITY_RUNTIME_DESIGN.md) that can
-- be proven without the game, written first so that the
-- part that cannot be proven offline - wrapping vanilla's
-- reload functions - has nothing left to get wrong but
-- the wiring.
--
-- THE PROBLEM. A handloaded round carries its casing
-- quality on the loose item. Loading turns the item into
-- a count (ISReloadWeaponAction, ISLoadBulletsInMagazine),
-- so a magazine or a firearm knows how many rounds it
-- holds and nothing about them.
--
-- THE RECORD. One small table beside that count:
--
--   version     layout of this record (CONFIG.version)
--   count       rounds the record describes
--   handloaded  how many of them are handloaded rounds
--               with a known quality
--   qualitySum  the sum of those rounds' qualities
--
-- Everything else is derived: factory = count -
-- handloaded, mean quality = qualitySum / handloaded.
-- A round whose origin is not known is a factory round.
--
-- There is no order. A tally cannot say WHICH round is
-- next, only what the mix is; rounds leave in proportion
-- to the mix (split), and a handloaded round that leaves
-- takes its share of the quality sum with it. See
-- docs/AMMO_QUALITY_RUNTIME_DESIGN.md, section 7, for why
-- this was chosen over a per-round queue and what it
-- means for a future effect.
--
-- RULES, all of them asserted by the tests:
--
--   0 <= handloaded <= count
--   handloaded * min <= qualitySum <= handloaded * max
--   every number is whole and finite
--   no function creates a round, a handloaded round or
--     quality: split + merge and transfer conserve all
--     three exactly, and the only way a sum grows is
--     addHandloaded()
--   whatever is passed in - nil, a word, NaN, a record
--     that contradicts itself - what comes out obeys the
--     rules above
--   doubt resolves toward FACTORY. A record that cannot
--     be trusted reads as "no handloaded rounds", never
--     as good ones. Damaged data cannot improve a load.
--
-- Every function returns new tables and changes none of
-- its arguments.

AC_QualityTally = AC_QualityTally or {}


------------------------------------------------
-- CONFIG
------------------------------------------------

AC_QualityTally.CONFIG = {

    -- Layout of the record. A record with a higher
    -- version was written by a later release: it is read
    -- as "nothing known" and reported as "newer", so the
    -- caller can leave it alone instead of overwriting
    -- what it does not understand.
    version = 1,

    -- No magazine, cylinder or tube holds this many
    -- (vanilla's largest is 30). A larger count is damage,
    -- and it keeps every product below far inside the
    -- range where a Lua number is exact.
    maxRounds = 10000,
}


-- Status of a record, as repair() and reconcile() report
-- it.
AC_QualityTally.OK = "ok"

AC_QualityTally.REPAIRED = "repaired"

AC_QualityTally.ADJUSTED = "adjusted"

AC_QualityTally.NEWER = "newer"


------------------------------------------------
-- Quality of one round: the range AC_CaseQuality rolls
-- and stores (1..100).
------------------------------------------------

local function qualityRange()

    local config =
        AC_CaseQuality.CONFIG


    return
        config.minQuality,
        config.maxQuality
end


local function isWhole(
    value
)

    return
        AC_SaveData.isFinite(value)
        and value == math.floor(value)
end


local function make(
    count,
    handloaded,
    qualitySum
)

    return {

        version = AC_QualityTally.CONFIG.version,

        count = count,

        handloaded = handloaded,

        qualitySum = qualitySum,
    }
end


-- A number of rounds asked for by a caller: whole, not
-- negative, at most limit. Anything unusable is 0.
local function roundsWanted(
    value,
    limit
)

    return
        AC_SaveData.whole(
            value,
            0,
            0,
            limit
        )
end


------------------------------------------------
-- EMPTY
------------------------------------------------
--
-- The record of count factory rounds (0 when left out).
------------------------------------------------

function AC_QualityTally.empty(
    count
)

    return
        make(
            roundsWanted(
                count,
                AC_QualityTally.CONFIG.maxRounds
            ),
            0,
            0
        )
end


------------------------------------------------
-- CHECK (read only)
------------------------------------------------
--
-- What is wrong with a record: a list of texts, empty
-- for a record that obeys every rule. Changes nothing.
------------------------------------------------

function AC_QualityTally.check(
    value
)

    if type(value) ~= "table" then
        return { "not a table" }
    end


    local problems = {}

    local config =
        AC_QualityTally.CONFIG

    local minimum,
          maximum =
        qualityRange()


    if value.version ~= config.version then
        table.insert(problems, "version is not " .. config.version)
    end


    for _,
        key
    in ipairs(
        { "count", "handloaded", "qualitySum" }
    )
    do

        if not isWhole(value[key])
            or value[key] < 0
        then
            table.insert(problems, key .. " is not a whole number of 0 or more")
        end
    end


    if #problems > 0 then
        return problems
    end


    if value.count > config.maxRounds then
        table.insert(problems, "count is above " .. config.maxRounds)
    end


    if value.handloaded > value.count then
        table.insert(problems, "more handloaded rounds than rounds")
    end


    if value.qualitySum < value.handloaded * minimum
        or value.qualitySum > value.handloaded * maximum
    then
        table.insert(problems, "qualitySum is outside what the handloaded rounds can hold")
    end


    return problems
end


------------------------------------------------
-- REPAIR
------------------------------------------------
--
-- Any value -> a record that obeys the rules, and how it
-- got there:
--
--   "ok"        it was sound; the result is a copy
--   "repaired"  something was wrong; see below
--   "newer"     a later release's layout: the result is
--               an empty record, and the caller should
--               not write it over the stored one
--
-- What counts as damage, and what it becomes:
--
--   not a table                  no rounds
--   count unusable               0 (and so no handloaded)
--   count above the limit        the limit
--   version missing or unusable  all factory
--   handloaded or qualitySum not a whole number of 0 or
--     more, more handloaded than rounds, or a quality sum
--     the handloaded rounds cannot hold
--                                all factory
--
-- "All factory" keeps the count and forgets the rest. It
-- never guesses: a quality sum of 900 on five rounds is
-- not clamped to 500, because a record that is wrong in
-- one field is not evidence for the others.
------------------------------------------------

function AC_QualityTally.repair(
    value
)

    local config =
        AC_QualityTally.CONFIG


    if type(value) ~= "table" then

        if value == nil then
            return AC_QualityTally.empty(0), AC_QualityTally.OK
        end


        return AC_QualityTally.empty(0), AC_QualityTally.REPAIRED
    end


    if isWhole(value.version)
        and value.version > config.version
    then
        return AC_QualityTally.empty(0), AC_QualityTally.NEWER
    end


    if #AC_QualityTally.check(value) == 0 then

        return
            make(
                value.count,
                value.handloaded,
                value.qualitySum
            ),
            AC_QualityTally.OK
    end


    local count = 0


    if type(value.count) == "number" then

        count =
            roundsWanted(
                value.count,
                config.maxRounds
            )
    end


    return
        make(
            count,
            0,
            0
        ),
        AC_QualityTally.REPAIRED
end


------------------------------------------------
-- RECONCILE
------------------------------------------------
--
-- The record brought into step with the count the game
-- itself holds. actualCount is the authority: vanilla
-- owns it, and any path the mod did not see (another
-- mod's reload action, a debug command) shows up as a
-- difference.
--
--   fewer rounds than recorded
--       rounds left that nobody told the tally about.
--       They leave in proportion to the mix, with the
--       handloaded share rounded DOWN, and the quality
--       sum shrinks with them, also rounded down.
--   more rounds than recorded
--       rounds arrived that nobody told the tally about.
--       They are factory rounds.
--
-- Status as for repair(), plus "adjusted" when a sound
-- record had to follow the count. An unusable
-- actualCount is 0 rounds.
------------------------------------------------

function AC_QualityTally.reconcile(
    value,
    actualCount
)

    local tally,
          status =
        AC_QualityTally.repair(value)


    if status == AC_QualityTally.NEWER then
        return tally, status
    end


    local actual =
        roundsWanted(
            actualCount,
            AC_QualityTally.CONFIG.maxRounds
        )


    if actual == tally.count then
        return tally, status
    end


    if status == AC_QualityTally.OK then
        status = AC_QualityTally.ADJUSTED
    end


    if actual > tally.count
        or tally.handloaded == 0
    then

        return
            make(
                actual,
                tally.handloaded,
                tally.qualitySum
            ),
            status
    end


    local handloaded =
        math.floor(tally.handloaded * actual / tally.count)

    local qualitySum =
        math.floor(tally.qualitySum * handloaded / tally.handloaded)


    return
        make(
            actual,
            handloaded,
            qualitySum
        ),
        status
end


------------------------------------------------
-- ADD
------------------------------------------------

-- rounds factory rounds are loaded (one when left out).
-- What does not fit below the limit is not counted.
function AC_QualityTally.addFactory(
    value,
    rounds
)

    local tally =
        AC_QualityTally.repair(value)


    if rounds == nil then
        rounds = 1
    end


    local added =
        roundsWanted(
            rounds,
            AC_QualityTally.CONFIG.maxRounds - tally.count
        )


    return
        make(
            tally.count + added,
            tally.handloaded,
            tally.qualitySum
        )
end


------------------------------------------------
-- One round is loaded. quality is what
-- AC_CaseQuality.getRoundQuality gave for the loose
-- item: a number, or nil for a factory round.
--
-- A quality that is not a finite number is no quality:
-- the round counts as a factory round. A finite one is
-- kept within the quality range and rounded DOWN to a
-- whole number.
------------------------------------------------

function AC_QualityTally.addHandloaded(
    value,
    quality
)

    local tally =
        AC_QualityTally.repair(value)


    if tally.count >= AC_QualityTally.CONFIG.maxRounds then
        return tally
    end


    if not AC_SaveData.isFinite(quality) then

        return
            make(
                tally.count + 1,
                tally.handloaded,
                tally.qualitySum
            )
    end


    local minimum,
          maximum =
        qualityRange()


    local whole =
        AC_SaveData.whole(
            quality,
            minimum,
            minimum,
            maximum
        )


    return
        make(
            tally.count + 1,
            tally.handloaded + 1,
            tally.qualitySum + whole
        )
end


------------------------------------------------
-- SPLIT
------------------------------------------------
--
-- rounds rounds leave the record: the record of what
-- left, and the record of what stayed. Together they
-- are exactly the record that was given: no round, no
-- handloaded round and no quality appears or is lost.
--
-- Which rounds leave: the mix, as evenly as whole rounds
-- allow. Of a magazine that is half handloaded, every
-- second round that leaves is a handloaded one. The
-- number that STAYS is the proportional share rounded to
-- the nearest whole round (a half rounds up, so on a tie
-- a factory round leaves first).
--
-- A handloaded round that leaves takes the mean quality
-- with it, rounded down; the rounding stays behind. No
-- individual round is remembered, so no selection is
-- possible: a player cannot unload "the good ones".
--
-- Asking for more rounds than there are takes them all.
------------------------------------------------

function AC_QualityTally.split(
    value,
    rounds
)

    local tally =
        AC_QualityTally.repair(value)


    local leaving =
        roundsWanted(
            rounds,
            tally.count
        )


    if leaving == 0 then
        return AC_QualityTally.empty(0), tally
    end


    local staying =
        tally.count - leaving


    local handloadedStaying =
        math.floor(
            (2 * tally.handloaded * staying + tally.count)
            / (2 * tally.count)
        )


    local handloadedLeaving =
        tally.handloaded - handloadedStaying


    local qualityLeaving = 0


    if handloadedLeaving > 0 then

        qualityLeaving =
            math.floor(tally.qualitySum * handloadedLeaving / tally.handloaded)
    end


    return
        make(
            leaving,
            handloadedLeaving,
            qualityLeaving
        ),
        make(
            staying,
            handloadedStaying,
            tally.qualitySum - qualityLeaving
        )
end


------------------------------------------------
-- MERGE
------------------------------------------------
--
-- Two records become one: a magazine goes into a gun
-- that has a round chambered, two part loads are
-- combined. What would exceed the limit is refused
-- whole: the result is then the first record alone and
-- the second return value is false.
------------------------------------------------

function AC_QualityTally.merge(
    first,
    second
)

    local a =
        AC_QualityTally.repair(first)

    local b =
        AC_QualityTally.repair(second)


    if a.count + b.count > AC_QualityTally.CONFIG.maxRounds then
        return a, false
    end


    return
        make(
            a.count + b.count,
            a.handloaded + b.handloaded,
            a.qualitySum + b.qualitySum
        ),
        true
end


------------------------------------------------
-- TRANSFER
------------------------------------------------
--
-- rounds rounds move from one record to another: a
-- magazine into a gun, a gun's magazine out again
-- leaving the chambered round behind. Returns the new
-- source and the new destination. Nothing is created or
-- lost between them; when the destination cannot take
-- the rounds, nothing moves.
------------------------------------------------

function AC_QualityTally.transfer(
    from,
    to,
    rounds
)

    local taken,
          rest =
        AC_QualityTally.split(
            from,
            rounds
        )


    local merged,
          fits =
        AC_QualityTally.merge(
            to,
            taken
        )


    if not fits then

        return
            AC_QualityTally.repair(from),
            merged
    end


    return rest, merged
end


------------------------------------------------
-- CONSUME
------------------------------------------------
--
-- One round is fired. Returns what stayed, and what the
-- round was:
--
--   { handloaded = true, quality = 82 }
--   { handloaded = false }
--   nil    there was no round
--
-- It is split() of one round: which kind leaves follows
-- the mix, with no random number, so a client and a
-- server that hold the same record agree on the answer.
------------------------------------------------

function AC_QualityTally.consume(
    value
)

    local taken,
          rest =
        AC_QualityTally.split(
            value,
            1
        )


    if taken.count == 0 then
        return rest, nil
    end


    if taken.handloaded == 0 then
        return rest, { handloaded = false }
    end


    return
        rest,
        {
            handloaded = true,
            quality = taken.qualitySum,
        }
end


------------------------------------------------
-- QUALITIES
------------------------------------------------
--
-- The handloaded rounds of a record as loose rounds: a
-- list of whole qualities, one per handloaded round,
-- that adds up to exactly the record's quality sum. They
-- differ by at most one (the mean, with the remainder
-- spread one point at a time).
------------------------------------------------

function AC_QualityTally.qualities(
    value
)

    local tally =
        AC_QualityTally.repair(value)

    local list = {}


    if tally.handloaded == 0 then
        return list
    end


    local base =
        math.floor(tally.qualitySum / tally.handloaded)

    local extra =
        tally.qualitySum - base * tally.handloaded


    for index = 1, tally.handloaded do

        if index <= extra then
            list[index] = base + 1
        else
            list[index] = base
        end
    end


    return list
end


------------------------------------------------
-- UNLOAD
------------------------------------------------
--
-- rounds rounds are taken out as loose items. Returns
-- what stayed, and what came out:
--
--   { factory = 3, qualities = { 71, 71, 70 } }
--
-- factory rounds are plain vanilla rounds; each entry of
-- qualities is a handloaded round to be given that
-- casing quality.
------------------------------------------------

function AC_QualityTally.unload(
    value,
    rounds
)

    local taken,
          rest =
        AC_QualityTally.split(
            value,
            rounds
        )


    return
        rest,
        {
            factory = taken.count - taken.handloaded,
            qualities = AC_QualityTally.qualities(taken),
        }
end


------------------------------------------------
-- DERIVED VALUES
------------------------------------------------

function AC_QualityTally.getFactory(
    value
)

    local tally =
        AC_QualityTally.repair(value)


    return
        tally.count - tally.handloaded
end


-- The mean quality of the handloaded rounds, or nil when
-- there are none.
function AC_QualityTally.getMeanQuality(
    value
)

    local tally =
        AC_QualityTally.repair(value)


    if tally.handloaded == 0 then
        return nil
    end


    return
        tally.qualitySum / tally.handloaded
end


-- The share of the rounds that is handloaded, 0..1; 0
-- for an empty record.
function AC_QualityTally.getHandloadedShare(
    value
)

    local tally =
        AC_QualityTally.repair(value)


    if tally.count == 0 then
        return 0
    end


    return
        tally.handloaded / tally.count
end


------------------------------------------------
-- LOAD MESSAGE
------------------------------------------------

print(
    "[AmmoMaking] Quality tally loaded (arithmetic only; nothing uses it yet)"
)

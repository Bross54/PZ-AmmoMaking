-- Ammo Making - Mine Ore timed action
-- Project Zomboid Build 42.20
--
-- Follows the same structure as
-- AC_DigGeologicalSampleAction. The actual extraction
-- is done by AC_Mining.extract().

require "TimedActions/ISBaseTimedAction"


AC_MineOreAction =
    ISBaseTimedAction:derive(
        "AC_MineOreAction"
    )


------------------------------------------------
-- SOUND CONFIG
------------------------------------------------

AC_MineOreAction.soundDelay = 6


------------------------------------------------
-- VALID
------------------------------------------------

function AC_MineOreAction:isValid()

    if not self.character
        or not self.square
        or not self.item
        or not self.metal
    then

        return false
    end


    if not AC_Mining.isMineableSquare(
        self.square
    ) then

        return false
    end


    if not AC_Mining.isUsablePickaxe(
        self.item
    ) then

        return false
    end


    ------------------------------------------------
    -- Pickaxe must still be in the player's hands.
    ------------------------------------------------

    if self.character:getPrimaryHandItem() ~= self.item
        and self.character:getSecondaryHandItem() ~= self.item
    then

        return false
    end


    if isClient()
        and not self.character:
            getInventory():
            containsID(
                self.item:getID()
            )
    then

        return false
    end


    ------------------------------------------------
    -- The assayed sample must still be carried.
    -- Dropping it mid-action cancels the action
    -- instead of wasting the full duration.
    ------------------------------------------------

    if not AC_Mining.findProspect(
        self.character,
        self.square,
        self.metal
    ) then

        return false
    end


    ------------------------------------------------
    -- Queued repeat attempts on a tile that is
    -- already known to be exhausted are dropped.
    ------------------------------------------------

    if AC_Deposits.isKnownExhausted(
        self.square:getX(),
        self.square:getY(),
        self.metal
    ) then

        return false
    end


    return true
end


------------------------------------------------
-- WAIT TO START
------------------------------------------------

function AC_MineOreAction:waitToStart()

    self.character:faceLocation(
        self.square:getX() + 0.5,
        self.square:getY() + 0.5
    )


    return
        self.character:isTurning()
        or self.character:shouldBeTurning()
end


------------------------------------------------
-- UPDATE
------------------------------------------------

function AC_MineOreAction:update()

    self.character:faceLocation(
        self.square:getX() + 0.5,
        self.square:getY() + 0.5
    )


    self.character:setMetabolicTarget(
        Metabolics.DiggingSpade
    )


    if self.item then

        self.item:setJobDelta(
            self:getJobDelta()
        )
    end


    ------------------------------------------------
    -- Vanilla-style muscle strain.
    ------------------------------------------------

    local strength =
        self.character:getPerkLevel(
            Perks.Strength
        )


    local strain =
        (
            1
            - (strength * 0.05)
        )
        / 10
        * getGameTime():getMultiplier()


    if self.item then

        self.character:addCombatMuscleStrain(
            self.item,
            1,
            strain
        )
    end


    ------------------------------------------------
    -- WORK SOUND
    --
    -- Same retry pattern as the sample digging
    -- action / vanilla ISBuildAction.
    ------------------------------------------------

    if self.soundTime
            + AC_MineOreAction.soundDelay
        < getTimestamp()
    then

        self.soundTime =
            getTimestamp()


        local emitter =
            self.character:getEmitter()


        if emitter then

            local playing =
                self.workSound ~= 0
                and emitter:isPlaying(
                    self.workSound
                )


            if not playing then

                self.workSound =
                    emitter:playSound(
                        AC_Mining.CONFIG.sound
                    )
            end
        end


        ------------------------------------------------
        -- Zombies can hear mining.
        ------------------------------------------------

        addSound(
            self.character,
            self.character:getX(),
            self.character:getY(),
            self.character:getZ(),
            AC_Mining.CONFIG.soundRadius,
            AC_Mining.CONFIG.soundRadius
        )
    end
end


------------------------------------------------
-- START
------------------------------------------------

function AC_MineOreAction:start()

    ------------------------------------------------
    -- Resolve item again for multiplayer.
    ------------------------------------------------

    if isClient()
        and self.item
    then

        self.item =
            self.character:
                getInventory():
                getItemById(
                    self.item:getID()
                )
    end


    if self.item then

        self.item:setJobType(
            "Mining "
            .. AC_Deposits.getMetalName(
                self.metal
            )
            .. " Ore"
        )


        self.item:setJobDelta(
            0.0
        )
    end


    ------------------------------------------------
    -- Placeholder animation: the vanilla shovel
    -- digging animation selector, which is already
    -- used by the sample digging action.
    ------------------------------------------------

    local animation = nil


    if BuildingHelper
        and BuildingHelper.getShovelAnim
    then

        ------------------------------------------------
        -- The vanilla selector is written for shovels;
        -- guard it so a pickaxe can never raise a Lua
        -- error inside the timed action.
        ------------------------------------------------

        local ok,
              result =
            pcall(
                BuildingHelper.getShovelAnim,
                self.item
            )


        if ok
            and type(result) == "string"
        then

            animation =
                result
        end
    end


    self:setActionAnim(
        animation
        or "DigShovel"
    )


    self:setOverrideHandModels(
        self.item,
        nil
    )


    self.workSound =
        0


    self.soundTime =
        0


    print(
        "[AmmoMaking] Started mining "
        .. tostring(self.metal)
        .. " at "
        .. tostring(self.square:getX())
        .. ", "
        .. tostring(self.square:getY())
        .. "; duration "
        .. tostring(self.maxTime)
    )
end


------------------------------------------------
-- STOP SOUND
------------------------------------------------

function AC_MineOreAction:stopSound()

    if not self.workSound
        or self.workSound == 0
    then

        return
    end


    local emitter =
        self.character:getEmitter()


    if emitter
        and emitter:isPlaying(
            self.workSound
        )
    then

        emitter:stopSound(
            self.workSound
        )
    end


    self.workSound =
        0
end


------------------------------------------------
-- STOP
------------------------------------------------

function AC_MineOreAction:stop()

    self:stopSound()


    if self.item then

        self.item:setJobDelta(
            0.0
        )
    end


    ISBaseTimedAction.stop(
        self
    )
end


------------------------------------------------
-- RESULT FEEDBACK
------------------------------------------------

local function showResult(
    character,
    metal,
    result,
    errorCode
)

    local metalName =
        AC_Deposits.getMetalName(
            metal
        )


    if result then

        local text =
            metalName
            .. " ore extracted"


        if result.remaining <= 0 then

            text =
                text
                .. " - the deposit is exhausted"

        elseif result.remaining
            <= AC_Mining.CONFIG.thinningThreshold
        then

            text =
                text
                .. " - the vein is thinning out"
        end


        HaloTextHelper.addText(
            character,
            text
        )


        return
    end


    if errorCode == "no_ore" then

        HaloTextHelper.addText(
            character,
            "No workable "
            .. string.lower(metalName)
            .. " ore here"
        )

    elseif errorCode == "no_prospect" then

        HaloTextHelper.addText(
            character,
            "You need an assayed sample of this site"
        )

    elseif errorCode == "no_pickaxe" then

        HaloTextHelper.addText(
            character,
            "Your pickaxe is not usable"
        )

    elseif errorCode == "multiplayer_unsupported" then

        HaloTextHelper.addText(
            character,
            "Ore extraction is not available in multiplayer yet"
        )

    else

        HaloTextHelper.addText(
            character,
            "Could not extract ore"
        )
    end
end


------------------------------------------------
-- PERFORM
------------------------------------------------

function AC_MineOreAction:perform()

    if self.item then

        local container =
            self.item:getContainer()


        if container then

            container:setDrawDirty(
                true
            )
        end


        self.item:setJobDelta(
            0.0
        )
    end


    self:stopSound()


    local result,
          errorCode =
        AC_Mining.extract(
            self.character,
            self.square,
            self.metal,
            self.item
        )


    showResult(
        self.character,
        self.metal,
        result,
        errorCode
    )


    if not result then

        print(
            "[AmmoMaking] Mining failed: "
            .. tostring(errorCode)
        )
    end


    ISBaseTimedAction.perform(
        self
    )
end


------------------------------------------------
-- DURATION
------------------------------------------------

function AC_MineOreAction:getDuration()

    if self.character:isTimedActionInstant() then

        return 1
    end


    return
        AC_Mining.getActionTime(
            self.character
        )
end


------------------------------------------------
-- CONSTRUCTOR
------------------------------------------------

function AC_MineOreAction:new(
    character,
    square,
    metal,
    pickaxe
)

    local o =
        ISBaseTimedAction.new(
            self,
            character
        )


    o.character =
        character


    o.square =
        square


    o.metal =
        metal


    o.item =
        pickaxe


    o.workSound =
        0


    o.soundTime =
        0


    o.stopOnWalk =
        true


    o.stopOnRun =
        true


    o.stopOnAim =
        true


    o.maxTime =
        o:getDuration()


    o.caloriesModifier =
        5


    return o
end


------------------------------------------------
-- LOAD MESSAGE
------------------------------------------------

print(
    "[AmmoMaking] Mine ore timed action loaded"
)

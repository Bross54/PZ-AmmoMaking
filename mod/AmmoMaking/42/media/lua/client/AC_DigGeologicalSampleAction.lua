-- Ammo Making - Dig Geological Sample timed action
-- Project Zomboid Build 42.20
--
-- Uses the same shovel animation and sound behavior
-- as vanilla grave digging / ISBuildAction.

require "TimedActions/ISBaseTimedAction"


AC_DigGeologicalSampleAction =
    ISBaseTimedAction:derive(
        "AC_DigGeologicalSampleAction"
    )


------------------------------------------------
-- SOUND CONFIG
------------------------------------------------

AC_DigGeologicalSampleAction.soundDelay = 6


------------------------------------------------
-- VALID
------------------------------------------------

function AC_DigGeologicalSampleAction:isValid()

    if not self.character
        or not self.square
        or not self.item
    then

        return false
    end


    if not AC_Geology.isSurveyableSquare(
        self.square
    ) then

        return false
    end


    if self.item:isBroken() then

        return false
    end


    if self.item:getCondition() <= 0 then

        return false
    end


    if isClient()
        and self.item
    then

        return
            self.character:
                getInventory():
                containsID(
                    self.item:getID()
                )
    end


    return true
end


------------------------------------------------
-- WAIT TO START
------------------------------------------------

function AC_DigGeologicalSampleAction:waitToStart()

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

function AC_DigGeologicalSampleAction:update()

    ------------------------------------------------
    -- Face digging location.
    ------------------------------------------------

    self.character:faceLocation(
        self.square:getX() + 0.5,
        self.square:getY() + 0.5
    )


    ------------------------------------------------
    -- Vanilla digging metabolic load.
    ------------------------------------------------

    self.character:setMetabolicTarget(
        Metabolics.DiggingSpade
    )


    ------------------------------------------------
    -- Shovel progress indicator.
    ------------------------------------------------

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
    -- SHOVELING SOUND
    --
    -- This copies the important behavior from
    -- vanilla ISBuildAction.
    --
    -- Vanilla does NOT simply start the sound once
    -- when the action starts. It retries it every
    -- few seconds and checks whether the previous
    -- event is still playing.
    ------------------------------------------------

    if self.soundTime
            + AC_DigGeologicalSampleAction.soundDelay
        < getTimestamp()
    then

        self.soundTime =
            getTimestamp()


        local emitter =
            self.character:getEmitter()


        if emitter then

            local playing =
                self.craftingSound ~= 0
                and emitter:isPlaying(
                    self.craftingSound
                )


            if not playing then

                self.craftingSound =
                    emitter:playSound(
                        "Shoveling"
                    )


                print(
                    "[AmmoMaking] Shoveling sound attempt, handle = "
                    .. tostring(
                        self.craftingSound
                    )
                )
            end
        end


        ------------------------------------------------
        -- Vanilla ISBuildAction also creates a world
        -- sound so zombies can hear construction.
        ------------------------------------------------

        addSound(
            self.character,
            self.character:getX(),
            self.character:getY(),
            self.character:getZ(),
            15,
            15
        )
    end
end


------------------------------------------------
-- START
------------------------------------------------

function AC_DigGeologicalSampleAction:start()

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


    ------------------------------------------------
    -- Job/progress data.
    ------------------------------------------------

    if self.item then

        self.item:setJobType(
            getText(
                "ContextMenu_Dig"
            )
        )


        self.item:setJobDelta(
            0.0
        )
    end


    ------------------------------------------------
    -- Exact vanilla shovel animation selector.
    ------------------------------------------------

    local animation =
        BuildingHelper.getShovelAnim(
            self.item
        )


    print(
        "[AmmoMaking] Shovel animation: "
        .. tostring(
            animation
        )
    )


    self:setActionAnim(
        animation
    )


    self:setOverrideHandModels(
        self.item,
        nil
    )


    ------------------------------------------------
    -- Same initialization style as ISBuildAction.
    --
    -- update() will start/restart the sound.
    ------------------------------------------------

    self.craftingSound =
        0


    self.soundTime =
        0


    print(
        "[AmmoMaking] Started digging geological sample"
    )
end


------------------------------------------------
-- STOP SOUND
------------------------------------------------

function AC_DigGeologicalSampleAction:stopSound()

    if not self.craftingSound
        or self.craftingSound == 0
    then

        return
    end


    local emitter =
        self.character:getEmitter()


    if emitter
        and emitter:isPlaying(
            self.craftingSound
        )
    then

        emitter:stopSound(
            self.craftingSound
        )
    end


    self.craftingSound =
        0
end


------------------------------------------------
-- STOP
------------------------------------------------

function AC_DigGeologicalSampleAction:stop()

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
-- PERFORM
------------------------------------------------

function AC_DigGeologicalSampleAction:perform()

    ------------------------------------------------
    -- Clear shovel job progress.
    ------------------------------------------------

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


    ------------------------------------------------
    -- Stop active shoveling sound.
    ------------------------------------------------

    self:stopSound()


    ------------------------------------------------
    -- Create geological sample.
    ------------------------------------------------

    local sample,
          errorCode =
        AC_GeologySampling.createSample(
            self.character,
            self.square,
            self.item
        )


    if sample then

        HaloTextHelper.addText(
            self.character,
            "Geological sample collected"
        )


        print(
            "[AmmoMaking] Geological sample digging completed at "
            .. tostring(
                self.square:getX()
            )
            .. ", "
            .. tostring(
                self.square:getY()
            )
        )

    else

        HaloTextHelper.addText(
            self.character,
            "Could not collect geological sample"
        )


        print(
            "[AmmoMaking] Dig sample failed: "
            .. tostring(
                errorCode
            )
        )
    end


    ISBaseTimedAction.perform(
        self
    )
end


------------------------------------------------
-- DURATION
------------------------------------------------

function AC_DigGeologicalSampleAction:getDuration()

    if self.character:isTimedActionInstant() then

        return 1
    end


    ------------------------------------------------
    -- Same base duration as vanilla grave work.
    ------------------------------------------------

    return 150
end


------------------------------------------------
-- CONSTRUCTOR
------------------------------------------------

function AC_DigGeologicalSampleAction:new(
    character,
    square,
    shovel
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


    o.item =
        shovel


    o.craftingSound =
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
    "[AmmoMaking] Geological digging timed action loaded"
)
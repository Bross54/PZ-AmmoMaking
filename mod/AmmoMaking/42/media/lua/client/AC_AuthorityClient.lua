-- Ammo Making - multiplayer server authority, client side
-- Project Zomboid Build 42.20
--
-- What a multiplayer client does when the server performs
-- the mod's actions (shared/AC_Authority.lua): send the menu
-- clicks as requests, show the server's answer, and keep the
-- server's copy of the depletion store for its menus.
--
-- Nothing here runs in single player: install() returns at
-- once unless this is a multiplayer client with the feature
-- "serverAuthority" on, and the request helpers are only
-- called from the menus' multiplayer branch.
--
-- The texts are the single-player menus' own (same keys,
-- same English), so a player reads the same message either
-- way.
--
-- REQUIRES FUTURE IN-GAME VERIFICATION: that the answers and
-- the global ModData arrive (OnServerCommand,
-- OnReceiveGlobalModData), and in which order an answer and
-- the item packets the server sent before it are applied.

AC_AuthorityClient = AC_AuthorityClient or {}


------------------------------------------------
-- TEXTS
------------------------------------------------

local function mineText(
    answer
)

    local metal =
        answer.metal


    if answer.ok then

        return
            AC_MineOreAction.getSuccessText(
                metal,
                {
                    remaining = tonumber(answer.remaining) or 0,
                    initial = tonumber(answer.initial) or 0,
                    xp = tonumber(answer.xp) or 0,
                }
            )
    end


    if answer.error == "no_ore"
        and AC_Deposits.isMetal(metal)
    then

        return
            AC_Text.get(
                "IGUI_AmmoMaking_NoWorkableOre",
                "No workable %1 ore here",
                AC_Text.metalInSentence(
                    metal,
                    AC_Deposits.getMetalName(
                        metal
                    )
                )
            )
    end


    if answer.error == "no_prospect" then

        return
            AC_Text.get(
                "IGUI_AmmoMaking_NeedAssayedSample",
                "You need an assayed sample of this site"
            )
    end


    if answer.error == "no_pickaxe" then

        return
            AC_Text.get(
                "IGUI_AmmoMaking_PickaxeNotUsable",
                "Your pickaxe is not usable"
            )
    end


    if answer.error == "multiplayer_unsupported" then

        return
            AC_Text.get(
                "IGUI_AmmoMaking_MiningMultiplayer",
                "Ore extraction is not available in multiplayer yet"
            )
    end


    return
        AC_Text.get(
            "IGUI_AmmoMaking_CouldNotExtract",
            "Could not extract ore"
        )
end


local function samplingText(
    answer
)

    if answer.error == "multiplayer_unsupported" then

        return
            AC_Text.get(
                "IGUI_AmmoMaking_Sampling_Multiplayer",
                "Geological sampling and assays are not available in multiplayer yet"
            )
    end


    if answer.action == "dig" then

        if answer.ok then

            return
                AC_Text.get(
                    "IGUI_AmmoMaking_SampleCollected",
                    "Geological sample collected"
                )
        end


        if answer.error == "too_far" then

            return
                AC_Text.get(
                    "IGUI_AmmoMaking_CannotReachSampling",
                    "Cannot reach sampling location"
                )
        end


        return
            AC_Text.get(
                "IGUI_AmmoMaking_SampleFailed",
                "Could not collect geological sample"
            )
    end


    if answer.ok then

        return
            AC_Text.get(
                "IGUI_AmmoMaking_SampleAnalyzed",
                "Sample analyzed"
            )
    end


    if answer.error == "kit_empty" then

        return
            AC_Text.get(
                "IGUI_AmmoMaking_KitEmpty",
                "Assay kit is empty"
            )
    end


    if answer.error == "already_analyzed" then

        return
            AC_Text.get(
                "IGUI_AmmoMaking_AlreadyAnalyzed",
                "Sample already has an equal or better assay"
            )
    end


    if answer.error == "lab_processing" then

        return
            AC_Text.get(
                "IGUI_AmmoMaking_SampleProcessing",
                "Sample is currently being analyzed"
            )
    end


    return
        AC_Text.get(
            "IGUI_AmmoMaking_AnalysisFailed",
            "Analysis failed"
        )
end


local function withXP(
    text,
    xp
)

    xp =
        tonumber(xp)
        or 0


    if xp <= 0 then
        return text
    end


    return
        text
        .. " - "
        .. AC_Text.get(
            "IGUI_AmmoMaking_ResultXP",
            "+%1 Ammo Making XP",
            AmmoMakingSkill.formatXP(
                xp
            )
        )
end


local function laboratoryText(
    answer
)

    if answer.error == "multiplayer_unsupported" then

        return
            AC_Text.get(
                "IGUI_AmmoMaking_LabUse_Multiplayer",
                "Using the laboratory analyzer is not available in multiplayer yet"
            )
    end


    if answer.error == "too_far" then

        return
            AC_Text.get(
                "IGUI_AmmoMaking_Lab_CannotReach",
                "Cannot reach the laboratory analyzer"
            )
    end


    if answer.action == "labStart" then

        if answer.ok then

            return
                AC_Text.get(
                    "IGUI_AmmoMaking_Lab_Started",
                    "Laboratory assay started - %1 hours",
                    AC_LaboratoryAnalyzer.CONFIG.processingHours
                )
        end


        if answer.error == "no_power" then

            return
                AC_Text.get(
                    "IGUI_AmmoMaking_Lab_RequiresElectricity",
                    "Laboratory analyzer requires electricity"
                )
        end


        if answer.error == "busy" then

            return
                AC_Text.get(
                    "IGUI_AmmoMaking_Lab_Busy",
                    "Laboratory analyzer is already occupied"
                )
        end


        if answer.error == "invalid_sample" then

            return
                AC_Text.get(
                    "IGUI_AmmoMaking_Lab_InvalidSample",
                    "This sample cannot be analyzed"
                )
        end


        return
            AC_Text.get(
                "IGUI_AmmoMaking_Lab_StartFailed",
                "Could not start laboratory assay"
            )
    end


    if answer.action == "labCollect" then

        if answer.ok then

            return
                withXP(
                    AC_Text.get(
                        "IGUI_AmmoMaking_Lab_Collected",
                        "Laboratory tested sample collected"
                    ),
                    answer.xp
                )
        end


        if answer.error == "not_ready" then

            return
                AC_Text.get(
                    "IGUI_AmmoMaking_Lab_StillProcessing",
                    "Laboratory assay is still processing"
                )
        end


        if answer.error == "empty" then

            return
                AC_Text.get(
                    "IGUI_AmmoMaking_Lab_Empty",
                    "Laboratory analyzer is empty"
                )
        end


        return
            AC_Text.get(
                "IGUI_AmmoMaking_Lab_CollectFailed",
                "Could not collect laboratory sample"
            )
    end


    if answer.action == "labCancel" then

        if answer.ok then

            return
                AC_Text.get(
                    "IGUI_AmmoMaking_Lab_Cancelled",
                    "Laboratory assay cancelled - sample returned"
                )
        end


        return
            AC_Text.get(
                "IGUI_AmmoMaking_Lab_CancelFailed",
                "Could not cancel the laboratory assay"
            )
    end


    ------------------------------------------------
    -- pickUp
    ------------------------------------------------

    if answer.ok then

        return
            AC_Text.get(
                "IGUI_AmmoMaking_Lab_PickedUp",
                "Laboratory Assay Analyzer picked up"
            )
    end


    return
        AC_PickUpAnalyzerAction.getRefusalText(
            answer.error
        )
end


AC_AuthorityClient.TEXT = {
    mine = mineText,
    dig = samplingText,
    assay = samplingText,
    pickUp = laboratoryText,
    labStart = laboratoryText,
    labCancel = laboratoryText,
    labCollect = laboratoryText,
}


-- The message for an answer of the server, or nil for an
-- answer that is not one of ours.
function AC_AuthorityClient.getText(
    answer
)

    if type(answer) ~= "table" then
        return nil
    end


    local text =
        AC_AuthorityClient.TEXT[answer.action]


    if not text then
        return nil
    end


    return
        text(
            answer
        )
end


------------------------------------------------
-- ANSWERS
------------------------------------------------

local function findLocalPlayer(
    answer
)

    local id =
        tonumber(answer.onlineID)


    if id
        and getPlayerByOnlineID
    then

        local player =
            getPlayerByOnlineID(
                id
            )


        if player then
            return player
        end
    end


    return
        getPlayer()
end


-- OnServerCommand(module, command, args).
function AC_AuthorityClient.onServerCommand(
    module,
    command,
    args
)

    if module ~= AC_Authority.MODULE
        or command ~= AC_Authority.REPLY
    then
        return nil
    end


    local text =
        AC_AuthorityClient.getText(
            args
        )


    if not text then
        return nil
    end


    local player =
        findLocalPlayer(
            args
        )


    if player then

        HaloTextHelper.addText(
            player,
            text
        )
    end


    print(
        "[AmmoMaking] Server answered "
        .. tostring(args.action)
        .. ": "
        .. (args.ok and "done" or tostring(args.error))
    )


    return text
end


-- OnReceiveGlobalModData(key, table or false). The engine
-- stores nothing itself (JAR GlobalModDataPacket.parse
-- only fires the event): the client keeps the server's
-- depletion store as its own copy, for its menus. Mining
-- code never writes it on a client.
function AC_AuthorityClient.onReceiveGlobalModData(
    key,
    received
)

    if key ~= AC_Deposits.CONFIG.modDataKey
        or type(received) ~= "table"
    then
        return false
    end


    ModData.add(
        key,
        received
    )


    return true
end


------------------------------------------------
-- REQUESTS
------------------------------------------------

function AC_AuthorityClient.requestAssay(
    player,
    sample,
    kit
)

    return
        AC_Authority.request(
            player,
            "assay",
            {
                sampleId = sample:getID(),
                kitId = kit:getID(),
            }
        )
end


-- Start, cancel or collect at a placed analyzer. The server
-- checks the distance again; asking from across the room
-- is answered here, without a request.
function AC_AuthorityClient.requestLaboratory(
    player,
    command,
    analyzer,
    sample
)

    local square =
        analyzer
        and analyzer:getSquare()


    if not square
        or not AC_LaboratoryAnalyzer.isPlacedAnalyzerObject(
            analyzer
        )
    then

        HaloTextHelper.addText(
            player,
            AC_Text.get(
                "IGUI_AmmoMaking_Lab_Invalid",
                "Invalid laboratory analyzer"
            )
        )


        return false
    end


    if not AC_Authority.isWithinReach(
        player,
        square
    ) then

        HaloTextHelper.addText(
            player,
            AC_Text.get(
                "IGUI_AmmoMaking_Lab_CannotReach",
                "Cannot reach the laboratory analyzer"
            )
        )


        return false
    end


    local args = {
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
    }


    if sample then

        args.sampleId =
            sample:getID()
    end


    return
        AC_Authority.request(
            player,
            command,
            args
        )
end


------------------------------------------------
-- INSTALL (client)
------------------------------------------------

function AC_AuthorityClient.install()

    if AC_AuthorityClient.installed then
        return true
    end


    if not AC_Authority.canRequest() then
        return nil
    end


    Events.OnServerCommand.Add(
        AC_AuthorityClient.onServerCommand
    )


    Events.OnReceiveGlobalModData.Add(
        AC_AuthorityClient.onReceiveGlobalModData
    )


    ------------------------------------------------
    -- The server's depletion store as it is now; from
    -- then on every extraction transmits it again.
    ------------------------------------------------

    ModData.request(
        AC_Deposits.CONFIG.modDataKey
    )


    AC_AuthorityClient.installed =
        true


    print(
        "[AmmoMaking] Server authority: this client asks the server"
    )


    return true
end


Events.OnGameStart.Add(
    AC_AuthorityClient.install
)


------------------------------------------------
-- LOAD MESSAGE
------------------------------------------------

print(
    "[AmmoMaking] Server authority client loaded"
)

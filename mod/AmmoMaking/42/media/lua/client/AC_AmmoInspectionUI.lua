-- Ammo Making - Ammunition Inspection UI
-- Project Zomboid Build 42.20

require "ISUI/ISPanel"
require "ISUI/ISButton"

AC_AmmoInspectionUI = ISPanel:derive("AC_AmmoInspectionUI")


------------------------------------------------
-- HELPERS
------------------------------------------------

local function calculatePanelHeight(inspection)
    local lineCount = 0

    if inspection and inspection.lines then
        for _, line in ipairs(inspection.lines) do
            if line ~= "Ammo Inspection" then
                lineCount = lineCount + 1
            end
        end
    end

    local titleArea = 65
    local lineHeight = 24
    local footerArea = 95

    local height =
        titleArea +
        (lineCount * lineHeight) +
        footerArea

    -- Minimum height for low-level inspections
    if height < 250 then
        height = 250
    end

    return height
end


------------------------------------------------
-- CONSTRUCTOR
------------------------------------------------

function AC_AmmoInspectionUI:new(player, inspection)
    local width = 430
    local height = calculatePanelHeight(inspection)

    local screenWidth = getCore():getScreenWidth()
    local screenHeight = getCore():getScreenHeight()

    ------------------------------------------------
    -- Prevent panel from becoming taller than screen
    ------------------------------------------------

    local maxHeight = screenHeight - 80

    if height > maxHeight then
        height = maxHeight
    end

    local x = (screenWidth - width) / 2
    local y = (screenHeight - height) / 2

    local o = ISPanel:new(
        x,
        y,
        width,
        height
    )

    setmetatable(o, self)
    self.__index = self

    o.player = player
    o.inspection = inspection

    o.backgroundColor = {
        r = 0,
        g = 0,
        b = 0,
        a = 0.90
    }

    o.borderColor = {
        r = 1,
        g = 1,
        b = 1,
        a = 0.35
    }

    o.moveWithMouse = true

    return o
end


------------------------------------------------
-- INITIALISE
------------------------------------------------

function AC_AmmoInspectionUI:initialise()
    ISPanel.initialise(self)
end


------------------------------------------------
-- CHILDREN
------------------------------------------------

function AC_AmmoInspectionUI:createChildren()
    ISPanel.createChildren(self)

    local buttonWidth = 100
    local buttonHeight = 25

    self.closeButton = ISButton:new(
        (self.width - buttonWidth) / 2,
        self.height - 40,
        buttonWidth,
        buttonHeight,
        "Close",
        self,
        AC_AmmoInspectionUI.onClose
    )

    self.closeButton:initialise()
    self.closeButton:instantiate()

    self:addChild(self.closeButton)
end


------------------------------------------------
-- PRE-RENDER
------------------------------------------------

function AC_AmmoInspectionUI:prerender()
    ISPanel.prerender(self)

    self:drawText(
        "AMMUNITION INSPECTION",
        20,
        15,
        1,
        1,
        1,
        1,
        UIFont.Medium
    )

    self:drawRectBorder(
        15,
        45,
        self.width - 30,
        1,
        0.4,
        1,
        1,
        1
    )
end


------------------------------------------------
-- RENDER
------------------------------------------------

function AC_AmmoInspectionUI:render()
    ISPanel.render(self)

    if not self.inspection
        or not self.inspection.lines
    then
        return
    end

    local y = 65
    local lineHeight = 24

    ------------------------------------------------
    -- INSPECTION INFORMATION
    ------------------------------------------------

    for _, line in ipairs(self.inspection.lines) do

        -- We draw our own title already
        if line ~= "Ammo Inspection" then

            self:drawText(
                tostring(line),
                25,
                y,
                1,
                1,
                1,
                1,
                UIFont.Small
            )

            y = y + lineHeight
        end
    end


    ------------------------------------------------
    -- PLAYER SKILL LEVEL
    ------------------------------------------------

    local footerY =
        self.height - 75

    self:drawText(
        "Ammo Making Level: "
        .. tostring(self.inspection.level or 0),
        25,
        footerY,
        0.7,
        0.7,
        0.7,
        1,
        UIFont.Small
    )
end


------------------------------------------------
-- CLOSE
------------------------------------------------

function AC_AmmoInspectionUI:onClose()
    self:setVisible(false)
    self:removeFromUIManager()

    AC_AmmoInspectionUI.instance = nil
end


------------------------------------------------
-- OPEN
------------------------------------------------

function AC_AmmoInspectionUI.open(
    player,
    inspection
)

    ------------------------------------------------
    -- Remove existing inspection window
    ------------------------------------------------

    if AC_AmmoInspectionUI.instance then

        AC_AmmoInspectionUI.instance:setVisible(false)

        AC_AmmoInspectionUI.instance:
            removeFromUIManager()

        AC_AmmoInspectionUI.instance = nil
    end


    ------------------------------------------------
    -- Create new panel
    ------------------------------------------------

    local panel =
        AC_AmmoInspectionUI:new(
            player,
            inspection
        )

    panel:initialise()
    panel:addToUIManager()
    panel:setVisible(true)

    AC_AmmoInspectionUI.instance =
        panel
end
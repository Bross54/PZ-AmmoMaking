-- Ammo Making - Geological Assay UI
-- Project Zomboid Build 42.20

require "ISUI/ISPanel"
require "ISUI/ISButton"


AC_GeologyAssayUI =
    ISPanel:derive(
        "AC_GeologyAssayUI"
    )


------------------------------------------------
-- CONSTRUCTOR
------------------------------------------------

function AC_GeologyAssayUI:new(
    player,
    sample
)

    local width = 420

    local lines =
        AC_GeologySampling.getResultLines(
            sample
        )
        or {}


    local height =
        150
        + (#lines * 24)


    if height < 240 then
        height = 240
    end


    local screenWidth =
        getCore():getScreenWidth()


    local screenHeight =
        getCore():getScreenHeight()


    local x =
        (screenWidth - width) / 2


    local y =
        (screenHeight - height) / 2


    local o =
        ISPanel:new(
            x,
            y,
            width,
            height
        )


    setmetatable(
        o,
        self
    )


    self.__index =
        self


    o.player =
        player


    o.sample =
        sample


    o.lines =
        lines


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


    o.moveWithMouse =
        true


    return o
end


------------------------------------------------
-- INITIALISE
------------------------------------------------

function AC_GeologyAssayUI:initialise()

    ISPanel.initialise(
        self
    )
end


------------------------------------------------
-- CHILDREN
------------------------------------------------

function AC_GeologyAssayUI:createChildren()

    ISPanel.createChildren(
        self
    )


    local buttonWidth =
        100


    local buttonHeight =
        25


    self.closeButton =
        ISButton:new(
            (self.width - buttonWidth) / 2,
            self.height - 40,
            buttonWidth,
            buttonHeight,
            "Close",
            self,
            AC_GeologyAssayUI.onClose
        )


    self.closeButton:initialise()

    self.closeButton:instantiate()

    self:addChild(
        self.closeButton
    )
end


------------------------------------------------
-- PRE-RENDER
------------------------------------------------

function AC_GeologyAssayUI:prerender()

    ISPanel.prerender(
        self
    )


    self:drawText(
        "GEOLOGICAL ASSAY",
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

function AC_GeologyAssayUI:render()

    ISPanel.render(
        self
    )


    local y =
        65


    for _,
        line
    in ipairs(
        self.lines
    )
    do

        self:drawText(
            tostring(
                line
            ),
            25,
            y,
            1,
            1,
            1,
            1,
            UIFont.Small
        )


        y =
            y + 24
    end
end


------------------------------------------------
-- CLOSE
------------------------------------------------

function AC_GeologyAssayUI:onClose()

    self:setVisible(
        false
    )


    self:removeFromUIManager()


    AC_GeologyAssayUI.instance =
        nil
end


------------------------------------------------
-- OPEN
------------------------------------------------

function AC_GeologyAssayUI.open(
    player,
    sample
)

    if AC_GeologyAssayUI.instance then

        AC_GeologyAssayUI.instance:
            setVisible(
                false
            )


        AC_GeologyAssayUI.instance:
            removeFromUIManager()


        AC_GeologyAssayUI.instance =
            nil
    end


    local panel =
        AC_GeologyAssayUI:new(
            player,
            sample
        )


    panel:initialise()

    panel:addToUIManager()

    panel:setVisible(
        true
    )


    AC_GeologyAssayUI.instance =
        panel
end
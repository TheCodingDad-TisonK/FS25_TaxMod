-- =========================================================
-- Tax Field Guide - Field Guide
-- =========================================================
-- BUILD 19:15 (George CLOSED DESIGN 18:55 item 5): every Realistic Farming Esc page gets its own
-- guide, in its own mod, opened from the shared Help footer through this guest's onOpenHelp. The
-- chrome is SoilGuideDialog's so all of them read as one family; only the words differ.
-- Rows are { t = "H" | "B" | "S" | "COL", v = "text" }: header, body, spacer, column break.
-- =========================================================

---@class TaxGuideDialog
TaxGuideDialog = TaxGuideDialog or {}
local TaxGuideDialog_mt = Class(TaxGuideDialog, ScreenElement)

local GUIDE_MOD_DIR = (TaxModModDirectory or g_currentModDirectory)

TaxGuideDialog.INSTANCE = nil
TaxGuideDialog.GUI_NAME = "TaxGuideDialog"

TaxGuideDialog.SUBTITLES = {
    "Overview - what the tax year does to your farm",
    "Status Page - reading the pause page line by line",
    "Settings & FAQ - options, controls and common questions",
}

TaxGuideDialog.PAGE1 = {
    { t="H", v="WHAT THIS MOD DOES" },
    { t="B", v="Tax Mod puts a yearly tax bill on your farm." },
    { t="B", v="Nothing is taken out of your account day to" },
    { t="B", v="day. A bill builds up all year instead, and" },
    { t="B", v="it is settled once, in March." },
    { t="S", v=" " },
    { t="H", v="THE TAX YEAR" },
    { t="B", v="Once each in-game day the mod looks at your" },
    { t="B", v="farm balance. If the balance is above the" },
    { t="B", v="minimum balance, a small share of it is" },
    { t="B", v="added to this year's bill. No money moves." },
    { t="S", v=" " },
    { t="B", v="In December a tax advisory message tells you" },
    { t="B", v="what March is likely to cost and what share" },
    { t="B", v="of your balance that is." },
    { t="S", v=" " },
    { t="B", v="In March the bill is settled. A percentage" },
    { t="B", v="of the built-up bill is taken, you are told" },
    { t="B", v="the amount, and the bill resets to zero for" },
    { t="B", v="the new year." },
    { t="COL", v="" },
    { t="H", v="THE PAUSE PAGE" },
    { t="B", v="Press Esc and open the Realistic Farming" },
    { t="B", v="tab. Pick Tax in the module list on the left" },
    { t="B", v="to bring up this mod's page." },
    { t="S", v=" " },
    { t="B", v="The page is a status block, not a table." },
    { t="B", v="Eight short lines fill two columns on the" },
    { t="B", v="right, with a summary line underneath them." },
    { t="S", v=" " },
    { t="B", v="It is a read-only glance. Nothing on this" },
    { t="B", v="page ever moves money or changes a setting." },
    { t="S", v=" " },
    { t="H", v="WHERE ELSE TO LOOK" },
    { t="B", v="The Tax HUD shows the same figures on screen" },
    { t="B", v="while you play, plus a short list of the" },
    { t="B", v="most recent tax events." },
    { t="S", v=" " },
    { t="B", v="Settings sit in the game settings under a" },
    { t="B", v="Tax Mod section. See the last tab." },
}

TaxGuideDialog.PAGE2 = {
    { t="H", v="THE LEFT COLUMN" },
    { t="B", v="A short help text sits at the top left. It" },
    { t="B", v="tells the same story in a sentence or two." },
    { t="S", v=" " },
    { t="B", v="Under it is the list of Realistic Farming" },
    { t="B", v="modules you have installed. Click Tax to" },
    { t="B", v="bring up the tax lines. The selector above" },
    { t="B", v="the list steps through the same modules." },
    { t="S", v=" " },
    { t="H", v="THE EIGHT STATUS LINES" },
    { t="B", v="Tax: whether the system is on or off." },
    { t="B", v="Accumulated bill: what this year has built" },
    { t="B", v="up so far." },
    { t="B", v="Projected March payment: what the March" },
    { t="B", v="settlement would cost at today's figure." },
    { t="B", v="Percent of balance: that payment as a share" },
    { t="B", v="of the money you hold right now." },
    { t="COL", v="" },
    { t="B", v="Next: the payment month or the advisory" },
    { t="B", v="month, whichever comes first, with the" },
    { t="B", v="number of months to go." },
    { t="B", v="Lifetime paid: every tax payment this save" },
    { t="B", v="has ever made." },
    { t="B", v="Companion ledger: credits and debits other" },
    { t="B", v="mods have recorded here. It reads none yet" },
    { t="B", v="until something records one." },
    { t="B", v="Days taxed: how many days have added to the" },
    { t="B", v="bill so far." },
    { t="S", v=" " },
    { t="H", v="THE SUMMARY LINE" },
    { t="B", v="Below the eight lines sits one line with" },
    { t="B", v="three figures: the daily rate, the March" },
    { t="B", v="rate and the minimum balance." },
    { t="S", v=" " },
    { t="B", v="The daily rate and the March rate are two" },
    { t="B", v="different settings. The daily one grows the" },
    { t="B", v="bill. The March one decides how much of that" },
    { t="B", v="bill you actually pay." },
    { t="S", v=" " },
    { t="B", v="The ledger totals are bookkeeping only. They" },
    { t="B", v="never change what you owe." },
}

TaxGuideDialog.PAGE3 = {
    { t="H", v="SETTINGS" },
    { t="B", v="Open the game settings and scroll the" },
    { t="B", v="general settings down to the Tax Mod" },
    { t="B", v="section. Five controls sit there." },
    { t="S", v=" " },
    { t="B", v="Enable Tax Mod turns the system on or off." },
    { t="B", v="Tax Rate sets the daily share: Low is one" },
    { t="B", v="percent, Medium two, High three." },
    { t="B", v="Annual Tax Rate sets the March share: Low is" },
    { t="B", v="two percent, Medium five, High ten." },
    { t="B", v="Notifications shows the in-game messages." },
    { t="B", v="Show Tax HUD shows or hides the overlay." },
    { t="S", v=" " },
    { t="B", v="Settings are saved with your savegame." },
    { t="COL", v="" },
    { t="H", v="CONTROLS" },
    { t="B", v="The mod ships with no keys assigned. Open" },
    { t="B", v="Options then Controls and look for Toggle" },
    { t="B", v="Tax HUD and Tax HUD Edit Mode." },
    { t="S", v=" " },
    { t="B", v="In edit mode, drag the panel with the left" },
    { t="B", v="mouse button, drag a corner to resize, drag" },
    { t="B", v="a side edge to change the width, then press" },
    { t="B", v="the right mouse button to finish. The layout" },
    { t="B", v="is kept with your savegame." },
    { t="S", v=" " },
    { t="H", v="COMMON QUESTIONS" },
    { t="B", v="Nothing was added today. Your balance was" },
    { t="B", v="under the minimum balance, or the system is" },
    { t="B", v="switched off." },
    { t="S", v=" " },
    { t="B", v="March cost less than the bill said. Only a" },
    { t="B", v="share of the built-up bill is charged." },
    { t="S", v=" " },
    { t="B", v="The returned total stays at zero. Refunds" },
    { t="B", v="are not paid out in this version." },
    { t="S", v=" " },
    { t="B", v="The page says the tax manager is not ready." },
    { t="B", v="Give the save a moment to finish loading." },
}

TaxGuideDialog.PAGE_CONTENT = { TaxGuideDialog.PAGE1, TaxGuideDialog.PAGE2, TaxGuideDialog.PAGE3 }

-- -- Constructor ------------------------------------------

function TaxGuideDialog.new(target, customMt)
    local self = ScreenElement.new(target, customMt or TaxGuideDialog_mt)
    self._contentLineEls = {}
    self._currentPage = 1
    return self
end

--- Loads the dialog into g_gui once. Safe to call twice, and safe to call when some other path has
--- already registered the same name.
function TaxGuideDialog.register(modDirectory)
    if g_gui == nil then return end
    if g_gui.guis ~= nil and g_gui.guis[TaxGuideDialog.GUI_NAME] ~= nil then return end
    if modDirectory ~= nil then GUIDE_MOD_DIR = modDirectory end
    if GUIDE_MOD_DIR == nil then return end
    TaxGuideDialog.INSTANCE = TaxGuideDialog.new()
    local ok, err = pcall(function()
        g_gui:loadGui(GUIDE_MOD_DIR .. "xml/gui/TaxGuideDialog.xml", TaxGuideDialog.GUI_NAME, TaxGuideDialog.INSTANCE)
    end)
    if not ok then
        print("[Tax] TaxGuideDialog: loadGui failed: " .. tostring(err))
        TaxGuideDialog.INSTANCE = nil
    end
end

function TaxGuideDialog.show()
    if g_gui == nil then return end
    local loaded = g_gui.guis ~= nil and g_gui.guis[TaxGuideDialog.GUI_NAME] ~= nil
    if not loaded then
        TaxGuideDialog.register(GUIDE_MOD_DIR)
        loaded = g_gui.guis ~= nil and g_gui.guis[TaxGuideDialog.GUI_NAME] ~= nil
    end
    if not loaded then return end
    g_gui:showDialog(TaxGuideDialog.GUI_NAME)
end

-- -- Lifecycle --------------------------------------------

function TaxGuideDialog:onGuiSetupFinished()
    TaxGuideDialog:superClass().onGuiSetupFinished(self)
    self._elCol1 = self:getDescendantById("taxGuide_col1")
    self._elCol2 = self:getDescendantById("taxGuide_col2")
    self._elSubtitle = self:getDescendantById("taxGuide_subtitle")
end

function TaxGuideDialog:onOpen()
    TaxGuideDialog:superClass().onOpen(self)
    self._currentPage = 1
    self:_selectPage(1)
end

function TaxGuideDialog:onClose()
    TaxGuideDialog:superClass().onClose(self)
    self:_clearContent()
    self._currentPage = 1
end

-- -- Tabs -------------------------------------------------

function TaxGuideDialog:onClickTab1() self:_selectPage(1) end
function TaxGuideDialog:onClickTab2() self:_selectPage(2) end
function TaxGuideDialog:onClickTab3() self:_selectPage(3) end

function TaxGuideDialog:_selectPage(pageNum)
    if self._currentPage == pageNum and #self._contentLineEls > 0 then return end
    self:_clearContent()
    self._currentPage = pageNum
    if self._elSubtitle ~= nil then
        self._elSubtitle:setText(TaxGuideDialog.SUBTITLES[pageNum] or "")
    end
    self:_buildContent(pageNum)
end

-- -- Content ----------------------------------------------

function TaxGuideDialog:_buildContent(pageNum)
    local profileH = g_gui:getProfile("taxGuide_colHeader")
    local profileB = g_gui:getProfile("taxGuide_colBody")
    local profileS = g_gui:getProfile("taxGuide_colSpacer")
    if not profileH or not profileB then
        print("[Tax] TaxGuideDialog: column profiles not found")
        return
    end
    local content = TaxGuideDialog.PAGE_CONTENT[pageNum]
    if content == nil then return end
    local currentBox = self._elCol1
    for _, row in ipairs(content) do
        if row.t == "COL" then
            if self._elCol1 ~= nil then self._elCol1:invalidateLayout() end
            currentBox = self._elCol2
        elseif currentBox ~= nil then
            local profile = (row.t == "H") and profileH
                         or (row.t == "S") and profileS
                         or profileB
            if profile ~= nil then
                local el = TextElement.new()
                el:loadProfile(profile, true)
                el:setText(row.v or "")
                currentBox:addElement(el)
                el:onGuiSetupFinished()
                table.insert(self._contentLineEls, { box = currentBox, el = el })
            end
        end
    end
    if self._elCol2 ~= nil then self._elCol2:invalidateLayout() end
end

function TaxGuideDialog:_clearContent()
    for _, entry in ipairs(self._contentLineEls or {}) do
        if entry.box ~= nil then
            entry.box:removeElement(entry.el)
        end
    end
    self._contentLineEls = {}
    if self._elCol1 ~= nil then self._elCol1:invalidateLayout() end
    if self._elCol2 ~= nil then self._elCol2:invalidateLayout() end
end

-- -- Button -----------------------------------------------

function TaxGuideDialog:onClickClose()
    g_gui:closeDialogByName(TaxGuideDialog.GUI_NAME)
end

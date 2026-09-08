-- =========================================================
-- TaxRfPdaGuest - Esc RF PDA Tax framework (Status shell)
-- Soft-detect: mission.taxManager -> g_TaxManager -> FS25TaxMod.
-- Read-only; no tax settle / money writes.
-- =========================================================

TaxRfPdaGuest = TaxRfPdaGuest or {}

local MOD_DIR = (TaxModModDirectory or g_currentModDirectory)
local MOD_NAME = (TaxModModName or g_currentModName)
local PANEL_ID = "tax"
local PANEL_ORDER = 60
local _registered = false

local function tr(key, fallback)
    local modEnv = g_modEnvironments and g_modEnvironments[MOD_NAME]
    local i18n = (modEnv and modEnv.i18n) or g_i18n
    if i18n then
        local ok, text = pcall(function() return i18n:getText(key) end)
        if ok and type(text) == "string" and text ~= "" then
            local lower = text:lower()
            if lower ~= tostring(key):lower()
                and text ~= ("$l10n_" .. key)
                and not lower:find("^missing%s")
                and not lower:find("^missing_")
            then
                return text
            end
        end
    end
    return fallback or key
end

local function getHost()
    if g_currentMission ~= nil and g_currentMission.rfEscModules ~= nil then
        return g_currentMission.rfEscModules
    end
    local env = getfenv(0)
    if env ~= nil and env.g_rfEscModules ~= nil then
        return env.g_rfEscModules
    end
    if RfEscModules ~= nil then
        return RfEscModules.getOrCreate()
    end
    return nil
end

local function getHostPage()
    if g_inGameMenu == nil then return nil end
    return g_inGameMenu.menuRealisticFarming
end

local function findDescendant(root, id)
    if root == nil or id == nil then return nil end
    if root.getDescendantById then
        local el = root:getDescendantById(id)
        if el ~= nil then return el end
    end
    local page = getHostPage()
    if page and page.getDescendantById then
        return page:getDescendantById(id)
    end
    return nil
end

local function setText(el, text)
    if el ~= nil and type(el.setText) == "function" then el:setText(text or "") end
end

local function setVis(el, visible)
    if el ~= nil and type(el.setVisible) == "function" then el:setVisible(visible) end
end

local function formatMoney(amount)
    if amount == nil then return "--" end
    if g_i18n and g_i18n.formatMoney then return g_i18n:formatMoney(amount, 0, true, true) end
    return string.format("%.0f", amount)
end

local function paintSide(container, key, fallback)
    setVis(findDescendant(container, "wcSideInfoShell"), false)
    setVis(findDescendant(container, "mdSideInfoShell"), false)
    local shell = findDescendant(container, "rfSideInfoShell")
    local body = findDescendant(container, "rfSideInfoBody")
    setVis(shell, true)
    setText(body, tr(key, fallback))
end


local function refreshFwAbs(container)
    local page = getHostPage()
    local host = findDescendant(container, "rfHostPlaceholder") or (page and page.rfHostPlaceholder)
    local shell = findDescendant(container, "rfFrameworkGlanceShell")
    local status = findDescendant(container, "rfFwStatusBlock")
    local tableBlock = findDescendant(container, "rfFwTableBlock")
    for _, el in ipairs({ host, shell, status, tableBlock }) do
        if el ~= nil and type(el.updateAbsolutePosition) == "function" then
            el:updateAbsolutePosition()
        end
    end
end

local function clearHostDupes(container)
    setText(findDescendant(container, "rfHostBody"), "")
    setText(findDescendant(container, "rfHostTitle"), "")
    setText(findDescendant(container, "rfHostBlurb"), "")
    setVis(findDescendant(container, "rfHostTitle"), false)
    setVis(findDescendant(container, "rfHostBlurb"), false)
end

local function showStatusMode(container)
    setVis(findDescendant(container, "rfFrameworkGlanceShell"), true)
    setVis(findDescendant(container, "rfFwStatusBlock"), true)
    setVis(findDescendant(container, "rfFwTableBlock"), false)
    refreshFwAbs(container)
end

local function showTableMode(container)
    setVis(findDescendant(container, "rfFrameworkGlanceShell"), true)
    setVis(findDescendant(container, "rfFwStatusBlock"), false)
    setVis(findDescendant(container, "rfFwTableBlock"), true)
    refreshFwAbs(container)
end

local function labeled(label, value)
    local lbl = tostring(label or ""):gsub(":%s*$", "")
    return string.format("%s: %s", lbl, tostring(value or "--"))
end

-- Daily taxRate map (same as HUD / main.lua TAX_RATE_VALUES). March annualTaxRate is separate.
local TAX_RATE_VALUES = { low = 0.01, medium = 0.02, high = 0.03 }

local function getTax()
    if g_currentMission ~= nil and g_currentMission.taxManager ~= nil then
        return g_currentMission.taxManager
    end
    if g_TaxManager ~= nil then
        return g_TaxManager
    end
    local env = getfenv(0)
    if env ~= nil and env.g_TaxManager ~= nil then
        return env.g_TaxManager
    end
    -- Temporary deepest fallback (named): global table FS25TaxMod
    if FS25TaxMod ~= nil then
        return FS25TaxMod
    end
    return nil
end

local function monthsUntil(target, current)
    local d = (tonumber(target) or 1) - (tonumber(current) or 1)
    if d <= 0 then d = d + 12 end
    return d
end

local _statusWarned = false

-- BUILD 16:32. The densify that used to live here moved rfFwLine1..8 to -280..-480 with
-- 26px type and X reset to 0. That was written for an unframed 580-tall status block,
-- where the lower band really was empty space. BUILD 15:35 put a 340-tall white stroke
-- round that block, so the same move now drops the whole status band under the bottom
-- rule and leaves an empty white box above it: the FAIL Wizard saw.
--
-- BUILD 20:37. Deleting the densify was only half of it. What replaced it captured the
-- element positions on the FIRST show and re-asserted those, which is only the XML baseline
-- if nothing had moved the shell before that first show. If anything had, the capture froze
-- the bad layout and every later show put it back faithfully. A one-shot capture cannot tell
-- a baseline from a mistake, so the locks are written out instead.
--
-- These px are read from this mod's own xml/gui/RfPdaMenuPage.xml and must stay equal to it.
-- The XML remains the one place that says where status text lives; this file's job is only
-- to put it back there if anything moved it.
local FW_STATUS_BLOCK = { "rfFwStatusBlock", "0px", "0px", "1140px", "340px" }
-- Two columns of four. Left at 10, right at 580, sharing the four Y axes.
local FW_STATUS_LINES = {
    { "rfFwLine1", "10px", "-8px" },
    { "rfFwLine2", "10px", "-56px" },
    { "rfFwLine3", "10px", "-104px" },
    { "rfFwLine4", "10px", "-152px" },
    { "rfFwLine5", "580px", "-8px" },
    { "rfFwLine6", "580px", "-56px" },
    { "rfFwLine7", "580px", "-104px" },
    { "rfFwLine8", "580px", "-152px" }
}
-- 550 wide, not 580: a line grown to 580 would run into the right column's own left edge.
local FW_LINE_W, FW_LINE_H = "550px", "22px"
local FW_STATUS_HINT = { "rfFwHint", "10px", "-208px", "1120px", "120px" }

--- Put the Status shell back on the XML locks. Runs every show, so a move from any earlier
--- session, or from a stale artifact still sitting in My Games, cannot survive into this one.
---
--- textSize is never written. The profile owns the type, and since there is no way to unset a
--- text size once it has been set, the only way to leave type alone is to never touch it.
local function restoreStatusBand(container)
    if container == nil then
        return
    end
    if GuiUtils == nil or type(GuiUtils.getNormalizedXValue) ~= "function"
        or type(GuiUtils.getNormalizedYValue) ~= "function"
        or type(GuiUtils.getNormalizedScreenValues) ~= "function" then
        if not _statusWarned then
            _statusWarned = true
            print("[RF] Tax status band: GuiUtils normalizer absent - leaving the XML geometry")
        end
        return
    end

    local function place(id, xPx, yPx, wPx, hPx)
        local el = findDescendant(container, id)
        if el == nil then
            return
        end
        if type(el.setPosition) == "function" then
            el:setPosition(GuiUtils.getNormalizedXValue(xPx, 0),
                           GuiUtils.getNormalizedYValue(yPx, 0))
        end
        if wPx ~= nil and hPx ~= nil and type(el.setSize) == "function" then
            local norms = GuiUtils.getNormalizedScreenValues(wPx .. " " .. hPx)
            if type(norms) == "table" and norms[1] ~= nil and norms[2] ~= nil then
                el:setSize(norms[1], norms[2])
            end
        end
        if type(el.updateAbsolutePosition) == "function" then el:updateAbsolutePosition() end
    end

    -- The card first, so the lines are placed inside a block that is already the right size.
    place(FW_STATUS_BLOCK[1], FW_STATUS_BLOCK[2], FW_STATUS_BLOCK[3],
          FW_STATUS_BLOCK[4], FW_STATUS_BLOCK[5])
    -- A literal 1..8 walk. An ipairs over this table would stop at the first nil if an edit
    -- ever left a hole in it, and silently place only the left column, which is the exact
    -- shape of the bug this suite paid for at 21:54.
    for i = 1, 8 do
        local row = FW_STATUS_LINES[i]
        if row ~= nil then
            place(row[1], row[2], row[3], FW_LINE_W, FW_LINE_H)
        end
    end
    place(FW_STATUS_HINT[1], FW_STATUS_HINT[2], FW_STATUS_HINT[3],
          FW_STATUS_HINT[4], FW_STATUS_HINT[5])
end

function TaxRfPdaGuest.onShow(container, lightOnly)
    clearHostDupes(container)
    showStatusMode(container)
    -- Every show, straight from the XML locks. Nothing is captured, so nothing can be
    -- frozen wrong on a first show that happened to land after something moved the shell.
    restoreStatusBand(container)
    paintSide(container, "rf_pda_side_info_tax",
        "Tax posture: on/off, year bill, March estimate, balance share, countdown.\n"
        .. "Daily rate and March rate differ. Esc never pays tax - use Tax HUD / Settings.")
    setText(findDescendant(container, "rfFwStatusTitle"), "")
    setVis(findDescendant(container, "rfFwStatusTitle"), false)

    local tax = getTax()
    local settings = tax and tax.settings
    local stats = tax and tax.stats
    if tax == nil or settings == nil or stats == nil then
        setText(findDescendant(container, "rfFwLine1"), tr("tax_rf_pda_waiting", "Tax manager not ready"))
        for i = 2, 8 do setText(findDescendant(container, "rfFwLine" .. i), "") end
        setText(findDescendant(container, "rfFwHint"), "")
        return
    end

    local onOff = settings.enabled and tr("tax_rf_pda_on", "On") or tr("tax_rf_pda_off", "Off")
    setText(findDescendant(container, "rfFwLine1"), labeled(tr("tax_rf_pda_lbl_enabled", "Tax"), onOff))

    local accum = tonumber(stats.taxesAccumulatedAnnual) or 0
    setText(findDescendant(container, "rfFwLine2"), labeled(tr("tax_rf_pda_lbl_accum", "Accumulated bill"), formatMoney(accum)))

    local annualRate = tonumber(settings.annualTaxRate) or 0.05
    local projected = math.floor(accum * annualRate)
    setText(findDescendant(container, "rfFwLine3"), labeled(tr("tax_rf_pda_lbl_projected", "Projected March payment"), formatMoney(projected)))

    local balance = 0
    local farmId = nil
    if g_farmManager ~= nil and g_currentMission ~= nil and type(g_currentMission.getFarmId) == "function" then
        farmId = g_currentMission:getFarmId()
        local farm = g_farmManager:getFarmById(farmId)
        balance = farm and farm.money or 0
    end
    local pct = balance > 0 and math.floor((projected / balance) * 100) or 0
    setText(findDescendant(container, "rfFwLine4"), labeled(tr("tax_rf_pda_lbl_pct", "Percent of balance"), string.format("%d%%", pct)))

    local env = g_currentMission and g_currentMission.environment
    local currentMonth = env and env.currentMonth or 1
    local advisoryMonth = stats.taxAdvisoryMonth or 12
    local returnMonth = stats.taxReturnMonth or 3
    local mToAdvisory = monthsUntil(advisoryMonth, currentMonth)
    local mToPayment = monthsUntil(returnMonth, currentMonth)
    local nextLine
    if mToPayment <= mToAdvisory then
        local when = mToPayment == 1 and tr("tax_rf_pda_next_month", "Next month!") or string.format("%d months", mToPayment)
        nextLine = labeled(tr("tax_rf_pda_next_pay", "Next: Tax payment"), when)
    else
        local when = mToAdvisory == 1 and tr("tax_rf_pda_next_month", "Next month!") or string.format("%d months", mToAdvisory)
        nextLine = labeled(tr("tax_rf_pda_next_adv", "Next: Advisory"), when)
    end
    setText(findDescendant(container, "rfFwLine5"), nextLine)

    -- Lifetime paid only. Never paint the returned-taxes total (no live writer).
    local paid = tonumber(stats.totalTaxesPaid) or 0
    setText(findDescendant(container, "rfFwLine6"), labeled(tr("tax_rf_pda_lbl_paid", "Lifetime paid"), formatMoney(paid)))

    -- Line 7: companion ledger credit/debit summary for current farm (honest empty if farm absent).
    local ledgerLbl = tr("tax_rf_pda_lbl_ledger", "Companion ledger")
    local farmLedger = nil
    local ledgerFarms = tax.ledger and tax.ledger.farms
    if ledgerFarms ~= nil and farmId ~= nil then
        farmLedger = ledgerFarms[farmId]
    end
    if farmLedger == nil then
        setText(findDescendant(container, "rfFwLine7"),
            labeled(ledgerLbl, tr("tax_rf_pda_ledger_none", "none yet")))
    else
        local credit = tonumber(farmLedger.creditTotal) or 0
        local debit = tonumber(farmLedger.debitTotal) or 0
        local pair = string.format("+%s / -%s", formatMoney(credit), formatMoney(debit))
        setText(findDescendant(container, "rfFwLine7"), labeled(ledgerLbl, pair))
    end

    -- Line 8: days taxed (0 is honest empty, not an error).
    local daysTaxed = tonumber(stats.daysTaxed) or 0
    setText(findDescendant(container, "rfFwLine8"),
        labeled(tr("tax_rf_pda_lbl_days", "Days taxed"), tostring(daysTaxed)))

    -- Hint: daily rate · March rate · min balance (distinct labels; never conflate).
    local rateKey = tostring(settings.taxRate or "medium")
    local dailyPct = (TAX_RATE_VALUES[rateKey] or 0.02) * 100
    local marchPct = annualRate * 100
    local minBal = tonumber(settings.minimumBalance) or 0
    local hint = string.format("%s: %s (%.0f%%) · %s: %.0f%% · %s: %s",
        tr("tax_rf_pda_lbl_daily_rate", "Daily rate"), rateKey, dailyPct,
        tr("tax_rf_pda_lbl_annual_rate", "March rate"), marchPct,
        tr("tax_rf_pda_lbl_min_balance", "Min balance"), formatMoney(minBal))
    setText(findDescendant(container, "rfFwHint"), hint)
end

--- Hand the Status shell back on the XML locks. Status is tax-only today (host maps
--- isFwStatus = "tax") and no host calls onHide, so this is correct-when-wired rather than
--- live; it stays because the day status is shared is the day it matters, and onShow now
--- re-asserts the same locks anyway.
function TaxRfPdaGuest.onHide(container)
    restoreStatusBand(container)
end

--- BUILD 19:15: the Esc Help footer asks whichever module is showing to open its own guide, so
--- every companion ships and owns its own help instead of borrowing Soil's.
---@param container table|nil
function TaxRfPdaGuest.onOpenHelp(container)
    if TaxGuideDialog ~= nil and type(TaxGuideDialog.show) == "function" then
        TaxGuideDialog.show()
    end
end

function TaxRfPdaGuest.tryRegister()
    if RfEscBootstrap ~= nil then
        if MOD_DIR == nil then
            print("[Tax] TaxRfPdaGuest: WARNING MOD_DIR nil - cannot ensureDoor")
        else
            local doorOk = RfEscBootstrap.ensureDoor(MOD_DIR, {
                profilesXml = MOD_DIR .. "xml/gui/rfEscProfiles.xml",
                iconPath = "textures/ui/menuIcon.dds",
            })
            -- BUILD 19:15 (George CLOSED DESIGN 18:55 item 5): load this mod's Field Guide at the
            -- same moment the door itself loads. A GUI loaded from a mod directory later, once the
            -- mod's own file system context has closed, fails to open.
            if TaxGuideDialog ~= nil and type(TaxGuideDialog.register) == "function" then
                pcall(TaxGuideDialog.register, MOD_DIR)
            end
            if not doorOk then print("[Tax] TaxRfPdaGuest: WARNING ensureDoor failed (will retry)") end
        end
    end
    local host = getHost()
    local registerFn = host and (host.registerModule or host.registerPanel)
    if host == nil or registerFn == nil then return false end
    if not _registered then
        local ok = registerFn(host, {
            id = PANEL_ID,
            title = tr("tax_rf_pda_module_title", "Tax"),
            blurb = tr("tax_rf_pda_blurb", "Tax posture glance: on/off, bill, March, balance share, countdown, lifetime paid, ledger summary."),
            order = PANEL_ORDER,
            isAvailable = function() return getTax() ~= nil end,
            onShow = TaxRfPdaGuest.onShow,
            onHide = TaxRfPdaGuest.onHide,
            onOpenHelp = TaxRfPdaGuest.onOpenHelp,
        })
        if ok then
            _registered = true
            print("[Tax] TaxRfPdaGuest: registered module tax on rfEscModules")
        else
            return false
        end
    end
    return _registered and g_inGameMenu ~= nil and g_inGameMenu.menuRealisticFarming ~= nil
end

function TaxRfPdaGuest.isRegistered() return _registered end
function TaxRfPdaGuest.reset() _registered = false end

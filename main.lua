-- =========================================================
-- FS25 Tax Mod (version 1.1.3.0)
-- =========================================================
-- Annual tax cycle: daily accumulation, March payment,
-- December advisory, configurable rates.
-- =========================================================
-- Author: TisonK
-- =========================================================

-- Hot-reload latch (FuelCosts reference): g_currentModDirectory and
-- g_currentModName are nil on a live re-source, so they are latched into
-- module globals on first load, with a g_modsDirectory loose-folder fallback.
TaxModModDirectory = TaxModModDirectory
    or g_currentModDirectory
    or (g_modsDirectory ~= nil and (g_modsDirectory .. "FS25_TaxMod/") or nil)
TaxModModName = TaxModModName or g_currentModName or "FS25_TaxMod"
local modDirectory = TaxModModDirectory
local modName = TaxModModName

source(modDirectory .. "src/integrations/OptionScalingResolver.lua")
source(modDirectory .. "src/settings/UIHelper.lua")
source(modDirectory .. "src/settings/SettingsUI.lua")
source(modDirectory .. "src/ui/TaxHUD.lua")
source(modDirectory .. "src/settings/SettingsHubBridge.lua")
source(modDirectory .. "src/integrations/TaxStateLedgerBridge.lua")  -- bedrock: optional StateLedger state bridge
source(modDirectory .. "src/integrations/TaxMasterHUDBridge.lua")    -- bedrock: optional MasterHUD draw bridge
source(modDirectory .. "src/integrations/CropStressIrrigationExpense.lua")  -- SCS-011: mirror SCS irrigation operating cost as a deductible expense

-- Esc RF PDA framework joiner (NO-HOST).
source((TaxModModDirectory or g_currentModDirectory) .. "src/gui/RfEscModules.lua")
source((TaxModModDirectory or g_currentModDirectory) .. "src/gui/RfPdaMenuPage.lua")
source((TaxModModDirectory or g_currentModDirectory) .. "src/gui/RfEscBootstrap.lua")
source((TaxModModDirectory or g_currentModDirectory) .. "src/gui/RfEscUiDebugger.lua")
source((TaxModModDirectory or g_currentModDirectory) .. "src/gui/TaxGuideDialog.lua")
source((TaxModModDirectory or g_currentModDirectory) .. "src/gui/TaxRfPdaGuest.lua")

FS25TaxMod = FS25TaxMod or {}
FS25TaxMod.modDir  = modDirectory
FS25TaxMod.modName = modName
FS25TaxMod.version = "1.1.5.12"
FS25TaxMod.Debug   = false

local settings = {
    enabled          = true,
    taxRate          = "medium",
    returnPercentage = 20,
    minimumBalance   = 1000,
    showNotification = true,
    showStatistics   = true,
    showHUD          = true,
    debugLevel       = 1,
    annualTaxRate    = 0.05 -- New annual tax rate
}
FS25TaxMod.settings = settings

local TAX_RATE_VALUES = { low = 0.01, medium = 0.02, high = 0.03 }

FS25TaxMod.SPINE_DAILY_TAX = {
    id   = "tm_dailyTaxRate",
    dial = "economy",
    base = 1.0,
}

FS25TaxMod.SPINE_ANNUAL_TAX = {
    id   = "tm_annualTaxRate",
    dial = "economy",
    base = 1.0,
}

local stats = {
    totalTaxesPaid        = 0, totalTaxesReturned = 0,
    taxesThisMonth        = 0, daysTaxed = 0, monthsReturned = 0,
    taxesAccumulatedAnnual= 0, -- New: Accumulated taxes for the current year
    lastTaxYear           = 0, -- New: The year for which taxes were last paid
    taxReturnMonth        = 3, -- New: Month (1-12) when annual taxes are paid (e.g., March)
    taxAdvisoryMonth      = 12, -- New: Month (1-12) when tax advisory appears (e.g., December)
    farmTax               = {}, -- Per-farm accrual (dedicated-safe; never key billing on getFarmId alone)
}
FS25TaxMod.stats = stats

-- Companion ledger: tracked money adjustments recorded by other mods via
-- g_TaxManager.recordExpense(). Pure bookkeeping, surfaced in stats/HUD.
-- It never moves money and never enters any tax computation.
local LEDGER_MAX_ENTRIES = 10
local ledger = { farms = {} }
FS25TaxMod.ledger = ledger

local lastDay = -1
local lastMonth = -1
local lastMinuteCheck = -1
local isInitialized = false
local infoNotificationTimer = nil
local taxHUD = nil
local taxSettingsUI = nil

local function log(msg, level)
    level = level or 1
    if settings.debugLevel >= level then
        print("[" .. modName .. "] " .. tostring(msg))
    end
end

local function formatMoney(amount)
    if g_i18n and g_i18n.formatMoney then
        return g_i18n:formatMoney(amount, 0, true, true)
    end
    return "$" .. tostring(amount)
end

local function _spineScale(decl)
    if OptionScalingResolver == nil then return 1.0 end
    local hub = (g_currentMission ~= nil and g_currentMission.settingsHub) or g_settingsHub
    local profile = OptionScalingResolver.readProfile(hub)
    if profile == nil then return 1.0 end
    return OptionScalingResolver.resolve(decl, profile)
end

local function getTaxRate()
    local base = TAX_RATE_VALUES[settings.taxRate] or 0.02
    return base * _spineScale(FS25TaxMod.SPINE_DAILY_TAX)
end

local function getAnnualTaxRate()
    return (settings.annualTaxRate or 0.05) * _spineScale(FS25TaxMod.SPINE_ANNUAL_TAX)
end

-- Real farm ids only (reject spectator / guided tour / invalid). Same shape as DairyCore F75.
local function _isRealFarmId(farmId)
    if type(farmId) ~= "number" or farmId <= 0 then return false end
    local fm = FarmManager
    local spectator = (fm ~= nil and fm.SPECTATOR_FARM_ID) or 0
    local tour      = (fm ~= nil and fm.GUIDED_TOUR_FARM_ID) or 14
    local invalid   = (fm ~= nil and fm.INVALID_FARM_ID) or 15
    return farmId ~= spectator and farmId ~= tour and farmId ~= invalid
end

-- Dedicated: getFarmId() is nil. Never use it as the only billing authority key.
-- Iterate real farms from FarmManager; local-farm fallback only when the list is empty.
local function _farmIdsToScan()
    local ids, seen = {}, {}
    pcall(function()
        local fm = g_farmManager
        if fm == nil or fm.getFarms == nil then return end
        for _, farm in pairs(fm:getFarms() or {}) do
            local id = farm ~= nil and farm.farmId or nil
            if id ~= nil and not seen[id] and _isRealFarmId(id) then
                seen[id] = true
                ids[#ids + 1] = id
            end
        end
    end)
    if #ids > 0 then return ids end
    local localId = nil
    pcall(function()
        if g_currentMission ~= nil and g_currentMission.getFarmId ~= nil then
            localId = g_currentMission:getFarmId()
        end
    end)
    if _isRealFarmId(localId) then return { localId } end
    return {}
end

-- Per-farm annual accrual (dedicated-safe). Global stats.* mirror remains for HUD/console.
local function _ensureFarmTax(farmId)
    if stats.farmTax == nil then
        stats.farmTax = {}
    end
    local ft = stats.farmTax[farmId]
    if ft == nil then
        ft = { taxesAccumulatedAnnual = 0, daysTaxed = 0, lastTaxYear = 0 }
        stats.farmTax[farmId] = ft
    end
    return ft
end

-- Seed legacy single-bucket accrual into per-farm on first multi-farm pass.
local function _migrateLegacyAccrual()
    if stats.farmTax == nil then
        stats.farmTax = {}
    end
    if next(stats.farmTax) ~= nil then return end
    local acc = stats.taxesAccumulatedAnnual or 0
    local days = stats.daysTaxed or 0
    local year = stats.lastTaxYear or 0
    if acc <= 0 and days <= 0 and year <= 0 then return end
    local ids = _farmIdsToScan()
    local seedId = ids[1]
    if seedId == nil then return end
    stats.farmTax[seedId] = {
        taxesAccumulatedAnnual = acc,
        daysTaxed = days,
        lastTaxYear = year,
    }
end

local function getSettingsPath()
    if g_currentMission and g_currentMission.missionInfo
       and g_currentMission.missionInfo.savegameDirectory then
        return g_currentMission.missionInfo.savegameDirectory .. "/modSettings/FS25_TaxMod.xml"
    end
end

local function saveSettings()
    local path = getSettingsPath()
    if not path then return end
    local xmlFile = createXMLFile("taxSettings", path, "settings")
    if xmlFile == 0 then return end
    setXMLBool(xmlFile,   "settings.enabled",          settings.enabled)
    setXMLString(xmlFile, "settings.taxRate",           settings.taxRate)
    setXMLInt(xmlFile,    "settings.returnPercentage",  settings.returnPercentage)
    setXMLInt(xmlFile,    "settings.minimumBalance",    settings.minimumBalance)
    setXMLBool(xmlFile,   "settings.showNotification",  settings.showNotification)
    setXMLBool(xmlFile,   "settings.showStatistics",    settings.showStatistics)
    setXMLBool(xmlFile,   "settings.showHUD",           settings.showHUD)
    setXMLInt(xmlFile,    "settings.debugLevel",        settings.debugLevel)
    setXMLFloat(xmlFile,  "settings.annualTaxRate",     settings.annualTaxRate)
    setXMLInt(xmlFile, "settings.stats.totalTaxesPaid",     stats.totalTaxesPaid     or 0)
    setXMLInt(xmlFile, "settings.stats.totalTaxesReturned", stats.totalTaxesReturned or 0)
    setXMLInt(xmlFile, "settings.stats.taxesThisMonth",     stats.taxesThisMonth     or 0)
    setXMLInt(xmlFile, "settings.stats.daysTaxed",          stats.daysTaxed          or 0)
    setXMLInt(xmlFile, "settings.stats.monthsReturned",     stats.monthsReturned     or 0)
    setXMLInt(xmlFile, "settings.stats.taxesAccumulatedAnnual", stats.taxesAccumulatedAnnual or 0) -- New
    setXMLInt(xmlFile, "settings.stats.lastTaxYear",        stats.lastTaxYear        or 0) -- New
    setXMLInt(xmlFile, "settings.lastDay",   tonumber(lastDay)   or 1)
    setXMLInt(xmlFile, "settings.lastMonth", tonumber(lastMonth) or 1)
    local farmTaxIndex = 0
    if type(stats.farmTax) == "table" then
        for farmId, ft in pairs(stats.farmTax) do
            local key = string.format("settings.farmTax.farm(%d)", farmTaxIndex)
            setXMLInt(xmlFile, key .. "#farmId", farmId)
            setXMLInt(xmlFile, key .. "#accumulated", ft.taxesAccumulatedAnnual or 0)
            setXMLInt(xmlFile, key .. "#daysTaxed", ft.daysTaxed or 0)
            setXMLInt(xmlFile, key .. "#lastTaxYear", ft.lastTaxYear or 0)
            farmTaxIndex = farmTaxIndex + 1
        end
    end
    local farmIndex = 0
    for farmId, farmLedger in pairs(ledger.farms) do
        local farmKey = string.format("settings.ledger.farm(%d)", farmIndex)
        setXMLInt(xmlFile,   farmKey .. "#farmId",      farmId)
        setXMLFloat(xmlFile, farmKey .. "#creditTotal", farmLedger.creditTotal or 0)
        setXMLFloat(xmlFile, farmKey .. "#debitTotal",  farmLedger.debitTotal  or 0)
        farmIndex = farmIndex + 1
    end
    saveXMLFile(xmlFile)
    delete(xmlFile)
end

-- Expose for SettingsUI (which cannot see local functions from other files)
function FS25TaxMod:saveSettings()
    saveSettings()
end

local function loadSettings()
    local path = getSettingsPath()
    if not path or not fileExists(path) then return end
    local xmlFile = loadXMLFile("taxSettings", path)
    if xmlFile == 0 then return end
    settings.enabled          = Utils.getNoNil(getXMLBool(xmlFile,   "settings.enabled"),          settings.enabled)
    settings.taxRate          = Utils.getNoNil(getXMLString(xmlFile, "settings.taxRate"),           settings.taxRate)
    settings.returnPercentage = Utils.getNoNil(getXMLInt(xmlFile,    "settings.returnPercentage"),  settings.returnPercentage)
    settings.minimumBalance   = Utils.getNoNil(getXMLInt(xmlFile,    "settings.minimumBalance"),    settings.minimumBalance)
    settings.showNotification = Utils.getNoNil(getXMLBool(xmlFile,   "settings.showNotification"),  settings.showNotification)
    settings.showStatistics   = Utils.getNoNil(getXMLBool(xmlFile,   "settings.showStatistics"),    settings.showStatistics)
    settings.showHUD          = Utils.getNoNil(getXMLBool(xmlFile,   "settings.showHUD"),           settings.showHUD)
    settings.debugLevel       = Utils.getNoNil(getXMLInt(xmlFile,    "settings.debugLevel"),        settings.debugLevel)
    settings.annualTaxRate    = Utils.getNoNil(getXMLFloat(xmlFile,  "settings.annualTaxRate"),      settings.annualTaxRate)
    stats.totalTaxesPaid     = Utils.getNoNil(getXMLInt(xmlFile, "settings.stats.totalTaxesPaid"),     0)
    stats.totalTaxesReturned = Utils.getNoNil(getXMLInt(xmlFile, "settings.stats.totalTaxesReturned"), 0)
    stats.taxesThisMonth     = Utils.getNoNil(getXMLInt(xmlFile, "settings.stats.taxesThisMonth"),     0)
    stats.daysTaxed          = Utils.getNoNil(getXMLInt(xmlFile, "settings.stats.daysTaxed"),          0)
    stats.monthsReturned     = Utils.getNoNil(getXMLInt(xmlFile, "settings.stats.monthsReturned"),     0)
    stats.taxesAccumulatedAnnual = Utils.getNoNil(getXMLInt(xmlFile, "settings.stats.taxesAccumulatedAnnual"), 0) -- New
    stats.lastTaxYear        = Utils.getNoNil(getXMLInt(xmlFile, "settings.stats.lastTaxYear"),        0) -- New
    lastDay   = Utils.getNoNil(getXMLInt(xmlFile, "settings.lastDay"),   lastDay)
    lastMonth = Utils.getNoNil(getXMLInt(xmlFile, "settings.lastMonth"), lastMonth)
    stats.farmTax = {}
    local farmTaxIndex = 0
    while true do
        local key = string.format("settings.farmTax.farm(%d)", farmTaxIndex)
        local farmId = getXMLInt(xmlFile, key .. "#farmId")
        if farmId == nil then break end
        stats.farmTax[farmId] = {
            taxesAccumulatedAnnual = Utils.getNoNil(getXMLInt(xmlFile, key .. "#accumulated"), 0),
            daysTaxed = Utils.getNoNil(getXMLInt(xmlFile, key .. "#daysTaxed"), 0),
            lastTaxYear = Utils.getNoNil(getXMLInt(xmlFile, key .. "#lastTaxYear"), 0),
        }
        farmTaxIndex = farmTaxIndex + 1
    end
    ledger.farms = {}
    local farmIndex = 0
    while true do
        local farmKey = string.format("settings.ledger.farm(%d)", farmIndex)
        local farmId = getXMLInt(xmlFile, farmKey .. "#farmId")
        if farmId == nil then break end
        ledger.farms[farmId] = {
            creditTotal = Utils.getNoNil(getXMLFloat(xmlFile, farmKey .. "#creditTotal"), 0),
            debitTotal  = Utils.getNoNil(getXMLFloat(xmlFile, farmKey .. "#debitTotal"),  0),
            entries     = {},
        }
        farmIndex = farmIndex + 1
    end
    delete(xmlFile)
    log("Settings loaded", 2)
end

-- =====================
-- STATE SERIALIZATION (StateLedger bridge)
-- =====================
-- serializeState/applyState are the in-memory twins of the state portion of
-- saveSettings/loadSettings (stats + the recordExpense ledger + the day/month
-- cursors). They carry STATE only, never settings (SettingsHub owns those).
-- The own XML stays the standalone safety copy; these feed the optional
-- StateLedger module TaxMod_Data when bedrock is present. Plain-table in/out so
-- StateLedger's generic serializer can round-trip them (number keys included).

function FS25TaxMod.serializeState()
    local farms = {}
    for farmId, fl in pairs(ledger.farms) do
        local entries = {}
        if type(fl.entries) == "table" then
            for i, e in ipairs(fl.entries) do
                entries[i] = { amount = e.amount, label = e.label, day = e.day, month = e.month }
            end
        end
        farms[farmId] = {
            creditTotal = fl.creditTotal or 0,
            debitTotal  = fl.debitTotal  or 0,
            entries     = entries,
        }
    end
    local farmTax = {}
    if type(stats.farmTax) == "table" then
        for farmId, ft in pairs(stats.farmTax) do
            farmTax[farmId] = {
                taxesAccumulatedAnnual = ft.taxesAccumulatedAnnual or 0,
                daysTaxed = ft.daysTaxed or 0,
                lastTaxYear = ft.lastTaxYear or 0,
            }
        end
    end
    return {
        version = 2,
        stats = {
            totalTaxesPaid         = stats.totalTaxesPaid         or 0,
            totalTaxesReturned     = stats.totalTaxesReturned     or 0,
            taxesThisMonth         = stats.taxesThisMonth         or 0,
            daysTaxed              = stats.daysTaxed              or 0,
            monthsReturned         = stats.monthsReturned         or 0,
            taxesAccumulatedAnnual = stats.taxesAccumulatedAnnual or 0,
            lastTaxYear            = stats.lastTaxYear            or 0,
            farmTax                = farmTax,
        },
        lastDay   = lastDay,
        lastMonth = lastMonth,
        ledger    = { farms = farms },
    }
end

function FS25TaxMod.applyState(data)
    if type(data) ~= "table" then return false end

    local st = data.stats
    if type(st) == "table" then
        stats.totalTaxesPaid         = tonumber(st.totalTaxesPaid)         or stats.totalTaxesPaid         or 0
        stats.totalTaxesReturned     = tonumber(st.totalTaxesReturned)     or stats.totalTaxesReturned     or 0
        stats.taxesThisMonth         = tonumber(st.taxesThisMonth)         or stats.taxesThisMonth         or 0
        stats.daysTaxed              = tonumber(st.daysTaxed)              or stats.daysTaxed              or 0
        stats.monthsReturned         = tonumber(st.monthsReturned)         or stats.monthsReturned         or 0
        stats.taxesAccumulatedAnnual = tonumber(st.taxesAccumulatedAnnual) or stats.taxesAccumulatedAnnual or 0
        stats.lastTaxYear            = tonumber(st.lastTaxYear)            or stats.lastTaxYear            or 0
        if type(st.farmTax) == "table" then
            stats.farmTax = {}
            for farmId, ft in pairs(st.farmTax) do
                local fid = tonumber(farmId)
                if fid ~= nil and type(ft) == "table" then
                    stats.farmTax[fid] = {
                        taxesAccumulatedAnnual = tonumber(ft.taxesAccumulatedAnnual) or 0,
                        daysTaxed = tonumber(ft.daysTaxed) or 0,
                        lastTaxYear = tonumber(ft.lastTaxYear) or 0,
                    }
                end
            end
        end
    end

    if data.lastDay   ~= nil then lastDay   = tonumber(data.lastDay)   or lastDay   end
    if data.lastMonth ~= nil then lastMonth = tonumber(data.lastMonth) or lastMonth end

    -- Rebuild ledger.farms IN PLACE so the table identity FS25TaxMod.ledger (and
    -- the HUD) already holds stays valid.
    for k in pairs(ledger.farms) do ledger.farms[k] = nil end
    local df = data.ledger and data.ledger.farms
    if type(df) == "table" then
        for farmId, fl in pairs(df) do
            local fid = tonumber(farmId)
            if fid ~= nil and type(fl) == "table" then
                local entries = {}
                if type(fl.entries) == "table" then
                    for _, e in ipairs(fl.entries) do
                        if type(e) == "table" then
                            entries[#entries + 1] = {
                                amount = tonumber(e.amount) or 0,
                                label  = tostring(e.label or ""),
                                day    = tonumber(e.day)   or 0,
                                month  = tonumber(e.month) or 0,
                            }
                        end
                    end
                end
                ledger.farms[fid] = {
                    creditTotal = tonumber(fl.creditTotal) or 0,
                    debitTotal  = tonumber(fl.debitTotal)  or 0,
                    entries     = entries,
                }
            end
        end
    end

    return true
end

local function applyDailyTax()
    if not settings.enabled or not g_currentMission then return end
    _migrateLegacyAccrual()
    local farmIds = _farmIdsToScan()
    if #farmIds == 0 then
        log("applyDailyTax: no real farms to bill (dedicated-safe fail-closed)", 2)
        return
    end

    local localFarmId = nil
    pcall(function()
        if g_currentMission.getFarmId ~= nil then
            localFarmId = g_currentMission:getFarmId()
        end
    end)

    local anyAccrued = 0
    for _, farmId in ipairs(farmIds) do
        local farm = g_farmManager and g_farmManager:getFarmById(farmId)
        if farm ~= nil and farm.money ~= nil and farm.money >= settings.minimumBalance then
            local taxAmount = math.floor(farm.money * getTaxRate())
            if taxAmount > 0 then
                local ft = _ensureFarmTax(farmId)
                ft.taxesAccumulatedAnnual = (ft.taxesAccumulatedAnnual or 0) + taxAmount
                ft.daysTaxed = (ft.daysTaxed or 0) + 1
                anyAccrued = anyAccrued + taxAmount

                -- Mirror local farm into global stats for existing HUD/console surfaces.
                if localFarmId ~= nil and farmId == localFarmId then
                    stats.taxesAccumulatedAnnual = ft.taxesAccumulatedAnnual
                    stats.daysTaxed = (stats.daysTaxed or 0) + 1
                    if taxHUD then
                        local env = g_currentMission.environment
                        taxHUD:recordTax(taxAmount, env and env.currentDay or 0, env and env.currentMonth or 0, false)
                    end
                    if settings.showNotification then
                        g_currentMission:addIngameNotification({1.0, 0.5, 0.0, 1.0},
                            string.format("Daily tax accumulated: %s", formatMoney(taxAmount)))
                    end
                end
            end
        end
    end

    -- Dedicated / no local farm: keep a global mirror as the sum so console stats stay non-zero.
    if localFarmId == nil and anyAccrued > 0 then
        local sum = 0
        for _, ft in pairs(stats.farmTax or {}) do
            sum = sum + (ft.taxesAccumulatedAnnual or 0)
        end
        stats.taxesAccumulatedAnnual = sum
        stats.daysTaxed = (stats.daysTaxed or 0) + 1
    end
end

local function applyMonthlyReturn()
    -- This function is being replaced by annual tax logic.
    -- The content will be empty or removed.
    stats.taxesThisMonth = 0
    saveSettings()
end

local function applyAnnualTax()
    if not settings.enabled or not g_currentMission then return end
    _migrateLegacyAccrual()
    local farmIds = _farmIdsToScan()
    if #farmIds == 0 then
        log("applyAnnualTax: no real farms to bill (dedicated-safe fail-closed)", 2)
        return
    end

    local currentYear = g_currentMission.environment.currentYear
    local isServer = g_currentMission:getIsServer()
    local localFarmId = nil
    pcall(function()
        if g_currentMission.getFarmId ~= nil then
            localFarmId = g_currentMission:getFarmId()
        end
    end)

    local anyPaid = false
    for _, farmId in ipairs(farmIds) do
        local ft = _ensureFarmTax(farmId)
        if (ft.lastTaxYear or 0) < currentYear then
            if (ft.taxesAccumulatedAnnual or 0) <= 0 then
                log(string.format("No annual tax accumulated for farm %d. Marking year processed.", farmId), 2)
                ft.lastTaxYear = currentYear
            else
                local taxAmount = math.floor(ft.taxesAccumulatedAnnual * getAnnualTaxRate())
                if taxAmount <= 0 then
                    log(string.format("Calculated annual tax is zero for farm %d. Resetting.", farmId), 2)
                    ft.taxesAccumulatedAnnual = 0
                    ft.lastTaxYear = currentYear
                else
                    -- Only the server may move money; engine syncs balance to clients.
                    -- Explicit farmId — never getFarmId() as dedicated authority.
                    if isServer then
                        g_currentMission:addMoney(-taxAmount, farmId, MoneyType.OTHER, true)
                    end
                    stats.totalTaxesPaid = (stats.totalTaxesPaid or 0) + taxAmount
                    ft.taxesAccumulatedAnnual = 0
                    ft.lastTaxYear = currentYear

                    if localFarmId ~= nil and farmId == localFarmId then
                        stats.taxesAccumulatedAnnual = 0
                        stats.lastTaxYear = currentYear
                        if taxHUD then
                            taxHUD:recordTax(taxAmount, 1, stats.taxReturnMonth, true)
                        end
                        if settings.showNotification then
                            g_currentMission:addIngameNotification({1.0, 0.0, 0.0, 1.0},
                                string.format("Annual tax deducted for %d: -%s", currentYear - 1, formatMoney(taxAmount)))
                        end
                    end
                end
            end
        end
    end

    -- Global lastTaxYear = max across farms so the month gate still fires once per year.
    local maxYear = stats.lastTaxYear or 0
    for _, ft in pairs(stats.farmTax or {}) do
        if (ft.lastTaxYear or 0) > maxYear then
            maxYear = ft.lastTaxYear
        end
    end
    stats.lastTaxYear = maxYear
    if localFarmId == nil then
        stats.taxesAccumulatedAnnual = 0
        for _, ft in pairs(stats.farmTax or {}) do
            stats.taxesAccumulatedAnnual = stats.taxesAccumulatedAnnual + (ft.taxesAccumulatedAnnual or 0)
        end
    end

    saveSettings()
end

local function taxAdvisory()
    if not settings.enabled or not g_currentMission then return end
    _migrateLegacyAccrual()

    local localFarmId = nil
    pcall(function()
        if g_currentMission.getFarmId ~= nil then
            localFarmId = g_currentMission:getFarmId()
        end
    end)

    local accrued = 0
    if _isRealFarmId(localFarmId) then
        local ft = _ensureFarmTax(localFarmId)
        accrued = ft.taxesAccumulatedAnnual or 0
    else
        -- Dedicated: advisory from sum of all real farms (log / notification if enabled).
        for _, ft in pairs(stats.farmTax or {}) do
            accrued = accrued + (ft.taxesAccumulatedAnnual or 0)
        end
    end
    if accrued <= 0 then return end

    local estimatedTax = math.floor(accrued * settings.annualTaxRate)
    local farm = (_isRealFarmId(localFarmId) and g_farmManager) and g_farmManager:getFarmById(localFarmId) or nil
    local balance = farm and farm.money or 0
    local pctOfBalance = balance > 0 and math.floor((estimatedTax / balance) * 100) or 0

    if settings.showNotification and localFarmId ~= nil then
        g_currentMission:addIngameNotification({0.0, 0.5, 1.0, 1.0},
            string.format("Tax Advisory: Est. March payment %s (%d%% of balance). Accumulated: %s",
                formatMoney(estimatedTax), pctOfBalance, formatMoney(accrued)))
    end
    log(string.format("Tax Advisory: Accumulated %s | Annual rate %.0f%% | Est. payment %s (%d%% of balance)",
        formatMoney(accrued), settings.annualTaxRate * 100,
        formatMoney(estimatedTax), pctOfBalance), 1)
end

local function createUpdateable()
    return {
        update = function(dt)
            if not isInitialized or not settings.enabled then return end
            if infoNotificationTimer ~= nil then
                local delta = (type(dt) == "table") and (dt.dt or dt.deltaTime or 0) or dt
                infoNotificationTimer = infoNotificationTimer - delta
                if infoNotificationTimer <= 0 then
                    infoNotificationTimer = nil
                    if settings.showNotification and g_currentMission then
                        g_currentMission:addIngameNotification({1.0, 0.5, 0.0, 1.0},
                            "Tax Mod Active - Type 'tax' in console (~) for settings")
                    end
                end
            end
            if g_currentMission and g_currentMission.environment then
                local currentMinute = math.floor(g_currentMission.environment.dayTime / 60000)
                if currentMinute ~= lastMinuteCheck then
                    lastMinuteCheck = currentMinute
                    local env = g_currentMission.environment
                    local currentYear = env.currentYear or 0

                    -- Daily tax accumulation
                    if env.currentDay ~= lastDay then
                        lastDay = env.currentDay
                        applyDailyTax()
                        -- SCS-011: mirror one day of SCS irrigation operating cost
                        -- into the ledger (read-only, server-only, neutral when SCS
                        -- is absent or costs are off).
                        if CropStressIrrigationExpense then
                            CropStressIrrigationExpense.accrueDaily(FS25TaxMod)
                        end
                    end

                    -- Monthly checks for annual tax events
                    if env.currentMonth ~= lastMonth then
                        lastMonth = env.currentMonth

                        -- December Tax Advisory
                        if lastMonth == stats.taxAdvisoryMonth then
                            taxAdvisory()
                        end

                        -- March Annual Tax Payment (for the previous year)
                        if lastMonth == stats.taxReturnMonth and currentYear > (stats.lastTaxYear or 0) then
                            applyAnnualTax()
                        end
                    end
                end
            end
        end,
        delete = function() log("Tax updateable removed") end
    }
end

-- =====================
-- PUBLIC WRITE API (companion mods)
-- =====================
-- g_TaxManager.recordExpense(farmId, amount, label) -> boolean success
-- Records a tracked money adjustment in the running per-farm credit/debit
-- ledger. Positive amount = credit (money the farm received, e.g. a rebate),
-- negative amount = debit (money the farm paid out, e.g. a wage).
-- Bookkeeping only: it never moves money and never changes any tax
-- computation (TaxMod taxes balance, not income). Callers are expected to be
-- server-side money code; on a non-server peer the call is rejected.
function FS25TaxMod.recordExpense(a, b, c, d)
    -- Tolerate colon-style calls (g_TaxManager:recordExpense(...))
    local farmId, amount, label = a, b, c
    if a == FS25TaxMod then
        farmId, amount, label = b, c, d
    end

    if g_currentMission == nil or not g_currentMission:getIsServer() then
        Logging.warning("[%s] recordExpense: server-only API called on a non-server peer, ignoring", modName)
        return false
    end
    if type(farmId) ~= "number" or farmId <= 0 then
        Logging.warning("[%s] recordExpense: invalid farmId '%s' (positive number expected)", modName, tostring(farmId))
        return false
    end
    if type(amount) ~= "number" or amount ~= amount or amount == math.huge or amount == -math.huge or amount == 0 then
        Logging.warning("[%s] recordExpense: invalid amount '%s' (finite non-zero number expected)", modName, tostring(amount))
        return false
    end
    if label ~= nil and type(label) ~= "string" then
        Logging.warning("[%s] recordExpense: invalid label '%s' (string expected)", modName, tostring(label))
        return false
    end
    label = label or "Companion expense"

    local farmLedger = ledger.farms[farmId]
    if farmLedger == nil then
        farmLedger = { creditTotal = 0, debitTotal = 0, entries = {} }
        ledger.farms[farmId] = farmLedger
    end

    if amount > 0 then
        farmLedger.creditTotal = farmLedger.creditTotal + amount
    else
        farmLedger.debitTotal = farmLedger.debitTotal - amount
    end

    local env = g_currentMission.environment
    table.insert(farmLedger.entries, 1, {
        amount = amount,
        label  = label,
        day    = env and env.currentDay   or 0,
        month  = env and env.currentMonth or 0,
    })
    while #farmLedger.entries > LEDGER_MAX_ENTRIES do
        table.remove(farmLedger.entries)
    end

    log(string.format("recordExpense: farm %d %s%s (%s)", farmId,
        amount > 0 and "+" or "", tostring(amount), label), 2)
    return true
end

-- =====================
-- CONSOLE COMMANDS
-- =====================
function FS25TaxMod:consoleCommandTax()
    print("========================================")
    print("         Tax Mod Commands               ")
    print("========================================")
    print("tax           - Show this help          ")
    print("taxStatus     - Show current settings   ")
    print("taxEnable     - Enable tax system       ")
    print("taxDisable    - Disable tax system      ")
    print("taxRate [low|medium|high]               ")
    print("taxAnnualRate [low|medium|high]         ")
    print("  low=2%  medium=5%  high=10%           ")
    print("taxMinimum [amount]                     ")
    print("taxStatistics - Show tax statistics     ")
    print("taxSimulate   - Simulate tax cycle      ")
    print("taxToggleHUD  - Toggle HUD visibility   ")
    print("taxDebug [0-3] - Set debug level        ")
    print("========================================")
end

function FS25TaxMod:consoleTaxStatus()
    print("=== Tax Mod Status ===")
    print("Enabled:         " .. tostring(settings.enabled))
    print("Tax Rate:        " .. settings.taxRate .. " (" .. (getTaxRate() * 100) .. "%)")
    print("Return %:        " .. settings.returnPercentage .. "%")
    print("Minimum Balance: " .. formatMoney(settings.minimumBalance))
    print("HUD:             " .. tostring(settings.showHUD))
    if g_currentMission and g_currentMission.environment then
        print("Current Day:     " .. (g_currentMission.environment.currentDay or "?"))
        print("Current Month:   " .. (g_currentMission.environment.currentMonth or "?"))
    end
    if settings.showStatistics then self:consoleTaxStatistics() end
end

function FS25TaxMod:consoleTaxEnable()
    settings.enabled = true; saveSettings()
    print("[Tax Mod] Tax system ENABLED")
    if g_currentMission then g_currentMission:addIngameNotification({0.0,1.0,0.0,1.0}, "Tax system ENABLED") end
end

function FS25TaxMod:consoleTaxDisable()
    settings.enabled = false; saveSettings()
    print("[Tax Mod] Tax system DISABLED")
    if g_currentMission then g_currentMission:addIngameNotification({1.0,0.0,0.0,1.0}, "Tax system DISABLED") end
end

function FS25TaxMod:consoleTaxRate(rate)
    if not rate then print("Usage: taxRate low|medium|high") return end
    rate = tostring(rate):lower()
    if rate ~= "low" and rate ~= "medium" and rate ~= "high" then print("Use: low, medium, or high") return end
    settings.taxRate = rate; saveSettings()
    print("[Tax Mod] Tax rate: " .. rate .. " (" .. (getTaxRate()*100) .. "%)")
end

function FS25TaxMod:consoleTaxReturn(pct)
    if not pct then print("Usage: taxReturn [0-100]") return end
    local v = tonumber(pct)
    if not v or v < 0 or v > 100 then print("Must be 0-100") return end
    settings.returnPercentage = v; saveSettings()
    print("[Tax Mod] Return %: " .. v .. "%")
end

function FS25TaxMod:consoleTaxMinimum(amt)
    if not amt then print("Usage: taxMinimum [amount]") return end
    local v = tonumber(amt)
    if not v or v < 0 then print("Must be positive") return end
    settings.minimumBalance = v; saveSettings()
    print("[Tax Mod] Min balance: " .. formatMoney(v))
end

function FS25TaxMod:consoleTaxStatistics()
    print("=== Tax Statistics ===")
    print("Total paid:      " .. formatMoney(stats.totalTaxesPaid))
    print("Total returned:  " .. formatMoney(stats.totalTaxesReturned))
    print("Annual accumulated: " .. formatMoney(stats.taxesAccumulatedAnnual))
    print("Days taxed:      " .. stats.daysTaxed)
    if stats.daysTaxed > 0 then
        print("Avg daily tax:   " .. formatMoney(math.floor(stats.totalTaxesPaid / stats.daysTaxed)))
    end
    print("=== Companion Ledger (recordExpense) ===")
    local farmCount = 0
    for farmId, farmLedger in pairs(ledger.farms) do
        farmCount = farmCount + 1
        print(string.format("Farm %d: credits +%s | debits -%s",
            farmId, formatMoney(farmLedger.creditTotal), formatMoney(farmLedger.debitTotal)))
        for i = 1, math.min(#farmLedger.entries, 3) do
            local entry = farmLedger.entries[i]
            print(string.format("  M%d D%d %s%s (%s)", entry.month, entry.day,
                entry.amount > 0 and "+" or "-", formatMoney(math.abs(entry.amount)), entry.label))
        end
    end
    if farmCount == 0 then
        print("No tracked entries yet")
    end
end

function FS25TaxMod:consoleTaxSimulate()
    if g_currentMission and g_currentMission.environment then
        applyDailyTax(); print("[Tax Mod] Daily tax simulated")
    else print("[Tax Mod] Game not loaded") end
end

function FS25TaxMod:consoleTaxHUD()
    if taxHUD then
        taxHUD:toggleVisibility()
        settings.showHUD = taxHUD.visible
        saveSettings()
    else print("[Tax Mod] HUD not ready") end
end

function FS25TaxMod:consoleTaxAnnualRate(rate)
    if not rate then
        print("Usage: taxAnnualRate low|medium|high|custom")
        print("  low=2%  medium=5%  high=10%  custom=[0.01-0.30]")
        return
    end
    local presets = { low = 0.02, medium = 0.05, high = 0.10 }
    local v = presets[tostring(rate):lower()]
    if not v then v = tonumber(rate) end
    if not v or v < 0.01 or v > 0.30 then
        print("[Tax Mod] Must be low/medium/high or a value between 0.01 and 0.30")
        return
    end
    settings.annualTaxRate = v
    saveSettings()
    print(string.format("[Tax Mod] Annual tax rate set to %.0f%%", v * 100))
end

function FS25TaxMod:consoleTaxDebug(level)
    if not level then print("taxDebug [0-3]"); return end
    local v = tonumber(level)
    if not v or v < 0 or v > 3 then print("Must be 0-3") return end
    settings.debugLevel = v; saveSettings()
    print("[Tax Mod] Debug level: " .. v)
end

-- =====================
-- LIFECYCLE HOOKS
-- =====================

local function onLoad(mission)
    if taxHUD == nil then
        taxHUD = TaxHUD.new(FS25TaxMod)
        FS25TaxMod.taxHUD = taxHUD
        taxSettingsUI = TaxSettingsUI.new(FS25TaxMod)
        FS25TaxMod.taxSettingsUI = taxSettingsUI
        getfenv(0)["g_TaxManager"] = FS25TaxMod
        mission.taxManager = FS25TaxMod
        log("Tax Mod v" .. FS25TaxMod.version .. ": Initialized")
    end

    -- Register T key to toggle HUD via PlayerInputComponent hook (race-condition-safe)
    if mission:getIsClient() and PlayerInputComponent and PlayerInputComponent.registerActionEvents then
        local original = PlayerInputComponent.registerActionEvents
        FS25TaxMod._inputHookOriginal = original
        PlayerInputComponent.registerActionEvents = function(inputComponent, ...)
            original(inputComponent, ...)
            if not (inputComponent.player and inputComponent.player.isOwner) then return end
            if FS25TaxMod.toggleHUDEventId then return end
            if not taxHUD then return end

            g_inputBinding:beginActionEventsModification(PlayerInputComponent.INPUT_CONTEXT_NAME)
            local ok, id = g_inputBinding:registerActionEvent(
                InputAction.TM_TOGGLE_HUD,
                FS25TaxMod,
                FS25TaxMod.onToggleHUDInput,
                false, true, false, true
            )
            if ok and id then
                FS25TaxMod.toggleHUDEventId = id
                g_inputBinding:setActionEventTextPriority(id, GS_PRIO_NORMAL)
                log("HUD toggle registered", 2)
            else
                log("HUD toggle registration failed", 1)
            end

            -- HUD drag (enter/exit edit mode) — PLAYER context
            local dragOk, dragId = g_inputBinding:registerActionEvent(
                InputAction.TM_HUD_DRAG,
                FS25TaxMod,
                FS25TaxMod.onHUDDragInput,
                false, true, false, true
            )
            if dragOk and dragId then
                FS25TaxMod.hudDragEventId = dragId
                g_inputBinding:setActionEventText(dragId, g_i18n:getText("input_TM_HUD_DRAG") or "Tax HUD Edit Mode")
                log("HUD drag registered", 2)
            end

            g_inputBinding:endActionEventsModification()
        end
    end
end

function FS25TaxMod:onHUDDragInput()
    if not taxHUD then return end
    if not taxHUD.visible then return end
    if taxHUD.editMode then
        taxHUD:exitEditMode()
    else
        taxHUD:enterEditMode()
    end
end

function FS25TaxMod:onToggleHUDInput()
    if taxHUD then
        taxHUD:toggleVisibility()
        settings.showHUD = taxHUD.visible
        saveSettings()
    end
end

local function onMissionLoaded(mission, node)
    if mission.cancelLoading then return end
    if isInitialized then return end
    if not (g_currentMission and g_currentMission.missionInfo) then return end

    loadSettings()

    -- Register with SettingsHub (if installed) so FarmTablet's System Settings
    -- app can list Tax Mod's settings. No-ops safely if SettingsHub is absent.
    TaxSettingsHubBridge.register(FS25TaxMod)

    -- Register with StateLedger (if installed) as the state load source of truth.
    -- No-ops safely if StateLedger is absent (own XML stays primary). Runs after
    -- loadSettings so, when the shared ledger is present, it overrides the state
    -- portion imported from the own XML.
    TaxStateLedgerBridge.register(FS25TaxMod)
    if TaxStateLedgerBridge.hasState() then
        TaxStateLedgerBridge.applyState(FS25TaxMod)
    end

    -- Register the tax HUD with MasterHUD (if installed) so it owns the single
    -- suspend-aware draw loop. No-ops safely if MasterHUD is absent; the own
    -- FSBaseMission.draw hook below stands down when this is active.
    TaxMasterHUDBridge.register(FS25TaxMod)

    local env = g_currentMission.environment
    if env then
        lastDay         = tonumber(env.currentDay)   or 1
        lastMonth       = tonumber(env.currentMonth) or 1
        lastMinuteCheck = math.floor((env.dayTime or 0) / 60000)
    end

    if taxHUD then
        taxHUD:loadLayout()
        settings.showHUD = taxHUD.visible  -- sync setting to what was actually saved
    end

    if settings.showNotification then
        infoNotificationTimer = 20000
    end

    local updateable = createUpdateable()
    FS25TaxMod.updateable = updateable
    g_currentMission:addUpdateable(updateable)
    isInitialized = true

    registerConsoleCommands()

    -- Inject settings UI into General Settings page
    if taxSettingsUI then
        taxSettingsUI:inject()
    end

    log(string.format("Tax Mod ready (Day %d, Month %d)", lastDay, lastMonth))
end

local function onUnload()
    if taxHUD then
        if taxHUD.editMode then taxHUD:exitEditMode() end
        taxHUD:saveLayout()
        taxHUD:delete()
        taxHUD = nil
        FS25TaxMod.taxHUD = nil
    end
    taxSettingsUI = nil
    FS25TaxMod.taxSettingsUI = nil
    if FS25TaxMod.updateable and g_currentMission then
        g_currentMission:removeUpdateable(FS25TaxMod.updateable)
    end
    if FS25TaxMod.toggleHUDEventId and g_inputBinding then
        g_inputBinding:removeActionEvent(FS25TaxMod.toggleHUDEventId)
        FS25TaxMod.toggleHUDEventId = nil
    end
    if FS25TaxMod.hudDragEventId and g_inputBinding then
        g_inputBinding:removeActionEvent(FS25TaxMod.hudDragEventId)
        FS25TaxMod.hudDragEventId = nil
    end
    if FS25TaxMod._inputHookOriginal and PlayerInputComponent then
        PlayerInputComponent.registerActionEvents = FS25TaxMod._inputHookOriginal
        FS25TaxMod._inputHookOriginal = nil
    end
    saveSettings()
    isInitialized = false
    getfenv(0)["g_TaxManager"] = nil
    if g_currentMission then g_currentMission.taxManager = nil end
    log("Tax Mod unloaded")
end

Mission00.load                  = Utils.prependedFunction(Mission00.load, onLoad)
Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, onMissionLoaded)
FSBaseMission.delete            = Utils.appendedFunction(FSBaseMission.delete, onUnload)

-- ---------------------------------------------------------
-- Realistic Farming Control Center: publish a runnable delegate.
--
-- MasterHUD owns the physical suite HUD keys, so TM_TOGGLE_HUD stays gated as a
-- native binding. It is surfaced here instead as a Control Center hide/show
-- button: the # key hides the whole suite at once, this toggles only the Tax HUD,
-- so a player can disable just this mod. TaxHUD:draw honours taxHUD.visible under
-- both the MasterHUD bridge and the standalone hook. Live "Hide"/"Show" caption.
-- ---------------------------------------------------------
local function registerControlCenterActions()
    local registry = g_currentMission ~= nil and g_currentMission.rfActionRegistry or nil
    if registry == nil then return end

    registry.registerAction({
        action = "TM_TOGGLE_HUD",
        button = function()
            local hud = FS25TaxMod ~= nil and FS25TaxMod.taxHUD or nil
            return (hud ~= nil and hud.visible) and "Hide" or "Show"
        end,
        run = function()
            local hud = FS25TaxMod ~= nil and FS25TaxMod.taxHUD or nil
            if hud ~= nil and hud.toggleVisibility ~= nil then
                hud:toggleVisibility()
                return hud.visible and "Tax HUD shown" or "Tax HUD hidden"
            end
        end,
    })
end

Mission00.loadMission00Finished = Utils.appendedFunction(
    Mission00.loadMission00Finished, registerControlCenterActions)

FSBaseMission.update = Utils.appendedFunction(FSBaseMission.update, function(mission, dt)
    if taxHUD then taxHUD:update(dt) end
end)

-- When MasterHUD is present it drives TaxMasterHUDBridge.drawStack in its own
-- suspend-aware loop, so this fallback hook stands down to avoid a double draw.
-- The draw body (the taxHUD + settings.showHUD guard) lives in drawStack so the
-- two paths can never diverge.
FSBaseMission.draw = Utils.appendedFunction(FSBaseMission.draw, function(mission)
    if TaxMasterHUDBridge and TaxMasterHUDBridge.active then return end
    if TaxMasterHUDBridge then
        TaxMasterHUDBridge.drawStack()
    elseif taxHUD and settings.showHUD then
        taxHUD:draw()
    end
end)

Mission00.saveToXMLFile = Utils.appendedFunction(Mission00.saveToXMLFile, function(mission, xmlFilename)
    saveSettings()
    if taxHUD then taxHUD:saveLayout() end
end)

local taxMouseHandler = {}
function taxMouseHandler:mouseEvent(posX, posY, isDown, isUp, button, eventUsed)
    if not eventUsed and taxHUD then
        eventUsed = taxHUD:onMouseEvent(posX, posY, isDown, isUp, button, eventUsed) or eventUsed
    end
    return eventUsed
end
addModEventListener(taxMouseHandler)

function registerConsoleCommands()
    addConsoleCommand("tax",           "Show tax mod help",      "consoleCommandTax",    FS25TaxMod)
    addConsoleCommand("taxStatus",     "Show tax settings",      "consoleTaxStatus",     FS25TaxMod)
    addConsoleCommand("taxEnable",     "Enable tax system",      "consoleTaxEnable",     FS25TaxMod)
    addConsoleCommand("taxDisable",    "Disable tax system",     "consoleTaxDisable",    FS25TaxMod)
    addConsoleCommand("taxRate",        "Set daily tax rate",       "consoleTaxRate",       FS25TaxMod)
    addConsoleCommand("taxAnnualRate",  "Set annual payment rate",  "consoleTaxAnnualRate", FS25TaxMod)
    addConsoleCommand("taxMinimum",    "Set minimum balance",    "consoleTaxMinimum",    FS25TaxMod)
    addConsoleCommand("taxStatistics", "Show tax statistics",    "consoleTaxStatistics", FS25TaxMod)
    addConsoleCommand("taxSimulate",   "Simulate tax cycle",     "consoleTaxSimulate",   FS25TaxMod)
    addConsoleCommand("taxHUD",        "Toggle HUD visibility",  "consoleTaxHUD",        FS25TaxMod)
    addConsoleCommand("taxDebug",      "Set debug level",        "consoleTaxDebug",      FS25TaxMod)
end

function tax()           FS25TaxMod:consoleCommandTax()    end
function taxStatus()     FS25TaxMod:consoleTaxStatus()     end
function taxEnable()     FS25TaxMod:consoleTaxEnable()     end
function taxDisable()    FS25TaxMod:consoleTaxDisable()    end
function taxRate(r)          FS25TaxMod:consoleTaxRate(r)          end
function taxAnnualRate(r)    FS25TaxMod:consoleTaxAnnualRate(r)    end
function taxMinimum(a)   FS25TaxMod:consoleTaxMinimum(a)   end
function taxStatistics() FS25TaxMod:consoleTaxStatistics() end
function taxSimulate()    FS25TaxMod:consoleTaxSimulate()   end
function taxToggleHUD()   FS25TaxMod:consoleTaxHUD()        end
function taxDebug(l)      FS25TaxMod:consoleTaxDebug(l)     end

print("========================================")
print("     FS25 Tax Mod v1.1.2.0 LOADED      ")
print("     Author: TisonK                     ")
print("     Type 'tax' in console for help     ")
print("========================================")


local function _rfEscTryRegister()
    if TaxRfPdaGuest ~= nil and type(TaxRfPdaGuest.tryRegister) == "function" then
        pcall(TaxRfPdaGuest.tryRegister)
    end
end

-- Esc RF PDA: register module after mission/door ready (retry-safe).
if Mission00 ~= nil then
    Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, function()
        _rfEscTryRegister()
    end)
end
if FSBaseMission ~= nil then
    FSBaseMission.onStartMission = Utils.appendedFunction(FSBaseMission.onStartMission, function()
        _rfEscTryRegister()
    end)
end

if FSBaseMission ~= nil then
    FSBaseMission.delete = Utils.appendedFunction(FSBaseMission.delete, function()
        if TaxRfPdaGuest ~= nil and type(TaxRfPdaGuest.reset) == "function" then
            TaxRfPdaGuest.reset()
        end
    end)
end

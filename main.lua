-- =========================================================
-- FS25 Tax Mod (version 1.1.3.0)
-- =========================================================
-- Annual tax cycle: daily accumulation, March payment,
-- December advisory, configurable rates.
-- =========================================================
-- Author: TisonK
-- =========================================================

local modDirectory = g_currentModDirectory
local modName      = g_currentModName

source(modDirectory .. "src/settings/UIHelper.lua")
source(modDirectory .. "src/settings/SettingsUI.lua")
source(modDirectory .. "src/ui/TaxHUD.lua")

FS25TaxMod = {}
FS25TaxMod.modDir  = modDirectory
FS25TaxMod.modName = modName
FS25TaxMod.version = "1.1.3.0"
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

local stats = {
    totalTaxesPaid        = 0, totalTaxesReturned = 0,
    taxesThisMonth        = 0, daysTaxed = 0, monthsReturned = 0,
    taxesAccumulatedAnnual= 0, -- New: Accumulated taxes for the current year
    lastTaxYear           = 0, -- New: The year for which taxes were last paid
    taxReturnMonth        = 3, -- New: Month (1-12) when annual taxes are paid (e.g., March)
    taxAdvisoryMonth      = 12 -- New: Month (1-12) when tax advisory appears (e.g., December)
}
FS25TaxMod.stats = stats

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

local function getTaxRate()
    return TAX_RATE_VALUES[settings.taxRate] or 0.02
end

local function getSettingsPath()
    if g_currentMission and g_currentMission.missionInfo then
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
    delete(xmlFile)
    log("Settings loaded", 2)
end

local function applyDailyTax()
    if not settings.enabled or not g_currentMission then return end
    local farmId = g_currentMission:getFarmId()
    if not farmId then return end
    local farm = g_farmManager:getFarmById(farmId)
    if not farm then return end
    if farm.money < settings.minimumBalance then return end
    local taxAmount = math.floor(farm.money * getTaxRate())
    if taxAmount <= 0 then return end
    stats.taxesAccumulatedAnnual = stats.taxesAccumulatedAnnual + taxAmount -- Accumulate (not yet deducted)
    stats.daysTaxed = stats.daysTaxed + 1
    if taxHUD then
        local env = g_currentMission.environment
        taxHUD:recordTax(taxAmount, env and env.currentDay or 0, env and env.currentMonth or 0, false)
    end
    if settings.showNotification then
        g_currentMission:addIngameNotification({1.0, 0.5, 0.0, 1.0},
            string.format("Daily tax accumulated: %s", formatMoney(taxAmount)))
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
    local farmId = g_currentMission:getFarmId()
    if not farmId then return end
    local farm = g_farmManager:getFarmById(farmId)
    if not farm then return end

    local currentYear = g_currentMission.environment.currentYear
    -- Only apply if we haven't paid for the current in-game year yet.
    if stats.lastTaxYear >= currentYear then return end

    if stats.taxesAccumulatedAnnual <= 0 then
        log("No annual tax accumulated for the previous year. Resetting lastTaxYear.", 2)
        stats.lastTaxYear = currentYear -- Mark as processed for this year
        saveSettings()
        return
    end

    local taxAmount = math.floor(stats.taxesAccumulatedAnnual * settings.annualTaxRate)
    if taxAmount <= 0 then
        log("Calculated annual tax is zero or less. Resetting accumulated tax.", 2)
        stats.taxesAccumulatedAnnual = 0
        stats.lastTaxYear = currentYear -- Mark as processed for this year
        saveSettings()
        return
    end

    g_currentMission:addMoney(-taxAmount, farmId, MoneyType.OTHER, true)
    stats.totalTaxesPaid = stats.totalTaxesPaid + taxAmount -- Update total paid with annual tax
    stats.taxesAccumulatedAnnual = 0 -- Reset annual accumulation
    stats.lastTaxYear = currentYear -- Mark tax as paid for this year

    if taxHUD then
        local env = g_currentMission.environment
        taxHUD:recordTax(taxAmount, 1, stats.taxReturnMonth, true) -- Record as payment for the year in return month
    end
    if settings.showNotification then
        g_currentMission:addIngameNotification({1.0, 0.0, 0.0, 1.0},
            string.format("Annual tax deducted for %d: -%s", currentYear - 1, formatMoney(taxAmount)))
    end
    saveSettings()
end

local function taxAdvisory()
    if not settings.enabled or not g_currentMission then return end
    if stats.taxesAccumulatedAnnual <= 0 then return end

    local estimatedTax = math.floor(stats.taxesAccumulatedAnnual * settings.annualTaxRate)
    local farm = g_farmManager and g_farmManager:getFarmById(g_currentMission:getFarmId())
    local balance = farm and farm.money or 0
    local pctOfBalance = balance > 0 and math.floor((estimatedTax / balance) * 100) or 0

    if settings.showNotification then
        g_currentMission:addIngameNotification({0.0, 0.5, 1.0, 1.0},
            string.format("Tax Advisory: Est. March payment %s (%d%% of balance). Accumulated: %s",
                formatMoney(estimatedTax), pctOfBalance, formatMoney(stats.taxesAccumulatedAnnual)))
    end
    log(string.format("Tax Advisory: Accumulated %s | Annual rate %.0f%% | Est. payment %s (%d%% of balance)",
        formatMoney(stats.taxesAccumulatedAnnual), settings.annualTaxRate * 100,
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
                log("HUD toggle (T) registered", 2)
            else
                log("HUD toggle (T) registration failed", 1)
            end
            g_inputBinding:endActionEventsModification()
        end
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

FSBaseMission.update = Utils.appendedFunction(FSBaseMission.update, function(mission, dt)
    if taxHUD then taxHUD:update(dt) end
end)

FSBaseMission.draw = Utils.appendedFunction(FSBaseMission.draw, function(mission)
    if taxHUD and settings.showHUD then taxHUD:draw() end
end)

Mission00.saveToXMLFile = Utils.appendedFunction(Mission00.saveToXMLFile, function(mission, xmlFilename)
    saveSettings()
    if taxHUD then taxHUD:saveLayout() end
end)

local taxMouseHandler = {}
function taxMouseHandler:mouseEvent(posX, posY, isDown, isUp, button, eventUsed)
    if taxHUD then taxHUD:onMouseEvent(posX, posY, isDown, isUp, button) end
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

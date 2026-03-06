-- =========================================================
-- FS25 Tax Mod (version 1.0.0.0)
-- =========================================================
-- Daily tax deductions with monthly returns
-- Converted from FS22 to FS25
-- =========================================================
-- Author: TisonK
-- =========================================================
-- COPYRIGHT NOTICE:
-- All rights reserved. Unauthorized redistribution, copying,
-- or claiming this code as your own is strictly prohibited.
-- Original author: TisonK
-- =========================================================

FS25TaxMod = {}
FS25TaxMod.modDir = g_currentModDirectory
FS25TaxMod.modName = "FS25_TaxMod"
FS25TaxMod.version = "1.0.0.0"
FS25TaxMod.Debug = false

local settings = {
    enabled = true,
    taxRate = "medium",
    returnPercentage = 20,
    minimumBalance = 1000,
    showNotification = true,
    showStatistics = true,
    debugLevel = 1
}
FS25TaxMod.settings = settings  -- cross-mod bridge: expose via g_TaxManager.settings

local TAX_RATE_VALUES = {
    low = 0.01,      -- 1%
    medium = 0.02,   -- 2%
    high = 0.03      -- 3%
}

-- =====================
-- TAX STATISTICS
-- =====================
local stats = {
    totalTaxesPaid = 0,
    totalTaxesReturned = 0,
    taxesThisMonth = 0,
    daysTaxed = 0,
    monthsReturned = 0
}
FS25TaxMod.stats = stats  -- cross-mod bridge: expose via g_TaxManager.stats

-- =====================
-- INTERNAL STATE
-- =====================
local lastDay = -1
local lastMonth = -1
local lastMinuteCheck = -1
local isInitialized = false
local infoNotificationTimer = nil

-- =====================
-- UTILITY FUNCTIONS
-- =====================
local function log(msg, level)
    level = level or 1
    if settings.debugLevel >= level then
        print("[" .. FS25TaxMod.modName .. "] " .. tostring(msg))
    end
end

local function debug(msg)
    if FS25TaxMod.Debug then
        print("[" .. FS25TaxMod.modName .. " DEBUG] " .. tostring(msg))
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

-- =====================
-- SETTINGS SYSTEM
-- =====================
local function getSettingsPath()
    if g_currentMission ~= nil and g_currentMission.missionInfo ~= nil then
        local base = g_currentMission.missionInfo.savegameDirectory .. "/modSettings"
        return base .. "/FS25_TaxMod.xml"
    end
    return nil
end

local function saveSettings()
    local settingsFile = getSettingsPath()
    if settingsFile == nil then
        log("Cannot save settings: no savegame path", 2)
        return
    end

    local xmlFile = createXMLFile("taxSettings", settingsFile, "settings")
    if xmlFile == 0 then
        log("Failed to create XML file: " .. settingsFile, 2)
        return
    end

    -- === SETTINGS ===
    setXMLBool(xmlFile, "settings.enabled", settings.enabled)
    setXMLString(xmlFile, "settings.taxRate", settings.taxRate)
    setXMLInt(xmlFile, "settings.returnPercentage", settings.returnPercentage)
    setXMLInt(xmlFile, "settings.minimumBalance", settings.minimumBalance)
    setXMLBool(xmlFile, "settings.showNotification", settings.showNotification)
    setXMLBool(xmlFile, "settings.showStatistics", settings.showStatistics)
    setXMLInt(xmlFile, "settings.debugLevel", settings.debugLevel)

    -- === STATISTICS ===
    setXMLInt(xmlFile, "settings.stats.totalTaxesPaid", stats.totalTaxesPaid or 0)
    setXMLInt(xmlFile, "settings.stats.totalTaxesReturned", stats.totalTaxesReturned or 0)
    setXMLInt(xmlFile, "settings.stats.taxesThisMonth", stats.taxesThisMonth or 0)
    setXMLInt(xmlFile, "settings.stats.daysTaxed", stats.daysTaxed or 0)
    setXMLInt(xmlFile, "settings.stats.monthsReturned", stats.monthsReturned or 0)

    -- === TIME STATE ===
    setXMLInt(xmlFile, "settings.lastDay", tonumber(lastDay) or 1)
    setXMLInt(xmlFile, "settings.lastMonth", tonumber(lastMonth) or 1)

    saveXMLFile(xmlFile)
    delete(xmlFile)

    log("Tax settings saved to: " .. settingsFile, 2)
end

local function loadSettings()
    local settingsFile = getSettingsPath()
    if settingsFile == nil or not fileExists(settingsFile) then
        log("No settings file found, using defaults", 2)
        return
    end

    local xmlFile = loadXMLFile("taxSettings", settingsFile)
    if xmlFile == 0 then
        log("Failed to load settings XML", 2)
        return
    end

    settings.enabled = getXMLBool(xmlFile, "settings.enabled", settings.enabled)
    settings.taxRate = getXMLString(xmlFile, "settings.taxRate", settings.taxRate)
    settings.returnPercentage = getXMLInt(xmlFile, "settings.returnPercentage", settings.returnPercentage)
    settings.minimumBalance = getXMLInt(xmlFile, "settings.minimumBalance", settings.minimumBalance)
    settings.showNotification = getXMLBool(xmlFile, "settings.showNotification", settings.showNotification)
    settings.showStatistics = getXMLBool(xmlFile, "settings.showStatistics", settings.showStatistics)
    settings.debugLevel = getXMLInt(xmlFile, "settings.debugLevel", settings.debugLevel)

    stats.totalTaxesPaid = getXMLInt(xmlFile, "settings.stats.totalTaxesPaid", 0)
    stats.totalTaxesReturned = getXMLInt(xmlFile, "settings.stats.totalTaxesReturned", 0)
    stats.taxesThisMonth = getXMLInt(xmlFile, "settings.stats.taxesThisMonth", 0)
    stats.daysTaxed = getXMLInt(xmlFile, "settings.stats.daysTaxed", 0)
    stats.monthsReturned = getXMLInt(xmlFile, "settings.stats.monthsReturned", 0)

    lastDay = getXMLInt(xmlFile, "settings.lastDay", lastDay)
    lastMonth = getXMLInt(xmlFile, "settings.lastMonth", lastMonth)

    delete(xmlFile)

    log("Tax settings loaded successfully", 2)
end

-- =====================
-- TAX LOGIC
-- =====================
local function applyDailyTax()
    if not settings.enabled then 
        return 
    end
    
    if not g_currentMission then
        log("Cannot apply tax: No mission", 2)
        return
    end
    
    local farmId = g_currentMission:getFarmId()
    if not farmId then
        log("Cannot apply tax: No farm ID", 2)
        return
    end
    
    local farm = g_farmManager:getFarmById(farmId)
    if not farm then
        log("Cannot apply tax: Farm not found", 2)
        return
    end
    
    local farmMoney = farm.money
    local minimumBalance = settings.minimumBalance
    
    if farmMoney < minimumBalance then
        log("Farm balance (" .. formatMoney(farmMoney) .. ") below minimum (" .. formatMoney(minimumBalance) .. "), skipping tax", 2)
        return
    end
    
    local taxRate = getTaxRate()
    local taxAmount = math.floor(farmMoney * taxRate)
    
    if taxAmount <= 0 then 
        return 
    end

    g_currentMission:addMoney(-taxAmount, farmId, MoneyType.OTHER, true)
    
    stats.totalTaxesPaid = stats.totalTaxesPaid + taxAmount
    stats.taxesThisMonth = stats.taxesThisMonth + taxAmount
    stats.daysTaxed = stats.daysTaxed + 1
    
    log("Daily tax applied | Farm ID: " .. farmId .. " | Amount: -" .. formatMoney(taxAmount) .. " | Rate: " .. (taxRate * 100) .. "%", 2)
    
    if settings.showNotification then
        local message = string.format("Daily tax deducted: -%s", formatMoney(taxAmount))
        g_currentMission:addIngameNotification({1.0, 0.0, 0.0, 1.0}, message)
    end
end

local function applyMonthlyReturn()
    if not settings.enabled then 
        return 
    end
    
    if not g_currentMission then
        log("Cannot apply return: No mission", 2)
        return
    end
    
    local farmId = g_currentMission:getFarmId()
    if not farmId then
        log("Cannot apply return: No farm ID", 2)
        return
    end
    
    local returnPercentage = math.min(math.max(settings.returnPercentage, 0), 100) / 100
    local returnAmount = math.floor(stats.taxesThisMonth * returnPercentage)
    
    if returnAmount <= 0 then
        log("No monthly return (no taxes paid this month)", 2)
        stats.taxesThisMonth = 0
        saveSettings()
        return
    end
    
    g_currentMission:addMoney(returnAmount, farmId, MoneyType.OTHER, true)
    
    stats.totalTaxesReturned = stats.totalTaxesReturned + returnAmount
    stats.monthsReturned = stats.monthsReturned + 1
    
    log("Monthly tax return | Farm ID: " .. farmId .. " | Amount: +" .. formatMoney(returnAmount) .. " | Return %: " .. (returnPercentage * 100) .. "%", 2)
    
    if settings.showNotification then
        local message = string.format("Monthly tax return: +%s (Taxes paid this month: %s)", 
                                    formatMoney(returnAmount), 
                                    formatMoney(stats.taxesThisMonth))
        g_currentMission:addIngameNotification({0.0, 1.0, 0.0, 1.0}, message)
    end
    
    stats.taxesThisMonth = 0
    saveSettings()
end

-- =====================
-- TIME CHECKING FUNCTIONS
-- =====================
local function checkDailyTax()
    if not g_currentMission or not g_currentMission.environment then
        return false
    end
    
    local env = g_currentMission.environment
    local currentDay = env.currentDay
    
    if currentDay ~= lastDay then
        lastDay = currentDay
        applyDailyTax()
        return true
    end
    
    return false
end

local function checkMonthlyReturn()
    if not g_currentMission or not g_currentMission.environment then
        return false
    end
    
    local env = g_currentMission.environment
    local currentMonth = env.currentMonth
    
    if currentMonth ~= lastMonth then
        lastMonth = currentMonth
        applyMonthlyReturn()
        return true
    end
    
    return false
end

-- =====================
-- UPDATE SYSTEM
-- =====================
local function createUpdateable()
    local updateable = {
        update = function(dt)
            if not isInitialized or not settings.enabled then
                return
            end
            
            if infoNotificationTimer ~= nil then
                local delta = dt

                if type(dt) == "table" then
                    delta = dt.dt or dt.deltaTime or 0
                end

                infoNotificationTimer = infoNotificationTimer - delta

                if infoNotificationTimer <= 0 then
                    infoNotificationTimer = nil
                    if settings.showNotification and g_currentMission then
                        local message = "Tax Mod Active - Type 'tax' in console (~) for settings"
                        g_currentMission:addIngameNotification({1.0, 0.5, 0.0, 1.0}, message)
                    end
                end
            end

            if g_currentMission and g_currentMission.environment then
                local currentMinute = math.floor(g_currentMission.environment.dayTime / 60000)
                
                if currentMinute ~= lastMinuteCheck then
                    lastMinuteCheck = currentMinute
                    
                    checkDailyTax()
                    
                    checkMonthlyReturn()
                end
            end
        end,
        
        delete = function()
            log("Tax updateable removed")
        end
    }
    
    return updateable
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
    print("taxReturn [percentage] (0-100)          ")
    print("taxMinimum [amount]                     ")
    print("taxStatistics - Show tax statistics     ")
    print("taxSimulate   - Simulate tax cycle      ")
    print("taxDebug [0-3] - Set debug level        ")
    print("========================================")
end

function FS25TaxMod:consoleTaxStatus()
    print("=== Tax Mod Status ===")
    print("Enabled:          " .. tostring(settings.enabled))
    print("Tax Rate:         " .. settings.taxRate .. " (" .. (getTaxRate() * 100) .. "%)")
    print("Return %:         " .. settings.returnPercentage .. "%")
    print("Minimum Balance:  " .. formatMoney(settings.minimumBalance))
    print("Notifications:    " .. tostring(settings.showNotification))
    print("Show Stats:       " .. tostring(settings.showStatistics))
    print("Debug Level:      " .. settings.debugLevel)
    
    if g_currentMission and g_currentMission.environment then
        local currentDay = g_currentMission.environment.currentDay or "unknown"
        local currentMonth = g_currentMission.environment.currentMonth or "unknown"

        print("Current Day:      " .. currentDay)
        print("Current Month:    " .. currentMonth)
    end

    
    if settings.showStatistics then
        self:consoleTaxStatistics()
    end
end

function FS25TaxMod:consoleTaxEnable()
    settings.enabled = true
    saveSettings()
    print("[Tax Mod] Tax system ENABLED")
    if g_currentMission then
        g_currentMission:addIngameNotification({0.0, 1.0, 0.0, 1.0}, "Tax system ENABLED")
    end
end

function FS25TaxMod:consoleTaxDisable()
    settings.enabled = false
    saveSettings()
    print("[Tax Mod] Tax system DISABLED")
    if g_currentMission then
        g_currentMission:addIngameNotification({1.0, 0.0, 0.0, 1.0}, "Tax system DISABLED")
    end
end

function FS25TaxMod:consoleTaxRate(rate)
    if rate == nil then
        print("Usage: taxRate low|medium|high")
        return
    end

    rate = tostring(rate):lower()
    if rate ~= "low" and rate ~= "medium" and rate ~= "high" then
        print("Invalid tax rate. Use: low, medium, or high")
        return
    end

    settings.taxRate = rate
    saveSettings()
    print("[Tax Mod] Tax rate set to " .. rate .. " (" .. (getTaxRate() * 100) .. "%)")

    if g_currentMission then
        g_currentMission:addIngameNotification({0.0, 0.5, 1.0, 1.0}, "Tax rate set to " .. rate)
    end
end

function FS25TaxMod:consoleTaxReturn(percentage)
    if percentage == nil then
        print("Usage: taxReturn [percentage] (0-100)")
        return
    end

    local value = tonumber(percentage)
    if value == nil or value < 0 or value > 100 then
        print("Invalid percentage. Must be between 0 and 100")
        return
    end

    settings.returnPercentage = value
    saveSettings()
    print("[Tax Mod] Return percentage set to " .. value .. "%")

    if g_currentMission then
        g_currentMission:addIngameNotification({0.0, 0.5, 1.0, 1.0}, "Return percentage set to " .. value .. "%")
    end
end

function FS25TaxMod:consoleTaxMinimum(amount)
    if amount == nil then
        print("Usage: taxMinimum [amount]")
        return
    end

    local value = tonumber(amount)
    if value == nil or value < 0 then
        print("Invalid amount. Must be positive number")
        return
    end

    settings.minimumBalance = value
    saveSettings()
    print("[Tax Mod] Minimum balance set to " .. formatMoney(value))

    if g_currentMission then
        g_currentMission:addIngameNotification({0.0, 0.5, 1.0, 1.0}, "Minimum balance set to " .. formatMoney(value))
    end
end

function FS25TaxMod:consoleTaxStatistics()
    print("=== Tax Statistics ===")
    print("Total taxes paid:      " .. formatMoney(stats.totalTaxesPaid))
    print("Total tax returns:     " .. formatMoney(stats.totalTaxesReturned))
    print("Taxes this month:      " .. formatMoney(stats.taxesThisMonth))
    print("Days taxed:            " .. stats.daysTaxed)
    print("Months returned:       " .. stats.monthsReturned)
    
    if stats.daysTaxed > 0 then
        local averageTax = math.floor(stats.totalTaxesPaid / stats.daysTaxed)
        print("Average daily tax:    " .. formatMoney(averageTax))
    end
    
    if stats.totalTaxesPaid > 0 then
        local netTax = stats.totalTaxesPaid - stats.totalTaxesReturned
        print("Net taxes paid:       " .. formatMoney(netTax))
    end
end

function FS25TaxMod:consoleTaxSimulate()
    print("[Tax Mod] Simulating tax cycle...")
    if g_currentMission and g_currentMission.environment then
        applyDailyTax()
        print("[Tax Mod] Daily tax simulation complete")
        
        if g_currentMission.environment.currentDay == 1 then
            applyMonthlyReturn()
            print("[Tax Mod] Monthly return simulation complete")
        end
    else
        print("[Tax Mod] Cannot simulate - game not loaded")
    end
end

function FS25TaxMod:consoleTaxDebug(level)
    if level == nil then
        print("Current debug level: " .. settings.debugLevel)
        print("Usage: taxDebug [0-3] (0=off, 1=basic, 2=detailed, 3=all)")
        return
    end

    local value = tonumber(level)
    if value == nil or value < 0 or value > 3 then
        print("Invalid debug level. Must be 0-3")
        return
    end

    settings.debugLevel = value
    saveSettings()
    print("[Tax Mod] Debug level set to " .. value)
end

-- =====================
-- MOD INITIALIZATION
-- =====================
function FS25TaxMod:loadMap(name)
    log("Loading Tax Mod for map: " .. (name or "unknown"))
    
    self:setupMissionIntegration()
    
    return true
end

function FS25TaxMod:setupMissionIntegration()
    
    local initUpdateable = {
        update = function(dt)
            if isInitialized then
                return true
            end

            if g_currentMission == nil
            or g_currentMission.environment == nil
            or g_currentMission.missionInfo == nil
            or g_currentMission.missionInfo.savegameDirectory == nil
            or g_currentMission.addUpdateable == nil then
                return false
            end

            loadSettings()

            local env = g_currentMission.environment
            lastDay = tonumber(env.currentDay) or 1
            lastMonth = tonumber(env.currentMonth) or 1
            lastMinuteCheck = math.floor((env.dayTime or 0) / 60000)

            if settings.showNotification then
                infoNotificationTimer = 20000
            end

            self.updateable = createUpdateable()
            g_currentMission:addUpdateable(self.updateable)

            isInitialized = true

            log(string.format(
                "Tax Mod initialized successfully (Day %d, Month %d)",
                lastDay,
                lastMonth
            ))

            registerConsoleCommands()

            return true
        end,
        
        delete = function()
            log("Tax init updateable removed")
        end
    }
    
    if g_currentMission and g_currentMission.addUpdateable then
        g_currentMission:addUpdateable(initUpdateable)
        log("Tax init updateable registered - waiting for mission to be ready...")
    else
        log("Warning: Could not register tax init updateable - mission not ready yet")
    end
end

function FS25TaxMod:deleteMap()
    log("Tax Mod shutting down")
    
    if self.updateable and g_currentMission then
        g_currentMission:removeUpdateable(self.updateable)
    end
    
    saveSettings()
    
    isInitialized = false
    log("Tax Mod unloaded")
end

-- =====================
-- CONSOLE COMMAND REGISTRATION
-- =====================
function registerConsoleCommands()
    print("[Tax Mod] Registering console commands (FS25)")

    addConsoleCommand("tax", "Show tax mod help", "consoleCommandTax", FS25TaxMod)
    addConsoleCommand("taxStatus", "Show tax settings", "consoleTaxStatus", FS25TaxMod)
    addConsoleCommand("taxEnable", "Enable tax system", "consoleTaxEnable", FS25TaxMod)
    addConsoleCommand("taxDisable", "Disable tax system", "consoleTaxDisable", FS25TaxMod)
    addConsoleCommand("taxRate", "Set tax rate level", "consoleTaxRate", FS25TaxMod)
    addConsoleCommand("taxReturn", "Set return percentage", "consoleTaxReturn", FS25TaxMod)
    addConsoleCommand("taxMinimum", "Set minimum balance", "consoleTaxMinimum", FS25TaxMod)
    addConsoleCommand("taxStatistics", "Show tax statistics", "consoleTaxStatistics", FS25TaxMod)
    addConsoleCommand("taxSimulate", "Simulate tax cycle", "consoleTaxSimulate", FS25TaxMod)
    addConsoleCommand("taxDebug", "Set debug level", "consoleTaxDebug", FS25TaxMod)

    print("[Tax Mod] Console commands registered")
end

-- =====================
-- GLOBAL FUNCTIONS
-- =====================
function tax()
    FS25TaxMod:consoleCommandTax()
end

function taxStatus()
    FS25TaxMod:consoleTaxStatus()
end

function taxEnable()
    FS25TaxMod:consoleTaxEnable()
end

function taxDisable()
    FS25TaxMod:consoleTaxDisable()
end

function taxRate(rate)
    FS25TaxMod:consoleTaxRate(rate)
end

function taxReturn(percentage)
    FS25TaxMod:consoleTaxReturn(percentage)
end

function taxMinimum(amount)
    FS25TaxMod:consoleTaxMinimum(amount)
end

function taxStatistics()
    FS25TaxMod:consoleTaxStatistics()
end

function taxSimulate()
    FS25TaxMod:consoleTaxSimulate()
end

function taxDebug(level)
    FS25TaxMod:consoleTaxDebug(level)
end

-- =====================
-- MOD REGISTRATION
-- =====================
addModEventListener(FS25TaxMod)

-- Cross-mod bridge: export to shared global table so other mods (e.g. FarmTablet)
-- can detect and read this mod via g_TaxManager.settings / g_TaxManager.stats
getfenv(0)["g_TaxManager"] = FS25TaxMod

log("========================================")
log("     FS25 Tax Mod v1.0.0.0 LOADED      ")
log("     Author: TisonK                     ")
log("     Type 'tax' in console for help     ")
log("========================================")
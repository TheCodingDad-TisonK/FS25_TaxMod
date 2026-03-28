-- =========================================================
-- FS25 Tax Mod (version 1.1.0.0)
-- =========================================================
-- SettingsUI - injects Tax Mod controls into the
-- General Settings page (InGameMenu > Settings).
-- Pattern copied from FS25_IncomeMod by TisonK.
-- =========================================================

---@class TaxSettingsUI
TaxSettingsUI = {}
local TaxSettingsUI_mt = Class(TaxSettingsUI)

function TaxSettingsUI.new(taxMod)
    local self = setmetatable({}, TaxSettingsUI_mt)
    self.taxMod   = taxMod
    self.injected = false
    return self
end

-- =========================================================
-- Inject into In-Game Settings
-- =========================================================

function TaxSettingsUI:inject()
    if self.injected then return end

    local page = g_gui.screenControllers[InGameMenu] and
                 g_gui.screenControllers[InGameMenu].pageSettings
    if not page then
        Logging.warning("TaxMod: Settings page not found - skipping injection")
        return
    end

    local layout = page.generalSettingsLayout
    if not layout then
        Logging.warning("TaxMod: generalSettingsLayout not found - skipping injection")
        return
    end

    local settings = self.taxMod.settings

    -- ── Section header ─────────────────────────────────────
    TaxUIHelper.createSection(layout, "tm_section")

    -- ── Enable Mod ─────────────────────────────────────────
    self.enabledOption = TaxUIHelper.createBinaryOption(
        layout, "tm_enabled", "tm_enabled",
        settings.enabled,
        function(val)
            settings.enabled = val
            self.taxMod:saveSettings()
        end
    )

    -- ── Tax Rate: Low / Medium / High ──────────────────────
    local rateIndex = ({ low = 1, medium = 2, high = 3 })[settings.taxRate] or 2
    self.taxRateOption = TaxUIHelper.createMultiOption(
        layout, "tm_taxrate", "tm_taxrate",
        {
            TaxUIHelper.getText("tm_taxrate_1"),
            TaxUIHelper.getText("tm_taxrate_2"),
            TaxUIHelper.getText("tm_taxrate_3"),
        },
        rateIndex,
        function(idx)
            local rates = { "low", "medium", "high" }
            settings.taxRate = rates[idx] or "medium"
            self.taxMod:saveSettings()
        end
    )

    -- ── Annual Tax Rate: Low (2%) / Medium (5%) / High (10%) ──
    local annualRateValues = { 0.02, 0.05, 0.10 }
    local annualRateIndex = 2  -- default: Medium (5%)
    for i, v in ipairs(annualRateValues) do
        if math.abs(v - settings.annualTaxRate) < 0.001 then annualRateIndex = i end
    end
    self.annualRateOption = TaxUIHelper.createMultiOption(
        layout, "tm_annualrate", "tm_annualrate",
        {
            TaxUIHelper.getText("tm_annualrate_1"),
            TaxUIHelper.getText("tm_annualrate_2"),
            TaxUIHelper.getText("tm_annualrate_3"),
        },
        annualRateIndex,
        function(idx)
            local values = { 0.02, 0.05, 0.10 }
            settings.annualTaxRate = values[idx] or 0.05
            self.taxMod:saveSettings()
        end
    )

    -- ── Notifications ──────────────────────────────────────
    self.notificationsOption = TaxUIHelper.createBinaryOption(
        layout, "tm_notifications", "tm_notifications",
        settings.showNotification,
        function(val)
            settings.showNotification = val
            self.taxMod:saveSettings()
        end
    )

    -- ── Show HUD ───────────────────────────────────────────
    self.showHUDOption = TaxUIHelper.createBinaryOption(
        layout, "tm_show_hud", "tm_show_hud",
        settings.showHUD,
        function(val)
            settings.showHUD = val
            if self.taxMod.taxHUD then
                self.taxMod.taxHUD.visible = val
            end
            self.taxMod:saveSettings()
        end
    )

    self.injected = true
    layout:invalidateLayout()

    Logging.info("Tax Mod: Settings UI injected successfully")
end

-- =========================================================
-- Refresh (called after external settings change)
-- =========================================================

function TaxSettingsUI:refreshUI()
    if not self.injected then return end

    local settings = self.taxMod.settings

    local function setCheck(opt, val)
        if not opt then return end
        if opt.setIsChecked then
            opt:setIsChecked(val)
        elseif opt.setState then
            opt:setState(val and 2 or 1)
        end
    end

    local function setMulti(opt, idx)
        if opt and opt.setState then opt:setState(idx) end
    end

    setCheck(self.enabledOption,       settings.enabled)
    setCheck(self.notificationsOption, settings.showNotification)
    setCheck(self.showHUDOption,       settings.showHUD)

    local rateIndex = ({ low = 1, medium = 2, high = 3 })[settings.taxRate] or 2
    setMulti(self.taxRateOption, rateIndex)

    local annualRateValues = { 0.02, 0.05, 0.10 }
    local annualRateIndex = 2
    for i, v in ipairs(annualRateValues) do
        if math.abs(v - settings.annualTaxRate) < 0.001 then annualRateIndex = i end
    end
    setMulti(self.annualRateOption, annualRateIndex)
end

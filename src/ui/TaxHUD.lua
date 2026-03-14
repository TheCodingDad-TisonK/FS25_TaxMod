-- =========================================================
-- FS25 Tax Mod (version 1.1.0.0)
-- =========================================================
-- Tax HUD Overlay
-- Displays tax status, current rate, and history.
-- Toggle with the T key (consoleCommandTaxHUD).
-- RMB on panel to drag/resize (same pattern as IncomeHUD).
-- =========================================================
-- Author: TisonK
-- =========================================================

---@class TaxHUD
TaxHUD = {}
local TaxHUD_mt = Class(TaxHUD)

TaxHUD.MAX_HISTORY_ROWS  = 5
TaxHUD.MIN_SCALE         = 0.60
TaxHUD.MAX_SCALE         = 1.80
TaxHUD.RESIZE_HANDLE_SIZE = 0.008

function TaxHUD.new(taxMod)
    local self = setmetatable({}, TaxHUD_mt)

    self.taxMod  = taxMod

    -- Runtime visibility (toggle key)
    self.visible = true

    -- Panel anchor: top-left of content area (text starts here)
    self.posX       = 0.77
    self.posY       = 0.72   -- slightly below IncomeHUD default
    self.panelWidth = 0.21

    -- Base layout constants (at scale 1.0)
    self.LINE_H      = 0.017
    self.PAD         = 0.007
    self.TEXT_TITLE  = 0.013
    self.TEXT_NORMAL = 0.011
    self.TEXT_SMALL  = 0.0095

    -- Scale & edit state
    self.scale            = 1.0
    self.editMode         = false
    self.dragging         = false
    self.resizing         = false
    self.dragOffsetX      = 0
    self.dragOffsetY      = 0
    self.resizeStartX     = 0
    self.resizeStartY     = 0
    self.resizeStartScale = 1.0
    self.hoverCorner      = nil
    self.animTimer        = 0

    -- Camera freeze
    self.savedCamRotX = nil
    self.savedCamRotY = nil
    self.savedCamRotZ = nil

    -- Cached panel bounds (updated each drawPanel, used for hit-testing)
    self.lastBgX = 0
    self.lastBgY = 0
    self.lastBgW = 0
    self.lastBgH = 0

    -- Payment / tax history (ring buffer, newest first)
    self.taxHistory = {}

    -- 1x1 pixel overlay for all rect draws
    self.bgOverlay = nil
    if createImageOverlay then
        self.bgOverlay = createImageOverlay("dataS/menu/base/graph_pixel.dds")
    end

    -- Color palette — identical to IncomeHUD for visual consistency
    self.COLORS = {
        BG           = {0.05, 0.05, 0.05, 0.82},
        BORDER       = {0.20, 0.20, 0.20, 0.40},
        DIVIDER      = {0.25, 0.25, 0.25, 0.85},
        SHADOW       = {0.00, 0.00, 0.00, 0.35},
        HEADER       = {1.00, 1.00, 1.00, 1.00},
        ENABLED      = {0.30, 0.90, 0.30, 1.00},
        DISABLED     = {0.90, 0.30, 0.30, 1.00},
        LABEL        = {0.72, 0.72, 0.72, 1.00},
        VALUE        = {1.00, 1.00, 1.00, 1.00},
        DIM          = {0.55, 0.55, 0.55, 1.00},
        AMOUNT_NEG   = {0.90, 0.35, 0.35, 1.00},   -- red for taxes deducted
        AMOUNT_POS   = {0.35, 0.90, 0.35, 1.00},   -- green for returns
        RATE         = {0.90, 0.78, 0.30, 1.00},   -- yellow for rate info
        HINT         = {0.52, 0.52, 0.52, 0.75},
        EDIT_BORDER  = {1.00, 0.60, 0.10, 0.90},
        EDIT_HANDLE  = {1.00, 0.70, 0.20, 0.85},
    }

    return self
end

-- =========================================================
-- Cleanup
-- =========================================================

function TaxHUD:delete()
    if self.editMode then self:exitEditMode() end
    if self.bgOverlay then
        delete(self.bgOverlay)
        self.bgOverlay = nil
    end
end

-- =========================================================
-- Toggle
-- =========================================================

function TaxHUD:toggleVisibility()
    self.visible = not self.visible
    local msg = self.visible and "Tax HUD shown" or "Tax HUD hidden"
    if g_currentMission and g_currentMission.hud and g_currentMission.hud.showBlinkingWarning then
        g_currentMission.hud:showBlinkingWarning(msg, 2000)
    end
end

-- =========================================================
-- History recording
-- =========================================================

function TaxHUD:recordTax(amount, day, month, isReturn)
    table.insert(self.taxHistory, 1, {
        amount   = amount,
        day      = day,
        month    = month,
        isReturn = isReturn,
    })
    -- Keep only last MAX_HISTORY_ROWS * 2 entries
    while #self.taxHistory > TaxHUD.MAX_HISTORY_ROWS * 2 do
        table.remove(self.taxHistory)
    end
end

-- =========================================================
-- Edit mode
-- =========================================================

function TaxHUD:enterEditMode()
    self.editMode = true
    self.dragging = false
    if g_inputBinding and g_inputBinding.setShowMouseCursor then
        g_inputBinding:setShowMouseCursor(true)
    end
    if getCamera and getRotation then
        local ok, cam = pcall(getCamera)
        if ok and cam and cam ~= 0 then
            local ok2, rx, ry, rz = pcall(getRotation, cam)
            if ok2 then
                self.savedCamRotX, self.savedCamRotY, self.savedCamRotZ = rx, ry, rz
            end
        end
    end
end

function TaxHUD:exitEditMode()
    self.editMode    = false
    self.dragging    = false
    self.resizing    = false
    self.hoverCorner = nil
    self.savedCamRotX, self.savedCamRotY, self.savedCamRotZ = nil, nil, nil
    if g_inputBinding and g_inputBinding.setShowMouseCursor then
        g_inputBinding:setShowMouseCursor(false)
    end
    self:saveLayout()
end

-- =========================================================
-- HUD layout persistence
-- =========================================================

function TaxHUD:getLayoutPath()
    if g_currentMission and g_currentMission.missionInfo and g_currentMission.missionInfo.savegameDirectory then
        return g_currentMission.missionInfo.savegameDirectory .. "/FS25_TaxMod_hud.xml"
    end
end

function TaxHUD:saveLayout()
    local path = self:getLayoutPath()
    if not path then return end
    local xml = XMLFile.create("tax_hud", path, "hudLayout")
    if xml then
        xml:setFloat("hudLayout.posX",   self.posX)
        xml:setFloat("hudLayout.posY",   self.posY)
        xml:setFloat("hudLayout.scale",  self.scale)
        xml:setBool("hudLayout.visible", self.visible)
        xml:save()
        xml:delete()
    end
end

function TaxHUD:loadLayout()
    local path = self:getLayoutPath()
    if not path or not fileExists(path) then return end
    local xml = XMLFile.load("tax_hud", path)
    if xml then
        self.posX    = xml:getFloat("hudLayout.posX",   self.posX)
        self.posY    = xml:getFloat("hudLayout.posY",   self.posY)
        self.scale   = xml:getFloat("hudLayout.scale",  self.scale)
        self.visible = xml:getBool("hudLayout.visible", self.visible)
        xml:delete()
    end
end

-- =========================================================
-- Geometry helpers
-- =========================================================

function TaxHUD:isPointerOverHUD(posX, posY)
    return posX >= self.lastBgX and posX <= self.lastBgX + self.lastBgW
       and posY >= self.lastBgY and posY <= self.lastBgY + self.lastBgH
end

function TaxHUD:getResizeHandleRects()
    local hs = TaxHUD.RESIZE_HANDLE_SIZE
    local bx, by, bw, bh = self.lastBgX, self.lastBgY, self.lastBgW, self.lastBgH
    return {
        bl = {x = bx,        y = by,        w = hs, h = hs},
        br = {x = bx+bw-hs,  y = by,        w = hs, h = hs},
        tl = {x = bx,        y = by+bh-hs,  w = hs, h = hs},
        tr = {x = bx+bw-hs,  y = by+bh-hs,  w = hs, h = hs},
    }
end

function TaxHUD:hitTestCorner(posX, posY)
    for key, r in pairs(self:getResizeHandleRects()) do
        if posX >= r.x and posX <= r.x + r.w
        and posY >= r.y and posY <= r.y + r.h then
            return key
        end
    end
    return nil
end

function TaxHUD:clampPosition()
    local bw = self.lastBgW
    local bh = self.lastBgH
    local pad = self.PAD * self.scale
    self.posX = math.max(pad + 0.01, math.min(1.0 - bw + pad - 0.01, self.posX))
    self.posY = math.max(bh - pad + 0.01, math.min(0.98, self.posY))
end

-- =========================================================
-- Mouse event
-- =========================================================

function TaxHUD:onMouseEvent(posX, posY, isDown, isUp, button)
    if not self.visible then return end

    if isDown and button == 3 then
        if self.editMode then
            self:exitEditMode()
        elseif self:isPointerOverHUD(posX, posY) then
            self:enterEditMode()
        end
        return
    end

    if not self.editMode then return end

    if isDown and button == 1 then
        local corner = self:hitTestCorner(posX, posY)
        if corner then
            self.resizing         = true
            self.dragging         = false
            self.resizeStartX     = posX
            self.resizeStartY     = posY
            self.resizeStartScale = self.scale
            return
        end
        if self:isPointerOverHUD(posX, posY) then
            self.dragging    = true
            self.resizing    = false
            self.dragOffsetX = posX - self.posX
            self.dragOffsetY = posY - self.posY
        end
        return
    end

    if isUp and button == 1 then
        if self.dragging or self.resizing then
            self.dragging = false
            self.resizing = false
            self:clampPosition()
        end
        return
    end

    if self.dragging then
        local bw = self.lastBgW
        self.posX = math.max(0.0, math.min(1.0 - bw, posX - self.dragOffsetX))
        self.posY = math.max(0.05, math.min(0.98, posY - self.dragOffsetY))
    end

    if self.resizing then
        local cx = self.lastBgX + self.lastBgW * 0.5
        local cy = self.lastBgY + self.lastBgH * 0.5
        local startDist = math.sqrt((self.resizeStartX-cx)^2 + (self.resizeStartY-cy)^2)
        local currDist  = math.sqrt((posX-cx)^2 + (posY-cy)^2)
        local delta     = (currDist - startDist) * 2.5
        self.scale = math.max(TaxHUD.MIN_SCALE,
            math.min(TaxHUD.MAX_SCALE, self.resizeStartScale + delta))
        self:clampPosition()
    end

    if not self.dragging and not self.resizing then
        self.hoverCorner = self:hitTestCorner(posX, posY)
    end
end

-- =========================================================
-- Update
-- =========================================================

function TaxHUD:update(dt)
    self.animTimer = self.animTimer + dt

    if self.editMode then
        if g_inputBinding and g_inputBinding.setShowMouseCursor then
            g_inputBinding:setShowMouseCursor(true)
        end
        if self.savedCamRotX ~= nil and getCamera and setRotation then
            local ok, cam = pcall(getCamera)
            if ok and cam and cam ~= 0 then
                pcall(setRotation, cam, self.savedCamRotX, self.savedCamRotY, self.savedCamRotZ)
            end
        end
        if g_gui and (g_gui:getIsGuiVisible() or g_gui:getIsDialogVisible()) then
            self:exitEditMode()
        end
        if not self.dragging and not self.resizing then
            if g_inputBinding and g_inputBinding.mousePosXLast then
                self.hoverCorner = self:hitTestCorner(
                    g_inputBinding.mousePosXLast, g_inputBinding.mousePosYLast)
            end
        end
    else
        self.hoverCorner = nil
    end
end

-- =========================================================
-- Draw
-- =========================================================

function TaxHUD:draw()
    if not g_currentMission or not g_currentMission:getIsClient() then return end

    if not self.editMode then
        if g_gui and (g_gui:getIsGuiVisible() or g_gui:getIsDialogVisible()) then return end
        if g_currentMission.hud and g_currentMission.hud.ingameMap then
            if g_currentMission.hud.ingameMap.state == IngameMap.STATE_LARGE_MAP then return end
        end
    end

    if not self.visible   then return end
    if not self.bgOverlay then return end

    self:drawPanel()
end

-- =========================================================
-- Panel Rendering
-- =========================================================

function TaxHUD:drawPanel()
    local sc      = self.scale
    local taxMod  = self.taxMod
    local settings = taxMod.settings
    local stats   = taxMod.stats

    local x   = self.posX
    local w   = self.panelWidth * sc
    local pad = self.PAD * sc
    local lh  = self.LINE_H * sc

    local histCount = math.min(#self.taxHistory, TaxHUD.MAX_HISTORY_ROWS)

    -- Row count: title + divider-gap + rate + next-tax + this-month + divider-gap + history-header + hist rows + divider-gap + hint
    local nRows = 7 + math.max(histCount - 1, 0)
    local nDividers = 3
    local bgH = pad * 2 + nRows * lh + nDividers * (0.004 * sc)
    local bgX = x - pad
    local bgY = self.posY - bgH + pad
    local bgW = w + pad * 2

    self.lastBgX = bgX
    self.lastBgY = bgY
    self.lastBgW = bgW
    self.lastBgH = bgH

    -- Drop shadow
    self:rect(bgX + 0.002, bgY - 0.002, bgW, bgH, self.COLORS.SHADOW)

    -- Background
    self:rect(bgX, bgY, bgW, bgH, self.COLORS.BG)

    -- Permanent border
    local bw = 0.0012
    self:rect(bgX,            bgY + bgH - bw, bgW, bw, self.COLORS.BORDER)
    self:rect(bgX,            bgY,            bgW, bw, self.COLORS.BORDER)
    self:rect(bgX,            bgY,            bw, bgH, self.COLORS.BORDER)
    self:rect(bgX + bgW - bw, bgY,            bw, bgH, self.COLORS.BORDER)

    -- Edit mode chrome
    if self.editMode then
        local pulse = 0.55 + 0.45 * math.sin(self.animTimer * 0.004)
        local ebw   = 0.002
        local ec    = self.COLORS.EDIT_BORDER
        self:rectA(bgX,             bgY,             bgW, ebw, ec, pulse)
        self:rectA(bgX,             bgY + bgH - ebw,  bgW, ebw, ec, pulse)
        self:rectA(bgX,             bgY,             ebw, bgH, ec, pulse)
        self:rectA(bgX + bgW - ebw, bgY,             ebw, bgH, ec, pulse)

        for key, r in pairs(self:getResizeHandleRects()) do
            local isHover = (self.hoverCorner == key)
            self:rectA(r.x, r.y, r.w, r.h, self.COLORS.EDIT_HANDLE, isHover and 1.0 or 0.65)
        end
    end

    -- ── Content rows ──────────────────────────────────────
    local tsTitle  = self.TEXT_TITLE  * sc
    local tsNormal = self.TEXT_NORMAL * sc
    local tsSmall  = self.TEXT_SMALL  * sc

    local cy = self.posY - pad

    -- ── Title + status ────────────────────────────────────
    setTextBold(true)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(self.COLORS.HEADER[1], self.COLORS.HEADER[2], self.COLORS.HEADER[3], self.COLORS.HEADER[4])
    renderText(x, cy - tsTitle, tsTitle, "TAX MOD")

    local statusColor = settings.enabled and self.COLORS.ENABLED or self.COLORS.DISABLED
    setTextAlignment(RenderText.ALIGN_RIGHT)
    setTextColor(statusColor[1], statusColor[2], statusColor[3], statusColor[4])
    renderText(x + w, cy - tsTitle, tsTitle, settings.enabled and "[ON]" or "[OFF]")
    setTextBold(false)
    cy = cy - lh

    -- Divider
    self:divider(bgX, cy + lh * 0.35, bgW, sc)
    cy = cy - 0.004 * sc

    -- ── Rate | Return% ────────────────────────────────────
    local TAX_RATE_VALUES = { low = 0.01, medium = 0.02, high = 0.03 }
    local rateVal = (TAX_RATE_VALUES[settings.taxRate] or 0.02) * 100
    local rateLabel = string.format("Rate: %s (%.0f%%)", settings.taxRate, rateVal)

    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(self.COLORS.RATE[1], self.COLORS.RATE[2], self.COLORS.RATE[3], self.COLORS.RATE[4])
    renderText(x, cy - tsNormal, tsNormal, rateLabel)

    setTextAlignment(RenderText.ALIGN_RIGHT)
    setTextColor(self.COLORS.AMOUNT_POS[1], self.COLORS.AMOUNT_POS[2], self.COLORS.AMOUNT_POS[3], self.COLORS.AMOUNT_POS[4])
    renderText(x + w, cy - tsNormal, tsNormal, "Return: " .. settings.returnPercentage .. "%")
    cy = cy - lh

    -- ── This month so far ─────────────────────────────────
    local thisMonthFmt = self:formatMoney(stats.taxesThisMonth)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(self.COLORS.LABEL[1], self.COLORS.LABEL[2], self.COLORS.LABEL[3], self.COLORS.LABEL[4])
    renderText(x, cy - tsSmall, tsSmall, "This month:")

    setTextAlignment(RenderText.ALIGN_RIGHT)
    setTextColor(self.COLORS.AMOUNT_NEG[1], self.COLORS.AMOUNT_NEG[2], self.COLORS.AMOUNT_NEG[3], self.COLORS.AMOUNT_NEG[4])
    renderText(x + w, cy - tsSmall, tsSmall, "-" .. thisMonthFmt)
    cy = cy - lh

    -- ── Min balance ───────────────────────────────────────
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(self.COLORS.DIM[1], self.COLORS.DIM[2], self.COLORS.DIM[3], self.COLORS.DIM[4])
    renderText(x, cy - tsSmall, tsSmall, "Min balance: " .. self:formatMoney(settings.minimumBalance))
    cy = cy - lh

    -- ── Totals ────────────────────────────────────────────
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(self.COLORS.LABEL[1], self.COLORS.LABEL[2], self.COLORS.LABEL[3], self.COLORS.LABEL[4])
    renderText(x, cy - tsSmall, tsSmall, "Total paid / returned:")
    cy = cy - lh

    local paidFmt   = self:formatMoney(stats.totalTaxesPaid)
    local retFmt    = self:formatMoney(stats.totalTaxesReturned)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(self.COLORS.AMOUNT_NEG[1], self.COLORS.AMOUNT_NEG[2], self.COLORS.AMOUNT_NEG[3], self.COLORS.AMOUNT_NEG[4])
    renderText(x, cy - tsSmall, tsSmall, "-" .. paidFmt)

    setTextAlignment(RenderText.ALIGN_RIGHT)
    setTextColor(self.COLORS.AMOUNT_POS[1], self.COLORS.AMOUNT_POS[2], self.COLORS.AMOUNT_POS[3], self.COLORS.AMOUNT_POS[4])
    renderText(x + w, cy - tsSmall, tsSmall, "+" .. retFmt)
    cy = cy - lh

    -- Divider
    self:divider(bgX, cy + lh * 0.35, bgW, sc)
    cy = cy - 0.004 * sc

    -- ── History header ───────────────────────────────────
    setTextBold(true)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(self.COLORS.LABEL[1], self.COLORS.LABEL[2], self.COLORS.LABEL[3], self.COLORS.LABEL[4])
    renderText(x, cy - tsNormal, tsNormal, "Recent Activity")
    setTextBold(false)
    cy = cy - lh

    -- ── History rows ──────────────────────────────────────
    if #self.taxHistory == 0 then
        setTextAlignment(RenderText.ALIGN_LEFT)
        setTextColor(self.COLORS.DIM[1], self.COLORS.DIM[2], self.COLORS.DIM[3], self.COLORS.DIM[4])
        renderText(x, cy - tsSmall, tsSmall, "No activity yet")
        cy = cy - lh
    else
        for i = 1, histCount do
            local entry = self.taxHistory[i]
            if entry then
                local timeStr = string.format("M%d D%d", entry.month, entry.day)
                local typeStr = entry.isReturn and "[RET]" or "[TAX]"
                local entAmt  = self:formatMoney(entry.amount)

                setTextAlignment(RenderText.ALIGN_LEFT)
                setTextColor(self.COLORS.DIM[1], self.COLORS.DIM[2], self.COLORS.DIM[3], self.COLORS.DIM[4])
                renderText(x, cy - tsSmall, tsSmall, timeStr .. " " .. typeStr)

                local amtColor = entry.isReturn and self.COLORS.AMOUNT_POS or self.COLORS.AMOUNT_NEG
                setTextAlignment(RenderText.ALIGN_RIGHT)
                setTextColor(amtColor[1], amtColor[2], amtColor[3], amtColor[4])
                renderText(x + w, cy - tsSmall, tsSmall, (entry.isReturn and "+" or "-") .. entAmt)
                cy = cy - lh
            end
        end
    end

    -- Divider
    self:divider(bgX, cy + lh * 0.35, bgW, sc)
    cy = cy - 0.004 * sc

    -- Hint row
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextColor(self.COLORS.HINT[1], self.COLORS.HINT[2], self.COLORS.HINT[3], self.COLORS.HINT[4])
    if self.editMode then
        renderText(x + w * 0.5, cy - tsSmall, tsSmall, "Drag: move   Corner: resize   RMB: done")
    else
        renderText(x + w * 0.5, cy - tsSmall, tsSmall, "T: toggle HUD   RMB: move/resize")
    end

    -- Reset text state
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
    setTextColor(1, 1, 1, 1)
end

-- =========================================================
-- Helpers
-- =========================================================

function TaxHUD:formatMoney(amount)
    if g_i18n and g_i18n.formatMoney then
        return g_i18n:formatMoney(amount or 0, 0, true, true)
    end
    return "$" .. tostring(amount or 0)
end

function TaxHUD:rect(rx, ry, rw, rh, color)
    setOverlayColor(self.bgOverlay, color[1], color[2], color[3], color[4])
    renderOverlay(self.bgOverlay, rx, ry, rw, rh)
end

function TaxHUD:rectA(rx, ry, rw, rh, color, alpha)
    setOverlayColor(self.bgOverlay, color[1], color[2], color[3], alpha)
    renderOverlay(self.bgOverlay, rx, ry, rw, rh)
end

function TaxHUD:divider(dx, dy, dw, sc)
    self:rect(dx, dy, dw, 0.001 * (sc or 1.0), self.COLORS.DIVIDER)
end

-- =========================================================
-- FS25 Tax Mod (version 1.1.0.0)
-- =========================================================
-- UI Helper - creates settings rows in the General Settings page.
-- Pattern copied from FS25_IncomeMod by TisonK.
-- =========================================================

---@class TaxUIHelper
TaxUIHelper = {}

-- =========================================================
-- Internal helpers
-- =========================================================

local function getText(key)
    local text = g_i18n:getText(key)
    if text == nil or text == "" then
        return key
    end
    return text
end

function TaxUIHelper.getText(key)
    return getText(key)
end

-- =========================================================
-- Shared tooltip applicator
-- =========================================================

local function applyTooltip(row, opt, lbl, tooltipText)
    if opt.setToolTipText then opt:setToolTipText(tooltipText) end
    if lbl and lbl.setToolTipText then lbl:setToolTipText(tooltipText) end
    opt.toolTipText = tooltipText
    if lbl then lbl.toolTipText = tooltipText end
    if row.setToolTipText then row:setToolTipText(tooltipText) end
    row.toolTipText = tooltipText
    if opt.elements and opt.elements[1] and opt.elements[1].setText then
        opt.elements[1]:setText(tooltipText)
    end
end

-- =========================================================
-- Section Header
-- =========================================================

function TaxUIHelper.createSection(layout, textId)
    local section = nil
    for _, el in ipairs(layout.elements) do
        if el.name == "sectionHeader" then
            section = el:clone(layout)
            section.id = nil
            section:setText(getText(textId))
            layout:addElement(section)
            break
        end
    end
    return section
end

-- =========================================================
-- Binary Option (On/Off toggle)
-- =========================================================

function TaxUIHelper.createBinaryOption(layout, id, textId, state, callback)
    local template = nil

    for _, el in ipairs(layout.elements) do
        if el.elements and #el.elements >= 2 then
            local firstChild = el.elements[1]
            if firstChild.id and (
                string.find(firstChild.id, "^check") or
                string.find(firstChild.id, "Check")
            ) then
                template = el
                break
            end
        end
    end

    if not template then
        Logging.warning("TaxMod: BinaryOption template not found!")
        return nil
    end

    local row = template:clone(layout)
    row.id = nil

    local opt = row.elements[1]
    local lbl = row.elements[2]

    opt.id = nil
    if lbl then lbl.id = nil end

    if opt.toolTipText then opt.toolTipText = "" end
    if lbl and lbl.toolTipText then lbl.toolTipText = "" end

    local Bridge = {}
    local Bridge_mt = Class(Bridge)

    function Bridge.new(cb)
        local self = setmetatable({}, Bridge_mt)
        self._callback = cb
        return self
    end

    function Bridge:handleChange(newState)
        if self._callback then
            self._callback(newState == 2)
        end
    end

    local bridge = Bridge.new(callback)
    opt.target = bridge
    opt.onClickCallback = "handleChange"

    if lbl and lbl.setText then
        lbl:setText(getText(textId .. "_short"))
    end

    layout:addElement(row)

    if opt.setState then opt:setState(1) end

    if state then
        if opt.setIsChecked then
            opt:setIsChecked(true)
        elseif opt.setState then
            opt:setState(2)
        end
    end

    applyTooltip(row, opt, lbl, getText(textId .. "_long"))

    return opt
end

-- =========================================================
-- Multi-value Option
-- =========================================================

function TaxUIHelper.createMultiOption(layout, id, textId, options, state, callback)
    local template = nil

    for _, el in ipairs(layout.elements) do
        if el.elements and #el.elements >= 2 then
            local firstChild = el.elements[1]
            if firstChild.id and string.find(firstChild.id, "^multi") then
                template = el
                break
            end
        end
    end

    if not template then
        Logging.warning("TaxMod: MultiOption template not found!")
        return nil
    end

    local row = template:clone(layout)
    row.id = nil

    local opt = row.elements[1]
    local lbl = row.elements[2]

    opt.id     = nil
    opt.target = nil
    if lbl then lbl.id = nil end

    if opt.toolTipText then opt.toolTipText = "" end
    if lbl and lbl.toolTipText then lbl.toolTipText = "" end

    if opt.setTexts then
        opt:setTexts(options)
    end
    opt.numTexts = #options

    opt.onClickCallback = function(_, element)
        if not callback then return end
        local idx = type(element) == "number" and element
                 or (type(element) == "table" and element.state)
        if idx ~= nil then
            callback(idx)
        end
    end

    if lbl and lbl.setText then
        lbl:setText(getText(textId .. "_short"))
    end

    layout:addElement(row)

    if opt.setState then
        opt:setState(state)
    end

    applyTooltip(row, opt, lbl, getText(textId .. "_long"))

    return opt
end

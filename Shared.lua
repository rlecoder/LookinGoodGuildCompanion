local _, ns = ...

local function readable(value)
    return not issecretvalue or not issecretvalue(value)
end

local function clean(value)
    return (value:gsub("|", ""):gsub("[%c]", " "):match("^%s*(.-)%s*$"))
end

local function nameKey(name)
    return clean(name):lower():gsub("[%s_%-]+", " ")
end

local function playerName(unit)
    local first, last = UnitFullName(unit)
    if not readable(first) or type(first) ~= "string" or first == "" then return end
    if first:find("[ %-_]") then return (first:gsub("[_%-]+", " ")) end
    if not readable(last) then return end
    if type(last) == "string" and last ~= "" then return first .. " " .. last end
    return first
end

local function getChatOpener()
    return ChatFrameUtil and ChatFrameUtil.OpenChat or ChatFrame_OpenChat
end

local function button(parent, label, width, x, y, callback)
    local control = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    control:SetSize(width, 24)
    control:SetPoint("TOPLEFT", x, y)
    control:SetText(label)
    control:SetScript("OnClick", callback)
    return control
end

local function label(parent, value, x, y, template)
    local text = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
    text:SetPoint("TOPLEFT", x, y)
    text:SetText(value)
    return text
end

local function panel(width, height, x, y)
    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetSize(width, height)
    frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 24,
        insets = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    frame:Hide()
    return frame
end

local function editBox(parent, title, width, x, y, maxBytes)
    label(parent, title, x, y)
    local field = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    field:SetSize(width, 26)
    field:SetPoint("TOPLEFT", x + 4, y - 20)
    field:SetAutoFocus(false)
    field:SetMaxBytes(maxBytes)
    field:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return field
end

ns.title = "Lookin Good Guild Companion"
ns.getChatOpener = getChatOpener
ns.readable, ns.clean, ns.nameKey, ns.playerName = readable, clean, nameKey, playerName
ns.panel, ns.button, ns.label, ns.editBox = panel, button, label, editBox
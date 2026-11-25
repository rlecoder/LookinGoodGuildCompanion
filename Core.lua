local addon, namespace = ...
local events = CreateFrame("Frame")
local readable, clean, nameKey, playerName = namespace.readable, namespace.clean, namespace.nameKey, namespace.playerName
local panel, button, label, editBox = namespace.panel, namespace.button, namespace.label, namespace.editBox
local db, settings, popup, targetStatus
local plates, lastSound, lastPopup = {}, {}, {}
local active, bankOpen, selected
local gorillaSound = 550967
local soundCharacters = {
    ["khallum razorarrow"] = "Khallum Razorarrow",
    ["khallum razorshank"] = "Khallum Razorshank",
}

local function visibleGuildmate(unit)
    if InCombatLockdown and InCombatLockdown() then return nil, "Detection paused in combat." end
    local visible = UnitIsVisible(unit)
    if not readable(visible) or not visible then return nil, "No visible target." end
    local player = UnitIsPlayer(unit)
    local self = UnitIsUnit(unit, "player")
    if not readable(player) or not player or not readable(self) or self then
        return nil, "Target another player in your guild."
    end
    if UnitIsInMyGuild then
        local guildmate = UnitIsInMyGuild(unit)
        if not readable(guildmate) then return nil, "Guild membership is unavailable." end
        if not guildmate then return nil, "Target is outside your guild." end
    else
        local ownGuild = GetGuildInfo("player")
        local otherGuild = GetGuildInfo(unit)
        if not readable(ownGuild) or not readable(otherGuild) then return nil, "Guild membership is unavailable." end
        if not ownGuild or ownGuild == "" or ownGuild ~= otherGuild then return nil, "Target is outside your guild." end
    end
    local name = playerName(unit)
    if not name then return nil, "Target name is unavailable." end
    return name
end

local function inAlertRange(unit)
    -- Inspect interaction range is approximately 28 yards.
    local inRange = CheckInteractDistance(unit, 1)
    if readable(inRange) then return inRange end
end

local function whoIsNear(unit)
    local name = visibleGuildmate(unit)
    if name and inAlertRange(unit) then return name end
end

local function updateTargetStatus()
    local name, reason = visibleGuildmate("target")
    if not name then
        targetStatus:SetText(reason)
        return
    end
    local inRange = inAlertRange("target")
    local range = inRange == nil and "range unavailable" or inRange and "in range" or "out of range"
    targetStatus:SetText(name .. " · " .. range)
end

local function sayAvailable()
    return namespace.getChatOpener() or C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
end

local function greeting(name)
    return "Lookin Good " .. name .. "!"
end

local function playGorilla()
    PlaySoundFile(gorillaSound, "Master")
end

local function hidePopup()
    active = nil
    popup:Hide()
end

local function showPopup(kind, name, line, key, unit)
    active = { kind = kind, key = key, unit = unit, line = line, shown = GetTime() }
    local headings = { live = "Nearby: ", test = "Test: ", bank = "" }
    popup.title:SetText(headings[kind] .. name)
    popup.line:SetText(line)
    popup.action:SetShown(kind ~= "bank")
    popup.action:SetText(kind == "test" and "Preview" or "Say")
    popup.clickHint:SetShown(kind ~= "bank")
    popup.dismiss:SetShown(kind == "bank")
    popup:Show()
end

local function buildPopup()
    popup = panel(350, 158, 0, 160)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetMovable(true)
    if db.position then
        popup:ClearAllPoints()
        popup:SetPoint("CENTER", UIParent, "CENTER", db.position.x, db.position.y)
    end
    local drag = CreateFrame("Frame", nil, popup)
    drag:SetPoint("TOPLEFT", 10, -8)
    drag:SetPoint("TOPRIGHT", -10, -8)
    drag:SetHeight(34)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() popup:StartMoving() end)
    local function stopMoving()
        popup:StopMovingOrSizing()
        local x, y = popup:GetCenter()
        local centerX, centerY = UIParent:GetCenter()
        if x and centerX then
            db.position = { x = x - centerX, y = y - centerY }
        end
    end
    drag:SetScript("OnDragStop", stopMoving)
    popup:SetScript("OnHide", stopMoving)
    popup.title = label(drag, "", 8, -9, "GameFontNormalLarge")
    popup.title:SetWidth(310)
    popup.title:SetJustifyH("LEFT")
    popup.line = label(popup, "", 18, -43, "GameFontHighlight")
    popup.line:SetSize(314, 65)
    popup.line:SetJustifyH("LEFT")
    popup.line:SetJustifyV("TOP")
    popup.action = button(popup, "Say", 94, 18, -115, function(_, mouseButton)
        if mouseButton == "RightButton" then hidePopup(); return end
        if not active or active.kind ~= "live" or not db.say or not sayAvailable() then return end
        local name = active.unit and whoIsNear(active.unit)
        if not name or nameKey(name) ~= active.key then hidePopup(); return end
        local line = active.line
        hidePopup()
        local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
        if send then
            local ok, result = pcall(send, line, "SAY")
            if ok and readable(result) and result ~= false then return end
        end
        local openChat = namespace.getChatOpener()
        if openChat then openChat("/say " .. line) end
    end)
    popup.action:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    popup.clickHint = label(popup, "Right-click the button to hide", 120, -121, "GameFontHighlightSmall")
    popup.dismiss = button(popup, "Dismiss", 94, 238, -115, hidePopup)
end

local function showBankReminder()
    local gold, silver = math.floor(db.silver / 100), db.silver % 100
    local amount = gold > 0 and ("%d gold"):format(gold) or ""
    if silver > 0 then
        amount = amount .. (gold > 0 and " " or "") .. ("%d silver"):format(silver)
    end
    showPopup("bank", "Guild bank contribution", ("Please deposit %s if you'd like to contribute."):format(amount))
end

local function buildSettings()
    settings = panel(518, 429, 0, 0)
    label(settings, namespace.title, 18, -16, "GameFontNormal")
    button(settings, "Help", 57, 234, -14, namespace.OpenHelp)
    button(settings, "Professions", 105, 305, -14, namespace.OpenProfessions)
    button(settings, "Close", 78, 422, -14, function() settings:Hide() end)

    local function checkbox(title, key, x, y)
        local control = CreateFrame("CheckButton", nil, settings, "UICheckButtonTemplate")
        control:SetPoint("TOPLEFT", x, y)
        control:SetChecked(db[key])
        label(settings, title, x + 30, y - 8)
        control:SetScript("OnClick", function(self)
            db[key] = self:GetChecked()
            if active and ((key == "say" and active.kind == "live" and not db.say)
                or (key == "bank" and active.kind == "bank" and not db.bank)) then
                hidePopup()
            end
        end)
    end
    checkbox("Play gorilla alert", "sound", 15, -48)
    checkbox("Show /say popups", "say", 245, -48)
    checkbox("Mute sounds in instances", "mute", 15, -79)
    checkbox("Guild bank reminder", "bank", 245, -79)

    local status = label(settings, "", 18, -366, "GameFontHighlightSmall")
    targetStatus = label(settings, "", 18, -390, "GameFontHighlight")
    settings:SetScript("OnShow", updateTargetStatus)
    local silver = editBox(settings, "Contribution (silver)", 98, 18, -139, 7)
    local cooldown = editBox(settings, "Cooldown (seconds)", 98, 155, -139, 5)
    silver:SetNumeric(true)
    cooldown:SetNumeric(true)
    local function saveSettings()
        local amount, seconds = tonumber(silver:GetText()), tonumber(cooldown:GetText())
        if not amount or amount < 1 or not seconds or seconds < 1 then
            status:SetText("Enter a positive amount and cooldown.")
            return
        end
        db.silver, db.cooldown = amount, seconds
        silver:ClearFocus()
        cooldown:ClearFocus()
        status:SetText("Settings saved.")
        if active and active.kind == "bank" then showBankReminder() end
    end
    button(settings, "Save settings", 108, 277, -159, saveSettings)
    silver:SetText(tostring(db.silver))
    cooldown:SetText(tostring(db.cooldown))
    silver:SetScript("OnEnterPressed", saveSettings)
    cooldown:SetScript("OnEnterPressed", saveSettings)

    local name = editBox(settings, "Guildmate (First Last)", 260, 18, -202, 100)
    button(settings, "Play Sound", 98, 18, -277, playGorilla)
    button(settings, "Test Popup", 98, 126, -277, function()
        local sampleName = clean(name:GetText())
        if sampleName == "" then sampleName = "Example Guildmate" end
        showPopup("test", sampleName, greeting(sampleName))
    end)

    local function loadRule(key)
        selected = key
        local rule = db.members[key]
        name:SetText(rule and rule.name or "")
        status:SetText("")
    end

    local function browse(direction)
        local keys, current = {}, 0
        for key in pairs(db.members) do keys[#keys + 1] = key end
        table.sort(keys)
        if #keys == 0 then
            status:SetText("No saved guildmates.")
            return
        end
        for index, key in ipairs(keys) do
            if key == selected then current = index break end
        end
        if current == 0 and direction < 0 then current = 1 end
        loadRule(keys[(current + direction - 1) % #keys + 1])
    end
    button(settings, "<", 38, 290, -222, function() browse(-1) end)
    button(settings, ">", 38, 335, -222, function() browse(1) end)
    button(settings, "New", 66, 383, -222, function() loadRule(nil) end)
    button(settings, "Save guildmate", 124, 18, -313, function()
        local display = clean(name:GetText()):gsub("[_%-]+", " ")
        local key = nameKey(display)
        if key == "" then
            status:SetText("Enter the guildmate's name, including their surname if they have one.")
            return
        end
        if selected and selected ~= key and db.members[key] then
            status:SetText("That guildmate already exists. Select their saved entry to edit it.")
            return
        end
        if selected and selected ~= key then db.members[selected] = nil end
        db.members[key] = { name = display }
        loadRule(key)
        status:SetText("Saved " .. display .. ".")
    end)
    button(settings, "Delete guildmate", 134, 151, -313, function()
        if selected then
            db.members[selected] = nil
            loadRule(nil)
            status:SetText("Guildmate removed.")
        end
    end)
    button(settings, "Add Current Target", 145, 294, -313, function()
        local target, reason = visibleGuildmate("target")
        if not target then status:SetText(reason); return end
        local key = nameKey(target)
        if db.members[key] then
            loadRule(key)
            status:SetText("Loaded " .. target .. ".")
        else
            db.members[key] = { name = target }
            loadRule(key)
            status:SetText("Added " .. target .. ".")
        end
    end)
    label(settings, "Use < and > to browse saved guildmates. Drag the popup by its title.", 18, -340, "GameFontHighlightSmall")
    loadRule(nil)
end

local function toggleSettings()
    settings:SetShown(not settings:IsShown())
end

local function scan()
    if settings:IsShown() then updateTargetStatus() end
    local now = GetTime()
    local inInstance = IsInInstance()
    local canSound = db.sound and not (inInstance and db.mute)
    local canSay = db.say and sayAvailable()
    local nearby, soundKey = {}, nil
    local function check(unit)
        local name = whoIsNear(unit)
        if not name then return end
        local key = nameKey(name)
        if canSound and soundCharacters[key]
            and now - (lastSound[key] or -math.huge) >= db.cooldown
            and (not soundKey or key < soundKey) then
            soundKey = key
        end
        if canSay and db.members[key] and not nearby[key] then
            nearby[key] = { name = name, unit = unit }
        end
    end
    if canSound or canSay and next(db.members) then
        check("target")
        check("mouseover")
        for unit in pairs(plates) do check(unit) end
    end
    if active and active.kind == "live" then
        local candidate = nearby[active.key]
        if canSay and candidate and now - active.shown < 12 then
            active.unit = candidate.unit
        else
            hidePopup()
        end
    end
    local popupKey
    for key in pairs(nearby) do
        if canSay and not active and now - (lastPopup[key] or -math.huge) >= db.cooldown
            and (not popupKey or key < popupKey) then
            popupKey = key
        end
    end
    if soundKey then
        playGorilla()
        lastSound[soundKey] = now
    end
    if popupKey then
        showPopup("live", nearby[popupKey].name, greeting(nearby[popupKey].name), popupKey, nearby[popupKey].unit)
        lastPopup[popupKey] = now
    end
end

local function initialize()
    if type(LookinGoodGuildCompanionDB) ~= "table" then
        LookinGoodGuildCompanionDB = type(WowYouLookinGoodDB) == "table" and WowYouLookinGoodDB
            or type(GuildNearbyDB) == "table" and GuildNearbyDB or {}
    end
    db = LookinGoodGuildCompanionDB
    WowYouLookinGoodDB, GuildNearbyDB = nil, nil
    local defaults = { sound = true, say = true, mute = true, bank = true, silver = 100, cooldown = 180 }
    for key, value in pairs(defaults) do
        if db[key] == nil then db[key] = value end
    end
    db.members = db.members or {}
    if not db.khallumPresetsAdded then
        for key, name in pairs(soundCharacters) do
            db.members[key] = db.members[key] or { name = name }
        end
        if db.silver == 10 then db.silver = 100 end
        db.khallumPresetsAdded = true
    end
    buildPopup()
    buildSettings()
    namespace.InitProfessions(db)
    local minimap = CreateFrame("Button", nil, Minimap)
    minimap:SetSize(30, 30)
    minimap:SetPoint("CENTER", Minimap, "CENTER", -55, -55)
    minimap:SetFrameLevel(Minimap:GetFrameLevel() + 10)
    minimap:SetNormalTexture("Interface\\Icons\\INV_Misc_GroupNeedMore")
    minimap:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    minimap:SetScript("OnClick", toggleSettings)
    minimap:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(namespace.title)
        GameTooltip:AddLine("Click to open settings", 1, 1, 1)
        GameTooltip:Show()
    end)
    minimap:SetScript("OnLeave", function() GameTooltip:Hide() end)
    SLASH_LOOKINGOODGUILDCOMPANION1 = "/lgc"
    SLASH_LOOKINGOODGUILDCOMPANION2 = "/wylg"
    SLASH_LOOKINGOODGUILDCOMPANION3 = "/gn"
    SLASH_LOOKINGOODGUILDCOMPANION4 = "/guildnearby"
    SlashCmdList.LOOKINGOODGUILDCOMPANION = toggleSettings
    local elapsed = 0
    events:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed < 0.4 then return end
        elapsed = 0
        scan()
    end)
end

local function setBankOpen(open)
    if bankOpen == open then return end
    bankOpen = open
    if open and db.bank then
        showBankReminder()
    elseif not open and active and active.kind == "bank" then
        hidePopup()
    end
end

events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, arg)
    if event == "ADDON_LOADED" and arg == addon then
        initialize()
        self:UnregisterEvent("ADDON_LOADED")
        self:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        self:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("PLAYER_LEAVING_WORLD")
        for _, name in ipairs({ "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED",
            "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" }) do
            pcall(self.RegisterEvent, self, name)
        end
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if readable(arg) and type(arg) == "string" then plates[arg] = true end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if readable(arg) and type(arg) == "string" then
            plates[arg] = nil
        end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_LEAVING_WORLD" then
        if event == "PLAYER_LEAVING_WORLD" then plates = {} end
        setBankOpen(false)
        if active and active.kind == "live" then hidePopup() end
    elseif event == "GUILDBANKFRAME_OPENED" then
        setBankOpen(true)
    elseif event == "GUILDBANKFRAME_CLOSED" then
        setBankOpen(false)
    elseif readable(arg) and arg ~= nil and Enum and Enum.PlayerInteractionType
        and arg == Enum.PlayerInteractionType.GuildBanker then
        setBankOpen(event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
    end
end)
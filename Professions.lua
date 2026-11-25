local _, addon = ...
local prefix = "GuildNearbyProf"
local panel, search, title, status, back, rows, headings
local db, page, selected, loaded, registered
local incoming, migratedGuilds, pending, cursor = {}, {}, {}, 1
local scheduledRequests = {}
local sending, uploadAgain, generation, revision = false, false, 0, 0
local lastRequest, lastUpload = -math.huge, -math.huge
local lastSnapshot, lastGuild, skillsChanged
local observedSkills = {}
local REQUEST_INTERVAL, UPLOAD_INTERVAL = 60, 15
local PART_SIZE, MAX_PARTS = 190, 64

local function plain(value, kind)
    return addon.readable(value) and type(value) == kind
end

local function guildID()
    if not C_Club or not C_Club.GetGuildClubId then return end
    local ok, id = pcall(C_Club.GetGuildClubId)
    if not ok then return end
    if plain(id, "number") and id > 0 then return id end
    if plain(id, "string") and id:match("^%d+$") and id:find("[1-9]") then
        if #id <= 15 then return tonumber(id) end
        return id
    end
end

-- Forever uses two-part names. Addon messages can append a hidden realm suffix.
local function characterName(raw)
    local name = addon.clean(raw):gsub("[%s_%-]+", " ")
    return name:match("^(%S+ %S+)") or name
end

local function guildCache()
    local id = guildID()
    if not id then return end
    local cache = db[id] or {}
    db[id] = cache
    if not migratedGuilds[id] then
        local legacy = {}
        for key, entry in pairs(cache) do
            local name = characterName(entry.name)
            local canonical = addon.nameKey(name)
            if key == canonical then
                entry.name = name
            else
                legacy[key] = { key = canonical, name = name, skills = entry.skills }
            end
        end
        for key, entry in pairs(legacy) do
            cache[key] = nil
            if not cache[entry.key] then cache[entry.key] = { name = entry.name, skills = entry.skills } end
        end
        migratedGuilds[id] = true
    end
    return cache, id
end

local function ownName()
    return addon.playerName("player")
end

local function memberOnline(key)
    local self = ownName()
    if self and addon.nameKey(self) == key then return true end
    if not GetNumGuildMembers or not GetGuildRosterInfo then return end
    local count = GetNumGuildMembers()
    if not plain(count, "number") then return end
    for index = 1, count do
        local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(index)
        if plain(name, "string") and addon.nameKey(characterName(name)) == key then
            if plain(online, "boolean") then return online end
            return
        end
    end
end

local function skills()
    if not GetProfessions or not GetProfessionInfo then return end
    local indices = { GetProfessions() }
    local result = {}
    for _, index in pairs(indices) do
        if not plain(index, "number") then return end
        local name, _, rank, cap, _, _, skill = GetProfessionInfo(index)
        if not plain(name, "string") or not plain(skill, "number") or skill <= 0 then return end
        local getInfo = C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID
        if getInfo then
            local ok, info = pcall(getInfo, skill)
            if ok and plain(info, "table") and not (issecrettable and issecrettable(info))
                and plain(info.skillLevel, "number") and plain(info.maxSkillLevel, "number")
                and info.skillLevel >= 0 and info.maxSkillLevel > 0 and info.maxSkillLevel >= info.skillLevel then
                rank, cap = info.skillLevel, info.maxSkillLevel
            end
        end
        if not plain(rank, "number") or not plain(cap, "number") or rank < 0 or cap < rank or cap <= 0 then return end
        result[skill] = { name = name:gsub("[%c|~;]", ""), rank = rank, cap = cap }
    end
    return result
end

local function recipeName(id)
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    if plain(name, "string") and name ~= "" then return name end
    return ("Recipe #%d"):format(id)
end

local columns = {
    { title = "Name", width = 178 },
    { title = "Primary 1", width = 150 },
    { title = "Primary 2", width = 150 },
    { title = "Cooking", width = 86, skillID = 185 },
    { title = "Fishing", width = 86, skillID = 356 },
    { title = "First Aid", width = 86, skillID = 129 },
}
local secondaryIDs = { [185] = true, [356] = true, [129] = true }

local function memberRow(key, entry, query)
    local cells = { { text = entry.name, key = key } }
    local primaries = {}
    local matched = entry.name:lower():find(query, 1, true)
    for id, skill in pairs(entry.skills) do
        local rank = ("%d/%d"):format(skill.rank, skill.cap)
        matched = matched or (skill.name .. " " .. rank):lower():find(query, 1, true)
        if not secondaryIDs[id] then
            primaries[#primaries + 1] = { text = skill.name .. " " .. rank, key = key, id = id }
        end
    end
    if not matched then return end
    table.sort(primaries, function(a, b) return a.id < b.id end)
    cells[2], cells[3] = primaries[1], primaries[2]
    for index = 4, #columns do
        local id = columns[index].skillID
        local skill = entry.skills[id]
        if skill then
            cells[index] = { text = ("%d/%d"):format(skill.rank, skill.cap), key = key, id = id }
        end
    end
    return { text = entry.name, cells = cells }
end

local function refresh()
    if not panel or not panel:IsShown() then return end
    local cache = guildCache() or {}
    local results, query = {}, (search:GetText() or ""):lower()
    local member = selected and cache[selected.key]
    local profession = member and member.skills[selected.id]
    if selected and not profession then selected = nil end
    local online = selected and memberOnline(selected.key)
    back:SetShown(selected ~= nil)
    for _, heading in ipairs(headings) do heading:SetShown(selected == nil) end
    if selected then
        title:SetText(member.name .. " · " .. profession.name)
        for _, id in ipairs(profession.recipes or {}) do
            local name = recipeName(id)
            if name:lower():find(query, 1, true) then results[#results + 1] = { text = name } end
        end
    else
        title:SetText("Guild Professions")
        for key, entry in pairs(cache) do
            local row = memberRow(key, entry, query)
            if row then results[#results + 1] = row end
        end
    end
    table.sort(results, function(a, b) return a.text < b.text end)
    local pages = math.max(1, math.ceil(#results / #rows))
    page = math.min(pages, math.max(1, page))
    for index, row in ipairs(rows) do
        local entry = results[(page - 1) * #rows + index]
        row.recipe:SetShown(selected ~= nil and entry ~= nil)
        if selected and entry then row.recipe:SetText(entry.text) end
        for column, button in ipairs(row.cells) do
            local cell = entry and entry.cells and entry.cells[column]
            button.entry = cell
            button:SetShown(selected == nil and entry ~= nil)
            if entry and not selected then
                button:SetText(cell and cell.text or "—")
                button:SetEnabled(cell ~= nil)
            end
        end
    end
    if selected then
        local presence = online == false and "Offline · " or (online == nil and "Status unavailable · " or "")
        if profession.recipes then
            local snapshot = online and "Recipe snapshot" or "Saved recipes"
            local summary = #results > 0 and ("Page %d/%d"):format(page, pages)
                or (#query > 0 and "No matching entries." or "No recipes recorded.")
            status:SetText(("%s%s: %s · %s"):format(presence, snapshot, date("%Y-%m-%d", profession.captured), summary))
        else
            status:SetText(presence .. "No recipe snapshot yet.")
        end
    elseif #results == 0 then
        status:SetText(#query > 0 and "No matching entries." or "No entries to show.")
    else
        status:SetText(("%d guildmates · Page %d/%d"):format(#results, page, pages))
    end
end

local function send(message)
    if not registered or not guildID() then return end
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, prefix, message, "GUILD")
    local success = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success or 0
    return ok and plain(result, "number") and result == success
end

local function upload(changedOnly)
    local now = GetTime()
    if not registered or now - lastUpload < UPLOAD_INTERVAL then return end
    if sending then
        uploadAgain = uploadAgain or changedOnly
        return
    end
    local cache, guild = guildCache()
    local name = ownName()
    local list = skills()
    if not cache or not name or not list then return end
    local key = addon.nameKey(name)
    local old = cache[key]
    local timestamp = GetServerTime()
    for id, skill in pairs(list) do
        local previous = old and old.skills[id]
        if previous then skill.recipes, skill.captured = previous.recipes, previous.captured end
    end
    if next(list) then
        observedSkills[guild] = true
    elseif old and next(old.skills) and not (skillsChanged and observedSkills[guild]) then
        return
    end
    skillsChanged = false
    cache[key] = { name = name, skills = list }
    refresh()

    local records = {}
    for id, skill in pairs(list) do
        records[#records + 1] = ("%d~%d~%d~%s~%d~%s"):format(id, skill.rank, skill.cap, skill.name,
            skill.captured or 0, table.concat(skill.recipes or {}, ","))
    end
    table.sort(records)
    local snapshot = table.concat(records, ";")
    if changedOnly and guild == lastGuild and snapshot == lastSnapshot then return end
    local total = math.max(1, math.ceil(#snapshot / PART_SIZE))
    if total > MAX_PARTS then return end
    revision = revision + 1
    local version = ("%d.%d"):format(timestamp, revision)
    pending, cursor = {}, 1
    for part = 1, total do
        pending[part] = ("D:%s:%d:%d:%s"):format(version, part, total, snapshot:sub((part - 1) * PART_SIZE + 1, part * PART_SIZE))
    end
    lastUpload, sending = now, true
    local function finish()
        sending, pending = false, {}
        if uploadAgain then
            uploadAgain = false
            C_Timer.After(UPLOAD_INTERVAL, function() upload(true) end)
        end
    end
    local function nextPart()
        if guildID() ~= guild or not send(pending[cursor]) then finish(); return end
        cursor = cursor + 1
        if pending[cursor] then
            C_Timer.After(0.5, nextPart)
        else
            lastGuild, lastSnapshot = guild, snapshot
            finish()
        end
    end
    nextPart()
end

local function scheduleUpload(delay)
    generation = generation + 1
    local this = generation
    delay = math.max(delay, lastUpload + UPLOAD_INTERVAL - GetTime() + 0.1)
    C_Timer.After(delay, function()
        if generation == this then upload(true) end
    end)
end

local function capture()
    local api = C_TradeSkillUI
    if not api or not api.GetBaseProfessionInfo or not api.GetAllRecipeIDs or not api.GetRecipeInfo then return end
    if api.IsTradeSkillReady and api.IsTradeSkillReady() ~= true
        or api.IsDataSourceChanging and api.IsDataSourceChanging()
        or api.IsTradeSkillLinked and api.IsTradeSkillLinked()
        or api.IsTradeSkillGuild and api.IsTradeSkillGuild()
        or api.IsTradeSkillGuildMember and api.IsTradeSkillGuildMember()
        or api.IsNPCCrafting and api.IsNPCCrafting() then return end
    local info = api.GetBaseProfessionInfo()
    local id = plain(info, "table") and info.professionID
    if not plain(id, "number") then return end
    local cache, name, list = guildCache(), ownName(), skills()
    if not cache or not name or not list or not list[id] then return end
    local ids = api.GetAllRecipeIDs()
    if not plain(ids, "table") or issecrettable and issecrettable(ids) or #ids == 0 then return end
    local known = {}
    for _, recipe in ipairs(ids) do
        if not plain(recipe, "number") then return end
        local data = api.GetRecipeInfo(recipe)
        if not plain(data, "table") or issecrettable and issecrettable(data) or not plain(data.learned, "boolean") then return end
        if data.learned then known[#known + 1] = recipe end
    end
    table.sort(known)
    local key = addon.nameKey(name)
    local previous = cache[key] and cache[key].skills[id]
    if previous and previous.recipes and table.concat(previous.recipes, ",") == table.concat(known, ",") then return end
    local member = cache[key] or { name = name, skills = {} }
    cache[key] = member
    member.skills[id] = list[id]
    member.skills[id].recipes, member.skills[id].captured = known, GetServerTime()
    refresh()
    scheduleUpload(2)
end

local function replyToRequests(guild)
    if scheduledRequests[guild] then return end
    scheduledRequests[guild] = true
    local function reply()
        if guildID() ~= guild then
            scheduledRequests[guild] = nil
            return
        end
        local delay = lastUpload + UPLOAD_INTERVAL - GetTime()
        if sending or delay > 0 then
            C_Timer.After(math.max(1, delay + 0.1), reply)
            return
        end
        scheduledRequests[guild] = nil
        upload(false)
    end
    C_Timer.After(math.max(math.random(2, 9), lastUpload + UPLOAD_INTERVAL - GetTime() + 0.1), reply)
end

local function receive(message, sender)
    local cache, guild = guildCache()
    local self = ownName()
    if not cache or not plain(sender, "string") or not plain(message, "string") or #message > 255 then return end
    local name = characterName(sender)
    local key = addon.nameKey(name)
    if key == "" or self and key == addon.nameKey(self) then return end
    if message == "Q" then
        replyToRequests(guild)
        return
    end
    local version, part, total, data = message:match("^D:(%d+%.%d+):(%d+):(%d+):(.*)$")
    part, total = tonumber(part), tonumber(total)
    if not part or not total or part < 1 or part > total or total > MAX_PARTS or #data > PART_SIZE then return end
    local now = GetTime()
    for author, packet in pairs(incoming) do
        if now - packet.at > 40 or packet.guild ~= guild then incoming[author] = nil end
    end
    local packet = incoming[key]
    if not packet or packet.version ~= version then
        packet = { version = version, total = total, at = now, guild = guild, parts = {} }
        incoming[key] = packet
    end
    if packet.total ~= total then return end
    packet.parts[part] = data
    for index = 1, total do if packet.parts[index] == nil then return end end
    incoming[key] = nil
    local list = {}
    for line in table.concat(packet.parts):gmatch("[^;]+") do
        local id, rank, cap, name, captured, recipes = line:match("^(%d+)~(%d+)~(%d+)~([^%c|~;]+)~(%d+)~([%d,]*)$")
        id, rank, cap, captured = tonumber(id), tonumber(rank), tonumber(cap), tonumber(captured)
        if not id or id < 1 or id > 2147483647 or cap < 1 or cap > 2147483647 or rank > cap
            or captured > GetServerTime() + 300 or #name > 100 or list[id] then return end
        local skill = { name = name, rank = rank, cap = cap }
        if captured > 0 then
            skill.captured, skill.recipes = captured, {}
            for recipe in recipes:gmatch("%d+") do
                local spell = tonumber(recipe)
                if spell < 1 or spell > 2147483647 then return end
                skill.recipes[#skill.recipes + 1] = spell
            end
        end
        list[id] = skill
    end
    cache[key] = { name = name, skills = list }
    refresh()
end

function addon.OpenProfessions()
    if not loaded then return end
    panel:Show()
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
    refresh()
end

local function whisperMember(key)
    local cache = guildCache()
    local entry = cache and cache[key]
    if not entry or not memberOnline(key) then return end
    local tell = ChatFrameUtil and ChatFrameUtil.SendTell or ChatFrame_SendTell
    if tell then
        tell(entry.name)
    else
        local openChat = addon.getChatOpener()
        if openChat then openChat((SLASH_WHISPER1 or "/w") .. " " .. entry.name .. " ") end
    end
end

function addon.InitProfessions(saved)
    saved.professions = saved.professions or {}
    db, page, rows, headings = saved.professions, 1, {}, {}
    panel = addon.panel(794, 445, 0, 25)
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    title = addon.label(panel, "Guild Professions", 18, -17, "GameFontNormalLarge")
    addon.button(panel, "Close", 75, 701, -13, function() panel:Hide() end)
    search = addon.editBox(panel, "Search guildmates, professions or recipes", 320, 18, -47, 100)
    search:SetScript("OnTextChanged", function() page = 1; refresh() end)
    addon.button(panel, "Sync Now", 95, 373, -66, function()
        local now = GetTime()
        if now - lastRequest < REQUEST_INTERVAL then return end
        lastRequest = now
        upload(false)
        if not send("Q") then status:SetText("Guild sync unavailable right now.") end
    end)
    local x = 18
    for index, column in ipairs(columns) do
        headings[index] = addon.label(panel, column.title, x + 4, -104)
        x = x + column.width + 4
    end
    for index = 1, 8 do
        local y = -125 - (index - 1) * 28
        local row = { cells = {} }
        row.recipe = addon.label(panel, "", 22, y - 5, "GameFontHighlight")
        x = 18
        for columnIndex, column in ipairs(columns) do
            local cell = addon.button(panel, "", column.width, x, y, function(self, mouseButton)
                local entry = self.entry
                if not entry then return end
                if mouseButton == "RightButton" then
                    whisperMember(entry.key)
                elseif entry.id then
                    selected, page = entry, 1
                    search:SetText("")
                    refresh()
                end
            end)
            cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            row.cells[columnIndex] = cell
            x = x + column.width + 4
        end
        rows[index] = row
    end
    back = addon.button(panel, "Back", 65, 18, -361, function()
        selected, page = nil, 1
        search:SetText("")
        refresh()
    end)
    addon.button(panel, "<", 38, 656, -361, function() page = page - 1; refresh() end)
    addon.button(panel, ">", 38, 700, -361, function() page = page + 1; refresh() end)
    addon.label(panel, "Click a profession to view recipes. Right-click a guildmate or profession to whisper.", 18, -391, "GameFontHighlightSmall")
    status = addon.label(panel, "", 18, -415, "GameFontHighlightSmall")

    local events = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "SKILL_LINES_CHANGED", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "CHAT_MSG_ADDON", "GUILD_ROSTER_UPDATE", "INITIAL_CLUBS_LOADED", "PLAYER_GUILD_UPDATE" }) do
        pcall(events.RegisterEvent, events, event)
    end
    events:SetScript("OnEvent", function(_, event, protocol, message, channel, sender)
        if event == "CHAT_MSG_ADDON" then
            if plain(protocol, "string") and protocol == prefix and plain(channel, "string") and channel == "GUILD" then
                receive(message, sender)
            end
        elseif event == "GUILD_ROSTER_UPDATE" then
            refresh()
        elseif event == "TRADE_SKILL_LIST_UPDATE" or event == "TRADE_SKILL_DATA_SOURCE_CHANGED" then
            pcall(capture)
        elseif event == "SKILL_LINES_CHANGED" then
            skillsChanged = true
            scheduleUpload(3)
        elseif event == "INITIAL_CLUBS_LOADED" or event == "PLAYER_GUILD_UPDATE" and protocol == "player" then
            refresh()
            scheduleUpload(3)
        elseif event == "PLAYER_ENTERING_WORLD" and (protocol or message) then
            scheduleUpload(6)
        end
    end)
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix and C_ChatInfo.SendAddonMessage then
        local result = C_ChatInfo.RegisterAddonMessagePrefix(prefix)
        local codes = Enum and Enum.RegisterAddonMessagePrefixResult
        local success = codes and codes.Success or 0
        local duplicate = codes and codes.DuplicatePrefix or 1
        registered = result == success or result == duplicate
    end
    loaded = true
    SLASH_GUILDNEARBYPROF1 = "/gnprofs"
    SlashCmdList.GUILDNEARBYPROF = addon.OpenProfessions
    if IsLoggedIn and IsLoggedIn() then scheduleUpload(6) end
end
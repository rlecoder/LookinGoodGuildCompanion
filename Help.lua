local _, ns = ...
local window
local sections = {
    { "Setup", [[
Open settings from the minimap or type /lgc.

Target a guildmate and click Add Current Target to add them for greetings. Settings shows whether your target is in range. Friendly nameplates help detection.

You can also enter a First Last name and click Save guildmate. Use the arrows to browse saved entries. Test Popup lets you drag the popup without sending chat or starting the cooldown.
]] },
    { "Greetings & alerts", [[
Left-click Say to send Lookin Good followed by the guildmate’s name. Right-click Say to hide the popup. The guild bank popup suggests a voluntary deposit of 1 gold by default.

Only the two preset characters trigger the gorilla alert. Play Sound previews it. You can toggle the alert and mute it in instances.
]] },
    { "Professions", [[
Open Professions in settings or type /gnprofs. Guildmates running the addon share ranks at login and after skill changes. Sync Now requests updates.

Open your own profession window to share a recipe snapshot. Each guildmate has a row with two primary slots plus Cooking, Fishing, and First Aid. Left-click a profession to browse recipes. Right-click an online guildmate’s name or profession to whisper. Previously shared recipes can still be viewed offline, with the date they were recorded.
]] },
}

function ns.OpenHelp()
    if not window then
        window = ns.panel(538, 322, 0, 0)
        window:SetFrameStrata("FULLSCREEN_DIALOG")
        ns.label(window, ns.title .. " Help", 18, -17, "GameFontNormalLarge")
        ns.button(window, "Close", 70, 450, -12, function() window:Hide() end)
        local body = ns.label(window, sections[1][2], 18, -98, "GameFontHighlight")
        body:SetWidth(502)
        body:SetJustifyH("LEFT")
        for index, section in ipairs(sections) do
            ns.button(window, section[1], 148, 18 + (index - 1) * 155, -54, function()
                body:SetText(section[2])
            end)
        end
    end
    window:Show()
end
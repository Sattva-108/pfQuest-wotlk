-- ============================================================================
-- RXP COMPATIBILITY SHIM (STATIC)
-- ============================================================================
RXP = RXP or { enabledLocale = {} }
RXPGuides = RXPGuides or {}
RXPGuides_Data = RXPGuides_Data or {}

function RXPGuides.RegisterGuide(arg1, arg2, arg3)
    local content = (type(arg2) == "string" and arg2) or (type(arg1) == "string" and arg1)
    if content then table.insert(RXPGuides_Data, content) end
end

-- ============================================================================
-- CORE ENGINE INITIALIZATION & ROUTE HIJACK
-- ============================================================================
pfGuide = CreateFrame("Frame", "pfGuideFrame", UIParent)
pfGuide.loadedGuides = {}
pfGuide.currentGuide = nil
pfGuide.currentStepIndex = 1
pfGuide.completedLabels = {}
pfGuide.activePassiveSteps = {}
pfGuide.activeSteps = {}
pfGuide.currentWaypointIndex = 1
pfGuide.gameSeason = 0
pfGuide.xpRate = 1.0
pfGuide.isHardcore = true

pfGuide.RouteReset = pfQuest.route.Reset
pfGuide.RouteAddPoint = pfQuest.route.AddPoint
pfGuide.RouteSetTarget = pfQuest.route.SetTarget
pfQuest.route.Reset = function() end
pfQuest.route.AddPoint = function() end
pfQuest.route.SetTarget = function() end

function pfGuide:FormatMoney(copper)
    copper = tonumber(copper) or 0
    if copper >= 10000 then
        local g = math.floor(copper / 10000)
        local s = math.floor((copper % 10000) / 100)
        local c = copper % 100
        return string.format("%dg %ds %dc", g, s, c)
    elseif copper >= 100 then
        local s = math.floor(copper / 100)
        local c = copper % 100
        return (c > 0) and string.format("%ds %dc", s, c) or string.format("%ds", s)
    else
        return string.format("%dc", copper)
    end
end

-- ============================================================================
-- ZONE LOOKUP TABLE
-- ============================================================================
pfGuide.ZoneMap = {
    ["Dun Morogh"]=1, ["Elwynn Forest"]=12, ["Westfall"]=40, ["Loch Modan"]=38, ["Silverpine Forest"]=130,
    ["Tirisfal Glades"]=85, ["Redridge Mountains"]=44, ["Duskwood"]=10, ["Hillsbrad Foothills"]=267,
    ["Wetlands"]=11, ["Alterac Mountains"]=36, ["Arathi Highlands"]=45, ["Badlands"]=3, ["Swamp of Sorrows"]=8,
    ["Stranglethorn Vale"]=33, ["Searing Gorge"]=51, ["Burning Steppes"]=46, ["Western Plaguelands"]=28,
    ["Eastern Plaguelands"]=139, ["Blasted Lands"]=17, ["Stormwind City"]=1519, ["Ironforge"]=1537, ["Undercity"]=1497,
    ["Durotar"]=14, ["Mulgore"]=215, ["Teldrassil"]=141, ["Darkshore"]=148, ["The Barrens"]=17,
    ["Northern Barrens"]=17, ["Southern Barrens"]=17, ["Stonetalon Mountains"]=406, ["Ashenvale"]=331,
    ["Thousand Needles"]=400, ["Desolace"]=405, ["Dustwallow Marsh"]=15, ["Feralas"]=357, ["Tanaris"]=440,
    ["Azshara"]=16, ["Felwood"]=361, ["Un'Goro Crater"]=490, ["Silithus"]=1377, ["Winterspring"]=618,
    ["Moonglade"]=493, ["Orgrimmar"]=1637, ["Thunder Bluff"]=1638, ["Darnassus"]=1657, ["Eversong Woods"]=3430,
    ["Ghostlands"]=3433, ["Azuremyst Isle"]=3524, ["Bloodmyst Isle"]=3525, ["Hellfire Peninsula"]=3483,
    ["Zangarmarsh"]=3521, ["Terokkar Forest"]=3519, ["Nagrand"]=3518, ["Blade's Edge Mountains"]=3522,
    ["Netherstorm"]=3523, ["Shadowmoon Valley"]=3520, ["Shattrath City"]=3703, ["Silvermoon City"]=3487,
    ["The Exodar"]=3557, ["Borean Tundra"]=3537, ["Howling Fjord"]=495, ["Dragonblight"]=65, ["Grizzly Hills"]=394,
    ["Zul'Drak"]=66, ["Sholazar Basin"]=2817, ["The Storm Peaks"]=67, ["Icecrown"]=210, ["Dalaran"]=4395,
}

function pfGuide:GetZoneID(zoneName)
    if not zoneName then return nil end
    return pfGuide.ZoneMap[zoneName] or (pfDatabase and pfDatabase.GetMapIDByName and pfDatabase:GetMapIDByName(zoneName))
end

function pfGuide:GetWorldBounds(zoneId)
    if not zoneId then return nil end
    if pfDB and pfDB.worldmaparea and pfDB.worldmaparea.data and pfDB.worldmaparea.data[zoneId] then
        return pfDB.worldmaparea.data[zoneId]
    end
    return nil
end

function pfGuide:GetProjectedCoords(targetX, targetY, targetZoneId)
    if not targetX or not targetY then return targetX, targetY end

    local currentContinent = GetCurrentMapContinent()
    local currentZone = GetCurrentMapZone()
    local currentZoneId = pfMap:GetMapID(currentContinent, currentZone)

    if not targetZoneId or not currentZoneId or targetZoneId == currentZoneId then
        return targetX, targetY
    end

    local targetBounds = pfGuide:GetWorldBounds(targetZoneId)
    local currentBounds = pfGuide:GetWorldBounds(currentZoneId)

    if not targetBounds or not currentBounds or targetBounds[5] ~= currentBounds[5] then
        return targetX, targetY
    end

    -- Bounds: { LocLeft (col5), LocRight (col6), LocTop (col7), LocBottom (col8), mapID }
    local tLeft, tRight, tTop, tBottom = targetBounds[3], targetBounds[4], targetBounds[1], targetBounds[2]
    local cLeft, cRight, cTop, cBottom = currentBounds[3], currentBounds[4], currentBounds[1], currentBounds[2]

    local tWidthX = tLeft - tRight
    local tHeightY = tTop - tBottom
    local cWidthX = cLeft - cRight
    local cHeightY = cTop - cBottom

    if tWidthX <= 0 or tHeightY <= 0 or cWidthX <= 0 or cHeightY <= 0 then
        return targetX, targetY
    end

    -- Target local coords -> True World Coordinates
    -- targetX (horizontal 0..100) maps along LocLeft -> LocRight
    -- targetY (vertical 0..100) maps along LocTop -> LocBottom
    local targetWorldX = tLeft - (targetX / 100) * tWidthX
    local targetWorldY = tTop - (targetY / 100) * tHeightY

    -- True World Coordinates -> Player Zone Projected coords (%%)
    local projX = ((cLeft - targetWorldX) / cWidthX) * 100
    local projY = ((cTop - targetWorldY) / cHeightY) * 100

    return projX, projY
end

function pfGuide:GetQuestTitle(questId)
    if not questId then return "Unknown Quest" end
    local loc = pfDB and pfDB.quests and pfDB.quests.loc and pfDB.quests.loc[questId]
    return (type(loc) == "table" and loc.T) or loc or ("Quest #" .. questId)
end

function pfGuide:GetObjectiveProgress(questId, objIndex)
    if not questId then return nil, false end
    local questTitle = pfDB and pfDB.quests and pfDB.quests.loc and pfDB.quests.loc[questId]
    questTitle = type(questTitle) == "table" and questTitle.T or questTitle
    local numEntries = GetNumQuestLogEntries() or 0

    for qIndex = 1, numEntries do
        local qTitle, _, _, isHeader, _, isComplete = pfQuestCompat.GetQuestLogTitle(qIndex)
        if not isHeader then
            local ids = pfDatabase and pfDatabase.GetQuestIDs and pfDatabase:GetQuestIDs(qIndex)
            local matchId = ids and tonumber(ids[1])
            if matchId == tonumber(questId) or (questTitle and questTitle ~= "" and questTitle == qTitle) then
                local numObj = GetNumQuestLeaderBoards(qIndex) or 0
                if objIndex and objIndex <= numObj then
                    local text, _, done = GetQuestLogLeaderBoard(objIndex, qIndex)
                    if text and text ~= "" then return text, done or isComplete end
                end
                return qTitle, isComplete
            end
        end
    end
    return nil, false
end

function pfGuide:GetItemCount(itemId)
    if not itemId then return 0 end
    local count = GetItemCount(itemId) or 0
    if count > 0 then return count end

    for bag = -2, 4 do
        local slots = GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local link = GetContainerItemLink(bag, slot)
            if link and link:find("item:" .. itemId .. ":") then
                local _, itemCount = GetContainerItemInfo(bag, slot)
                count = count + (itemCount or 1)
            end
        end
    end
    return count
end

function pfGuide:IsCollectComplete(elem)
    if not elem or not elem.itemId then return 0, false end
    local count = pfGuide:GetItemCount(elem.itemId)
    local qty = elem.qty or 1
    local turnedIn = elem.questId and pfQuest_history and pfQuest_history[elem.questId]
    local onQuest = elem.questId and pfQuest.questlog and pfQuest.questlog[elem.questId]
    local isStarterItem = elem.questId and (
        elem.itemId == 4881 or elem.itemId == 4882 or
        (pfDatabase and pfDatabase.itemToQuest and pfDatabase.itemToQuest[elem.itemId])
    )
    return count, count >= qty or turnedIn or (onQuest and isStarterItem) or false
end

function pfGuide:IsQuestComplete(questId)
    if not questId then return false end
    if pfQuest_history and pfQuest_history[questId] then return true end
    local qData = pfQuest.questlog and pfQuest.questlog[questId]
    if qData and qData.qlogid then
        local _, _, _, _, _, isComplete = pfQuestCompat.GetQuestLogTitle(qData.qlogid)
        if isComplete then return true end
        local numObj = GetNumQuestLeaderBoards(qData.qlogid) or 0
        if numObj > 0 then
            for i = 1, numObj do
                local _, _, done = GetQuestLogLeaderBoard(i, qData.qlogid)
                if not done then return false end
            end
            return true
        end
    end
    return false
end

function pfGuide:GetDistanceToPoint(pX, pY, targetX, targetY, targetZoneId)
    if not pX or not pY or not targetX or not targetY or pX == 0 or pY == 0 then
        return math.huge, math.huge
    end

    local currentContinent = GetCurrentMapContinent()
    local currentZone = GetCurrentMapZone()
    local currentZoneId = pfMap:GetMapID(currentContinent, currentZone)

    local targetBounds = pfGuide:GetWorldBounds(targetZoneId)
    local currentBounds = pfGuide:GetWorldBounds(currentZoneId)

    if targetBounds and currentBounds and targetBounds[5] == currentBounds[5] then
        local tLeft, tRight, tTop, tBottom = targetBounds[3], targetBounds[4], targetBounds[1], targetBounds[2]
        local cLeft, cRight, cTop, cBottom = currentBounds[3], currentBounds[4], currentBounds[1], currentBounds[2]

        local targetWorldX = tLeft - (targetX / 100) * (tLeft - tRight)
        local targetWorldY = tTop - (targetY / 100) * (tTop - tBottom)

        local playerWorldX = cLeft - (pX / 100) * (cLeft - cRight)
        local playerWorldY = cTop - (pY / 100) * (cTop - cBottom)

        local dX = targetWorldX - playerWorldX
        local dY = targetWorldY - playerWorldY
        local yards = math.sqrt(dX * dX + dY * dY)
        return yards, yards / 16.0
    end

    local projX, projY = pfGuide:GetProjectedCoords(targetX, targetY, targetZoneId)
    local dX = (pX - projX) * 1.45
    local dY = (pY - projY)
    local mapDist = math.sqrt(dX * dX + dY * dY)
    local yards = mapDist * 16.0
    return yards, mapDist
end

function pfGuide:GetEquippedItemStat(slot, statName)
    local itemLink = GetInventoryItemLink("player", slot)
    if not itemLink then return 0 end
    if statName == "QUALITY" then
        local _, _, quality = GetItemInfo(itemLink)
        return quality or 0
    end
    local stats = GetItemStats(itemLink) or {}
    if stats[statName] then return stats[statName] end
    if statName == "ITEM_MOD_DAMAGE_PER_SECOND_SHORT" then
        pfGuide.scanTooltip = pfGuide.scanTooltip or CreateFrame("GameTooltip", "pfGuideScanTooltip", nil, "GameTooltipTemplate")
        local tt = pfGuide.scanTooltip
        tt:SetOwner(WorldFrame, "ANCHOR_NONE")
        tt:ClearLines()
        tt:SetInventoryItem("player", slot)
        for i = 1, tt:NumLines() do
            local text = _G["pfGuideScanTooltipTextLeft" .. i] and _G["pfGuideScanTooltipTextLeft" .. i]:GetText() or ""
            local dps = text:match("(%d+%.?%d*)%s+damage per second") or text:match("(%d+%.?%d*)%s+единиц урона в секунду")
            if dps then return tonumber(dps) or 0 end
        end
    end
    return 0
end

-- ============================================================================
-- UI WINDOW & DEBUG DIALOG
-- ============================================================================
local pfGuideWindow = CreateFrame("Frame", "pfQuestGuideWindow", UIParent)
pfGuideWindow:SetWidth(360)
pfGuideWindow:SetHeight(75)
pfGuideWindow:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -100)
pfGuideWindow:SetFrameStrata("HIGH")
pfGuideWindow:SetMovable(true)
pfGuideWindow:EnableMouse(true)
pfGuideWindow:RegisterForDrag("LeftButton")
pfGuideWindow:SetScript("OnDragStart", function() this:StartMoving() end)
pfGuideWindow:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
pfGuideWindow:SetClampedToScreen(true)
pfGuideWindow:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
})
pfGuideWindow:SetBackdropColor(0, 0, 0, 0.85)
pfGuideWindow:SetBackdropBorderColor(0.2, 0.8, 1, 1)

pfGuideWindow.title = pfGuideWindow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
pfGuideWindow.title:SetPoint("TOPLEFT", pfGuideWindow, "TOPLEFT", 8, -6)
pfGuideWindow.title:SetText("RXP Guide")

pfGuideWindow.text = pfGuideWindow:CreateFontString(nil, "OVERLAY", "GameFontWhite")
pfGuideWindow.text:SetPoint("TOPLEFT", pfGuideWindow.title, "BOTTOMLEFT", 0, -4)
pfGuideWindow.text:SetPoint("BOTTOMRIGHT", pfGuideWindow, "BOTTOMRIGHT", -8, 8)
pfGuideWindow.text:SetJustifyH("LEFT")
pfGuideWindow.text:SetJustifyV("TOP")
pfGuideWindow.text:SetWordWrap(true)
pfGuideWindow.text:SetNonSpaceWrap(false)
pfGuideWindow.text:SetText("No guide loaded.")

pfGuideWindow.prevBtn = CreateFrame("Button", nil, pfGuideWindow, "UIPanelButtonTemplate")
pfGuideWindow.prevBtn:SetSize(20, 18)
pfGuideWindow.prevBtn:SetPoint("TOPRIGHT", pfGuideWindow, "TOPRIGHT", -26, -4)
pfGuideWindow.prevBtn:SetText("<")
pfGuideWindow.prevBtn:RegisterForClicks("LeftButtonUp")
pfGuideWindow.prevBtn:SetScript("OnClick", function()
    pfGuide:PrevStep()
end)

pfGuideWindow.nextBtn = CreateFrame("Button", nil, pfGuideWindow, "UIPanelButtonTemplate")
pfGuideWindow.nextBtn:SetSize(20, 18)
pfGuideWindow.nextBtn:SetPoint("TOPRIGHT", pfGuideWindow, "TOPRIGHT", -4, -4)
pfGuideWindow.nextBtn:SetText(">")
pfGuideWindow.nextBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
pfGuideWindow.nextBtn:SetScript("OnClick", function(self, button)
    if button == "RightButton" then
        if pfGuide.currentGuide then
            pfGuide.currentStepIndex = pfGuide:FindFurthestActiveStep(pfGuide.currentGuide)
            pfGuide.furthestStepIndex = pfGuide.currentStepIndex
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[pfGuide]|r Fast-Forwarded to Step %d/%d", pfGuide.currentStepIndex, #pfGuide.currentGuide.steps))
            pfGuide:FindNearestWaypoint()
            pfGuide:ExecuteCurrentStep()
            pfGuide:UpdateUI()
        end
    else
        pfGuide:NextStep(true)
    end
end)

pfGuideWindow.debugBtn = CreateFrame("Button", nil, pfGuideWindow, "UIPanelButtonTemplate")
pfGuideWindow.debugBtn:SetSize(20, 18)
pfGuideWindow.debugBtn:SetPoint("TOPRIGHT", pfGuideWindow.prevBtn, "TOPLEFT", -2, 0)
pfGuideWindow.debugBtn:SetText("?")
pfGuideWindow.debugBtn:SetScript("OnClick", function()
    local guide = pfGuide.currentGuide
    local step = guide and guide.steps[pfGuide.currentStepIndex]
    if step then
        pfGuide.activeDebugText = string.format("Guide: %s\nStep: %d/%d\n\n%s", guide.name, pfGuide.currentStepIndex, #guide.steps, step.rawText or "")
        StaticPopup_Show("PFGUIDE_STEP_DEBUG")
    end
end)

StaticPopupDialogs["PFGUIDE_STEP_DEBUG"] = {
    text = "Current RXP Step Data (Press Ctrl+C to copy):",
    button1 = "Close",
    hasEditBox = true,
    hasWideEditBox = true,
    OnShow = function(self)
        local editBox = _G[self:GetName().."WideEditBox"] or _G[self:GetName().."EditBox"]
        if editBox then
            editBox:SetText(pfGuide.activeDebugText or "")
            editBox:HighlightText()
            editBox:SetFocus()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

SLASH_PFGUIDE1 = "/guide"
SLASH_PFGUIDE2 = "/rxp"
SlashCmdList["PFGUIDE"] = function(msg)
    msg = msg and msg:match("^%s*(.-)%s*$") or ""
    if msg == "hc" or msg == "hardcore" then
        local guideName = pfGuide.currentGuide and pfGuide.currentGuide.name
        pfGuide.isHardcore = not pfGuide.isHardcore
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[pfGuide]|r Mode changed to: %s", pfGuide.isHardcore and "|cffff0000HARDCORE (No Deathskips)|r" or "|cff00ff00SOFTCORE|r"))
        if guideName then
            pfGuide:LoadAllGuides()
            pfGuide:SetCurrentGuide(guideName)
        end
    elseif msg == "list" then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[pfGuide]|r Loaded Guides:")
        for name in pairs(pfGuide.loadedGuides) do DEFAULT_CHAT_FRAME:AddMessage(" - " .. name) end
    elseif msg ~= "" and pfGuide.loadedGuides[msg] then
        pfGuide:SetCurrentGuide(msg)
    else
        if pfGuideWindow:IsShown() then pfGuideWindow:Hide() else pfGuideWindow:Show() end
    end
end

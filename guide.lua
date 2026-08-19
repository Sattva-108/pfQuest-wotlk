-- ============================================================================
-- RXP COMPATIBILITY SHIM (DATA STORAGE)
-- ============================================================================
RXP = RXP or {}
RXP.enabledLocale = RXP.enabledLocale or {}

RXPGuides = RXPGuides or {}
RXPGuides_Data = RXPGuides_Data or {}

function RXPGuides.RegisterGuide(arg1, arg2, arg3)
    local content = (type(arg2) == "string" and arg2) or (type(arg1) == "string" and arg1)
    if content then
        table.insert(RXPGuides_Data, content)
    end
end

-- ============================================================================
-- MAIN PFQUEST RXP GUIDE ENGINE
-- ============================================================================
pfGuide = CreateFrame("Frame", "pfGuideFrame", UIParent)
pfGuide.loadedGuides = {}
pfGuide.currentGuide = nil
pfGuide.currentStepIndex = 1
pfGuide.currentGuideKey = nil
pfGuide.completedLabels = {}
pfGuide.currentWaypointIndex = 1

-- WotLK 3.3.5 settings
pfGuide.gameSeason = 0  -- 0 = Normal / WotLK, 1 = SoM, 2 = SoD
pfGuide.xpRate = 1.0    -- Default 1.0x rate

-- Hijack pfQuest route to control arrow navigation directly
pfGuide.RouteReset = pfQuest.route.Reset
pfGuide.RouteAddPoint = pfQuest.route.AddPoint
pfGuide.RouteSetTarget = pfQuest.route.SetTarget

pfQuest.route.Reset = function() end
pfQuest.route.AddPoint = function() end
pfQuest.route.SetTarget = function() end

-- ============================================================================
-- ZONE NAME TO ZONE ID MAPPING
-- ============================================================================
pfGuide.ZoneMap = {
    -- Eastern Kingdoms
    ["Dun Morogh"] = 1, ["Elwynn Forest"] = 12, ["Westfall"] = 40, ["Loch Modan"] = 38,
    ["Silverpine Forest"] = 130, ["Tirisfal Glades"] = 85, ["Redridge Mountains"] = 44,
    ["Duskwood"] = 10, ["Hillsbrad Foothills"] = 267, ["Wetlands"] = 11, ["Alterac Mountains"] = 36,
    ["Arathi Highlands"] = 45, ["Badlands"] = 3, ["Swamp of Sorrows"] = 8, ["Stranglethorn Vale"] = 33,
    ["Searing Gorge"] = 51, ["Burning Steppes"] = 46, ["Western Plaguelands"] = 28,
    ["Eastern Plaguelands"] = 139, ["Blasted Lands"] = 17, ["Stormwind City"] = 1519,
    ["Ironforge"] = 1537, ["Undercity"] = 1497,

    -- Kalimdor
    ["Durotar"] = 14, ["Mulgore"] = 215, ["Teldrassil"] = 141, ["Darkshore"] = 148,
    ["The Barrens"] = 17, ["Northern Barrens"] = 17, ["Southern Barrens"] = 17,
    ["Stonetalon Mountains"] = 406, ["Ashenvale"] = 331, ["Thousand Needles"] = 400,
    ["Desolace"] = 405, ["Dustwallow Marsh"] = 15, ["Feralas"] = 357, ["Tanaris"] = 440,
    ["Azshara"] = 16, ["Felwood"] = 361, ["Un'Goro Crater"] = 490, ["Silithus"] = 1377,
    ["Winterspring"] = 618, ["Moonglade"] = 493, ["Orgrimmar"] = 1637,
    ["Thunder Bluff"] = 1638, ["Darnassus"] = 1657,

    -- TBC / Outland
    ["Eversong Woods"] = 3430, ["Ghostlands"] = 3433, ["Azuremyst Isle"] = 3524,
    ["Bloodmyst Isle"] = 3525, ["Hellfire Peninsula"] = 3483, ["Zangarmarsh"] = 3521,
    ["Terokkar Forest"] = 3519, ["Nagrand"] = 3518, ["Blade's Edge Mountains"] = 3522,
    ["Netherstorm"] = 3523, ["Shadowmoon Valley"] = 3520, ["Shattrath City"] = 3703,
    ["Silvermoon City"] = 3487, ["The Exodar"] = 3557,

    -- WotLK / Northrend
    ["Borean Tundra"] = 3537, ["Howling Fjord"] = 495, ["Dragonblight"] = 65,
    ["Grizzly Hills"] = 394, ["Zul'Drak"] = 66, ["Sholazar Basin"] = 2817,
    ["The Storm Peaks"] = 67, ["Icecrown"] = 210, ["Crystalsong Forest"] = 2817,
    ["Hrothgar's Landing"] = 4742, ["Dalaran"] = 4395, ["Wintergrasp"] = 4197,
}

function pfGuide:GetZoneID(zoneName)
    if not zoneName then return nil end
    if pfGuide.ZoneMap[zoneName] then
        return pfGuide.ZoneMap[zoneName]
    end
    if pfDatabase and pfDatabase.GetMapIDByName then
        local id = pfDatabase:GetMapIDByName(zoneName)
        if id then return id end
    end
    return nil
end

-- ============================================================================
-- HELPER: GET QUEST AND OBJECTIVE NAMES FROM PFDB & QUESTLOG
-- ============================================================================
function pfGuide:GetQuestTitle(questId)
    if not questId then return "Unknown Quest" end
    if pfDB and pfDB.quests and pfDB.quests.loc and pfDB.quests.loc[questId] then
        local locData = pfDB.quests.loc[questId]
        if type(locData) == "table" and locData.T then
            return locData.T
        elseif type(locData) == "string" then
            return locData
        end
    end
    return "Quest #" .. questId
end

function pfGuide:GetObjectiveProgress(questId, objIndex)
    if not questId then return nil, false end
    local qData = pfQuest.questlog and pfQuest.questlog[questId]
    if qData and qData.qlogid then
        local text, typeStr, done = GetQuestLogLeaderBoard(objIndex or 1, qData.qlogid)
        if text and text ~= "" then
            return text, done
        end
    end
    return nil, false
end

-- ============================================================================
-- CONDITION CHECKER (Applies)
-- ============================================================================
function pfGuide:Applies(conditionStr)
    if not conditionStr or conditionStr == "" then return true end

    local _, playerClass = UnitClass("player")
    local _, playerRace = UnitRace("player")
    local playerFaction = UnitFactionGroup("player")
    local playerLevel = UnitLevel("player") or 1

    playerClass = string.upper(playerClass or "")
    playerRace = playerRace or ""
    playerFaction = playerFaction or ""

    if playerRace == "Scourge" then playerRace = "Undead" end

    for branch in string.gmatch(conditionStr, "[^/]+") do
        local branchValid = true

        for token in string.gmatch(branch, "!?[%w%d]+") do
            local isNegated = (token:sub(1, 1) == "!")
            local name = isNegated and token:sub(2) or token
            local upper = string.upper(name)

            local match = false
            if upper == playerClass or name == playerRace or name == playerFaction or upper == "WOTLK" or upper == "CLASSIC" or upper == "TBC" then
                match = true
            elseif tonumber(name) then
                if playerLevel >= tonumber(name) then
                    match = true
                end
            end

            if (not match and not isNegated) or (match and isNegated) then
                branchValid = false
                break
            end
        end

        if branchValid then
            return true
        end
    end

    return false
end

-- ============================================================================
-- RXP PARSER
-- ============================================================================
function pfGuide:ParseGuideText(rawText)
    local guide = {
        name = "Unknown Guide",
        group = "Default",
        defaultFor = nil,
        next = nil,
        labels = {},
        steps = {}
    }

    local currentStep = nil
    local stepCounter = 0
    local skipCurrentStep = false

    for line in string.gmatch(rawText, "[^\r\n]+") do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        line = line:gsub("%-%-.*$", ""):gsub("^%s+", ""):gsub("%s+$", "")

        if line ~= "" then
            if line:sub(1, 4) == "step" then
                local stepCondition = line:match("^step%s*<<%s*(.+)$")
                if stepCondition and not pfGuide:Applies(stepCondition) then
                    skipCurrentStep = true
                    currentStep = nil
                else
                    skipCurrentStep = false
                    stepCounter = stepCounter + 1
                    currentStep = {
                        index = stepCounter,
                        elements = {},
                        gotoPoints = {},
                        text = "",
                        hasAcceptOrTurnIn = false,
                        hasComplete = false,
                        requires = nil,
                        label = nil,
                        completeWith = nil,
                        isLoop = false
                    }
                    table.insert(guide.steps, currentStep)
                end

            elseif not currentStep and line:sub(1, 1) == "#" then
                local tag, val = line:match("^#(%S+)%s*(.*)")
                tag = string.lower(tag or "")
                if tag == "name" then
                    guide.name = val
                elseif tag == "group" then
                    guide.group = val
                elseif tag == "defaultfor" then
                    guide.defaultFor = val
                elseif tag == "next" then
                    guide.next = val
                end

            elseif currentStep and not skipCurrentStep then
                if line:sub(1, 1) == "#" then
                    local tag, val = line:match("^#(%S+)%s*(.*)")
                    tag = string.lower(tag or "")

                    if tag == "season" then
                        local seasonNum = tonumber(val) or 0
                        if seasonNum ~= pfGuide.gameSeason then
                            table.remove(guide.steps)
                            stepCounter = stepCounter - 1
                            currentStep = nil
                            skipCurrentStep = true
                        end
                    elseif tag == "xprate" then
                        local op, rate = val:match("([<>]?)(%d+%.?%d*)")
                        rate = tonumber(rate) or 1.0
                        if (op == "<" and pfGuide.xpRate >= rate) or (op == ">" and pfGuide.xpRate <= rate) then
                            table.remove(guide.steps)
                            stepCounter = stepCounter - 1
                            currentStep = nil
                            skipCurrentStep = true
                        end
                    elseif tag == "label" then
                        currentStep.label = val
                        guide.labels[val] = currentStep.index
                    elseif tag == "requires" then
                        currentStep.requires = val
                    elseif tag == "completewith" then
                        currentStep.completeWith = val
                    elseif tag == "loop" then
                        currentStep.isLoop = true
                    elseif tag == "sticky" then
                        currentStep.sticky = true
                    end

                elseif currentStep and line:sub(1, 1) == "." then
                    local lineCondition = line:match("<<%s*(.+)$")
                    local lineValid = true
                    if lineCondition then
                        line = line:gsub("%s*<<.*$", "")
                        lineValid = pfGuide:Applies(lineCondition)
                    end

                    if lineValid then
                        local directive, rest = line:match("^%.(%S+)%s*(.*)")
                        directive = string.lower(directive or "")

                        local descText = rest:match(">>%s*(.*)")
                        local argsStr = descText and rest:gsub("%s*>>.*$", "") or rest

                        local args = {}
                        for arg in string.gmatch(argsStr, "[^,]+") do
                            table.insert(args, arg:match("^%s*(.-)%s*$"))
                        end

                        local element = {
                            tag = directive,
                            args = args,
                            text = descText or ""
                        }

                        if directive == "goto" then
                            element.zone = args[1]
                            element.x = tonumber(args[2])
                            element.y = tonumber(args[3])
                            element.radius = tonumber(args[4]) or 10
                            table.insert(currentStep.gotoPoints, element)
                        elseif directive == "accept" or directive == "turnin" then
                            element.questId = tonumber(args[1])
                            currentStep.hasAcceptOrTurnIn = true
                        elseif directive == "complete" then
                            element.questId = tonumber(args[1])
                            element.objIndex = tonumber(args[2]) or 1
                            currentStep.hasComplete = true
                        elseif directive == "xp" then
                            element.xpTarget = args[1]
                        end

                        table.insert(currentStep.elements, element)

                        if descText and descText ~= "" and currentStep.text == "" then
                            currentStep.text = descText
                        end
                    end

                elseif currentStep and (line:sub(1, 1) == "+" or line:sub(1, 1) == "*") then
                    local lineCondition = line:match("<<%s*(.+)$")
                    local lineValid = true
                    if lineCondition then
                        line = line:gsub("%s*<<.*$", "")
                        lineValid = pfGuide:Applies(lineCondition)
                    end

                    if lineValid then
                        local text = line:sub(2):match("^%s*(.-)%s*$")
                        table.insert(currentStep.elements, {
                            tag = "info",
                            text = text
                        })
                        if currentStep.text == "" then
                            currentStep.text = text
                        end
                    end
                end
            end
        end
    end

    local validSteps = {}
    for _, s in ipairs(guide.steps) do
        if #s.elements > 0 then
            table.insert(validSteps, s)
            s.index = #validSteps
            if s.label then
                guide.labels[s.label] = s.index
            end
        end
    end
    guide.steps = validSteps

    return guide
end

-- ============================================================================
-- LOAD ALL GUIDES INTO REGISTRY
-- ============================================================================
function pfGuide:LoadAllGuides()
    pfGuide.loadedGuides = {}
    for i, rawText in ipairs(RXPGuides_Data) do
        local guide = pfGuide:ParseGuideText(rawText)
        if guide and #guide.steps > 0 then
            pfGuide.loadedGuides[guide.name] = guide
        end
    end
end

function pfGuide:FindDefaultGuide()
    for name, guide in pairs(pfGuide.loadedGuides) do
        if guide.defaultFor and pfGuide:Applies(guide.defaultFor) then
            return guide
        end
    end

    for name, guide in pairs(pfGuide.loadedGuides) do
        return guide
    end
    return nil
end

function pfGuide:SetCurrentGuide(guideName)
    local guide = pfGuide.loadedGuides[guideName]
    if not guide then return end

    pfGuide.currentGuide = guide
    pfGuide.currentGuideKey = guide.name
    pfGuide.currentStepIndex = 1
    pfGuide.completedLabels = {}
    pfGuide.currentWaypointIndex = 1

    pfGuide:ExecuteCurrentStep()
    pfGuide:UpdateUI()
end

-- ============================================================================
-- STEP EXECUTION & NAVIGATION
-- ============================================================================
function pfGuide:PointToCoords(x, y, zoneId, title)
    if not x or not y then return end

    local node = {
        [1] = x,
        [2] = y,
        [3] = {
            title = title or "RXP Objective",
            texture = pfQuestConfig.path .. "\\img\\cluster_mob",
            qlvl = 0
        }
    }

    pfGuide.RouteReset(pfQuest.route)
    pfGuide.RouteAddPoint(pfQuest.route, node)
    pfGuide.RouteSetTarget(pfQuest.route, node[3])

    if pfQuest.route.arrow then
        pfQuest.route.arrow:Show()
    end
end

function pfGuide:ExecuteCurrentStep()
    local guide = pfGuide.currentGuide
    if not guide or not guide.steps[pfGuide.currentStepIndex] then return end

    local step = guide.steps[pfGuide.currentStepIndex]

    -- Check #requires dependency
    if step.requires and not pfGuide.completedLabels[step.requires] then
        pfGuide:NextStep()
        return
    end

    local targetFound = false

    -- 1. Check for .goto waypoint points
    if #step.gotoPoints > 0 then
        local wp = step.gotoPoints[pfGuide.currentWaypointIndex] or step.gotoPoints[1]
        if wp and wp.x and wp.y then
            local zoneId = pfGuide:GetZoneID(wp.zone)
            local title = wp.text ~= "" and wp.text or step.text
            pfGuide:PointToCoords(wp.x, wp.y, zoneId, title)
            targetFound = true
        end
    end

    -- 2. Fallback to pfDB database coordinates
    if not targetFound then
        for _, elem in ipairs(step.elements) do
            if elem.tag == "accept" and elem.questId and pfDB.quests and pfDB.quests.data[elem.questId] then
                local qData = pfDB.quests.data[elem.questId]
                if qData.start and qData.start.U and qData.start.U[1] then
                    local uData = pfDB.units and pfDB.units.data[qData.start.U[1]]
                    if uData and uData.coords and uData.coords[1] then
                        pfGuide:PointToCoords(uData.coords[1][1], uData.coords[1][2], uData.coords[1][3], step.text)
                        targetFound = true
                        break
                    end
                end
            elseif (elem.tag == "turnin" or elem.tag == "complete") and elem.questId and pfDB.quests and pfDB.quests.data[elem.questId] then
                local qData = pfDB.quests.data[elem.questId]
                if qData["end"] and qData["end"].U and qData["end"].U[1] then
                    local uData = pfDB.units and pfDB.units.data[qData["end"].U[1]]
                    if uData and uData.coords and uData.coords[1] then
                        pfGuide:PointToCoords(uData.coords[1][1], uData.coords[1][2], uData.coords[1][3], step.text)
                        targetFound = true
                        break
                    end
                end
            end
        end
    end

    pfGuide:UpdateUI()
end

function pfGuide:CheckStepCompletion()
    local guide = pfGuide.currentGuide
    if not guide or not guide.steps[pfGuide.currentStepIndex] then return end

    local step = guide.steps[pfGuide.currentStepIndex]
    local isCompleted = true

    -- Check #completewith label condition
    if step.completeWith then
        if step.completeWith ~= "next" and pfGuide.completedLabels[step.completeWith] then
            pfGuide:NextStep()
            return
        end
    end

    -- Check step elements
    for _, elem in ipairs(step.elements) do
        if elem.tag == "accept" and elem.questId then
            local onQuest = pfQuest.questlog and pfQuest.questlog[elem.questId]
            local inHistory = pfQuest_history and pfQuest_history[elem.questId]
            if not onQuest and not inHistory then
                isCompleted = false
            end
        elseif elem.tag == "turnin" and elem.questId then
            local inHistory = pfQuest_history and pfQuest_history[elem.questId]
            if not inHistory then
                isCompleted = false
            end
        elseif elem.tag == "complete" and elem.questId then
            local qData = pfQuest.questlog and pfQuest.questlog[elem.questId]
            if not qData then
                local inHistory = pfQuest_history and pfQuest_history[elem.questId]
                if not inHistory then isCompleted = false end
            else
                local qlogid = qData.qlogid
                if qlogid then
                    local _, _, done = GetQuestLogLeaderBoard(elem.objIndex or 1, qlogid)
                    if not done then isCompleted = false end
                else
                    isCompleted = false
                end
            end
        end
    end

    -- Process waypoint distance progression
    if #step.gotoPoints > 0 then
        local pX, pY = GetPlayerMapPosition("player")
        pX, pY = pX * 100, pY * 100
        local wp = step.gotoPoints[pfGuide.currentWaypointIndex]
        if wp and pX > 0 and pY > 0 then
            local dist = math.sqrt((pX - wp.x)^2 + (pY - wp.y)^2)
            if dist <= (wp.radius or 10) then
                if pfGuide.currentWaypointIndex < #step.gotoPoints then
                    pfGuide.currentWaypointIndex = pfGuide.currentWaypointIndex + 1
                    pfGuide:ExecuteCurrentStep()
                elseif step.isLoop then
                    pfGuide.currentWaypointIndex = 1
                    pfGuide:ExecuteCurrentStep()
                end
            end
        end

        -- If step has no quest directives, complete upon reaching last waypoint
        if not step.hasAcceptOrTurnIn and not step.hasComplete and pfGuide.currentWaypointIndex >= #step.gotoPoints then
            local lastWp = step.gotoPoints[#step.gotoPoints]
            local dist = math.sqrt((pX - lastWp.x)^2 + (pY - lastWp.y)^2)
            if dist > (lastWp.radius or 10) then
                isCompleted = false
            end
        end
    end

    if isCompleted and #step.elements > 0 then
        if step.label then
            pfGuide.completedLabels[step.label] = true
        end
        pfGuide:NextStep()
    else
        -- Update UI live so kill/loot counts refresh immediately
        pfGuide:UpdateUI()
    end
end

function pfGuide:NextStep()
    local guide = pfGuide.currentGuide
    if not guide then return end

    if pfGuide.currentStepIndex < #guide.steps then
        pfGuide.currentStepIndex = pfGuide.currentStepIndex + 1
        pfGuide.currentWaypointIndex = 1
        pfGuide:ExecuteCurrentStep()
    else
        if guide.next and pfGuide.loadedGuides[guide.next] then
            pfGuide:SetCurrentGuide(guide.next)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[pfGuide]|r Guide completed!")
        end
    end
end

function pfGuide:PrevStep()
    if pfGuide.currentStepIndex > 1 then
        pfGuide.currentStepIndex = pfGuide.currentStepIndex - 1
        pfGuide.currentWaypointIndex = 1
        pfGuide:ExecuteCurrentStep()
    end
end

-- ============================================================================
-- MINIMALIST USER INTERFACE
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

-- Title / Step Header
pfGuideWindow.title = pfGuideWindow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
pfGuideWindow.title:SetPoint("TOPLEFT", pfGuideWindow, "TOPLEFT", 8, -6)
pfGuideWindow.title:SetText("RXP Guide")

-- Instruction text
pfGuideWindow.text = pfGuideWindow:CreateFontString(nil, "OVERLAY", "GameFontWhite")
pfGuideWindow.text:SetPoint("TOPLEFT", pfGuideWindow.title, "BOTTOMLEFT", 0, -4)
pfGuideWindow.text:SetPoint("BOTTOMRIGHT", pfGuideWindow, "BOTTOMRIGHT", -8, 8)
pfGuideWindow.text:SetJustifyH("LEFT")
pfGuideWindow.text:SetJustifyV("TOP")
pfGuideWindow.text:SetWordWrap(true)
pfGuideWindow.text:SetNonSpaceWrap(false)
pfGuideWindow.text:SetText("No guide loaded.")

-- Previous Step Button (<)
pfGuideWindow.prevBtn = CreateFrame("Button", nil, pfGuideWindow, "UIPanelButtonTemplate")
pfGuideWindow.prevBtn:SetSize(20, 18)
pfGuideWindow.prevBtn:SetPoint("TOPRIGHT", pfGuideWindow, "TOPRIGHT", -26, -4)
pfGuideWindow.prevBtn:SetText("<")
pfGuideWindow.prevBtn:SetScript("OnClick", function() pfGuide:PrevStep() end)

-- Next Step Button (>)
pfGuideWindow.nextBtn = CreateFrame("Button", nil, pfGuideWindow, "UIPanelButtonTemplate")
pfGuideWindow.nextBtn:SetSize(20, 18)
pfGuideWindow.nextBtn:SetPoint("TOPRIGHT", pfGuideWindow, "TOPRIGHT", -4, -4)
pfGuideWindow.nextBtn:SetText(">")
pfGuideWindow.nextBtn:SetScript("OnClick", function() pfGuide:NextStep() end)

function pfGuide:UpdateUI()
    local guide = pfGuide.currentGuide
    if not guide or not guide.steps[pfGuide.currentStepIndex] then
        pfGuideWindow.title:SetText("pfQuest RXP Guide")
        pfGuideWindow.text:SetText("No active step.")
        return
    end

    local step = guide.steps[pfGuide.currentStepIndex]
    pfGuideWindow.title:SetText(string.format("|cff00ff00%s|r [Step %d/%d]", guide.name, pfGuide.currentStepIndex, #guide.steps))

    local displayText = ""
    local hasDirectAction = step.hasAcceptOrTurnIn or step.hasComplete

    for _, elem in ipairs(step.elements) do
        if elem.tag == "accept" then
            local title = pfGuide:GetQuestTitle(elem.questId)
            displayText = displayText .. "|cffffff00[!] Accept:|r " .. title .. "\n"
        elseif elem.tag == "turnin" then
            local title = pfGuide:GetQuestTitle(elem.questId)
            displayText = displayText .. "|cff00ff00[?] Turn in:|r " .. title .. "\n"
        elseif elem.tag == "complete" then
            local progressText, isDone = pfGuide:GetObjectiveProgress(elem.questId, elem.objIndex)
            local title = pfGuide:GetQuestTitle(elem.questId)
            local mainText = (progressText and progressText ~= "") and progressText or title
            local status = isDone and " |cff00ff00(Done)|r" or ""
            displayText = displayText .. "|cffff5555[*]|r " .. mainText .. status .. "\n"
        elseif elem.tag == "goto" and not hasDirectAction and #step.gotoPoints <= 2 then
            displayText = displayText .. "|cff00bfff[>] Travel to:|r " .. string.format("%s (%.1f, %.1f)", elem.zone or "", elem.x or 0, elem.y or 0) .. "\n"
        elseif elem.tag == "info" then
            displayText = displayText .. elem.text .. "\n"
        end
    end

    if displayText == "" then
        displayText = step.text or "Follow navigation arrow."
    end

    pfGuideWindow.text:SetText(displayText)

    local lineCount = select(2, displayText:gsub("\n", "\n"))
    pfGuideWindow:SetHeight(math.max(65, 34 + lineCount * 14))
end

-- ============================================================================
-- EVENTS & INITIALIZATION
-- ============================================================================
pfGuide:RegisterEvent("PLAYER_ENTERING_WORLD")
pfGuide:RegisterEvent("QUEST_ACCEPTED")
pfGuide:RegisterEvent("QUEST_LOG_UPDATE")
pfGuide:RegisterEvent("QUEST_WATCH_UPDATE")
pfGuide:RegisterEvent("PLAYER_XP_UPDATE")
pfGuide:RegisterEvent("ZONE_CHANGED")
pfGuide:RegisterEvent("ZONE_CHANGED_NEW_AREA")
pfGuide:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")

pfGuide:SetScript("OnEvent", function()
    if event == "PLAYER_ENTERING_WORLD" then
        pfGuide:LoadAllGuides()
        local defaultGuide = pfGuide:FindDefaultGuide()
        if defaultGuide then
            pfGuide:SetCurrentGuide(defaultGuide.name)
        end
        pfGuideWindow:Show()
    else
        pfGuide:CheckStepCompletion()
    end
end)

local lastUpdate = 0
pfGuide:SetScript("OnUpdate", function()
    local now = GetTime()
    if now - lastUpdate > 0.5 then
        lastUpdate = now
        pfGuide:CheckStepCompletion()
    end
end)

-- ============================================================================
-- SLASH COMMANDS
-- ============================================================================
SLASH_PFGUIDE1 = "/guide"
SLASH_PFGUIDE2 = "/rxp"
SlashCmdList["PFGUIDE"] = function(msg)
    msg = msg and msg:match("^%s*(.-)%s*$") or ""
    if msg == "list" then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[pfGuide]|r Loaded Guides:")
        for name, _ in pairs(pfGuide.loadedGuides) do
            DEFAULT_CHAT_FRAME:AddMessage(" - " .. name)
        end
    elseif msg ~= "" and pfGuide.loadedGuides[msg] then
        pfGuide:SetCurrentGuide(msg)
    else
        if pfGuideWindow:IsShown() then
            pfGuideWindow:Hide()
        else
            pfGuideWindow:Show()
        end
    end
end
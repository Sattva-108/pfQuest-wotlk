-- ============================================================================
-- ACTIVE GUIDE ENGINE LOGIC (PARSER & STEP MACHINE)
-- ============================================================================

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

function pfGuide:Applies(conditionStr)
    if not conditionStr or conditionStr == "" then return true end
    local _, pClass = UnitClass("player")
    local _, pRace = UnitRace("player")
    local pFaction = UnitFactionGroup("player") or ""
    local pLevel = UnitLevel("player") or 1

    pClass = string.upper(pClass or "")
    pRace = pRace == "Scourge" and "Undead" or (pRace or "")

    for branch in string.gmatch(conditionStr, "[^/]+") do
        local valid = true
        for token in string.gmatch(branch, "!?[%w%d]+") do
            local neg = (token:sub(1, 1) == "!")
            local name = neg and token:sub(2) or token
            local upper = string.upper(name)
            local match = (upper == pClass or name == pRace or name == pFaction or upper == "WOTLK" or upper == "CLASSIC" or upper == "TBC") or (tonumber(name) and pLevel >= tonumber(name))
            if (not match and not neg) or (match and neg) then
                valid = false
                break
            end
        end
        if valid then return true end
    end
    return false
end

function pfGuide:ParseGuideText(rawText)
    local guide = { name = "Unknown Guide", group = "Default", defaultFor = nil, next = nil, labels = {}, steps = {} }
    local currentStep = nil
    local stepCounter = 0
    local skipStep = false

    for line in string.gmatch(rawText, "[^\r\n]+") do
        local rawLine = line
        line = line:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%-%-.*$", "")
        if line ~= "" then
            if line:sub(1, 4) == "step" then
                local cond = line:match("^step%s*<<%s*(.+)$")
                if cond and not pfGuide:Applies(cond) then
                    skipStep = true
                    currentStep = nil
                else
                    skipStep = false
                    stepCounter = stepCounter + 1
                    currentStep = { index = stepCounter, elements = {}, gotoPoints = {}, rawLines = { rawLine }, text = "", hasAcceptOrTurnIn = false, hasComplete = false, hasVendor = false, hasTrainer = false, hasCollect = false }
                    table.insert(guide.steps, currentStep)
                end
            elseif not skipStep then
                -- Universal condition evaluation: if line has << Class/Race, check if it applies
                local cond = line:match("<<%s*(.+)$")
                local lineValid = true
                if cond then
                    line = line:gsub("%s*<<.*$", ""):gsub("%s+$", "")
                    lineValid = pfGuide:Applies(cond)
                end

                if lineValid and line ~= "" then
                    if not currentStep and line:sub(1, 1) == "#" then
                        local tag, val = line:match("^#(%S+)%s*(.*)")
                        tag = string.lower(tag or "")
                        if tag == "name" then guide.name = val
                        elseif tag == "group" then guide.group = val
                        elseif tag == "defaultfor" then guide.defaultFor = val
                        elseif tag == "next" then guide.next = val end
                    elseif currentStep then
                        table.insert(currentStep.rawLines, rawLine)
                        if line:sub(1, 1) == "#" then
                            local tag, val = line:match("^#(%S+)%s*(.*)")
                            tag = string.lower(tag or "")
                            if tag == "season" and (tonumber(val) or 0) ~= pfGuide.gameSeason then
                                table.remove(guide.steps); stepCounter = stepCounter - 1; currentStep = nil; skipStep = true
                            elseif tag == "xprate" then
                                local op, rate = val:match("([<>]?)(%d+%.?%d*)")
                                rate = tonumber(rate) or 1.0
                                if (op == "<" and pfGuide.xpRate >= rate) or (op == ">" and pfGuide.xpRate <= rate) then
                                    table.remove(guide.steps); stepCounter = stepCounter - 1; currentStep = nil; skipStep = true
                                end
                            elseif tag == "label" then currentStep.label = val; guide.labels[val] = currentStep.index
                            elseif tag == "requires" then currentStep.requires = val
                            elseif tag == "completewith" then currentStep.completeWith = val
                            elseif tag == "loop" then currentStep.isLoop = true
                            elseif tag == "sticky" then currentStep.sticky = true end
                        elseif line:sub(1, 1) == "." then
                            local directive, rest = line:match("^%.(%S+)%s*(.*)")
                            directive = string.lower(directive or "")
                            local desc = rest:match(">>%s*(.*)")
                            local argsStr = desc and rest:gsub("%s*>>.*$", "") or rest
                            local args = {}
                            for arg in string.gmatch(argsStr, "[^,]+") do table.insert(args, arg:match("^%s*(.-)%s*$")) end
                            local elem = { tag = directive, args = args, text = desc or "" }
                            if directive == "goto" then
                                elem.zone = args[1]; elem.x = tonumber(args[2]); elem.y = tonumber(args[3]); elem.radius = (tonumber(args[4]) and tonumber(args[4]) > 0) and tonumber(args[4]) or 15
                                table.insert(currentStep.gotoPoints, elem)
                            elseif directive == "accept" or directive == "turnin" then
                                elem.questId = tonumber(args[1]); currentStep.hasAcceptOrTurnIn = true
                            elseif directive == "complete" then
                                elem.questId = tonumber(args[1]); elem.objIndex = tonumber(args[2]) or 1; currentStep.hasComplete = true
                            elseif directive == "collect" then
                                elem.itemId = tonumber(args[1])
                                elem.qty = tonumber(args[2]) or 1
                                elem.questId = tonumber(args[3])
                                currentStep.hasCollect = true
                                currentStep.hasComplete = true
                            elseif directive == "itemcount" then
                                elem.itemId = tonumber(args[1])
                                local op, qty = (args[2] or ""):match("([<>]?)(%d+)")
                                elem.op = op ~= "" and op or ">"
                                elem.qty = tonumber(qty) or 1
                            elseif directive == "money" then
                                local op, amt = argsStr:match("([<>]?)(%d+%.?%d*)")
                                elem.op = op ~= "" and op or ">"
                                elem.amount = (tonumber(amt) or 0) * 10000
                                currentStep.hasMoney = true
                            elseif directive == "vendor" then
                                currentStep.hasVendor = true
                            elseif directive == "target" then
                                elem.target = args[1]
                            elseif directive == "trainer" or directive == "train" then
                                elem.spellId = tonumber(args[1])
                                elem.flags = tonumber(args[2]) or 0
                                if elem.flags % 2 == 1 then
                                    elem.textOnly = true
                                else
                                    currentStep.hasTrainer = true
                                end
                            elseif directive == "itemstat" then
                                elem.slot = tonumber(args[1]) or 16
                                elem.stat = args[2] or "ITEM_MOD_DAMAGE_PER_SECOND_SHORT"
                                local op, val = (args[3] or ""):match("([<>]?)(%d+%.?%d*)")
                                elem.op = op ~= "" and op or "<"
                                elem.value = tonumber(val) or 0
                            elseif directive == "isonquest" then
                                elem.questId = tonumber(args[1])
                            elseif directive == "isquestcomplete" then
                                elem.questId = tonumber(args[1])
                            elseif directive == "isquestnotcomplete" then
                                elem.questId = tonumber(args[1])
                            elseif directive == "isnotonquest" then
                                elem.questId = tonumber(args[1])
                            elseif directive == "isquestturnedin" then
                                elem.questId = tonumber(args[1])
                            elseif directive == "hs" then
                                currentStep.hasHS = true
                                currentStep.hasComplete = true
                            elseif directive == "xp" then
                                elem.rawXp = argsStr
                                local op, lvl, xp, skip = argsStr:match("([<>]?)(%d+)%+(%d+),?(%d*)")
                                if not lvl then
                                    op, lvl, skip = argsStr:match("([<>]?)(%d+),?(%d*)")
                                end
                                elem.op = op ~= "" and op or ">="
                                elem.level = tonumber(lvl) or 1
                                elem.xp = tonumber(xp) or 0
                                elem.isSkipCheck = (tonumber(skip) and tonumber(skip) > 0) or (op == "<") or (op == ">")
                                if not elem.isSkipCheck then
                                    currentStep.hasComplete = true
                                end
                            elseif directive == "deathskip" then
                                currentStep.hasDeathskip = true
                            elseif directive == "subzone" then
                                elem.subzoneId = tonumber(args[1])
                                currentStep.hasComplete = true
                            elseif directive == "subzoneskip" then
                                elem.subzoneId = tonumber(args[1])
                            end
                            table.insert(currentStep.elements, elem)
                            if desc and desc ~= "" and currentStep.text == "" then currentStep.text = desc end
                        elseif line:sub(1, 1) == "+" or line:sub(1, 1) == "*" then
                            local text = line:sub(2):match("^%s*(.-)%s*$")
                            table.insert(currentStep.elements, { tag = "info", text = text })
                            if currentStep.text == "" then currentStep.text = text end
                        end
                    end
                end
            end
        end
    end

    local validSteps = {}
    for _, s in ipairs(guide.steps) do
        -- Detect ghost buy-steps: had .collect in raw text but all items filtered out by class/race
        local hadCollectInRaw = false
        for _, rawLine in ipairs(s.rawLines or {}) do
            if rawLine:find("%.collect%s+") then hadCollectInRaw = true; break end
        end
        local isGhostBuyStep = hadCollectInRaw and not s.hasCollect and not s.hasAcceptOrTurnIn and not s.hasComplete and not s.hasVendor and not s.hasTrainer

        if #s.elements > 0 and not isGhostBuyStep then
            table.insert(validSteps, s)
            s.index = #validSteps
            s.rawText = table.concat(s.rawLines or {}, "\n")
            if s.label then guide.labels[s.label] = s.index end
        end
    end
    guide.steps = validSteps

    -- Mark ambient steps: only side tasks (never .hs, .deathskip, or pure travel)
    for _, s in ipairs(guide.steps) do
        local isPureTravel = not s.hasAcceptOrTurnIn and not s.hasComplete and not s.hasVendor and not s.hasTrainer and not s.hasCollect and not s.hasHS and not s.hasDeathskip
        if s.completeWith and s.completeWith ~= "next" and not s.label and not isPureTravel and not s.hasHS and not s.hasDeathskip then
            s.isAmbient = true
        else
            s.isAmbient = false
        end
    end

    return guide
end

function pfGuide:LoadAllGuides()
    pfGuide.loadedGuides = {}
    for _, rawText in ipairs(RXPGuides_Data) do
        local guide = pfGuide:ParseGuideText(rawText)
        if guide and #guide.steps > 0 then pfGuide.loadedGuides[guide.name] = guide end
    end
end

function pfGuide:FindDefaultGuide()
    for _, guide in pairs(pfGuide.loadedGuides) do
        if guide.defaultFor and pfGuide:Applies(guide.defaultFor) then return guide end
    end
    for _, guide in pairs(pfGuide.loadedGuides) do return guide end
    return nil
end

function pfGuide:FindFurthestActiveStep(guide)
    if not guide or not guide.steps or #guide.steps == 0 then return 1 end

    local activeIndex = #guide.steps
    local activeReason = "End of guide"
    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00bfff[pfGuide FF]|r Starting Fast-Forward scan for guide: %s (%d steps)...", guide.name, #guide.steps))

    for i, step in ipairs(guide.steps) do
        local isStepPassed = true
        local hasQuestAction = false
        local unfinishedReason
        local stepDebugInfo = ""

        -- Evaluate quest and action elements in sequence.
        for _, elem in ipairs(step.elements or {}) do
            if elem.tag == "turnin" and elem.questId then
                hasQuestAction = true
                local turnedIn = pfQuest_history and pfQuest_history[elem.questId]
                stepDebugInfo = string.format("TurnIn Q#%d (%s)", elem.questId, turnedIn and "TURNED_IN" or "NOT_TURNED_IN")
                if not turnedIn then
                    isStepPassed = false
                    unfinishedReason = "Need to turn in quest " .. elem.questId .. " (" .. pfGuide:GetQuestTitle(elem.questId) .. ")"
                    break
                end
            elseif elem.tag == "complete" and elem.questId then
                hasQuestAction = true
                local onQuest = pfQuest.questlog and pfQuest.questlog[elem.questId]
                local turnedIn = pfQuest_history and pfQuest_history[elem.questId]
                local isComplete = onQuest and pfGuide:IsQuestComplete(elem.questId)
                stepDebugInfo = string.format("Complete Q#%d (%s)", elem.questId, turnedIn and "TURNED_IN" or (isComplete and "OBJ_DONE" or (onQuest and "OBJ_INCOMPLETE" or "NOT_IN_LOG")))
                if onQuest and not isComplete then
                    isStepPassed = false
                    unfinishedReason = "Incomplete quest objective: " .. pfGuide:GetQuestTitle(elem.questId)
                    break
                elseif not onQuest and not turnedIn then
                    isStepPassed = false
                    unfinishedReason = "Upcoming quest not yet accepted: " .. pfGuide:GetQuestTitle(elem.questId)
                    break
                end
            elseif elem.tag == "accept" and elem.questId then
                hasQuestAction = true
                local onQuest = pfQuest.questlog and pfQuest.questlog[elem.questId]
                local turnedIn = pfQuest_history and pfQuest_history[elem.questId]
                stepDebugInfo = string.format("Accept Q#%d (%s)", elem.questId, turnedIn and "TURNED_IN" or (onQuest and "ON_QUEST" or "NOT_ACCEPTED"))
                if not onQuest and not turnedIn then
                    isStepPassed = false
                    unfinishedReason = "Need to accept quest " .. elem.questId .. " (" .. pfGuide:GetQuestTitle(elem.questId) .. ")"
                    break
                end
            elseif elem.tag == "collect" and elem.itemId then
                hasQuestAction = true
                local onQuest = elem.questId and pfQuest.questlog and pfQuest.questlog[elem.questId]
                local turnedIn = elem.questId and pfQuest_history and pfQuest_history[elem.questId]
                local count = pfGuide:GetItemCount(elem.itemId)
                stepDebugInfo = string.format("Collect Item#%d (%d/%d)%s", elem.itemId, count, elem.qty or 1, (onQuest or turnedIn) and " (QUEST_SATISFIED)" or "")
                if not (onQuest or turnedIn) and count < (elem.qty or 1) then
                    isStepPassed = false
                    unfinishedReason = "Need to collect item #" .. elem.itemId .. string.format(" (%d/%d)", count, elem.qty or 1)
                    break
                end
            elseif elem.tag == "train" and elem.spellId and not elem.textOnly then
                hasQuestAction = true
                local isKnown = IsSpellKnown(elem.spellId)
                stepDebugInfo = string.format("Train Spell#%d (%s)", elem.spellId, isKnown and "KNOWN" or "NOT_KNOWN")
                if not isKnown then
                    isStepPassed = false
                    unfinishedReason = "Need to train spell #" .. elem.spellId
                    break
                end
            elseif elem.tag == "xp" and elem.level and elem.op ~= "<" and not elem.isSkipCheck then
                hasQuestAction = true
                local pLevel = UnitLevel("player") or 1
                local pXp = UnitXP("player") or 0
                local reqXp = elem.xp or 0
                local reqMet = pLevel > elem.level or (pLevel == elem.level and pXp >= reqXp)
                stepDebugInfo = string.format("Grind Lv%d (+%d XP) [Current: Lv%d %d XP -> %s]", elem.level, reqXp, pLevel, pXp, reqMet and "MET" or "NOT_MET")
                if not reqMet then
                    isStepPassed = false
                    unfinishedReason = string.format("Grind required: Lv%d (+%d XP)", elem.level, reqXp)
                    break
                end
            end
        end

        -- Resolve pure travel, vendor, deathskip, and hearthstone steps from nearby quests.
        if not hasQuestAction then
            local upcomingQuestsTurnedIn = false
            local nextQuestChecked = "None"
            for k = i + 1, math.min(i + 8, #guide.steps) do
                for _, nextElem in ipairs(guide.steps[k].elements or {}) do
                    if (nextElem.tag == "turnin" or nextElem.tag == "complete" or nextElem.tag == "accept") and nextElem.questId then
                        nextQuestChecked = string.format("Q#%d", nextElem.questId)
                        if pfQuest_history and pfQuest_history[nextElem.questId] then
                            upcomingQuestsTurnedIn = true
                            break
                        end
                    end
                end
                if upcomingQuestsTurnedIn then break end
            end

            stepDebugInfo = string.format("Travel/Vendor step (Upcoming %s %s)", nextQuestChecked, upcomingQuestsTurnedIn and "TURNED_IN" or "NOT_TURNED_IN")
            if not upcomingQuestsTurnedIn then
                isStepPassed = false
                unfinishedReason = (step.text ~= "" and step.text) or "Travel / Navigation step"
            end
        end

        if not isStepPassed then
            activeIndex = i
            activeReason = unfinishedReason or "Active step"
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffffcc00[pfGuide FF]|r STOP at Step %d: %s [Info: %s]", i, activeReason, stepDebugInfo))
            break
        end

        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff808080[pfGuide FF]|r PASS Step %d [Info: %s]", i, stepDebugInfo ~= "" and stepDebugInfo or "No direct quest action"))
    end

    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[pfGuide FF]|r Fast-Forward Selected Step %d/%d (%s)", activeIndex, #guide.steps, activeReason))
    return activeIndex
end

function pfGuide:SetCurrentGuide(guideName)
    local guide = pfGuide.loadedGuides[guideName]
    if not guide then return end
    pfGuide.currentGuide = guide
    pfGuide.currentGuideKey = guide.name
    pfGuide.completedLabels = {}
    pfGuide.activePassiveSteps = {}
    pfGuide.currentWaypointIndex = 1
    pfGuide.merchantOpen = false
    pfGuide.merchantInteracted = false
    pfGuide.merchantVisited = false
    pfGuide.trainerVisited = false
    pfGuide.trainerOpen = false
    pfGuide.hearthstoneUsed = false

    pfGuide.currentStepIndex = pfGuide:FindFurthestActiveStep(guide)
    pfGuide.furthestStepIndex = pfGuide.currentStepIndex
    for i = 1, pfGuide.currentStepIndex - 1 do
        local step = guide.steps[i]
        if step.label then
            pfGuide.completedLabels[step.label] = true
        end
    end
    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[pfGuide]|r Guide loaded at Step %d/%d", pfGuide.currentStepIndex, #guide.steps))
    pfGuide:FindNearestWaypoint()
    pfGuide:ExecuteCurrentStep()
    pfGuide:UpdateUI()
end

function pfGuide:PointToCoords(x, y, zoneId, title)
    if not x or not y then return end
    local node = { [1] = x, [2] = y, [3] = { title = title or "RXP Objective", texture = pfQuestConfig.path .. "\\img\\cluster_mob", qlvl = 0 }, [4] = 0 }
    pfQuest.route.coords = { node }
    pfQuest.route.firstnode = nil
    pfQuest.route.recalculate = 0
    pfQuest.route.SetTarget(node[3])
    if pfQuest.route.arrow then
        pfQuest.route.arrow.parent = pfQuest.route
        pfQuest.route.arrow:Show()
    end
end

function pfGuide:FindNearestWaypoint()
    local guide = pfGuide.currentGuide
    if not guide or not guide.steps[pfGuide.currentStepIndex] then return end
    local step = guide.steps[pfGuide.currentStepIndex]
    if #step.gotoPoints <= 1 then pfGuide.currentWaypointIndex = 1 return end

    local pX, pY = GetPlayerMapPosition("player")
    pX, pY = pX * 100, pY * 100
    if pX == 0 and pY == 0 then return end

    local bestIndex, bestDist = 1, math.huge
    for i, wp in ipairs(step.gotoPoints) do
        local yards = pfGuide:GetDistanceToPoint(pX, pY, wp.x, wp.y)
        if yards < bestDist then bestDist = yards; bestIndex = i end
    end
    pfGuide.currentWaypointIndex = bestIndex
end

local function GetNearestCoord(coordsList)
    if not coordsList or #coordsList == 0 then return nil end
    local pX, pY = GetPlayerMapPosition("player")
    pX, pY = pX * 100, pY * 100
    local best, bestDist = coordsList[1], math.huge
    for _, c in ipairs(coordsList) do
        local yards = pfGuide:GetDistanceToPoint(pX, pY, c[1], c[2])
        if yards < bestDist then bestDist = yards; best = c end
    end
    return best
end

function pfGuide:ExecuteCurrentStep(isManual)
    local guide = pfGuide.currentGuide
    if not guide or not guide.steps[pfGuide.currentStepIndex] then return end
    local step = guide.steps[pfGuide.currentStepIndex]
    pfGuide.hasArrivedAtTarget = false

    -- Announce step activation only once per step.
    if pfGuide.lastAnnouncedStep ~= pfGuide.currentStepIndex then
        pfGuide.lastAnnouncedStep = pfGuide.currentStepIndex
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00bfff[pfGuide]|r Activating Step %d/%d (Elements: %d, WPs: %d)", pfGuide.currentStepIndex, #guide.steps, #step.elements, #step.gotoPoints))
    end

    -- Register label immediately when step is activated
    if step.label then
        pfGuide.completedLabels[step.label] = true
    end

    local canAutoSkip = not isManual and (pfGuide.currentStepIndex >= (pfGuide.furthestStepIndex or 1))

    if canAutoSkip and step.requires then
        local reqIndex = guide.labels[step.requires]
        if reqIndex and pfGuide.currentStepIndex >= reqIndex then
            pfGuide.completedLabels[step.requires] = true
        end

        if not pfGuide.completedLabels[step.requires] then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[pfGuide]|r Step %d skipped: Requires label '%s' (not yet reached)", pfGuide.currentStepIndex, step.requires))
            pfGuide:NextStep()
            return
        end
    end

    -- Handle ambient/passive steps: add to background list and advance primary arrow
    if canAutoSkip and step.isAmbient then
        local alreadyTracked = false
        for _, pStep in ipairs(pfGuide.activePassiveSteps) do
            if pStep == step then alreadyTracked = true; break end
        end
        if not alreadyTracked then
            table.insert(pfGuide.activePassiveSteps, step)
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[pfGuide]|r Step " .. pfGuide.currentStepIndex .. " added as ambient background task")
        end
        pfGuide.currentStepIndex = pfGuide.currentStepIndex + 1
        pfGuide.currentWaypointIndex = 1
        pfGuide:ExecuteCurrentStep()
        return
    end

    -- Pre-check conditions with chat feedback
    if canAutoSkip then
    for _, elem in ipairs(step.elements) do
        if elem.tag == "money" then
            local copper = GetMoney() or 0
            if elem.op == "<" and copper < elem.amount then
                DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[pfGuide]|r Step %d skipped: Money condition (< %s, current: %s)", pfGuide.currentStepIndex, pfGuide:FormatMoney(elem.amount), pfGuide:FormatMoney(copper)))
                pfGuide:NextStep()
                return
            elseif elem.op == ">" and step.hasVendor and copper >= elem.amount then
                DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[pfGuide]|r Step %d skipped: Already have %s (>= %s), bypassing vendor", pfGuide.currentStepIndex, pfGuide:FormatMoney(copper), pfGuide:FormatMoney(elem.amount)))
                pfGuide:NextStep()
                return
            end
        elseif elem.tag == "isquestcomplete" and elem.questId and not pfGuide:IsQuestComplete(elem.questId) then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[pfGuide]|r Step %d skipped: Quest %d is not complete", pfGuide.currentStepIndex, elem.questId))
            pfGuide:NextStep()
            return
        elseif elem.tag == "isquestnotcomplete" and elem.questId and pfGuide:IsQuestComplete(elem.questId) then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[pfGuide]|r Step %d skipped: Quest %d is already complete", pfGuide.currentStepIndex, elem.questId))
            pfGuide:NextStep()
            return
        elseif elem.tag == "isonquest" and elem.questId and not (pfQuest.questlog and pfQuest.questlog[elem.questId]) then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[pfGuide]|r Step %d skipped: Not on quest %d", pfGuide.currentStepIndex, elem.questId))
            pfGuide:NextStep()
            return
        elseif elem.tag == "isnotonquest" and elem.questId and pfQuest.questlog and pfQuest.questlog[elem.questId] then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[pfGuide]|r Step %d skipped: Already on quest %d", pfGuide.currentStepIndex, elem.questId))
            pfGuide:NextStep()
            return
        elseif elem.tag == "isquestturnedin" and elem.questId then
            local hasIncompleteXp = false
            for _, e in ipairs(step.elements) do
                if e.tag == "xp" and e.level and e.op ~= "<" then
                    local pLevel = UnitLevel("player") or 1
                    local pXp = UnitXP("player") or 0
                    if pLevel < e.level or (pLevel == e.level and pXp < (e.xp or 0)) then
                        hasIncompleteXp = true
                        break
                    end
                end
            end
            if not hasIncompleteXp and not (pfQuest_history and pfQuest_history[elem.questId]) then
                DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[pfGuide]|r Step %d skipped: Quest %d not yet turned in", pfGuide.currentStepIndex, elem.questId))
                pfGuide:NextStep()
                return
            end
        elseif elem.tag == "itemstat" then
            local currentStat = pfGuide:GetEquippedItemStat(elem.slot, elem.stat)
            if (elem.op == "<" and currentStat >= elem.value) or (elem.op == ">" and currentStat <= elem.value) then
                DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[pfGuide]|r Step %d skipped: Better gear equipped (Slot %d = %.2f)", pfGuide.currentStepIndex, elem.slot, currentStat))
                pfGuide:NextStep()
                return
            end
        elseif elem.tag == "xp" and elem.level then
            local pLevel = UnitLevel("player") or 1
            local pXp = UnitXP("player") or 0
            local reqXp = elem.xp or 0

            if elem.op == "<" then
                if pLevel < elem.level or (pLevel == elem.level and pXp < reqXp) then
                    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[pfGuide]|r Step %d skipped: Level below %d", pfGuide.currentStepIndex, elem.level))
                    pfGuide:NextStep()
                    return
                end
            elseif elem.op == ">" then
                if pLevel >= elem.level then
                    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[pfGuide]|r Step %d skipped: Level %d or above", pfGuide.currentStepIndex, elem.level))
                    pfGuide:NextStep()
                    return
                end
            else
                if pLevel > elem.level or (pLevel == elem.level and pXp >= reqXp) then
                    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[pfGuide]|r Grind step %d skipped: Already Lv%d", pfGuide.currentStepIndex, pLevel))
                    pfGuide:NextStep()
                    return
                else
                    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffffcc00[pfGuide]|r Grind step %d ACTIVE: Need Lv%d (+%d XP) [Current: Lv%d %d XP]", pfGuide.currentStepIndex, elem.level, reqXp, pLevel, pXp))
                end
            end
        end
    end
    end

    -- Auto-skip ghost steps: all actionable items (.collect, .vendor, etc.) filtered out by class/race conditions
    local hasAction = step.hasAcceptOrTurnIn or step.hasComplete or step.hasVendor or step.hasTrainer or step.hasCollect or step.hasDeathskip or step.hasMoney or (#step.gotoPoints > 0)
    if canAutoSkip and not hasAction and not step.isAmbient and #step.elements > 0 then
        local isGhostStep = true
        for _, elem in ipairs(step.elements) do
            if elem.tag == "accept" or elem.tag == "turnin" or elem.tag == "complete" or elem.tag == "collect" or elem.tag == "vendor" or elem.tag == "trainer" or elem.tag == "train" or elem.tag == "deathskip" or elem.tag == "xp" or elem.tag == "money" or elem.tag == "goto" then
                isGhostStep = false
                break
            end
        end
        if isGhostStep then
            pfGuide:NextStep()
            return
        end
    end

    local targetFound = false

    if #step.gotoPoints > 0 then
        local wp = step.gotoPoints[pfGuide.currentWaypointIndex] or step.gotoPoints[1]
        if wp and wp.x and wp.y then
            local wpLabel = (#step.gotoPoints > 1) and string.format(" [WP %d/%d]", pfGuide.currentWaypointIndex, #step.gotoPoints) or ""
            local title = (wp.text ~= "" and wp.text or step.text) .. wpLabel
            pfGuide:PointToCoords(wp.x, wp.y, pfGuide:GetZoneID(wp.zone), title)
            targetFound = true
        end
    end

    if not targetFound then
        for _, elem in ipairs(step.elements) do
            local qId = elem.questId
            local qData = qId and pfDB.quests and pfDB.quests.data and pfDB.quests.data[qId]
            if qData then
                if elem.tag == "complete" and qData.obj then
                    if qData.obj.O then
                        for _, objId in ipairs(qData.obj.O) do
                            local oData = pfDB.objects and pfDB.objects.data and pfDB.objects.data[objId]
                            local best = oData and GetNearestCoord(oData.coords)
                            if best then pfGuide:PointToCoords(best[1], best[2], best[3], step.text); targetFound = true; break end
                        end
                    end
                    if not targetFound and qData.obj.I then
                        for _, itemId in ipairs(qData.obj.I) do
                            local iData = pfDB.items and pfDB.items.data and pfDB.items.data[itemId]
                            if iData and iData.O then
                                for objId in pairs(iData.O) do
                                    local oData = pfDB.objects and pfDB.objects.data and pfDB.objects.data[objId]
                                    local best = oData and GetNearestCoord(oData.coords)
                                    if best then pfGuide:PointToCoords(best[1], best[2], best[3], step.text); targetFound = true; break end
                                end
                            end
                            if not targetFound and iData and iData.U then
                                for unitId in pairs(iData.U) do
                                    local uData = pfDB.units and pfDB.units.data and pfDB.units.data[unitId]
                                    local best = uData and GetNearestCoord(uData.coords)
                                    if best then pfGuide:PointToCoords(best[1], best[2], best[3], step.text); targetFound = true; break end
                                end
                            end
                        end
                    end
                    if not targetFound and qData.obj.U then
                        for _, unitId in ipairs(qData.obj.U) do
                            local uData = pfDB.units and pfDB.units.data and pfDB.units.data[unitId]
                            local best = uData and GetNearestCoord(uData.coords)
                            if best then pfGuide:PointToCoords(best[1], best[2], best[3], step.text); targetFound = true; break end
                        end
                    end
                elseif elem.tag == "accept" and qData.start and qData.start.U and qData.start.U[1] then
                    local uData = pfDB.units and pfDB.units.data and pfDB.units.data[qData.start.U[1]]
                    local best = uData and GetNearestCoord(uData.coords)
                    if best then pfGuide:PointToCoords(best[1], best[2], best[3], step.text); targetFound = true; break end
                elseif elem.tag == "turnin" and qData["end"] and qData["end"].U and qData["end"].U[1] then
                    local uData = pfDB.units and pfDB.units.data and pfDB.units.data[qData["end"].U[1]]
                    local best = uData and GetNearestCoord(uData.coords)
                    if best then pfGuide:PointToCoords(best[1], best[2], best[3], step.text); targetFound = true; break end
                end
            end
            if targetFound then break end
        end
    end

    -- If no target found, try .mob directives or clear stale arrow
    if not targetFound then
        for _, elem in ipairs(step.elements) do
            if elem.tag == "mob" and elem.args and elem.args[1] then
                local mobName = elem.args[1]
                local mobIds = pfDB and pfDB.units and pfDB.units.loc and pfDB.units.loc[mobName]
                if mobIds then
                    for mId in pairs(mobIds) do
                        local uData = pfDB.units and pfDB.units.data and pfDB.units.data[mId]
                        local best = uData and GetNearestCoord(uData.coords)
                        if best then
                            pfGuide:PointToCoords(best[1], best[2], best[3], "Kill " .. mobName)
                            targetFound = true
                            break
                        end
                    end
                end
            end
            if targetFound then break end
        end
    end

    if not targetFound then
        pfQuest.route.coords = {}
        if pfQuest.route.arrow then pfQuest.route.arrow:Hide() end
    end

    pfGuide:UpdateUI()
end

function pfGuide:CheckStepCompletion()
    local guide = pfGuide.currentGuide
    if not guide or not guide.steps[pfGuide.currentStepIndex] then return end
    if pfGuide.currentStepIndex < (pfGuide.furthestStepIndex or 1) then
        return
    end

    -- Remove completed ambient steps when reaching their target label
    local toRemove = {}
    for i, pStep in ipairs(pfGuide.activePassiveSteps) do
        if pStep.completeWith and pfGuide.completedLabels[pStep.completeWith] then
            table.insert(toRemove, i)
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[pfGuide]|r Ambient step removed (label '" .. pStep.completeWith .. "' reached)")
        else
            -- Check if ambient step objectives are fully done
            local allDone = true
            for _, elem in ipairs(pStep.elements) do
                if elem.tag == "collect" and elem.itemId then
                    local onQuest = elem.questId and pfQuest.questlog and pfQuest.questlog[elem.questId]
                    local turnedIn = elem.questId and pfQuest_history and pfQuest_history[elem.questId]
                    if not (onQuest or turnedIn) then
                        local count = pfGuide:GetItemCount(elem.itemId)
                        if count < elem.qty then allDone = false; break end
                    end
                elseif elem.tag == "complete" and elem.questId then
                    local qData = pfQuest.questlog and pfQuest.questlog[elem.questId]
                    if qData then
                        local _, done = pfGuide:GetObjectiveProgress(elem.questId, elem.objIndex)
                        if not done then allDone = false; break end
                    else
                        if not (pfQuest_history and pfQuest_history[elem.questId]) then
                            allDone = false; break
                        end
                    end
                elseif elem.tag == "xp" and elem.level and not elem.isSkipCheck then
                    local pLevel = UnitLevel("player") or 1
                    local pXp = UnitXP("player") or 0
                    local reqXp = elem.xp or 0
                    if pLevel < elem.level or (pLevel == elem.level and pXp < reqXp) then
                        allDone = false
                        break
                    end
                end
            end
            if allDone and #pStep.elements > 0 then
                table.insert(toRemove, i)
                DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[pfGuide]|r Ambient step auto-completed (all objectives done)")
            end
        end
    end
    for j = #toRemove, 1, -1 do
        table.remove(pfGuide.activePassiveSteps, toRemove[j])
    end

    -- Handle sticky/completewith for primary step
    local step = guide.steps[pfGuide.currentStepIndex]
    local isCompleted = true
    local pendingReason = nil

    if step.completeWith and step.completeWith ~= "next" and pfGuide.completedLabels[step.completeWith] then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[pfGuide]|r Auto-skip: #completewith label '%s' reached", step.completeWith))
        pfGuide:NextStep()
        return
    end

    if step.hasVendor and not pfGuide.merchantVisited then
        isCompleted = false
        pendingReason = "Waiting for vendor interaction (Talk to NPC and close merchant window)"
    end
    if step.hasTrainer and not pfGuide.trainerVisited then
        local needsTraining = false
        for _, elem in ipairs(step.elements) do
            if (elem.tag == "train" or elem.tag == "trainer") and elem.spellId then
                if not IsSpellKnown(elem.spellId) then
                    needsTraining = true
                    break
                end
            end
        end
        if needsTraining then
            isCompleted = false
            pendingReason = "Waiting for trainer interaction"
        end
    end

    for _, elem in ipairs(step.elements) do
        if elem.tag == "itemstat" then
            local currentStat = pfGuide:GetEquippedItemStat(elem.slot, elem.stat)
            if (elem.op == "<" and currentStat >= elem.value) or (elem.op == ">" and currentStat <= elem.value) then
                DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[pfGuide]|r Step skipped: Better gear equipped (Slot %d = %.2f)", elem.slot, currentStat))
                pfGuide:NextStep()
                return
            end
        elseif elem.tag == "money" then
            local copper = GetMoney() or 0
            if elem.op == "<" then
                if step.hasVendor then
                    if pfGuide.merchantVisited and not pfGuide.merchantOpen and copper < elem.amount then
                        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[pfGuide]|r Step skipped: Insufficient funds after selling (%d / %d copper)", copper, elem.amount))
                        pfGuide:NextStep()
                        return
                    end
                elseif copper < elem.amount then
                    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[pfGuide]|r Step skipped: Cannot afford item purchase (%d / %d copper)", copper, elem.amount))
                    pfGuide:NextStep()
                    return
                end
            elseif elem.op == ">" then
                if not step.hasVendor and copper < elem.amount then
                    isCompleted = false
                    pendingReason = string.format("Need more money (%s / %s)", pfGuide:FormatMoney(copper), pfGuide:FormatMoney(elem.amount))
                end
            end
        elseif elem.tag == "collect" and elem.itemId then
            local onQuest = elem.questId and pfQuest.questlog and pfQuest.questlog[elem.questId]
            local turnedIn = elem.questId and pfQuest_history and pfQuest_history[elem.questId]
            local count = pfGuide:GetItemCount(elem.itemId)
            if not (onQuest or turnedIn) and count < elem.qty then
                isCompleted = false
                pendingReason = string.format("Collecting item %d (%d/%d)", elem.itemId, count, elem.qty)
            end
        elseif elem.tag == "itemcount" and elem.itemId then
            local count = pfGuide:GetItemCount(elem.itemId)
            if (elem.op == "<" and count >= elem.qty) or (elem.op == ">" and count <= elem.qty) then
                DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[pfGuide]|r Step skipped: Item count condition met (%d items)", count))
                pfGuide:NextStep()
                return
            end
        elseif elem.tag == "isonquest" and elem.questId then
            if not (pfQuest.questlog and pfQuest.questlog[elem.questId]) then
                pfGuide:NextStep()
                return
            end
        elseif elem.tag == "isquestcomplete" and elem.questId then
            if not pfGuide:IsQuestComplete(elem.questId) then
                pfGuide:NextStep()
                return
            end
        elseif elem.tag == "isquestnotcomplete" and elem.questId then
            if pfGuide:IsQuestComplete(elem.questId) then
                pfGuide:NextStep()
                return
            end
        elseif elem.tag == "isnotonquest" and elem.questId then
            if pfQuest.questlog and pfQuest.questlog[elem.questId] then
                pfGuide:NextStep()
                return
            end
        elseif elem.tag == "isquestturnedin" and elem.questId then
            local xpFulfilled = false
            for _, e in ipairs(step.elements) do
                if e.tag == "xp" and e.level and e.op ~= "<" then
                    local pLevel = UnitLevel("player") or 1
                    local pXp = UnitXP("player") or 0
                    if pLevel > e.level or (pLevel == e.level and pXp >= (e.xp or 0)) then
                        xpFulfilled = true
                        break
                    end
                end
            end
            if not xpFulfilled and not (pfQuest_history and pfQuest_history[elem.questId]) then
                isCompleted = false
                pendingReason = "Requires quest " .. elem.questId .. " turned in"
            end
        elseif elem.tag == "train" and elem.spellId and not elem.textOnly then
            if not IsSpellKnown(elem.spellId) then
                isCompleted = false
                local spellName = GetSpellInfo(elem.spellId) or ("Spell #" .. elem.spellId)
                pendingReason = "Train " .. spellName
            end
        elseif elem.tag == "xp" and elem.level and not elem.isSkipCheck then
            local pLevel = UnitLevel("player") or 1
            local pXp = UnitXP("player") or 0
            local reqXp = elem.xp or 0
            if pLevel < elem.level or (pLevel == elem.level and pXp < reqXp) then
                isCompleted = false
                pendingReason = string.format("Grind XP: Lv%d (+%d XP) [%d/%d]", elem.level, reqXp, pXp, reqXp)
            end
        elseif elem.tag == "deathskip" then
            local isGhost = UnitIsDeadOrGhost("player")
            if not isGhost then
                isCompleted = false
                pendingReason = "Die and respawn at Spirit Healer"
            end
        elseif elem.tag == "subzone" and elem.subzoneId then
            local subzoneText = GetSubZoneText and GetSubZoneText() or ""
            local minimapText = GetMinimapZoneText and GetMinimapZoneText() or ""
            local zoneLoc = pfDB and pfDB.zones and pfDB.zones.loc
            local subzoneName = zoneLoc and zoneLoc[elem.subzoneId] or ""
            local inSubzone = pfGuide.hasArrivedAtTarget

            if subzoneName and subzoneName ~= "" then
                inSubzone = inSubzone or subzoneText == subzoneName or minimapText == subzoneName
            end

            if not inSubzone and elem.subzoneId == 372 then
                inSubzone = (subzoneText ~= "" and (subzoneText:find("Tiragarde") or subzoneText:find("Тирагард"))) or
                    (minimapText ~= "" and (minimapText:find("Tiragarde") or minimapText:find("Тирагард")))
            end

            if not inSubzone then
                isCompleted = false
                pendingReason = "Travel to " .. (step.text ~= "" and step.text or "target area")
            end
        elseif elem.tag == "subzoneskip" and elem.subzoneId then
            local subzone = GetMinimapZoneText and GetMinimapZoneText() or ""
            if subzone ~= "" then
                isCompleted = false
                pendingReason = "Leave area: " .. subzone
            end
        elseif elem.tag == "hs" then
            if not pfGuide.hearthstoneUsed then
                isCompleted = false
                pendingReason = "Use Hearthstone"
            end
        elseif elem.tag == "accept" and elem.questId then
            if not (pfQuest.questlog and pfQuest.questlog[elem.questId]) and not (pfQuest_history and pfQuest_history[elem.questId]) then
                isCompleted = false
                pendingReason = "Accept quest " .. elem.questId
            end
        elseif elem.tag == "turnin" and elem.questId then
            if not (pfQuest_history and pfQuest_history[elem.questId]) then
                isCompleted = false
                pendingReason = "Turn in quest " .. elem.questId
            end
        elseif elem.tag == "complete" and elem.questId then
            local qData = pfQuest.questlog and pfQuest.questlog[elem.questId]
            if not qData then
                if not (pfQuest_history and pfQuest_history[elem.questId]) then
                    isCompleted = false
                    pendingReason = "Complete quest " .. elem.questId
                end
            else
                local _, done = pfGuide:GetObjectiveProgress(elem.questId, elem.objIndex)
                if not done then
                    isCompleted = false
                    pendingReason = "Complete quest objective " .. elem.questId
                end
            end
        end
    end

    if #step.gotoPoints > 0 then
        local pX, pY = GetPlayerMapPosition("player")
        if pX == 0 and pY == 0 then SetMapToCurrentZone(); pX, pY = GetPlayerMapPosition("player") end
        pX, pY = pX * 100, pY * 100

        local wp = step.gotoPoints[pfGuide.currentWaypointIndex]
        if wp and pX > 0 and pY > 0 then
            local dX = (pX - wp.x) * 1.45
            local dY = (pY - wp.y)
            local mapDist = math.sqrt(dX * dX + dY * dY)
            if mapDist <= math.max((wp.radius or 15) / 45.0, 0.6) then
                pfGuide.hasArrivedAtTarget = true
                if pfGuide.currentWaypointIndex < #step.gotoPoints then
                    pfGuide.currentWaypointIndex = pfGuide.currentWaypointIndex + 1
                    pfGuide:ExecuteCurrentStep()
                elseif #step.gotoPoints > 1 and (step.isLoop or step.hasComplete or step.hasCollect) then
                    pfGuide.currentWaypointIndex = 1
                    pfGuide:ExecuteCurrentStep()
                end
            end
        end

        local isPureTravel = not step.hasAcceptOrTurnIn and not step.hasComplete and not step.hasVendor and not step.hasTrainer and not step.hasCollect
        if isPureTravel and pfGuide.currentWaypointIndex >= #step.gotoPoints then
            local lastWp = step.gotoPoints[#step.gotoPoints]
            local dX = (pX - lastWp.x) * 1.45
            local dY = (pY - lastWp.y)
            if math.sqrt(dX * dX + dY * dY) > math.max((lastWp.radius or 15) / 45.0, 0.6) then
                isCompleted = false
                pendingReason = "Travel to waypoint"
            end
        end
    end

    if isCompleted and #step.elements > 0 then
        if step.label then pfGuide.completedLabels[step.label] = true end
        pfGuide.furthestStepIndex = math.max(pfGuide.furthestStepIndex or 1, pfGuide.currentStepIndex + 1)
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[pfGuide]|r Step %d completed!", pfGuide.currentStepIndex))
        pfGuide:NextStep()
    else
        local reason = pendingReason or "No completion condition met"
        if pfGuide.lastPendingStep ~= pfGuide.currentStepIndex or pfGuide.lastPendingReason ~= reason then
            print(string.format("[pfGuide Debug] Step %d waiting: %s", pfGuide.currentStepIndex, reason))
            pfGuide.lastPendingStep = pfGuide.currentStepIndex
            pfGuide.lastPendingReason = reason
        end
        pfGuide:UpdateUI()
    end
end

function pfGuide:NextStep(isManual)
    local guide = pfGuide.currentGuide
    if not guide then return end
    if pfGuide.currentStepIndex < #guide.steps then
        pfGuide.currentStepIndex = pfGuide.currentStepIndex + 1
        if not isManual or pfGuide.currentStepIndex > (pfGuide.furthestStepIndex or 1) then
            pfGuide.furthestStepIndex = pfGuide.currentStepIndex
        end
        pfGuide.currentWaypointIndex = 1
        pfGuide.lastPendingStep = nil
        pfGuide.lastPendingReason = nil
        pfGuide.merchantInteracted = false
        pfGuide.merchantVisited = false
        pfGuide.merchantOpen = false
        pfGuide.hasArrivedAtTarget = false
        pfGuide.trainerVisited = false
        pfGuide.trainerOpen = false
        pfGuide.hearthstoneUsed = false

        -- Complete any ambient tasks with completeWith == "next"
        local toRemove = {}
        for i, pStep in ipairs(pfGuide.activePassiveSteps) do
            if pStep.completeWith == "next" then
                table.insert(toRemove, i)
            end
        end
        for j = #toRemove, 1, -1 do
            table.remove(pfGuide.activePassiveSteps, toRemove[j])
        end

        pfGuide:FindNearestWaypoint()
        pfGuide:ExecuteCurrentStep()
        pfGuide:UpdateUI()
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
        pfGuide.lastPendingStep = nil
        pfGuide.lastPendingReason = nil
        pfGuide.merchantVisited = false
        pfGuide.trainerVisited = false
        pfGuide.merchantOpen = false
        pfGuide.trainerOpen = false
        pfGuide.hasArrivedAtTarget = false
        pfGuide:FindNearestWaypoint()
        pfGuide:ExecuteCurrentStep(true)
        pfGuide:UpdateUI()
    end
end

function pfGuide:UpdateUI()
    local guide = pfGuide.currentGuide
    if not guide or not guide.steps[pfGuide.currentStepIndex] then
        pfQuestGuideWindow.title:SetText("pfQuest RXP Guide")
        pfQuestGuideWindow.text:SetText("No active step.")
        return
    end

    local step = guide.steps[pfGuide.currentStepIndex]
    pfQuestGuideWindow.title:SetText(string.format("|cff00ff00%s|r [Step %d/%d]", guide.name, pfGuide.currentStepIndex, #guide.steps))

    local displayText = ""
    local hasDirectAction = step.hasAcceptOrTurnIn or step.hasComplete or step.hasTrainer or step.hasVendor or step.hasCollect

    for _, elem in ipairs(step.elements) do
        if elem.tag == "accept" then
            displayText = displayText .. "|cffffff00[!] Accept:|r " .. pfGuide:GetQuestTitle(elem.questId) .. "\n"
        elseif elem.tag == "turnin" then
            displayText = displayText .. "|cff00ff00[?] Turn in:|r " .. pfGuide:GetQuestTitle(elem.questId) .. "\n"
        elseif elem.tag == "complete" then
            local progText, isDone = pfGuide:GetObjectiveProgress(elem.questId, elem.objIndex)
            local title = pfGuide:GetQuestTitle(elem.questId)
            local main = (progText and progText ~= "") and progText or title
            displayText = displayText .. "|cffff5555[*]|r " .. main .. (isDone and " |cff00ff00(Done)|r" or "") .. "\n"
        elseif elem.tag == "collect" then
            local count = pfGuide:GetItemCount(elem.itemId)
            local itemName = (pfDB and pfDB.items and pfDB.items.loc and pfDB.items.loc[elem.itemId]) or ("Item #" .. elem.itemId)
            displayText = displayText .. "|cffff5555[*]|r Collect " .. itemName .. string.format(" (%d/%d)", count, elem.qty) .. "\n"
        elseif elem.tag == "goto" and not hasDirectAction and #step.gotoPoints <= 2 then
            displayText = displayText .. "|cff00bfff[>] Travel to:|r " .. string.format("%s (%.1f, %.1f)", elem.zone or "", elem.x or 0, elem.y or 0) .. "\n"
        elseif elem.tag == "target" and not hasDirectAction then
            displayText = displayText .. "|cffffff00[Talk]|r " .. (step.text ~= "" and step.text or ("Talk to " .. (elem.target or "NPC"))) .. "\n"
        elseif elem.tag == "train" or elem.tag == "trainer" then
            local spellName = (elem.spellId and GetSpellInfo(elem.spellId)) or (elem.text ~= "" and elem.text) or "Class Skills"
            local isKnown = elem.spellId and IsSpellKnown(elem.spellId)
            displayText = displayText .. "|cff00ffcc[T] Train:|r " .. spellName .. (isKnown and " |cff00ff00(Done)|r" or "") .. "\n"
        elseif elem.tag == "vendor" then
            displayText = displayText .. "|cffffff00[Vendor]|r " .. (step.text ~= "" and step.text or "Sell Junk / Vendor Trash") .. "\n"
        elseif elem.tag == "money" and elem.op == ">" and not step.hasVendor then
            local copper = GetMoney() or 0
            displayText = displayText .. string.format("|cffff5555[*]|r Farm %s from mobs (Current: %s)\n", pfGuide:FormatMoney(elem.amount), pfGuide:FormatMoney(copper))
        elseif elem.tag == "xp" and not elem.isSkipCheck then
            local pLevel = UnitLevel("player") or 1
            local pXp = UnitXP("player") or 0
            displayText = displayText .. string.format("|cffff5555[*]|r Grind to Lv %d (+%d XP) [%d/%d]\n", elem.level, elem.xp or 0, pXp, elem.xp or 0)
        elseif elem.tag == "deathskip" then
            displayText = displayText .. "|cffff0000[Death]|r " .. (step.text ~= "" and step.text or "Die and respawn at Spirit Healer") .. "\n"
        elseif elem.tag == "hs" then
            displayText = displayText .. "|cff00ccff[HS]|r " .. (step.text ~= "" and step.text or "Use Hearthstone") .. "\n"
        elseif elem.tag == "info" then
            displayText = displayText .. elem.text .. "\n"
        end
    end

    if displayText == "" then displayText = step.text or "Follow navigation arrow." end

    -- Append ambient/passive side tasks
    if #pfGuide.activePassiveSteps > 0 then
        displayText = displayText .. "\n---------------------------------"
        for _, pStep in ipairs(pfGuide.activePassiveSteps) do
            for _, elem in ipairs(pStep.elements) do
                if elem.tag == "complete" then
                    local progText, isDone = pfGuide:GetObjectiveProgress(elem.questId, elem.objIndex)
                    local title = pfGuide:GetQuestTitle(elem.questId)
                    local main = (progText and progText ~= "") and progText or title
                    displayText = displayText .. "\n|cff888888[Side]|r " .. main
                elseif elem.tag == "collect" then
                    local count = pfGuide:GetItemCount(elem.itemId)
                    local itemName = (pfDB and pfDB.items and pfDB.items.loc and pfDB.items.loc[elem.itemId]) or ("Item #" .. elem.itemId)
                    displayText = displayText .. string.format("\n|cff888888[Side]|r Collect %s (%d/%d)", itemName, count, elem.qty)
                elseif elem.tag == "xp" and elem.level and not elem.isSkipCheck then
                    local pLevel = UnitLevel("player") or 1
                    local pXp = UnitXP("player") or 0
                    local reqXp = elem.xp or 0
                    displayText = displayText .. string.format("\n|cff888888[Side]|r Grind to Lv %d (+%d XP) [%d/%d]", elem.level, reqXp, pXp, reqXp)
                end
            end
        end
    end

    pfQuestGuideWindow.text:SetText(displayText)
    local lineCount = select(2, displayText:gsub("\n", "\n"))
    pfQuestGuideWindow:SetHeight(math.max(65, 34 + lineCount * 14))
end

-- Events
pfGuide:RegisterEvent("PLAYER_ENTERING_WORLD")
pfGuide:RegisterEvent("QUEST_ACCEPTED")
pfGuide:RegisterEvent("QUEST_LOG_UPDATE")
pfGuide:RegisterEvent("QUEST_WATCH_UPDATE")
pfGuide:RegisterEvent("PLAYER_XP_UPDATE")
pfGuide:RegisterEvent("ZONE_CHANGED")
pfGuide:RegisterEvent("ZONE_CHANGED_NEW_AREA")
pfGuide:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
pfGuide:RegisterEvent("MERCHANT_SHOW")
pfGuide:RegisterEvent("MERCHANT_CLOSED")
pfGuide:RegisterEvent("TRAINER_SHOW")
pfGuide:RegisterEvent("TRAINER_CLOSED")
pfGuide:RegisterEvent("PLAYER_MONEY")
pfGuide:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

pfGuide:SetScript("OnEvent", function()
    if event == "PLAYER_ENTERING_WORLD" then
        pfGuide:LoadAllGuides()
        if pfQuest and pfQuest.UpdateQuestlog then
            pfQuest:UpdateQuestlog()
        end
        if QueryQuestsCompleted then
            QueryQuestsCompleted()
        end
        local def = pfGuide:FindDefaultGuide()
        if def then pfGuide:SetCurrentGuide(def.name) end
        pfQuestGuideWindow:Show()
    elseif event == "MERCHANT_SHOW" then
        pfGuide.merchantOpen = true
        pfGuide.hasArrivedAtTarget = true
        pfGuide.merchantInteracted = true
        print(string.format("[pfGuide Debug] MERCHANT_SHOW: Step %d, hasVendor=%s, hasCollect=%s, merchantOpen=%s, merchantInteracted=%s", pfGuide.currentStepIndex or 0, tostring(pfGuide.currentGuide and pfGuide.currentGuide.steps[pfGuide.currentStepIndex] and pfGuide.currentGuide.steps[pfGuide.currentStepIndex].hasVendor), tostring(pfGuide.currentGuide and pfGuide.currentGuide.steps[pfGuide.currentStepIndex] and pfGuide.currentGuide.steps[pfGuide.currentStepIndex].hasCollect), tostring(pfGuide.merchantOpen), tostring(pfGuide.merchantInteracted)))
    elseif event == "MERCHANT_CLOSED" then
        pfGuide.merchantOpen = false
        local guide = pfGuide.currentGuide
        local step = guide and guide.steps[pfGuide.currentStepIndex]
        if step and (step.hasVendor or step.hasCollect) then
            pfGuide.merchantVisited = true
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[pfGuide]|r Merchant closed, checking vendor step completion...")
            pfGuide:CheckStepCompletion()
        end
    elseif event == "TRAINER_SHOW" then
        pfGuide.trainerOpen = true
    elseif event == "TRAINER_CLOSED" then
        pfGuide.trainerOpen = false
        local guide = pfGuide.currentGuide
        local step = guide and guide.steps[pfGuide.currentStepIndex]
        if step and step.hasTrainer then
            pfGuide.trainerVisited = true
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[pfGuide]|r Trainer closed, checking step completion...")
            pfGuide:CheckStepCompletion()
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, spellName = arg1, arg2
        local hsName = GetSpellInfo(8690) or "Hearthstone"
        local arName = GetSpellInfo(556) or "Astral Recall"
        if unit == "player" and (spellName == hsName or spellName == arName) then
            pfGuide.hearthstoneUsed = true
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[pfGuide]|r Hearthstone cast succeeded!")
            pfGuide:CheckStepCompletion()
        end
    else
        pfGuide:CheckStepCompletion()
    end
end)

local lastUpdate = 0
pfGuide:SetScript("OnUpdate", function()
    local now = GetTime()
    if now - lastUpdate > 0.25 then
        lastUpdate = now
        pfGuide:CheckStepCompletion()
    end
end)

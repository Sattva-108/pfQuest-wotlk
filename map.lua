-- multi api compat
local compat = pfQuestCompat

-- fake the pfQuest minimap node names to Gatherer names,
-- if any minimap-breaking addon collector is found.
local nodename = "pfMiniMapPin"
local minimapbreakers = {
    ["ElvUI_MinimapButtons"] = true,
    ["MBB"] = true,
}

local compatnamefake = CreateFrame("Frame")
compatnamefake:RegisterEvent("PLAYER_ENTERING_WORLD")
compatnamefake:SetScript("OnEvent", function()
    -- only run once on login
    this:UnregisterAllEvents()

    -- scan through all addons to identify button collectors
    for i=1, GetNumAddOns() do
        local name, title, notes, enabled = GetAddOnInfo(i)
        if enabled and minimapbreakers[name] then
            nodename = "GatherNoteCompatFake"
        end
    end
end)

-- checking for control key is very time expensive in 1.12
-- this loop puts it into one place and only updates it every .2 seconds
-- it also only updates the key if the mouse is over a relevant frame
local controlkey = CreateFrame("Frame", "pfQuestControlKey", UIParent)
controlkey:SetScript("OnUpdate", function()
    if ( this.throttle or .2) > GetTime() then return else this.throttle = GetTime() + .2 end
    if WorldMapFrame:IsShown() and MouseIsOver(WorldMapFrame) or MouseIsOver(pfMap.drawlayer) then
        controlkey.pressed = IsControlKeyDown()
    end
end)

local validmaps = setmetatable({},{__mode="kv"})
local rgbcache = setmetatable({},{__mode="kv"})
local minimap_sizes = pfDB["minimap"]
local minimap_zoom = {
    [0] = { [0] = 300,
            [1] = 240,
            [2] = 180,
            [3] = 120,
            [4] = 80,
            [5] = 50,
    },

    [1] = { [0] = 466 + 2/3,
            [1] = 400,
            [2] = 333 + 1/3,
            [3] = 266 + 2/6,
            [4] = 200,
            [5] = 133 + 1/3,
    },
}

local unifiedcache = {}

-- used to store/cache combined meta data across nodes of
-- the same kind to avoid duplicating data for each pin
-- the objects here get directly attached to the pfMap nodes
local similar_nodes = {}

local function IsEmpty(tabl)
    for k,v in pairs(tabl) do
        return false
    end
    return true
end

local layers = {
    -- regular icons
    [pfQuestConfig.path.."\\img\\available"]          = 1,
    [pfQuestConfig.path.."\\img\\available_c"]        = 2,
    [pfQuestConfig.path.."\\img\\complete"]           = 3,
    [pfQuestConfig.path.."\\img\\complete_c"]         = 4,
    [pfQuestConfig.path.."\\img\\icon_vendor"]        = 5,
    [pfQuestConfig.path.."\\img\\fav"]                = 6,

    -- cluster textures
    [pfQuestConfig.path.."\\img\\cluster_item"]       = 9,
    [pfQuestConfig.path.."\\img\\cluster_mob"]        = 9,
    [pfQuestConfig.path.."\\img\\cluster_misc"]       = 9,
    [pfQuestConfig.path.."\\img\\cluster_mob_mono"]   = 9,
    [pfQuestConfig.path.."\\img\\cluster_item_mono"]  = 9,
    [pfQuestConfig.path.."\\img\\cluster_misc_mono"]  = 9,
}

local function GetLayerByTexture(tex)
    if layers[tex] then return layers[tex] else return 1 end
end

local function minimap_indoor()
    local tempzoom = 0
    local state = 1
    if GetCVar("minimapZoom") == GetCVar("minimapInsideZoom") then
        if GetCVar("minimapInsideZoom")+0 >= 3 then
            pfMap.drawlayer:SetZoom(pfMap.drawlayer:GetZoom() - 1)
            tempzoom = 1
        else
            pfMap.drawlayer:SetZoom(pfMap.drawlayer:GetZoom() + 1)
            tempzoom = -1
        end
    end

    if GetCVar("minimapInsideZoom")+0 == pfMap.drawlayer:GetZoom() then
        state = 0
    end

    pfMap.drawlayer:SetZoom(pfMap.drawlayer:GetZoom() + tempzoom)
    return state
end

local function str2rgb(text)
    if not text then return 1, 1, 1 end
    if pfQuest_colors[text] then return unpack(pfQuest_colors[text]) end
    if rgbcache[text] then return unpack(rgbcache[text]) end
    local counter = 1
    local l = string.len(text)
    for i = 1, l, 3 do
        counter = compat.mod(counter*8161, 4294967279) +
            (string.byte(text,i)*16776193) +
            ((string.byte(text,i+1) or (l-i+256))*8372226) +
            ((string.byte(text,i+2) or (l-i+256))*3932164)
    end
    local hash = compat.mod(compat.mod(counter, 4294967291),16777216)
    local r = (hash - (compat.mod(hash,65536))) / 65536
    local g = ((hash - r*65536) - ( compat.mod((hash - r*65536),256)) ) / 256
    local b = hash - r*65536 - g*256
    rgbcache[text] = { r / 255, g / 255, b / 255 }
    return unpack(rgbcache[text])
end

local fpsmod, step
local function NodeAnimate(self, zoom, alpha, fps)
    local cur_zoom = self:GetWidth()
    local cur_alpha = self:GetAlpha()
    local change = nil
    self:EnableMouse(true)
    fpsmod = math.min(2/fps, 2)
    step = fpsmod/10

    -- update size
    if math.abs(cur_zoom - zoom) < 3 then
        self:SetWidth(zoom)
        self:SetHeight(zoom)
    elseif cur_zoom < zoom then
        self:SetWidth(cur_zoom + fpsmod)
        self:SetHeight(cur_zoom + fpsmod)
        change = true
    elseif cur_zoom > zoom then
        self:SetWidth(cur_zoom - fpsmod)
        self:SetHeight(cur_zoom - fpsmod)
        change = true
    end

    -- update alpha
    if math.abs(cur_alpha - alpha) < step then
        self:SetAlpha(alpha)

        -- disable mouse on hidden
        if alpha < .1 then
            self:EnableMouse(nil)
        end
    elseif cur_alpha < alpha then
        self:SetAlpha(cur_alpha + step)
        change = true
    elseif cur_alpha > alpha then
        self:SetAlpha(cur_alpha - step)
        change = true
    end

    return change
end

-- put player position above everything on worldmap
for k, v in pairs({WorldMapFrame:GetChildren()}) do
    if v:IsObjectType("Model") and not v:GetName() then
        if string.find(strlower(v:GetModel()), "interface\\minimap\\minimaparrow") then
            v:SetFrameLevel(255)
            break
        end
    end
end

pfMap = CreateFrame("Frame", "pfQuestMap", WorldFrame)
pfMap.str2rgb = str2rgb
pfMap.tooltips = {}
pfMap.nodes = {}
pfMap.pins = {}
pfMap.mpins = {}
pfMap.drawlayer = Minimap
pfMap.unifiedcache = unifiedcache
pfMap.playerIsInUnderbelly = false
pfMap.checkUnderbelly = false

pfMap.minimap_indoor = minimap_indoor
pfMap.minimap_zoom = minimap_zoom
pfMap.minimap_sizes = minimap_sizes

-- Ctrl+Map blob switching state
pfMap.showBlizzardBlobs = false
pfMap.originalQuestPOI = nil  -- Store original questPOI setting

-- INSERT: Track the node that owns the currently displayed tooltip so we can fully rebuild it when Alt is pressed.
pfMap.tooltipCurrentNode = nil

-- Очистить квест из всех кэшей и структур данных
function pfMap:ClearQuestFromCaches(questID)
    -- Удалить квест из pfQuest.questlog чтобы он перестал считаться активным
    pfQuest.questlog[questID] = nil

    -- Удалить квест из очереди pfQuest.queue
    for idx, entry in pairs(pfQuest.queue) do
        if entry[2] == questID then
            pfQuest.queue[idx] = nil
        end
    end

    -- Принудительно обновить доступные квесты для этого NPC
    pfQuest.updateQuestGivers = true
    pfQuest.updateQuestLog = true

    -- Очистить кэш кластеров чтобы принудительно пересканировать этого NPC
    pfMap.clusterCache = nil

    -- Принудительно обновить карту сейчас же
    pfMap.queue_update = GetTime()

    -- Полностью очистить все кэши чтобы принудительно пересканировать доступные квесты
    pfMap.unifiedcache = {}
    for k,v in pairs(similar_nodes) do
        if v and v.questid == questID then
            similar_nodes[k] = nil
        end
    end
end

-- XP Rate Detection System
pfMap.xpRateDetector = {
    detectedRate = 1.0,           -- Current detected rate
    confidence = 0,               -- Confidence level (0-100)
    samples = {},                 -- Sliding window of rate samples
    maxSamples = 7,               -- Maximum samples in sliding window
    minSamples = 1,               -- Minimum samples for rate calculation
    changeThreshold = 20,         -- Percentage threshold for rate change detection
    waitingForQuestXP = false,    -- Flag for quest XP tracking
    currentQuestID = nil,         -- Currently tracked quest

    -- Add a new XP sample and update rate
    AddSample = function(self, questID, receivedXP)
        -- Get base XP from database
        local baseXP = pfDB and pfDB["quests"] and pfDB["quests"]["data"] and
            pfDB["quests"]["data"][questID] and pfDB["quests"]["data"][questID]["xp"]

        if not baseXP or baseXP <= 0 or receivedXP <= 0 then
            return
        end

        local newRate = receivedXP / baseXP

        -- Filter out unreasonable rates
        if newRate < 0.1 or newRate > 50 then
            return
        end

        -- Check if this might be a rate change
        if table.getn(self.samples) > 0 then
            local currentRate = self:GetCurrentRate()
            local percentDiff = math.abs((newRate - currentRate) / currentRate * 100)

            if percentDiff > self.changeThreshold then
                -- Possible rate change - clear old samples
                self.samples = {}
                self.confidence = 0
            end
        end

        -- Add new sample
        table.insert(self.samples, newRate)

        -- Maintain sliding window
        if table.getn(self.samples) > self.maxSamples then
            table.remove(self.samples, 1)
        end

        -- Update detected rate and confidence
        self:UpdateRate()
    end,

    -- Update detected rate based on current samples
    UpdateRate = function(self)
        local sampleCount = table.getn(self.samples)
        if sampleCount == 0 then
            self.detectedRate = 1.0
            self.confidence = 0
            return
        end

        -- Calculate median for stability
        local sortedSamples = {}
        for i, sample in ipairs(self.samples) do
            table.insert(sortedSamples, sample)
        end
        table.sort(sortedSamples)

        local median
        if math.mod(sampleCount, 2) == 0 then
            median = (sortedSamples[sampleCount/2] + sortedSamples[sampleCount/2 + 1]) / 2
        else
            median = sortedSamples[math.ceil(sampleCount/2)]
        end

        self.detectedRate = median

        -- Calculate confidence based on sample count and consistency
        if sampleCount >= 3 then
            self.confidence = math.min(90, 60 + sampleCount * 5)
        else
            self.confidence = 30 + sampleCount * 15
        end

        -- Reduce confidence if samples are inconsistent
        local variance = 0
        for _, sample in ipairs(self.samples) do
            variance = variance + (sample - median)^2
        end
        variance = variance / sampleCount

        -- High variance reduces confidence
        if variance > 0.01 then  -- 10% variance threshold
            self.confidence = self.confidence * 0.7
        end

        self.confidence = math.floor(self.confidence)
    end,

    -- Get current rate for calculations
    GetCurrentRate = function(self)
        return self.detectedRate
    end,

    -- Estimate XP for a quest
    EstimateQuestXP = function(self, questID)
        local baseXP = pfDB and pfDB["quests"] and pfDB["quests"]["data"] and
            pfDB["quests"]["data"][questID] and pfDB["quests"]["data"][questID]["xp"]

        if baseXP and baseXP > 0 then
            local estimatedXP = math.floor(baseXP * self:GetCurrentRate())
            return estimatedXP, self.confidence
        end

        return nil, 0
    end,

    -- Start tracking quest XP
    StartTracking = function(self, questID)
        self.waitingForQuestXP = true
        self.currentQuestID = questID

        -- Register temporary events
        pfMap:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
        pfMap:RegisterEvent("PLAYER_XP_UPDATE")
        pfMap:RegisterEvent("GOSSIP_CLOSED")
    end,

    -- Stop tracking and clean up
    StopTracking = function(self)
        self.waitingForQuestXP = false
        self.currentQuestID = nil

        -- Unregister temporary events
        pfMap:UnregisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
        pfMap:UnregisterEvent("PLAYER_XP_UPDATE")
        pfMap:UnregisterEvent("GOSSIP_CLOSED")
    end,

    -- Parse XP from combat message
    ParseXPMessage = function(self, message)
        if not message then return nil end

        -- Only accept messages without comma (quest XP, not kill XP)
        if string.find(message, ",") then
            return nil
        end

        -- Parse XP amount from message
        local xp = string.match(message, "(%d+)")
        return xp and tonumber(xp) or nil
    end
}

pfMap.tooltip = CreateFrame("Frame" , "pfMapTooltip", GameTooltip)
pfMap.tooltip:SetScript("OnShow", function()
    local focus = GetMouseFocus()
    -- abort on pfQuest nodes
    if focus and focus.title then return end
    -- abort on quest timers
    if focus and focus.GetName and strsub((focus:GetName() or ""),0,10) == "QuestTimer" then return end
    -- abort if tooltips are disabled
    if pfQuest_config.showtooltips == "0" then return end

    -- Save original Blizzard tooltip lines
    pfMap._origLines = {}
    for i = 1, GameTooltip:NumLines() do
        local txt = _G["GameTooltipTextLeft"..i]:GetText()
        pfMap._origLines[#pfMap._origLines+1] = txt
    end

    local name = getglobal("GameTooltipTextLeft1") and getglobal("GameTooltipTextLeft1"):GetText() or "__NONE__"
    local zone = pfMap:GetMapID(GetCurrentMapContinent(), GetCurrentMapZone())

    -- remove all colors from received tooltip text
    name = string.gsub(name, "|c%x%x%x%x%x%x%x%x", "")
    name = string.gsub(name, "|r", "")

    if pfMap.tooltips[name] and pfMap.tooltips[name] then
        -- Build (or reset) the list of meta tables that belong to this tooltip so
        -- we can properly rebuild it later (e.g. when <Alt> is pressed).
        pfMap.tooltipMetaList = {}

        -- Calculate total tooltip size first
        local totalEstimatedChars = 0
        for title, obj in pairs(pfMap.tooltips[name]) do
            if obj[zone] and obj[zone]["questid"] then
                totalEstimatedChars = pfMap:addObjectiveChars(obj[zone]["questid"], totalEstimatedChars)
            end
        end
        local shouldCompact = (totalEstimatedChars > 200)

        -- Show all tooltips with same compact setting and remember their meta tables
        for title, obj in pairs(pfMap.tooltips[name]) do
            if obj[zone] then
                table.insert(pfMap.tooltipMetaList, obj[zone])
                pfMap:ShowTooltip(obj[zone], GameTooltip, shouldCompact)
                GameTooltip:Show()
            end
        end

        -- If for some reason we did not collect any meta data, clear the list to avoid stale references
        if pfMap.tooltipMetaList and table.getn(pfMap.tooltipMetaList) == 0 then
            pfMap.tooltipMetaList = nil
        end
    end
end)

-- Separate cleanup for each tooltip type
GameTooltip:HookScript("OnHide", function()
    -- Clear GameTooltip-specific data
    pfMap.tooltipMeta = nil
    pfMap.tooltipMetaList = nil
    pfMap._origLines = nil
end)

-- WorldMapTooltip cleanup when needed
if WorldMapTooltip then
    WorldMapTooltip:HookScript("OnHide", function()
        -- Clear WorldMap-specific data only when really hiding
        if not WorldMapFrame:IsShown() then
            pfMap.tooltipCurrentNode = nil
        end
    end)
end

-- dummy function that can be used by extensions
-- to avoid drawing the minimap at some locations
function pfMap:HasMinimap()
    return true
end


function pfMap.tooltip:GetColor(min, max)
    local max = max or 1
    local min = min or max or 1

    local perc = min / max
    local r1, g1, b1, r2, g2, b2
    if perc <= 0.5 then
        perc = perc * 2
        r1, g1, b1 = 1, 0, 0
        r2, g2, b2 = 1, 1, 0
    else
        perc = perc * 2 - 1
        r1, g1, b1 = 1, 1, 0
        r2, g2, b2 = 0, 1, 0
    end
    r = r1 + (r2 - r1)*perc
    g = g1 + (g2 - g1)*perc
    b = b1 + (b2 - b1)*perc

    return r, g, b
end

function pfMap:HexDifficultyColor(level, force)
    if force and UnitLevel("player") < level then
        return "|cffff5555"
    else
        local c = pfQuestCompat.GetDifficultyColor(level)
        return string.format("|cff%02x%02x%02x", c.r*255, c.g*255, c.b*255)
    end
end

-- GetQuestXP: Calculate quest experience based on AzerothCore source code
function pfMap:GetQuestXP(questData)
    if not questData then return 0 end

    -- Lightweight max-level check: when the player has reached the current server cap
    -- the WoW client reports UnitXPMax("player") == 0 and hides MainMenuExpBar.
    -- Rely on that API (instead of hard-coding level 80/70/255, etc.) so the logic
    -- works on servers with custom level caps and even if other addons hide the bar.
    if UnitXPMax("player") == 0 then
        return 0
    end

    local playerLevel = UnitLevel("player") or 1
    -- AzerothCore logic: quest_level = (Level == -1 ? playerLevel : Level)
    local questLevel = (questData.lvl == -1) and playerLevel or (questData.lvl or 1)
    local xpDifficulty = questData.xp_diff or 0  -- Default to difficulty 0 if not set

    -- Step 1: Get base XP from questxp lookup table (QuestXP.dbc)
    local baseXP = 0
    if pfDB["questxp"] and pfDB["questxp"]["data"] and pfDB["questxp"]["data"][questLevel] then
        local xpTable = pfDB["questxp"]["data"][questLevel]
        -- Convert 0-based database index to 1-based Lua index
        local luaIndex = xpDifficulty + 1
        if xpTable and xpTable[luaIndex] then
            baseXP = xpTable[luaIndex]
        end
    end

    -- Step 2: Apply AzerothCore diffFactor formula
    -- diffFactor = clamp(2 * (questLevel - playerLevel) + 20, 1, 10)
    local diffFactor = 2 * (questLevel - playerLevel) + 20
    diffFactor = math.max(1, math.min(10, diffFactor))

    -- Step 3: Calculate XP with diffFactor
    local xp = diffFactor * baseXP / 10

    -- Step 4: Apply AzerothCore rounding (stepped rounding)
    if xp <= 100 then
        xp = 5 * math.floor((xp + 2) / 5)
    elseif xp <= 500 then
        xp = 10 * math.floor((xp + 5) / 10)
    elseif xp <= 1000 then
        xp = 25 * math.floor((xp + 12) / 25)
    else
        xp = 50 * math.floor((xp + 25) / 50)
    end

    -- Step 5: Apply server rate (GetQuestRate)
    local serverRate = (pfMap.xpRateDetector and pfMap.xpRateDetector:GetCurrentRate()) or 1
    xp = xp * serverRate * 1

    -- Step 6: Final floor (as AzerothCore converts to uint32)
    return math.floor(xp)
end

function pfMap:ShowTooltip(meta, tooltip, forceCompact)
    local catch = nil
    local catch_obj = nil
    local tooltip = tooltip or GameTooltip

    -- Safety check: don't set meta if tooltip is not shown
    if not tooltip:IsShown() then
        return
    end

    -- Ultra lightweight: just store meta when tooltip shown
    pfMap.tooltipMeta = meta

    -- add quest data
    if meta["quest"] then
        -- scan all quest entries for matches
        for qid=1, GetNumQuestLogEntries() do
            local qtitle, _, _, _, _, complete = compat.GetQuestLogTitle(qid)

            if meta["quest"] == qtitle then
                -- handle active quests
                local objectives = GetNumQuestLeaderBoards(qid)
                catch = true

                local symbol = complete and "|cff555555[|cffffcc00?|cff555555]|r " or "|cff555555[|cff888888?|cff555555]|r "
                tooltip:AddLine(symbol .. meta["quest"], 1, 1, 0)

                if objectives then
                    for i=1, objectives, 1 do
                        local text, type, finished = GetQuestLogLeaderBoard(i, qid)

                        if type == "monster" then
                            -- kill
                            local i, j, monsterName, objNum, objNeeded = strfind(text, pfUI.api.SanitizePattern(QUEST_MONSTERS_KILLED))
                            if monsterName and meta["spawn"] == monsterName then
                                catch_obj = true
                                local r,g,b = pfMap.tooltip:GetColor(objNum, objNeeded)
                                tooltip:AddLine("|cffaaaaaa- |r" .. monsterName .. ": " .. objNum .. "/" .. objNeeded, r, g, b)
                            end
                        elseif table.getn(meta["item"]) > 0 and type == "item" and meta["droprate"] then
                            -- loot
                            local i, j, itemName, objNum, objNeeded = strfind(text, pfUI.api.SanitizePattern(QUEST_OBJECTS_FOUND))

                            for mid, item in pairs(meta["item"]) do
                                if item == itemName then
                                    catch_obj = true
                                    local r,g,b = pfMap.tooltip:GetColor(objNum, objNeeded)
                                    local dr,dg,db = pfMap.tooltip:GetColor(tonumber(meta["droprate"]), 100)
                                    local lootcolor = string.format("%02x%02x%02x", dr * 255,dg * 255, db * 255)
                                    tooltip:AddLine("|cffaaaaaa- |r" .. itemName .. ": " .. objNum .. "/" .. objNeeded .. " |cff555555[|cff" .. lootcolor .. meta["droprate"] .. "%|cff555555]", r, g, b)
                                end
                            end
                        elseif table.getn(meta["item"]) > 0 and type == "item" and meta["sellcount"] then
                            -- vendor
                            local i, j, itemName, objNum, objNeeded = strfind(text, pfUI.api.SanitizePattern(QUEST_OBJECTS_FOUND))

                            for mid, item in pairs(meta["item"]) do
                                if item == itemName then
                                    catch_obj = true
                                    local r,g,b = pfMap.tooltip:GetColor(objNum, objNeeded)
                                    local sellcount = tonumber(meta["sellcount"]) > 0 and " |cff555555[|cffcccccc" .. meta["sellcount"] .. "x" .. "|cff555555]" or ""
                                    tooltip:AddLine("|cffaaaaaa- |r" .. pfQuest_Loc["Buy"] .. ": " .. itemName .. ": " .. objNum .. "/" .. objNeeded .. sellcount, r, g, b)
                                end
                            end
                        end
                    end
                end
            end
        end

        if not catch then
            tooltip:AddLine("|cff555555[|cffffcc00!|cff555555]|r " .. meta["quest"], 1, 1, 0)
        end

        if not catch_obj then
            -- handle inactive quests
            local catchFallback = nil

            if meta["item"] and meta["item"][1] and meta["droprate"] then
                for mid, item in pairs(meta["item"]) do
                    catchFallback = true
                    local dr, dg, db = pfMap.tooltip:GetColor(tonumber(meta["droprate"]), 100)
                    local lootcolor = string.format("%02x%02x%02x", dr * 255, dg * 255, db * 255)
                    tooltip:AddLine("|cffaaaaaa- |r" .. item .. " |cff555555[|cff" .. lootcolor .. meta["droprate"] .. "%|cff555555]", .7, .7, .7)
                end
            end

            if meta["item"] and meta["item"][1] and meta["sellcount"] then
                for mid, item in pairs(meta["item"]) do
                    catchFallback = true
                    local sellcount = tonumber(meta["sellcount"]) > 0 and " |cff555555[|cffcccccc" .. meta["sellcount"] .. "x" .. "|cff555555]" or ""
                    tooltip:AddLine("|cffaaaaaa- |r" .. pfQuest_Loc["Buy"] .. ": " .. item .. sellcount, .7, .7, .7)
                end
            end

            if not catchFallback and meta["spawn"] and not meta["texture"] then
                catchFallback = true
                tooltip:AddLine("|cffaaaaaa- |r" .. (meta["spawntype"] and meta["spawntype"] == "Trigger" and pfQuest_Loc["Explore"] or meta["spawn"]), .7,.7,.7)
            end

            if not catchFallback and meta["texture"] and meta["qlvl"] then
                local texts = meta["questid"] and pfDB["quests"]["loc"][meta["questid"]] or nil

                if texts and texts["O"] and texts["O"] ~= "" then
                    local objectiveText = forceCompact and pfMap:truncateAtDoubleB(texts["O"]) or texts["O"]
                    local formattedText = pfDatabase:FormatQuestText(objectiveText)


                    tooltip:AddLine(formattedText,1,1,.9,true)
                end

                local qlvlstr = pfQuest_Loc["Level"] .. ": " .. pfMap:HexDifficultyColor(meta["qlvl"]) .. meta["qlvl"] .. "|r"
                local qminstr = meta["qmin"] and " / " .. pfQuest_Loc["Required"] .. ": " .. pfMap:HexDifficultyColor(meta["qmin"], true) .. meta["qmin"] .. "|r"  or ""
                tooltip:AddLine("|cffaaaaaa- |r" .. qlvlstr .. qminstr , .8,.8,.8)

                -- Add quest experience information
                if meta["questid"] then
                    local questData = pfDB["quests"] and pfDB["quests"]["data"] and pfDB["quests"]["data"][meta["questid"]]
                    if questData then
                        local questXP = pfMap:GetQuestXP(questData)
                        if questXP and questXP > 0 then
                            local xpText = pfQuest_Loc["Experience"] and pfQuest_Loc["Experience"] or "Experience"
                            xpText = xpText .. ": " .. pfMap:HexDifficultyColor(meta["qlvl"]) .. questXP .. "|r"

                            -- Show server rate if detected and not 1x
                            if pfMap.xpRateDetector then
                                local serverRate = pfMap.xpRateDetector:GetCurrentRate()
                                if serverRate and serverRate ~= 1 then
                                    local rateColor = "|cff00ff00"  -- Green for rate indicator
                                    xpText = xpText .. " " .. rateColor .. "(" .. serverRate .. "x)|r"
                                end
                            end

                            tooltip:AddLine("|cffaaaaaa- |r" .. xpText, .8,.8,.8)
                        end
                    end
                end

                -- Add quest chain information
                if meta["questid"] then
                    local chainCount = pfMap:CountQuestsInChain(meta["questid"])
                    local chainTotalXP = pfMap:GetChainTotalXP(meta["questid"])

                    if chainCount > 0 then
                        local chainText
                        if UnitXPMax("player") == 0 then
                            -- Max level player - hide XP info
                            chainText = "Chain: " .. chainCount .. " quests"
                        else
                            chainText = "Chain: " .. chainCount .. " quests (" .. chainTotalXP .. " XP total)"
                        end
                        tooltip:AddLine(chainText, .6, .8, 1)

                        -- Alt expand
                        if IsAltKeyDown() then
                            local chainSummary = pfMap:GetChainSummary(meta["questid"])
                            if table.getn(chainSummary) > 0 then
                                tooltip:AddLine("", .5, .5, .5)  -- Empty line for separator spacing
                                for _, summaryLine in ipairs(chainSummary) do
                                    tooltip:AddLine("|cffaaaaaa" .. summaryLine .. "|r", .7, .7, .7)
                                end
                            end
                        else
                            tooltip:AddLine("|cff00ff00[Alt]|r for details", .5, .5, .5)
                        end
                    end
                end

                -- Add unlock information
                if meta["questid"] then
                    local unlockCount = pfMap:CountUnlockedQuests(meta["questid"])
                    if unlockCount > 0 then
                        local unlockText = "Unlocks: " .. unlockCount .. " quests"
                        tooltip:AddLine(unlockText, .6, .8, 1)

                        if IsAltKeyDown() then
                            local unlockSummary = pfMap:GetUnlockSummary(meta["questid"])
                            if table.getn(unlockSummary) > 0 then
                                tooltip:AddLine("", .5, .5, .5)  -- Empty line for separator spacing
                                for _, uline in ipairs(unlockSummary) do
                                    tooltip:AddLine("|cffaaaaaa" .. uline .. "|r", .7, .7, .7)
                                end
                            end
                        else
                            tooltip:AddLine("|cff00ff00[Alt]|r for unlocks", .5, .5, .5)
                        end
                    end
                end
            end
        end
    else
        -- handle non-quest objects
        if meta["item"] and meta["item"][1] and meta["itemid"] and not meta["itemlink"] then
            local _, _, itemQuality = GetItemInfo(meta["itemid"])
            if itemQuality then
                local itemColor = "|c" .. string.format("%02x%02x%02x%02x", 255,
                    ITEM_QUALITY_COLORS[itemQuality].r * 255,
                    ITEM_QUALITY_COLORS[itemQuality].g * 255,
                    ITEM_QUALITY_COLORS[itemQuality].b * 255)

                meta["itemlink"] = itemColor .."|Hitem:".. meta["itemid"] ..":0:0:0|h[".. meta["item"][1] .."]|h|r"
            end
        end

        if meta["sellcount"] then
            local item = meta["itemlink"] or (meta["item"] and meta["item"][1] and "[" .. meta["item"][1] .. "]") or "[Unknown Item]"
            local sellcount = tonumber(meta["sellcount"]) > 0 and " |cff555555[|cffcccccc" .. meta["sellcount"] .. "x" .. "|cff555555]" or ""
            tooltip:AddLine(pfQuest_Loc["Vendor"] .. ": " .. item .. sellcount, 1,1,1)
        elseif meta["item"] and meta["item"][1] then
            local item = meta["itemlink"] or "[" .. meta["item"][1] .. "]"
            local r,g,b = pfMap.tooltip:GetColor(tonumber(meta["droprate"]), 100)
            tooltip:AddLine("|cffffffff" .. pfQuest_Loc["Loot"] .. ": " .. item ..  " |cff555555[|r" .. meta["droprate"] .. "%|cff555555]", r,g,b)
        end
    end

    tooltip:Show()
end

function pfMap:GetMapNameByID(id)
    id = tonumber(id)
    return pfDB["zones"]["loc"][id] or nil
end

function pfMap:GetMapIDByName(search)
    for id, name in pairs(pfDB["zones"]["loc"]) do
        if name == search then
            return id
        end
    end
end

function pfMap:ShowMapID(map)
    if map then
        if ToggleWorldMap then
            -- vanilla & tbc
            if not WorldMapFrame:IsShown() then
                ToggleWorldMap()
            end
        else
            -- wotlk
            ShowUIPanel(WorldMapFrame)
        end

        pfMap:SetMapByID(map)
        pfMap:UpdateNodes()
        return true
    end

    return nil
end

function pfMap:SetMapByID(id)
    local search = pfDB["zones"]["loc"][id]

    for cid, cname in pairs({GetMapContinents()}) do
        for mid, mname in pairs({GetMapZones(cid)}) do
            if mname == search then
                SetMapZoom(cid, mid)
                return
            end
        end
    end
end

local customids = {
    ["AlteracValley"] = 2597,
    ["Acherus: The Ebon Hold"] = 4298,
    ["Plaguelands: The Scarlet Enclave"] = 4298,
    ["The Scarlet Enclave"] = 4298,
    ["ScarletEnclave"] = 4298,
    ["UtgardeKeep"] = 206,

    -- 5-ппл
    ["UtgardePinnacle"] = 1196,
    ["TheNexus"] = 4265,
    ["Nexus80"] = 4228,  -- The Oculus
    ["HallsofStone"] = 4264,
    ["HallsofLightning"] = 4272,
    ["AzjolNerub"] = 4277,
    ["Ahnkahet"] = 4494,
    ["DrakTharonKeep"] = 4196,
    ["Gundrak"] = 4416,
    ["VioletHold"] = 4415,
    ["CoTStratholme"] = 4100,

    -- рейды
    ["Naxxramas"] = 3456,
    ["TheObsidianSanctum"] = 4493,
    ["Ulduar"] = 4273,
    ["TheEyeofEternity"] = 4500,
    ["VaultofArchavon"] = 4603,
    ["IcecrownCitadel"] = 4812,
    ["TrialoftheChampion"] = 4723,
    ["TrialoftheCrusader"] = 4722,
}

local map_zone_cache = { }
function pfMap:GetMapID(cid, mid)
    cid = cid or GetCurrentMapContinent()
    mid = mid or GetCurrentMapZone()

    -- Debug для всех инстансов и особых случаев
    local mapInfo = GetMapInfo()
    local realZone = GetRealZoneText()
    local subZone = GetSubZoneText()

    --[[
    if cid == 0 or mid == 0 or cid == -1 or
       (mapInfo and (string.find(mapInfo, "Utgarde") or string.find(mapInfo, "Acherus") or string.find(mapInfo, "Ebon"))) then
      print(string.format("🗺️ [MAP DEBUG] cid=%s, mid=%s, mapInfo='%s', realZone='%s', subZone='%s'",
        tostring(cid), tostring(mid), tostring(mapInfo), tostring(realZone), tostring(subZone)))
    end
    --]]

    -- GetMapZones() should always return the same amount
    -- of zones for each continent, so we can cache it to
    -- avoid further creations of the same table.
    -- For special maps (cid=0 or cid=-1), don't try to cache zones
    if cid ~= 0 and cid ~= -1 and not map_zone_cache[cid] then
        map_zone_cache[cid] = { GetMapZones(cid) }
    end

    local list = map_zone_cache[cid]
    local name = list and list[mid]
    local id = pfMap:GetMapIDByName(name)

    -- For special maps (continent=0/-1 or zone=0), always try customids first
    if cid == 0 or mid == 0 or cid == -1 then
        id = customids[GetMapInfo()]

        --[[
        if cid == 0 or mid == 0 or cid == -1 then
          print(string.format("🗺️ [MAP DEBUG] Special map logic - id from customids: %s", tostring(id)))
        end
        --]]

        -- For Acherus specifically (continent=-1, zone=0)
        -- We know from .gps that it's Map 609 which should map to zone 4298
        -- Use mapInfo ID which should be language-independent
        if not id and cid == -1 and mid == 0 and mapInfo == "ScarletEnclave" then
            id = 4298  -- Hardcoded for Acherus/Ebon Hold
            -- print(string.format("🗺️ [MAP DEBUG] Applied Acherus hardcode: id=%s", tostring(id)))
        end
    else
        id = id or customids[GetMapInfo()]
    end

    --[[
    if cid == 0 or mid == 0 or cid == -1 or
       (mapInfo and (string.find(mapInfo, "Utgarde") or string.find(mapInfo, "Acherus") or string.find(mapInfo, "Ebon"))) then
      print(string.format("🗺️ [MAP DEBUG] Final result: id=%s", tostring(id)))
    end
    --]]

    return id
end

function pfMap:AddNode(meta)
    if not meta then return end
    if not meta["zone"] then return end
    if not meta["title"] then return end

    meta["description"] = pfDatabase:BuildQuestDescription(meta)

    local addon = meta["addon"] or "PFDB"
    local map = meta["zone"]
    local coords = meta["x"] .. "|" .. meta["y"]
    local title = meta["title"]
    local layer = GetLayerByTexture(meta["texture"])
    local spawn = meta["spawn"]
    local item = meta["item"]

    local sindex = string.format("%s:%s:%s:%s:%s:%s",
        (addon or ""), (map or ""), (coords or ""), (title or ""), (layer or ""), (spawn or ""), (item or ""))

    -- use prioritized clusters
    if layer >= 9 and meta["priority"] then
        layer = layer + (10 - min(meta["priority"], 10))
    end

    if not pfMap.nodes[addon] then pfMap.nodes[addon] = {} end
    if not pfMap.nodes[addon][map] then pfMap.nodes[addon][map] = {} end
    if not pfMap.nodes[addon][map][coords] then pfMap.nodes[addon][map][coords] = {} end

    -- skip early on existing nodes
    if pfMap.nodes[addon][map][coords][title] then
        if item and table.getn(pfMap.nodes[addon][map][coords][title].item) > 0 then
            -- check if item already exists
            for id, name in pairs(pfMap.nodes[addon][map][coords][title].item) do
                if name == item then return end
            end

            -- add new item and exit
            table.insert(pfMap.nodes[addon][map][coords][title].item, item)
            return
        end

        if pfMap.nodes[addon][map][coords][title] and pfMap.nodes[addon][map][coords][title].layer and layer and
            pfMap.nodes[addon][map][coords][title].layer >= layer then
            -- identical node already exists, exit here
            return
        end
    end

    -- create new combined data node from given meta data
    if not similar_nodes[sindex] then
        similar_nodes[sindex] = {}
        for key, val in pairs(meta) do similar_nodes[sindex][key] = val end
        similar_nodes[sindex].item = { [1] = item }
    end

    -- set current node to combined node
    pfMap.nodes[addon][map][coords][title] = similar_nodes[sindex]

    -- add node to unified cluster cache
    if not meta["cluster"] and not meta["texture"] then
        local node_index = meta.item or meta.spawn or UNKNOWN
        local x, y = tonumber(meta.x), tonumber(meta.y)

        -- create prerequisite table structure
        unifiedcache[title] = unifiedcache[title] or {}
        unifiedcache[title][map] = unifiedcache[title][map] or {}

        if not unifiedcache[title][map][node_index] then
            -- create new unified node from given meta data
            local unified_meta = {}
            for key, val in pairs(meta) do unified_meta[key] = val end

            -- save node to unified cache
            unifiedcache[title][map][node_index] = { meta = unified_meta, coords = {} }
        end

        -- append new coords to unified cache unified cache
        table.insert(unifiedcache[title][map][node_index].coords, { x, y })
    end

    -- add to gametooltips
    if spawn and title then
        pfMap.tooltips[spawn] = pfMap.tooltips[spawn] or {}
        pfMap.tooltips[spawn][title] = pfMap.tooltips[spawn][title] or {}
        pfMap.tooltips[spawn][title][map] = pfMap.tooltips[spawn][title][map] or similar_nodes[sindex]
    end

    pfMap.queue_update = GetTime()
end

function pfMap:GetNodes(addon, title)
    local nodes = {}

    if title and pfMap.nodes[addon] then
        for map, foo in pairs(pfMap.nodes[addon]) do
            for coords, node in pairs(pfMap.nodes[addon][map]) do
                if pfMap.nodes[addon][map][coords][title] then
                    table.insert(nodes, pfMap.nodes[addon][map][coords][title])
                end
            end
        end
    end

    return nodes
end

function pfMap:DeleteNode(addon, title)
    -- remove tooltips
    if not addon then
        pfMap.tooltips = {}
    else
        for mk, mv in pairs(pfMap.tooltips) do
            for tk, tv in pairs(mv) do
                if ( title and tk == title ) or ( not title and tv.addon == addon ) then
                    pfMap.tooltips[mk][tk] = nil
                end
            end
        end
    end

    -- remove nodes
    if not addon then
        pfMap.nodes = {}
    elseif not title then
        pfMap.nodes[addon] = {}
    elseif pfMap.nodes[addon] then
        for map, foo in pairs(pfMap.nodes[addon]) do
            for coords, node in pairs(pfMap.nodes[addon][map]) do
                if pfMap.nodes[addon][map][coords][title] then
                    pfMap.nodes[addon][map][coords][title] = nil
                    if IsEmpty(pfMap.nodes[addon][map][coords]) then
                        pfMap.nodes[addon][map][coords] = nil
                    end
                end
            end
        end
    end

    pfMap.queue_update = GetTime()
end

function pfMap:NodeClick()
    if IsShiftKeyDown() then
        local questidToMark = nil

        -- DETAILED DEBUG: Check cycling state at click time
        --print("=== MARK AS DONE DEBUG ===")
        --print("Clicked frame questid:", this.questid)
        --print("Clicked frame spawn:", this.spawn)
        --print("pfMap.activeQuestId:", pfMap.activeQuestId)
        --print("pfMap.activeSpawnName:", pfMap.activeSpawnName)
        --print("pfMap.cycleData exists:", pfMap.cycleData ~= nil)

        -- PRIORITY 1: For clusters, use cycling system's activeQuestId
        if pfMap.cycleData and pfMap.activeQuestId and not pfQuest_history[pfMap.activeQuestId] then
            questidToMark = pfMap.activeQuestId
            --print("Mark as Done: Using cycling activeQuestId", questidToMark, "from", pfMap.activeSpawnName, "(cluster)")
        -- PRIORITY 2: For single NPCs, use clicked frame's questid
        elseif this.questid and this.texture and this.layer < 5 and not pfQuest_history[this.questid] then
            questidToMark = this.questid
            --print("Mark as Done: Using clicked frame questid", questidToMark, "from", this.spawn, "(single NPC)")
        -- PRIORITY 3: Fallback to activeQuestId for edge cases
        elseif pfMap.activeQuestId and not pfQuest_history[pfMap.activeQuestId] then
            questidToMark = pfMap.activeQuestId
            --print("Mark as Done: Using fallback activeQuestId", questidToMark, "from", pfMap.activeSpawnName, "(fallback)")
        end

        if not questidToMark then
            --print("ERROR: No questid found to mark as done!")
            -- Если не можем найти квест для пометки, всё равно удаляем узел
            -- чтобы не зависать визуально на уже выполненных квестах
            if this.node and this.title and this.node[this.title] then
                --print("Force removing visual node since all quests appear completed")
            end
        end

        -- Mark questnode as done if we have a questid
        local shouldDeleteNode = false
        if questidToMark then
            if pfQuest_history[questidToMark] then
                --print("Quest", questidToMark, "is already marked as done - but will still remove node")
                shouldDeleteNode = true
            else
                -- Get full chain and mark all quests
                local fullChain = pfMap:GetFullChainQuestIds(questidToMark)
                local markedNames = {}
                local markedIds = {}

                for chainQuestId, _ in pairs(fullChain) do
                    if not pfQuest_history[chainQuestId] then
                        pfQuest_history[chainQuestId] = { time(), UnitLevel("player") }
                        pfMap:ClearQuestFromCaches(chainQuestId)
                        table.insert(markedIds, chainQuestId)

                        local qLoc = pfDB["quests"]["loc"] and pfDB["quests"]["loc"][chainQuestId]
                        local name = qLoc and qLoc["T"] or ("#" .. chainQuestId)
                        table.insert(markedNames, name)
                    end
                end

                -- Store for undo
                pfMap.lastChainMark = {}
                for _, id in ipairs(markedIds) do
                    pfMap.lastChainMark[id] = true
                end

                -- Print results with clickable quest links
                if table.getn(markedNames) > 1 then
                    local links = {}
                    for _, id in ipairs(markedIds) do
                        local qLoc = pfDB["quests"]["loc"] and pfDB["quests"]["loc"][id]
                        local qData = pfDB["quests"]["data"] and pfDB["quests"]["data"][id]
                        local name = qLoc and qLoc["T"] or ("#" .. id)
                        local lvl = qData and qData["lvl"] or 0
                        local color = pfQuestCompat.GetDifficultyColor(lvl)
                        local hex = pfUI and pfUI.api and pfUI.api.rgbhex(color) or "|cffffffff"
                        table.insert(links, hex .. "|Hquest:" .. id .. ":" .. lvl .. "|h[" .. name .. "]|h|r")
                    end
                    local list = table.concat(links, " ")
                    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpf|cffffffffQuest: |cffffff00Chain marked: " .. list .. " |Hpfquestundo|h|cff33ffcc[Undo]|h|r")
                else
                    local id = markedIds[1]
                    local qLoc = pfDB["quests"]["loc"] and pfDB["quests"]["loc"][id]
                    local qData = pfDB["quests"]["data"] and pfDB["quests"]["data"][id]
                    local name = qLoc and qLoc["T"] or ("#" .. id)
                    local lvl = qData and qData["lvl"] or 0
                    local color = pfQuestCompat.GetDifficultyColor(lvl)
                    local hex = pfUI and pfUI.api and pfUI.api.rgbhex(color) or "|cffffffff"
                    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpf|cffffffffQuest: |cffffff00Marked: " .. hex .. "|Hquest:" .. id .. ":" .. lvl .. "|h[" .. name .. "]|h|r |Hpfquestundo|h|cff33ffcc[Undo]|h|r")
                end

                shouldDeleteNode = true
            end
        else
            -- Force remove node if no valid questid found but node exists
            if this.node and this.title and this.node[this.title] then
                shouldDeleteNode = true
            end
        end
        --print("===========================")

        if shouldDeleteNode and this.node and this.title and this.node[this.title] then
            -- delete node from map
            pfMap:DeleteNode(this.node[this.title].addon, this.title)

            -- Force clear the current node to prevent it from reappearing
            this.node[this.title] = nil
            if IsEmpty(this.node) then
                this.node = nil
            end

            -- clear cached cluster so that tooltip refresh reflects removal
            pfMap.clusterCache = nil

            -- Remove all chain quest nodes from map
            if questidToMark then
                local fullChain = pfMap:GetFullChainQuestIds(questidToMark)
                for addon, addonData in pairs(pfMap.nodes) do
                    for mapId, mapData in pairs(addonData) do
                        for coord, coordNodes in pairs(mapData) do
                            for t, meta in pairs(coordNodes) do
                                if meta.questid == questidToMark or fullChain[meta.questid] then
                                    pfMap.nodes[addon][mapId][coord][t] = nil
                                    if IsEmpty(pfMap.nodes[addon][mapId][coord]) then
                                        pfMap.nodes[addon][mapId][coord] = nil
                                    end
                                end
                            end
                        end
                    end
                end
            end

            -- force immediate map refresh so current frame data updates
            pfMap.queue_update = GetTime()

            -- Сбросить все данные циклинга и скрыть текущий tooltip,
            -- чтобы при следующем OnEnter построилось заново уже без удалённого квеста
            pfMap.cycleData      = nil
            pfMap.cycleIndex     = 1
            pfMap.activeQuestId  = nil
            pfMap.activeSpawnName= nil

            local tt = (this:GetParent() == WorldMapButton) and WorldMapTooltip or GameTooltip
            if tt and tt:IsShown() then tt:Hide() end
        end

        pfQuest.updateQuestGivers = true
        pfQuest.updateQuestLog = true   -- Форс-обновление журналa, чтобы подхватить новые квесты
    elseif this.texture and pfQuest.route and
        (( pfQuest_config["routecluster"] == "1" and this.layer >= 9 ) or
            ( pfQuest_config["routeender"] == "1" and this.layer == 4) or
            ( pfQuest_config["routestarter"] == "1" and this.layer == 1) or
            ( pfQuest_config["routestarter"] == "1" and this.layer == 2))
    then
        -- set as arrow target priority
        pfQuest.route.SetTarget((not pfQuest.route.IsTarget(this) and this))
        pfMap.queue_update = GetTime()
    else
        -- switch color
        pfQuest_colors[this.color] = { str2rgb(this.color .. GetTime()) }
        pfMap.queue_update = GetTime()
    end
end

function pfMap:NodeEnter()
    -- wotlk: need to disable blop tooltips first
    if compat.client >= 30300 then
        WorldMapPOIFrame.allowBlobTooltip = false
    end

    local tooltip = this:GetParent() == WorldMapButton and WorldMapTooltip or GameTooltip

    -- Use ANCHOR_CURSOR_LEFT with node - cursor anchors only work with actual frames
    if this ~= tooltip then
        tooltip:SetOwner(this, "ANCHOR_CURSOR_RIGHT", 10, 5)
    else
        tooltip:SetOwner(UIParent, "ANCHOR_CURSOR_RIGHT", 10, 5)
    end

    -- Remember the node that is currently showing a tooltip
    -- CRITICAL FIX: Don't let GameTooltip set itself as current node
    if this ~= GameTooltip and this ~= WorldMapTooltip then
        pfMap.tooltipCurrentNode = this
    end

    -- Only proceed with tooltip if this is a valid node (not GameTooltip itself)
    if this ~= GameTooltip and this ~= WorldMapTooltip then
        local spawnName = this.spawn or UNKNOWN
        local originalSpawn = this.spawn

        -- Temporarily set spawn for tooltip (restore after)
        this.spawn = spawnName
        pfMap:ShowClusterTooltip(this, tooltip)
        this.spawn = originalSpawn
    end

    -- Save tooltip context for cycling
    if pfMap.cycleData then
        pfMap.cycleData.currentNode = this
        pfMap.cycleData.currentTooltip = tooltip
    end

    pfMap.highlight = pfQuest_config["mouseover"] == "1" and this.title

    -- Always reset cycle index when starting a fresh hover
end

-- Helper function to get quest symbol and status
function pfMap:GetQuestSymbol(questTitle)
    local questInLog = false
    local questComplete = false

    for qid=1, GetNumQuestLogEntries() do
        local qtitle, _, _, _, _, complete = compat.GetQuestLogTitle(qid)

        if questTitle == qtitle or (questTitle and qtitle and string.lower(questTitle) == string.lower(qtitle)) then
            questInLog = true
            questComplete = complete
            break
        end
    end

    local symbol
    if questInLog then
        if questComplete then
            symbol = "|cff555555[|cffffcc00?|cff555555]|r "  -- Yellow ? for ready to turn in
        else
            symbol = "|cff555555[|cff888888?|cff555555]|r "  -- Gray ? for in progress
        end
    else
        symbol = "|cff555555[|cffffcc00!|cff555555]|r "  -- Yellow ! for available
    end


    return symbol, questInLog, questComplete
end

-- Helper function to truncate text after $b$b or $B$B
function pfMap:truncateAtDoubleB(text)
    if not text then return "" end
    local cutPos = string.find(text, "$b$b") or string.find(text, "$B$B")
    return cutPos and string.sub(text, 1, cutPos - 1) or text
end

-- Helper function to count characters in truncated text
function pfMap:countTruncatedChars(text)
    return string.len(self:truncateAtDoubleB(text))
end

-- Helper function to count visible characters (without color codes)
function pfMap:countVisibleChars(text)
    if not text then return 0 end
    -- Remove all WoW color/formatting codes
    local visibleText = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "") -- |cffcccccc
    visibleText = string.gsub(visibleText, "|r", "") -- |r
    visibleText = string.gsub(visibleText, "|H.-|h", "") -- |Hlinks|h
    visibleText = string.gsub(visibleText, "|h", "") -- |h
    visibleText = string.gsub(visibleText, "|T.-|t", "") -- |Ttextures|t
    visibleText = string.gsub(visibleText, "|K.-|k", "") -- |Kkeys|k
    return string.len(visibleText)
end

-- Helper function to add quest objective characters to estimation
function pfMap:addObjectiveChars(questid, estimatedChars)
    if questid and pfDB and pfDB["quests"] and pfDB["quests"]["loc"] and pfDB["quests"]["loc"][questid] then
        local questData = pfDB["quests"]["loc"][questid]
        if questData["O"] then
            return estimatedChars + self:countTruncatedChars(questData["O"])
        end
    end
    return estimatedChars
end

-- Global variables for simple cycling
pfMap.cycleData = nil
pfMap.cycleIndex = 1
pfMap.rightPressed = false

-- Store active spawn's questid for Mark as Done
pfMap.activeQuestId = nil
pfMap.activeSpawnName = nil

-- Cluster cache to prevent tooltip flickering
pfMap.clusterCache = nil

-- Track current cluster coordinates to preserve cycle data within same cluster
pfMap.currentClusterHash = nil

-- Helper function to count quests in chain after given quest
function pfMap:CountQuestsInChain(questid)
    if not questid or not pfDB or not pfDB["quests"] or not pfDB["quests"]["data"] then
        return 0
    end

    local questData = pfDB["quests"]["data"][questid]
    if not questData then
        return 0
    end

    local count = 0
    local visited = {}

    -- Count follow-up quests recursively
    local function countFollowUps(qid)
        if visited[qid] or count > 20 then return end -- Prevent infinite loops, max 20 quests
        visited[qid] = true

        local qData = pfDB["quests"]["data"][qid]
        if qData and qData["chain"] then
            for _, nextQuestId in ipairs(qData["chain"]) do
                count = count + 1
                countFollowUps(nextQuestId)
            end
        end
    end

    countFollowUps(questid)
    return count
end

-- Helper function to calculate total XP for entire quest chain
function pfMap:GetChainTotalXP(questid)
    if not questid or not pfDB or not pfDB["quests"] or not pfDB["quests"]["data"] then
        return 0
    end

    local totalXP = 0
    local visited = {}

    local function addChainXP(qid)
        if visited[qid] or totalXP > 100000 then return end -- Prevent infinite loops, max reasonable XP
        visited[qid] = true

        local qData = pfDB["quests"]["data"][qid]
        if qData then
            -- Add XP for current quest
            local questXP = self:GetQuestXP(qData)
            if questXP and questXP > 0 then
                totalXP = totalXP + questXP
            end

            -- Process chain quests
            if qData["chain"] then
                for _, nextQuestId in ipairs(qData["chain"]) do
                    addChainXP(nextQuestId)
                end
            end
        end
    end

    addChainXP(questid)
    return totalXP
end

-- Helper function to get quest chain summary
function pfMap:GetChainSummary(questid)
    if not questid or not pfDB or not pfDB["quests"] or not pfDB["quests"]["data"] then
        return {}
    end

    local chainSummary = {}
    local visited = {}
    local questCounter = 1
    local isFirstQuest = true

    local function addChainInfo(qid)
        if visited[qid] or questCounter > 10 then return end -- Prevent infinite loops, max 10 quests in summary
        visited[qid] = true

        local qData = pfDB["quests"]["data"][qid]
        local qLoc = pfDB["quests"]["loc"] and pfDB["quests"]["loc"][qid]

        if qData and qLoc then
            local questName = qLoc["T"] or "Unknown Quest"
            local objectiveZones = {}
            local endNPCZone = "Unknown"

            -- Get end NPC/Object zone - try different structures
            local endNPCId = nil
            if qData["end"] then
                -- Try different possible structures
                if qData["end"]["U"] and type(qData["end"]["U"]) == "table" and qData["end"]["U"][1] then
                    endNPCId = qData["end"]["U"][1]
                elseif qData["end"]["O"] and type(qData["end"]["O"]) == "table" and qData["end"]["O"][1] then
                    endNPCId = qData["end"]["O"][1]
                elseif qData["end"][1] then
                    endNPCId = qData["end"][1]
                end

                if endNPCId then
                    local mapId = nil
                    local endType = "unknown"

                    -- Check what type of end this should be based on quest data
                    local isObjectEnd = qData["end"]["O"] ~= nil

                    if isObjectEnd then
                        -- For Object ends, try Object first
                        if pfDB["objects"] and pfDB["objects"]["data"] and pfDB["objects"]["data"][endNPCId] then
                            local objectData = pfDB["objects"]["data"][endNPCId]
                            endType = "Object"
                            if objectData and objectData["coords"] and objectData["coords"][1] and objectData["coords"][1][3] then
                                mapId = objectData["coords"][1][3]
                            end
                        end

                        -- Fallback to NPC if Object not found
                        if not mapId and pfDB["units"] and pfDB["units"]["data"] and pfDB["units"]["data"][endNPCId] then
                            local npcData = pfDB["units"]["data"][endNPCId]
                            endType = "NPC (fallback)"
                            if npcData then
                                if npcData[1] and npcData[1][1] then
                                    mapId = npcData[1][1]
                                elseif npcData["coords"] and npcData["coords"][1] and npcData["coords"][1][3] then
                                    mapId = npcData["coords"][1][3]
                                end
                            end
                        end
                    else
                        -- For NPC ends, try NPC first
                        if pfDB["units"] and pfDB["units"]["data"] and pfDB["units"]["data"][endNPCId] then
                            local npcData = pfDB["units"]["data"][endNPCId]
                            endType = "NPC"
                            if npcData then
                                if npcData[1] and npcData[1][1] then
                                    mapId = npcData[1][1]
                                elseif npcData["coords"] and npcData["coords"][1] and npcData["coords"][1][3] then
                                    mapId = npcData["coords"][1][3]
                                end
                            end
                        end

                        -- Fallback to Object if NPC not found
                        if not mapId and pfDB["objects"] and pfDB["objects"]["data"] and pfDB["objects"]["data"][endNPCId] then
                            local objectData = pfDB["objects"]["data"][endNPCId]
                            endType = "Object (fallback)"
                            if objectData and objectData["coords"] and objectData["coords"][1] and objectData["coords"][1][3] then
                                mapId = objectData["coords"][1][3]
                            end
                        end
                    end

                    if mapId then
                        local zoneName = pfMap:GetZoneName(mapId)
                        if zoneName and zoneName ~= "Unknown Zone" then
                            endNPCZone = zoneName
                        end
                    end
                end
            end

            -- Note: Start NPC zone is not added to objectives - only actual objective locations matter

            -- Get objective zones from quest objectives
            if qData["obj"] then
                for objKey, obj in pairs(qData["obj"]) do
                    if type(obj) == "table" then
                        -- Try to find Item/NPC/Object IDs in objectives
                        for i = 1, 5 do
                            local objId = obj[i]
                            if objId and type(objId) == "number" then
                                local mapId = nil

                                -- Try to find mapId through different paths:
                                local objType = "unknown"

                                -- 1. Direct NPC lookup (for "U" objectives)
                                if objKey == "U" and pfDB["units"] and pfDB["units"]["data"] and pfDB["units"]["data"][objId] then
                                    local npcData = pfDB["units"]["data"][objId]
                                    objType = "NPC"
                                    if npcData then
                                        if npcData[1] and npcData[1][1] then
                                            mapId = npcData[1][1]
                                        elseif npcData["coords"] and npcData["coords"][1] and npcData["coords"][1][3] then
                                            mapId = npcData["coords"][1][3]
                                        end
                                    end
                                end

                                -- 2. Direct Object lookup (for "O" objectives)
                                if not mapId and objKey == "O" and pfDB["objects"] and pfDB["objects"]["data"] and pfDB["objects"]["data"][objId] then
                                    local objectData = pfDB["objects"]["data"][objId]
                                    objType = "Object"
                                    if objectData and objectData["coords"] and objectData["coords"][1] and objectData["coords"][1][3] then
                                        mapId = objectData["coords"][1][3]
                                    end
                                end

                                -- 3. Item lookup (for "I" objectives) → Object lookup (like 4918 → 3290)
                                if not mapId and objKey == "I" and pfDB["items"] and pfDB["items"]["data"] and pfDB["items"]["data"][objId] then
                                    local itemData = pfDB["items"]["data"][objId]
                                    objType = "Item"
                                    if itemData and itemData["O"] then
                                        -- Find first object that drops this item
                                        for objectId, _ in pairs(itemData["O"]) do
                                            if pfDB["objects"] and pfDB["objects"]["data"] and pfDB["objects"]["data"][objectId] then
                                                local objectData = pfDB["objects"]["data"][objectId]
                                                if objectData and objectData["coords"] and objectData["coords"][1] and objectData["coords"][1][3] then
                                                    mapId = objectData["coords"][1][3]
                                                    objType = "Item→Object(" .. objectId .. ")"
                                                    break
                                                end
                                            end
                                        end
                                    end
                                end

                                -- 4. Item Required lookup (for "IR" objectives)
                                if not mapId and objKey == "IR" then
                                    objType = "ItemReq"
                                    -- Find targets where this item should be used (following database.lua logic)
                                    if pfDB["quests-itemreq"] and pfDB["quests-itemreq"]["data"] and pfDB["quests-itemreq"]["data"][objId] then
                                        local itemreqData = pfDB["quests-itemreq"]["data"][objId]
                                        -- Find coordinates of TARGET entities, not the item itself
                                        for targetId, spellId in pairs(itemreqData) do
                                            local realId = tonumber(targetId) or 0
                                            if realId > 0 then
                                                -- Positive ID = NPC target
                                                if pfDB["units"] and pfDB["units"]["data"] and pfDB["units"]["data"][realId] then
                                                    local npcData = pfDB["units"]["data"][realId]
                                                    if npcData and npcData["coords"] and npcData["coords"][1] and npcData["coords"][1][3] then
                                                        mapId = npcData["coords"][1][3]
                                                        objType = "ItemReq→UseOnNPC(" .. realId .. ")"
                                                        break
                                                    end
                                                end
                                            elseif realId < 0 then
                                                -- Negative ID = GameObject target
                                                local goId = math.abs(realId)
                                                if pfDB["objects"] and pfDB["objects"]["data"] and pfDB["objects"]["data"][goId] then
                                                    local objectData = pfDB["objects"]["data"][goId]
                                                    if objectData and objectData["coords"] and objectData["coords"][1] and objectData["coords"][1][3] then
                                                        mapId = objectData["coords"][1][3]
                                                        objType = "ItemReq→UseOnObject(" .. goId .. ")"
                                                        break
                                                    end
                                                end
                                            end
                                        end
                                    end
                                    -- Note: No fallback to item drop locations for ItemReq - they need specific targets
                                end

                                -- Add zone if found
                                if mapId then
                                    local zoneName = pfMap:GetZoneName(mapId)
                                    if zoneName and zoneName ~= "Unknown Zone" and not objectiveZones[zoneName] then
                                        objectiveZones[zoneName] = true
                                    end
                                end
                            end
                        end
                    end
                end
            end

            -- Convert objective zones table to comma-separated string with icons
            local objZonesList = {}
            local hasKillObjectives = false
            local hasItemObjectives = false
            local hasObjectObjectives = false

            -- Analyze quest objectives to determine icons needed
            local hasAreaObjectives = false
            if qData["obj"] then
                for objKey, obj in pairs(qData["obj"]) do
                    if objKey == "U" then hasKillObjectives = true end
                    if objKey == "I" or objKey == "IR" then hasItemObjectives = true end
                    if objKey == "O" then hasObjectObjectives = true end
                    if objKey == "A" then hasAreaObjectives = true end
                end
            end

            -- Collect clean zone names for comparison
            local cleanZonesList = {}
            for zone, _ in pairs(objectiveZones) do
                table.insert(cleanZonesList, zone)
            end
            local cleanObjZonesStr = table.getn(cleanZonesList) > 0 and table.concat(cleanZonesList, ", ") or endNPCZone

            -- Create zones with icons for display
            for zone, _ in pairs(objectiveZones) do
                local zoneWithIcon = zone
                -- Add appropriate icon based on objective types
                local icons = ""
                if hasKillObjectives then icons = icons .. "|T"..pfQuestConfig.path.."\\img\\cluster_mob:12:12:0:0|t" end
                if hasItemObjectives then icons = icons .. "|T"..pfQuestConfig.path.."\\img\\cluster_item:12:12:0:0|t" end
                if hasObjectObjectives then icons = icons .. "|T"..pfQuestConfig.path.."\\img\\icon_object:12:12:0:0|t" end
                if hasAreaObjectives then icons = icons .. "|T"..pfQuestConfig.path.."\\img\\cluster_misc:12:12:0:0|t" end

                if icons ~= "" then
                    zoneWithIcon = icons .. " " .. zone
                end
                table.insert(objZonesList, zoneWithIcon)
            end
            local objZonesStr = table.getn(objZonesList) > 0 and table.concat(objZonesList, ", ") or endNPCZone

            -- Create summary without zone duplication
            local summary
            if cleanObjZonesStr == endNPCZone then
                -- Same zone for objectives and turn-in, show only once with icons
                local zoneWithIcons = endNPCZone
                local icons = ""
                if hasKillObjectives then icons = icons .. "|T"..pfQuestConfig.path.."\\img\\cluster_mob:12:12:0:0|t" end
                if hasItemObjectives then icons = icons .. "|T"..pfQuestConfig.path.."\\img\\cluster_item:12:12:0:0|t" end
                if hasObjectObjectives then icons = icons .. "|T"..pfQuestConfig.path.."\\img\\icon_object:12:12:0:0|t" end
                if hasAreaObjectives then icons = icons .. "|T"..pfQuestConfig.path.."\\img\\cluster_misc:12:12:0:0|t" end

                -- If no objectives, this is a turn-in only quest
                if icons == "" then
                    zoneWithIcons = "|cff555555[|cffffcc00?|cff555555]|r " .. endNPCZone
                else
                    zoneWithIcons = icons .. " " .. endNPCZone
                end
                if isFirstQuest then
                    summary = "|cffffffff>|r " .. questName .. " - " .. zoneWithIcons
                else
                    summary = (questCounter - 1) .. ". " .. questName .. " - " .. zoneWithIcons
                end
            else
                -- Different zones, show both with turn-in icon
                local turnInZone = "|cff555555[|cffffcc00?|cff555555]|r " .. endNPCZone
                if isFirstQuest then
                    summary = "|cffffffff>|r " .. questName .. " - " .. objZonesStr .. " - " .. turnInZone
                else
                    summary = (questCounter - 1) .. ". " .. questName .. " - " .. objZonesStr .. " - " .. turnInZone
                end
            end

            -- Debug: Show what objectives were found and where
            --[[ COMMENTED OUT FOR LESS SPAM
            print("QUEST DEBUG " .. qid .. " (" .. questName .. "):")
            if qData["obj"] then
                for objKey, obj in pairs(qData["obj"]) do
                    if type(obj) == "table" then
                        local objIds = {}
                        for i = 1, 5 do
                            if obj[i] and type(obj[i]) == "number" then
                                table.insert(objIds, tostring(obj[i]))
                            end
                        end
                        print("  Objective " .. objKey .. ": [" .. table.concat(objIds, ", ") .. "]")
                    end
                end
            end
            print("  Start NPC: " .. (startNPCId or "none"))
            print("  End NPC: " .. (endNPCId or "none"))
            print("  Found zones: " .. (table.getn(objZonesList) > 0 and table.concat(objZonesList, ", ") or "none"))
            print("  End zone: " .. endNPCZone)
            print("  Summary: " .. summary)
            print("")
            --]]

            table.insert(chainSummary, summary)
            questCounter = questCounter + 1
            isFirstQuest = false

            -- Process chain quests
            if qData["chain"] then
                for _, nextQuestId in ipairs(qData["chain"]) do
                    addChainInfo(nextQuestId)
                end
            end
        end
    end

    addChainInfo(questid)
    return chainSummary
end

-- Helper function to get zone name from map ID
function pfMap:GetZoneName(mapId)
    if not pfDB or not pfDB["zones"] then
        return "Unknown Zone"
    end

    -- Try to get zone name from localized data first
    local locale = GetLocale() or "enUS"

    if pfDB["zones"][locale] and pfDB["zones"][locale][mapId] then
        return pfDB["zones"][locale][mapId]
    end

    -- Fallback to enUS if current locale not found
    if locale ~= "enUS" and pfDB["zones"]["enUS"] and pfDB["zones"]["enUS"][mapId] then
        return pfDB["zones"]["enUS"][mapId]
    end

    -- Last fallback: look for any available locale
    for localeKey, localeData in pairs(pfDB["zones"]) do
        if localeKey ~= "data" and type(localeData) == "table" and localeData[mapId] then
            return localeData[mapId]
        end
    end

    return "Unknown Zone"
end

function pfMap:ShowClusterTooltip(currentNode, tooltip)
    -- Ensure we start with a clean tooltip to avoid duplicated lines
    tooltip = tooltip or GameTooltip
    if tooltip.ClearLines then
        tooltip:ClearLines()
    end

    -- Early estimation of tooltip size for compact decisions
    local estimatedChars = 0
    estimatedChars = estimatedChars + string.len(currentNode.spawn or "")
    for title, meta in pairs(currentNode.node or {}) do
        if meta.quest then
            estimatedChars = estimatedChars + string.len(meta.quest or "")
        end
        if meta.spawn then
            estimatedChars = estimatedChars + string.len(meta.spawn or "")
        end
        estimatedChars = self:addObjectiveChars(meta.questid, estimatedChars)
    end

    -- Use cluster cache or perform fresh connected-component scan
    local nearbyNodes, questTitles
    local map = pfMap:GetMapID(GetCurrentMapContinent(), GetCurrentMapZone())

    local clusterRadius = currentNode:GetParent() ~= WorldMapButton and 0.3 or 1.3

    -- Helper to check if a meta represents a quest-giver (start or end, NPC or object)
    local function IsQuestGiver(meta)
        return meta and meta.QTYPE and (meta.QTYPE == "NPC_START" or meta.QTYPE == "NPC_END" or meta.QTYPE == "OBJECT_START" or meta.QTYPE == "OBJECT_END")
    end

    local isCurrentNodeQuestGiver = false
    for __t, __m in pairs(currentNode.node or {}) do
        if IsQuestGiver(__m) then
            isCurrentNodeQuestGiver = true
            break
        end
    end

    -- Function that performs BFS connected search and returns results plus hash
    local function buildCluster()
        -- print("Cluster: Fresh scan for", currentNode.spawn)
        local results = {}
        local qTitles = {}
        local visitedSpawn = {}

        local function addNode(meta, title, dist)
            local spawnName = meta.spawn or title
            results[#results+1] = {
                spawn    = spawnName,
                level    = meta.level,
                spawntype= meta.spawntype,
                respawn  = meta.respawn,
                spawnid  = meta.spawnid,
                distance = dist or 0,
                title    = title,
                node     = {[title]=meta}
            }
            if meta.quest then qTitles[meta.quest] = true end
        end

        -- seed queue with current node coords
        local seedX, seedY
        for t,m in pairs(currentNode.node or {}) do if m.x and m.y then seedX,seedY=tonumber(m.x),tonumber(m.y); break end end
        if not seedX then return results,qTitles,"" end

        local queue={{x=seedX,y=seedY,node=currentNode}}
        while #queue>0 do
            local cur=table.remove(queue,1)
            local bx,by=cur.x,cur.y

            for addonName,addonData in pairs(pfMap.nodes) do
                if addonData[map] then
                    for coords,coordNodes in pairs(addonData[map]) do
                        for title,meta in pairs(coordNodes) do
                            if meta.x and meta.y then
                                local sx,sy=tonumber(meta.x),tonumber(meta.y)
                                local dist=math.sqrt((sx-bx)^2+(sy-by)^2)
                                if dist<=clusterRadius then
                                    local spawnName=meta.spawn or title
                                    local isQuestGiver = meta.QTYPE and (meta.QTYPE == "NPC_START" or meta.QTYPE == "NPC_END" or meta.QTYPE == "OBJECT_START" or meta.QTYPE == "OBJECT_END")
                                    if isQuestGiver and not visitedSpawn[spawnName] then
                                        visitedSpawn[spawnName]=true
                                        addNode(meta,title,dist)
                                        queue[#queue+1] = {x = sx, y = sy, node = coordNodes}
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        local names={}
        for n,_ in pairs(visitedSpawn) do names[#names+1]=n end
        table.sort(names)
        local hash=table.concat(names,"|")
        return results,qTitles,hash
    end

    -- decide cache reuse
    if pfMap.clusterCache and pfMap.clusterCache.key and pfMap.tooltipCurrentNode and pfMap.clusterCache.nodeRef==pfMap.tooltipCurrentNode then
        nearbyNodes = pfMap.clusterCache.nearbyNodes
        questTitles = pfMap.clusterCache.questTitles
    else
        local clusterHash
        nearbyNodes, questTitles, clusterHash = buildCluster()
        pfMap.clusterCache = {
            key=clusterHash,
            nearbyNodes=nearbyNodes,
            questTitles=questTitles,
            nodeRef=currentNode
        }
    end

    -- Sort by distance (closest first)
    table.sort(nearbyNodes, function(a, b) return a.distance < b.distance end)

    local nodeCount = table.getn(nearbyNodes)
    if nodeCount == 0 then
        -- Fallback to current node if no nearby nodes found
        nearbyNodes = {{
                           spawn = currentNode.spawn,
                           level = currentNode.level,
                           spawntype = currentNode.spawntype,
                           respawn = currentNode.respawn,
                           spawnid = currentNode.spawnid,
                           distance = 0,
                           title = currentNode.title,
                           node = currentNode.node
                       }}
        nodeCount = 1

        -- Add current node's quests to highlight
        for title, meta in pairs(currentNode.node or {}) do
            if meta.quest then
                questTitles[meta.quest] = true
            end
        end

        -- If this is not a quest giver, use simple tooltip
        if not isCurrentNodeQuestGiver then
            tooltip:SetText(currentNode.spawn..(pfQuest_config.showids == "1" and " |cffcccccc("..currentNode.spawnid..")|r" or ""), .3, 1, .8)
            tooltip:AddDoubleLine(pfQuest_Loc["Level"] .. ":", (currentNode.level or UNKNOWN), .8,.8,.8, 1,1,1)
            tooltip:AddDoubleLine(pfQuest_Loc["Type"] .. ":", (currentNode.spawntype or UNKNOWN), .8,.8,.8, 1,1,1)
            tooltip:AddDoubleLine(pfQuest_Loc["Respawn"] .. ":", (currentNode.respawn or UNKNOWN), .8,.8,.8, 1,1,1)

            for title, meta in pairs(currentNode.node or {}) do
                pfMap:ShowTooltip(meta, tooltip)
            end

            -- add tooltip help if setting is enabled
            if pfQuest_config["tooltiphelp"] == "1" then
                local text = pfQuest_Loc["Use <Shift>-Click To Remove Nodes"]

                if currentNode.cluster then
                    text = pfQuest_Loc["Hold <Ctrl> To Hide Cluster"]
                elseif tooltip == GameTooltip then
                    text = pfQuest_Loc["Hold <Ctrl> To Hide Minimap Nodes"]
                elseif not currentNode.texture then
                    text = pfQuest_Loc["Click Node To Change Color"]
                elseif currentNode.questid and currentNode.texture and currentNode.layer < 5 then
                    text = pfQuest_Loc["Use <Shift>-Click To Mark Quest As Done"]
                end

                tooltip:AddLine(text, .6, .6, .6)
            end

            tooltip:Show()
            return  -- Exit early for non-quest NPCs
        end
    end

    -- Count unique spawns for header
    local uniqueSpawns = {}
    for i, nodeData in ipairs(nearbyNodes) do
        if nodeData.distance > 0 then -- Skip current node
            uniqueSpawns[nodeData.spawn] = true
        end
    end
    local uniqueSpawnCount = 0
    for _ in pairs(uniqueSpawns) do uniqueSpawnCount = uniqueSpawnCount + 1 end

    -- Initialize mainSpawnData with current node (will be updated after altCycleData setup)
    local mainSpawnData
    local otherSpawns

    -- Show information for each nearby node but avoid duplicate spawn headers
    local currentSpawn = currentNode.spawn
    local shownSpawns = {[currentSpawn] = true}

    -- Group nearby nodes by spawn for better organization
    local spawnGroups = {}

    for i, nodeData in ipairs(nearbyNodes) do
        if nodeData.distance > 0 then -- Skip current node
            local spawnName = nodeData.spawn
            if not spawnGroups[spawnName] then
                spawnGroups[spawnName] = {
                    spawn = spawnName,
                    distance = nodeData.distance,
                    nodes = {},
                    hasStarter = false,
                    hasEnder = false,
                    isVendor = false
                }
            end

            -- Add node and categorize
            for title, meta in pairs(nodeData.node) do
                table.insert(spawnGroups[spawnName].nodes, {title = title, meta = meta})

                -- Categorize spawn type for priority
                if meta.QTYPE == "NPC_START" or meta.QTYPE == "OBJECT_START" then
                    spawnGroups[spawnName].hasStarter = true
                elseif meta.QTYPE == "NPC_END" or meta.QTYPE == "OBJECT_END" then
                    spawnGroups[spawnName].hasEnder = true
                end

                if meta.spawntype and (meta.spawntype == "Vendor" or meta.sellcount) then
                    spawnGroups[spawnName].isVendor = true
                end
            end
        end
    end

    -- Sort spawns by priority: starters > enders > vendors > others
    local sortedSpawns = {}
    for spawnName, data in pairs(spawnGroups) do
        table.insert(sortedSpawns, data)
    end

    table.sort(sortedSpawns, function(a, b)
        -- Priority: quest starters first, then enders, then vendors, then by distance
        if a.hasStarter and not b.hasStarter then return true end
        if b.hasStarter and not a.hasStarter then return false end
        if a.hasEnder and not b.hasEnder then return true end
        if b.hasEnder and not a.hasEnder then return false end
        if a.isVendor and not b.isVendor then return false end
        if b.isVendor and not a.isVendor then return true end
        return a.distance < b.distance
    end)

    -- Add characters from nearby spawns to early estimation
    for i, spawnData in ipairs(sortedSpawns) do
        estimatedChars = estimatedChars + string.len(spawnData.spawn or "")
        for _, nodeInfo in ipairs(spawnData.nodes) do
            if nodeInfo.meta.quest then
                estimatedChars = estimatedChars + string.len(nodeInfo.meta.quest or "")
            end
            if nodeInfo.meta.spawn then
                estimatedChars = estimatedChars + string.len(nodeInfo.meta.spawn or "")
            end
            estimatedChars = self:addObjectiveChars(nodeInfo.meta.questid, estimatedChars)
        end
    end
    local maxTooltipChars = 400 -- Max comfortable tooltip character count
    local useCompactFormat = (estimatedChars > maxTooltipChars)

    -- Setup Alt-cycling for tooltips with multiple spawns
    if table.getn(sortedSpawns) > 0 then
        -- Create all spawns list including current node
        local allSpawns = {}
        -- Get questid from currentNode for consistency
        local currentQuestId = nil
        local currentTitle = nil
        if currentNode.node then
            for title, meta in pairs(currentNode.node or {}) do
                if meta.questid then
                    currentQuestId = meta.questid
                    currentTitle = title
                    break
                end
            end
        end

        table.insert(allSpawns, {
            spawn = currentNode.spawn,
            node = currentNode.node,
            isCurrent = true,
            level = currentNode.level,
            spawntype = currentNode.spawntype,
            respawn = currentNode.respawn,
            spawnid = currentNode.spawnid,
            questid = currentQuestId,  -- Store questid directly
            title = currentTitle  -- Store title for highlight
        })
        for _, spawnData in ipairs(sortedSpawns) do
            -- Get metadata from first node in the group
            local firstNode = spawnData.nodes and spawnData.nodes[1]
            local meta = firstNode and firstNode.meta

            -- Create proper node structure for cycling
            local nodeStructure = nil
            if firstNode and firstNode.title and meta then
                nodeStructure = {[firstNode.title] = meta}
            end

            table.insert(allSpawns, {
                spawn = spawnData.spawn,
                nodes = spawnData.nodes,
                node = nodeStructure,  -- Add proper node structure
                isCurrent = false,
                level = meta and meta.level,
                spawntype = meta and meta.spawntype,
                respawn = meta and meta.respawn,
                spawnid = meta and meta.spawnid,
                questid = meta and meta.questid,  -- Store questid directly
                title = firstNode and firstNode.title  -- Store title for highlight
            })
        end

        -- Create cluster hash based on all spawns in cluster (not just current node)
        local clusterSpawns = {}
        table.insert(clusterSpawns, currentNode.spawn)
        for _, spawnData in ipairs(sortedSpawns) do
            table.insert(clusterSpawns, spawnData.spawn)
        end
        table.sort(clusterSpawns) -- Sort to ensure consistent hash
        local clusterHash = table.concat(clusterSpawns, "|")

        -- Initialize simple cycling data ONLY if this is a different cluster
        local isSameCluster = pfMap.currentClusterHash == clusterHash

        -- Check if the current spawn already exists in the previously built cycle
        local spawnInCurrentCycle = false
        if pfMap.cycleData and pfMap.cycleData.allSpawns then
            for _, s in ipairs(pfMap.cycleData.allSpawns) do
                if s.spawn == currentNode.spawn then
                    spawnInCurrentCycle = true
                    break
                end
            end
        end

        -- Decide whether to create a new cycle (default) or reuse the existing one
        -- If the cluster hash changed, we ALWAYS create a new cycle – even if the
        -- current spawn already exists in the previous cycle. This prevents
        -- accidentally merging two nearby but distinct clusters that just happen
        -- to share an NPC name (e.g. multiple "Candy Bucket" gameobjects).
        local shouldCreateNewCycle = (not pfMap.cycleData) or (not isSameCluster)

        if shouldCreateNewCycle then
            -- print("Cycling: Creating NEW cycle data for cluster:", clusterHash)
            pfMap.cycleData = {allSpawns = allSpawns, nodeHash = currentNode.spawn}
            pfMap.cycleIndex = 1
            pfMap.expandedSpawnIndex = 1
            pfMap.currentClusterHash = clusterHash

            -- Initialize activeQuestId for the first spawn
            pfMap.activeQuestId = nil
            pfMap.activeSpawnName = nil
            if allSpawns[1] then
                pfMap.activeSpawnName = allSpawns[1].spawn
                -- Try direct questid field first (new improved structure)
                if allSpawns[1].questid then
                    pfMap.activeQuestId = allSpawns[1].questid
                    -- print("Cycling: Initial questid", pfMap.activeQuestId, "for", allSpawns[1].spawn)
                elseif allSpawns[1].node then
                    for title, meta in pairs(allSpawns[1].node) do
                        if meta.questid then
                            pfMap.activeQuestId = meta.questid
                            -- print("Cycling: Initial questid", pfMap.activeQuestId, "for", allSpawns[1].spawn)
                            break
                        end
                    end
                end
            end

            -- print("Cycling: Initialized with", table.getn(allSpawns), "spawns")
        else
            -- Re-use current cycle data but add any NEW spawns that were discovered
            -- print("Cycling: REUSING cycle data for same cluster")

            if pfMap.cycleData and pfMap.cycleData.allSpawns then
                local existing = {}
                for _, s in ipairs(pfMap.cycleData.allSpawns) do existing[s.spawn] = true end
                for _, s in ipairs(allSpawns) do
                    if not existing[s.spawn] then
                        table.insert(pfMap.cycleData.allSpawns, s)
                    end
                end
            end
        end
    else
        -- Clear cycling data when no nearby spawns
        pfMap.cycleData = nil
    end

    -- For in-place expansion, all spawns are treated equally
    local allSpawnsToShow = {}
    if pfMap.cycleData then
        -- Copy all spawns in original order
        for i, spawnData in ipairs(pfMap.cycleData.allSpawns) do
            table.insert(allSpawnsToShow, {
                spawn = spawnData.spawn,
                node = spawnData.node,
                nodes = spawnData.nodes,
                level = spawnData.level,
                spawntype = spawnData.spawntype,
                respawn = spawnData.respawn,
                spawnid = spawnData.spawnid,
                isCurrent = spawnData.isCurrent,
                isExpanded = (i == pfMap.expandedSpawnIndex)
            })
        end
        -- Use first spawn for header info
        mainSpawnData = pfMap.cycleData.allSpawns[pfMap.expandedSpawnIndex]
        otherSpawns = {} -- Not used in new logic
    else
        -- No cycling, single spawn
        table.insert(allSpawnsToShow, {
            spawn = currentNode.spawn,
            node = currentNode.node,
            level = currentNode.level,
            spawntype = currentNode.spawntype,
            respawn = currentNode.respawn,
            spawnid = currentNode.spawnid,
            isExpanded = true
        })
        mainSpawnData = {
            spawn = currentNode.spawn, node = currentNode.node, isCurrent = true,
            level = currentNode.level, spawntype = currentNode.spawntype,
            respawn = currentNode.respawn, spawnid = currentNode.spawnid
        }
        otherSpawns = sortedSpawns
    end

    -- Get current displayed spawn info from mainSpawnData
    local displaySpawn = mainSpawnData.spawn
    local displayLevel = mainSpawnData.level or (mainSpawnData.isCurrent and currentNode.level) or UNKNOWN
    local displayType = mainSpawnData.spawntype or (mainSpawnData.isCurrent and currentNode.spawntype) or UNKNOWN
    local displayRespawn = mainSpawnData.respawn or (mainSpawnData.isCurrent and currentNode.respawn) or UNKNOWN
    local displaySpawnId = mainSpawnData.spawnid or (mainSpawnData.isCurrent and currentNode.spawnid) or ""

    -- Set minimal tooltip header (cycling info only)
    local cycleIndicator = ""
    if pfMap.cycleData and table.getn(pfMap.cycleData.allSpawns) > 1 then
        cycleIndicator = " |cffcccccc(" .. pfMap.expandedSpawnIndex .. "/" .. table.getn(pfMap.cycleData.allSpawns) .. ")|r"
        tooltip:SetText("NPCs" .. cycleIndicator, .6, .6, .6)
        tooltip:AddLine(" ") -- Spacer after header
    else
        -- For single NPC, show traditional header
        tooltip:SetText(displaySpawn .. (pfQuest_config.showids == "1" and " |cffcccccc("..displaySpawnId..")|r" or ""), .3, 1, .8)
        tooltip:AddDoubleLine(pfQuest_Loc["Level"] .. ":", displayLevel, .8,.8,.8, 1,1,1)
        tooltip:AddDoubleLine(pfQuest_Loc["Type"] .. ":", displayType, .8,.8,.8, 1,1,1)
        tooltip:AddDoubleLine(pfQuest_Loc["Respawn"] .. ":", displayRespawn, .8,.8,.8, 1,1,1)
    end

    -- Show all spawns in order with in-place expansion
    local shouldCompact = (estimatedChars > 200) -- Trigger compacting when tooltip exceeds 200 chars
    local maxSpawns = 15 -- Show max 15 different spawns
    local spawnCount = 0
    local remainingCounts = {starters = 0, enders = 0, vendors = 0, others = 0}

    -- Show all spawns in place
    for i, spawnData in ipairs(allSpawnsToShow) do
        if spawnCount < maxSpawns then
            -- Build node list first and deduplicate
            local nodes = {}

            if spawnData.nodes and type(spawnData.nodes) == "table" then
                for _, nodeInfo in ipairs(spawnData.nodes) do
                    table.insert(nodes, nodeInfo)
                end
            end

            if spawnData.node and type(spawnData.node) == "table" then
                for _title, meta in pairs(spawnData.node) do
                    local dup = false
                    for _, nodeInfo in ipairs(nodes) do
                        if nodeInfo.meta == meta then dup = true break end
                    end
                    if not dup then
                        table.insert(nodes, { meta = meta })
                    end
                end
            end

            -- Determine if there is anything meaningful to display
            local hasDisplay = false
            for _, nodeInfo in ipairs(nodes) do
                local m = nodeInfo.meta or nodeInfo
                if m.quest or m.item or m.sellcount or m.droprate then
                    hasDisplay = true
                    break
                end
            end

            if hasDisplay then
                -- Add spacer before each spawn
                if i > 1 then
                    tooltip:AddLine(" ") -- spacer
                end

                -- Show spawn header info (only for cycling mode)
                if pfMap.cycleData and table.getn(pfMap.cycleData.allSpawns) > 1 then
                    if spawnData.isExpanded then
                        -- Show header for expanded NPC
                        local spawnName = "|cffFFFFFF>|r " .. spawnData.spawn .. (pfQuest_config.showids == "1" and " |cffcccccc("..(spawnData.spawnid or "")..")|r" or "")
                        tooltip:AddLine(spawnName, 0.3, 1, 0.8) -- Teal name with white arrow

                        -- Add metadata lines
                        tooltip:AddDoubleLine(pfQuest_Loc["Level"] .. ":", (spawnData.level or UNKNOWN), .8,.8,.8, 1,1,1)
                        tooltip:AddDoubleLine(pfQuest_Loc["Type"] .. ":", (spawnData.spawntype or UNKNOWN), .8,.8,.8, 1,1,1)
                        tooltip:AddDoubleLine(pfQuest_Loc["Respawn"] .. ":", (spawnData.respawn or UNKNOWN), .8,.8,.8, 1,1,1)
                    else
                        -- Show compact header for non-expanded NPC with bullet and muted color
                        tooltip:AddLine("• " .. spawnData.spawn, .4, .8, .4) -- Muted green for compact
                    end
                end

                for _, nodeInfo in ipairs(nodes) do
                    local meta = nodeInfo.meta or nodeInfo
                    if meta.quest then
                        -- Show expanded details for expanded spawn, compact for others
                        if spawnData.isExpanded then
                            pfMap:ShowTooltip(meta, tooltip, shouldCompact)
                        else
                            local symbol = pfMap:GetQuestSymbol(meta.quest)
                            -- Dim non-active quests by 30%
                            local r, g, b = 1, 1, 0
                            if pfMap.activeQuestId and meta.questid and meta.questid ~= pfMap.activeQuestId then
                                r, g, b = r * 0.7, g * 0.7, b * 0.7
                            end
                            tooltip:AddLine(symbol .. meta.quest, r, g, b)
                        end
                    else
                        -- Always show full details for non-quest items
                        pfMap:ShowTooltip(meta, tooltip, shouldCompact)
                    end
                end

                spawnCount = spawnCount + 1
            end
        else
            -- Count remaining spawns by category
            if spawnData.hasStarter then
                remainingCounts.starters = remainingCounts.starters + 1
            elseif spawnData.hasEnder then
                remainingCounts.enders = remainingCounts.enders + 1
            elseif spawnData.isVendor then
                remainingCounts.vendors = remainingCounts.vendors + 1
            else
                remainingCounts.others = remainingCounts.others + 1
            end
        end
    end

    -- Show summary of remaining spawns with cycling prompt
    local totalHidden = remainingCounts.starters + remainingCounts.enders + remainingCounts.vendors + remainingCounts.others
    if spawnCount >= maxSpawns and totalHidden > 0 then
        tooltip:AddLine(" ") -- spacer
        tooltip:AddLine("|cffaaaaaa... +" .. totalHidden .. " more NPCs hidden|r")
    end

    -- Fallback: Show otherSpawns if cycling is not active and we have sorted spawns
    if not pfMap.cycleData and otherSpawns and table.getn(otherSpawns) > 0 then
        for i, spawnData in ipairs(otherSpawns) do
            if spawnCount < maxSpawns then
                -- Build node list first and deduplicate
                local nodes = {}

                if spawnData.nodes and type(spawnData.nodes) == "table" then
                    for _, nodeInfo in ipairs(spawnData.nodes) do
                        table.insert(nodes, nodeInfo)
                    end
                end

                -- Determine if there is anything meaningful to display
                local hasDisplay = false
                for _, nodeInfo in ipairs(nodes) do
                    local m = nodeInfo.meta or nodeInfo
                    if m.quest or m.item or m.sellcount or m.droprate then
                        hasDisplay = true
                        break
                    end
                end

                if hasDisplay then
                    tooltip:AddLine(" ") -- spacer
                    tooltip:AddLine("|cff00ff00" .. spawnData.spawn .. "|r", .8, 1, .8)

                    for _, nodeInfo in ipairs(nodes) do
                        local meta = nodeInfo.meta or nodeInfo
                        if meta.quest then
                            if useCompactFormat then
                                local symbol = pfMap:GetQuestSymbol(meta.quest)
                                -- Dim non-active quests by 30%
                                local r, g, b = 1, 1, 0
                                if pfMap.activeQuestId and meta.questid and meta.questid ~= pfMap.activeQuestId then
                                    r, g, b = r * 0.7, g * 0.7, b * 0.7
                                end
                                tooltip:AddLine(symbol .. meta.quest, r, g, b)
                            else
                                pfMap:ShowTooltip(meta, tooltip, shouldCompact)
                            end
                        else
                            pfMap:ShowTooltip(meta, tooltip, shouldCompact)
                        end
                    end

                    spawnCount = spawnCount + 1
                end
            end
        end
    end

    -- Set up highlighting for all related quests (only on initial hover, not during cycling)
    if pfQuest_config["mouseover"] == "1" and not pfMap.cycleData then
        pfMap.clusterHighlights = questTitles
    end

    -- add tooltip help if setting is enabled
    if pfQuest_config["tooltiphelp"] == "1" then
        local text = pfQuest_Loc["Use <Shift>-Click To Remove Nodes"]

        if currentNode.cluster then
            text = pfQuest_Loc["Hold <Ctrl> To Hide Cluster"]
        elseif tooltip == GameTooltip then
            text = pfQuest_Loc["Hold <Ctrl> To Hide Minimap Nodes"]
        elseif not currentNode.texture then
            text = pfQuest_Loc["Click Node To Change Color"]
        elseif currentNode.questid and currentNode.texture and currentNode.layer < 5 then
            text = pfQuest_Loc["Use <Shift>-Click To Mark Quest As Done"]
        end

        -- update tooltip and sizes with separator
        tooltip:AddLine(" ") -- Spacer before help text
        tooltip:AddLine("• " .. text, .5, .5, .8) -- Light blue with bullet

        -- Add right-click cycling help for tooltips with multiple spawns
        if pfMap.cycleData and table.getn(pfMap.cycleData.allSpawns) > 1 then
            tooltip:AddLine("• Use <Right>-Click To Cycle Through All " .. table.getn(pfMap.cycleData.allSpawns) .. " NPCs", .5, .5, .8)
        end


        tooltip:Show()
    end

    -- Scale tooltip down for more compact view
    tooltip:SetScale(0.9)

    -- Store tooltip position during cycling to prevent jumping
    if pfMap.cycleData and table.getn(pfMap.cycleData.allSpawns) > 1 then
        if not pfMap.tooltipAnchor then
            pfMap.tooltipAnchor = {tooltip:GetPoint()}
        end
        if pfMap.tooltipAnchor[1] then
            tooltip:ClearAllPoints()
            tooltip:SetPoint(pfMap.tooltipAnchor[1], pfMap.tooltipAnchor[2], pfMap.tooltipAnchor[3], pfMap.tooltipAnchor[4] or 0, pfMap.tooltipAnchor[5] or 0)
        end
    end

    tooltip:Show()
end

function pfMap:NodeLeave()
    -- wotlk: re-enable blop tooltips
    if compat.client >= 30300 then
        WorldMapPOIFrame.allowBlobTooltip = true
    end

    local tooltip = this:GetParent() == WorldMapButton and WorldMapTooltip or GameTooltip
    tooltip:Hide()
    pfMap.highlight = nil
    pfMap.clusterHighlights = nil -- Clear cluster highlights
    pfMap.tooltipAnchor = nil -- Clear tooltip anchor
    pfMap.tooltipMeta = nil -- Clear tooltip meta for Alt
    pfMap.tooltipCurrentNode = nil -- Clear stored node reference
    pfMap.tooltipMetaList = nil -- Clear any stored meta list
    -- Clear highlight flags

    -- Use a timer to delay clearing - gives time for mouse to move to nearby nodes
    if pfMap.clearTimer then
        pfMap.clearTimer = nil
    end

    pfMap.clearTimer = CreateFrame("Frame")
    pfMap.clearTimer:SetScript("OnUpdate", function()
        -- Check if mouse is still over any frame that could be part of the cluster
        local stillActive = false

        -- Check if any tooltip is still shown or mouse is over map areas
        if (GameTooltip:IsShown() and MouseIsOver(GameTooltip)) or
           (WorldMapTooltip:IsShown() and MouseIsOver(WorldMapTooltip)) or
           MouseIsOver(WorldMapButton) or MouseIsOver(pfMap.drawlayer) then
            stillActive = true
        end

        if not stillActive then
            --print("NodeLeave: Clearing cycle data after timeout")
            pfMap.cycleData = nil
            pfMap.cycleIndex = 1
            pfMap.rightPressed = false
            pfMap.activeQuestId = nil
            pfMap.activeSpawnName = nil
            pfMap.clusterCache = nil
            pfMap.currentClusterHash = nil

            -- Remove this timer
            if pfMap.clearTimer then
                pfMap.clearTimer:SetScript("OnUpdate", nil)
                pfMap.clearTimer = nil
            end
        end
    end)
end

function pfMap:BuildNode(name, parent)
    local f = CreateFrame("Button", name, parent)

    if parent == WorldMapButton then
        f.defalpha = tonumber(pfQuest_config["worldmaptransp"]) or 1
        f.defsize = 16
    else
        f.defalpha = tonumber(pfQuest_config["minimaptransp"]) or 1
        f.defsize = 16
        f.minimap = true
    end

    f:SetWidth(f.defsize)
    f:SetHeight(f.defsize)

    f.Animate = NodeAnimate
    f:SetScript("OnEnter", pfMap.NodeEnter)
    f:SetScript("OnLeave", pfMap.NodeLeave)

    f.tex = f:CreateTexture(nil, "BACKGROUND")
    f.tex:SetAllPoints(f)

    f.hl = f:CreateTexture(nil, "BORDER")
    f.hl:SetTexture(pfQuestConfig.path.."\\img\\track")
    f.hl:SetPoint("TOPLEFT", f, "TOPLEFT", -5, 5)
    f.hl:SetWidth(12)
    f.hl:SetHeight(12)
    return f
end

pfMap.highlightdb = {}
function pfMap:UpdateNode(frame, node, color, obj)
    -- clear node to title association table
    if pfMap.highlightdb[frame] then
        for k,v in pairs(pfMap.highlightdb[frame]) do
            pfMap.highlightdb[frame][k] = nil
        end
    else
        pfMap.highlightdb[frame] = {}
    end

    -- reset layer
    frame.layer = 0

    for title, tab in pairs(node) do
        pfMap.highlightdb[frame][title] = true

        tab.layer = GetLayerByTexture(tab.texture)

        -- use prioritized clusters
        if tab.cluster and tab.priority then
            tab.layer = tab.layer + (10 - min(tab.priority , 10))
        end

        if tab.spawn and ( tab.layer > frame.layer or not frame.spawn ) then
            frame.updateTexture = (frame.texture ~= tab.texture)
            frame.updateVertex = (frame.vertex ~= tab.vertex )
            frame.updateColor = (frame.color ~= tab.color)
            frame.updateLayer = (frame.layer ~= tab.layer)

            -- set title and texture to the entry with highest layer
            -- and add core information
            frame.layer       = tab.layer
            frame.spawn       = tab.spawn
            frame.spawnid     = tab.spawnid
            frame.spawntype   = tab.spawntype
            frame.respawn     = tab.respawn
            frame.level       = tab.level
            frame.questid     = tab.questid
            frame.texture     = tab.texture
            frame.vertex      = tab.vertex
            frame.title       = title
            frame.func        = tab.func
            frame.cluster     = tab.cluster
            frame.description = tab.description
            frame.priority    = tab.priority
            frame.quest       = tab.quest
            frame.qlvl        = tab.qlvl
            frame.itemreq     = tab.itemreq
            frame.arrow       = tab.arrow

            if pfQuest_config["spawncolors"] == "1" then
                frame.color = tab.spawn or tab.title
            else
                frame.color = tab.title
            end
        end
    end

    if ( frame.updateTexture or frame.updateVertex or not frame.tex:GetTexture() ) and frame.texture then
        frame.tex:SetTexture(frame.texture)
        frame.tex:SetVertexColor(1,1,1)

        if frame.updateVertex and frame.vertex then
            local r, g, b = unpack(frame.vertex)
            if r > 0 or g > 0 or b > 0 then
                frame.tex:SetVertexColor(r, g, b, 1)
            end
        end
    end

    if ( frame.updateColor or frame.updateTexture or not frame.tex:GetTexture() ) and not frame.texture then
        local r,g,b = str2rgb(frame.color)

        if obj == "minimap" and pfQuest_config["cutoutminimap"] == "1" then
            frame.tex:SetTexture(pfQuestConfig.path.."\\img\\nodecut")
            frame.tex:SetVertexColor(r,g,b,1)
        elseif obj ~= "minimap" and pfQuest_config["cutoutworldmap"] == "1" then
            frame.tex:SetTexture(pfQuestConfig.path.."\\img\\nodecut")
            frame.tex:SetVertexColor(r,g,b,1)
        elseif frame.title and pfQuest.icons[frame.title] then
            frame.tex:SetTexture(pfQuest.icons[frame.title])
            frame.tex:SetVertexColor(1,1,1,1)
        else
            frame.tex:SetTexture(pfQuestConfig.path.."\\img\\node")
            frame.tex:SetVertexColor(r,g,b,1)
        end
    end

    if frame.updateLayer then
        frame:SetFrameLevel((obj == "minimap" and 4 or 112) + frame.layer)
    end

    if frame.updateTexture or frame.updateVertex or frame.updateColor or frame.updateLayer then
        frame:SetScript("OnClick", (frame.func or pfMap.NodeClick))
    end

    local highlight = frame.texture and pfMap.highlightdb[frame][pfMap.highlight] and true or nil
    local target = frame.texture and pfQuest.route and pfQuest.route.IsTarget(frame) or nil

    -- set default sizes for different node types
    frame.defsize = (frame.cluster or frame.layer == 4) and 22 or 16

    -- make the current route target visible
    if target then frame.hl:Show() else frame.hl:Hide() end

    -- reset frame size except for highlights
    if not highlight then
        frame:SetWidth(frame.defsize)
        frame:SetHeight(frame.defsize)
    end

    frame.node = node
end

function pfMap:UpdateNodes()
    pfQuest:Debug("Update Nodes")

    local color = pfQuest_config["spawncolors"] == "1" and "spawn" or "title"
    local map = pfMap:GetMapID(GetCurrentMapContinent(), GetCurrentMapZone())
    local i = 1


    -- build zone index for tracker performance
    pfQuest.tracker:BuildZoneIndex()

    -- reset tracker
    pfQuest.tracker.Reset()

    -- reset route
    pfQuest.route:Reset()

    -- refresh all nodes
    for addon, _ in pairs(pfMap.nodes) do
        if pfMap.nodes[addon][map] then
            for coords, node in pairs(pfMap.nodes[addon][map]) do
                if not pfMap.pins[i] then
                    pfMap.pins[i] = pfMap:BuildNode("pfMapPin" .. i, WorldMapButton)
                end

                pfMap:UpdateNode(pfMap.pins[i], node, color)

                -- set position
                local _, _, x, y = strfind(coords, "(.*)|(.*)")

                -- write points to the route plan
                if ( pfQuest_config["routecluster"] == "1" and pfMap.pins[i].layer >= 9 ) or
                    ( pfQuest_config["routeender"] == "1" and pfMap.pins[i].layer == 4) or
                    ( pfQuest_config["routestarter"] == "1" and pfMap.pins[i].layer == 1 and pfMap.pins[i].texture) or
                    ( pfQuest_config["routestarter"] == "1" and pfMap.pins[i].layer == 2) or
                    pfMap.pins[i].arrow == true
                then
                    pfQuest.route:AddPoint({ x, y, pfMap.pins[i] })
                end

                -- hide cluster nodes if set
                if pfQuest_config["showcluster"] == "0" and pfMap.pins[i].cluster then
                    pfMap.pins[i]:Hide()
                    -- hide individual quest spawns
                elseif pfQuest_config["showspawn"] == "0" and addon == "PFQUEST" and not pfMap.pins[i].texture then
                    pfMap.pins[i]:Hide()
                else
                    -- populate quest list on map
                    for title, node in pairs(pfMap.pins[i].node) do
                        pfQuest.tracker.ButtonAdd(title, node)
                    end

                    -- Coordinate transformation for Utgarde Pinnacle (zone 1196)
                    if map == 1196 then
                        -- Convert from DungeonMap coordinates to WorldMap coordinates
                        x = ((x - 20) * 1.2) + 20  -- scale and center adjustment
                        y = ((y - 30) * 1.1) + 25  -- scale and center adjustment
                    end

                    x = x / 100 * WorldMapButton:GetWidth()
                    y = y / 100 * WorldMapButton:GetHeight()

                    pfMap.pins[i]:ClearAllPoints()
                    pfMap.pins[i]:SetPoint("CENTER", WorldMapButton, "TOPLEFT", x, -y)

                    pfMap.pins[i]:Show()
                end

                i = i + 1
            end
        end
    end

    -- hide remaining pins
    for j=i, table.getn(pfMap.pins) do
        if pfMap.pins[j] then pfMap.pins[j]:Hide() end
    end
end

local coord_cache = {}
function pfMap:UpdateMinimap()
    -- check for disabled minimap nodes
    if pfQuest_config["minimapnodes"] == "0" then
        return
    end

    -- check for Underbelly only when in Dalaran (lightweight)
    if pfMap.checkUnderbelly then
        if GetCurrentMapDungeonLevel() == 2 then
            -- Hide all minimap nodes when in Underbelly
            for id, pin in pairs(pfMap.mpins) do
                pin:Hide()
            end
            return
        end
    end

    -- hide all minimap nodes while shift is pressed
    if controlkey.pressed and MouseIsOver(pfMap.drawlayer) then
        this.xPlayer = nil

        for id, pin in pairs(pfMap.mpins) do
            pin:Hide()
        end

        return
    end

    -- hide nodes and skip further processing in dungeons
    local xPlayer, yPlayer = GetPlayerMapPosition("player")
    if xPlayer == 0 and yPlayer == 0 then
        for pins, pin in pairs(pfMap.mpins) do pin:Hide() end
        return
    end

    local mZoom = pfMap.drawlayer:GetZoom()
    xPlayer, yPlayer = xPlayer * 100, yPlayer * 100

    -- force refresh every second even without changed values, otherwise skip
    if this.xPlayer == xPlayer and this.yPlayer == yPlayer and this.mZoom == mZoom then
        if ( this.tick or 1) > GetTime() then return else this.tick = GetTime() + 1 end
    end

    this.xPlayer, this.yPlayer, this.mZoom = xPlayer, yPlayer, mZoom
    local color = pfQuest_config["spawncolors"] == "1" and "spawn" or "title"
    local mapID = pfMap:GetMapIDByName(GetRealZoneText())
    local indoor = minimap_indoor()
    local mapZoom = minimap_zoom[indoor] and minimap_zoom[indoor][mZoom] or Minimap:GetViewRadius() * 2
    local mapWidth = minimap_sizes[mapID] and minimap_sizes[mapID][1] or 0
    local mapHeight = minimap_sizes[mapID] and minimap_sizes[mapID][2] or 0

    local xScale = mapZoom / mapWidth
    local yScale = mapZoom / mapHeight

    local xDraw = pfMap.drawlayer:GetWidth() / xScale / 100
    local yDraw = pfMap.drawlayer:GetHeight() / yScale / 100

    local i = 1

    -- refresh all nodes
    for addon, data in pairs(pfMap.nodes) do
        -- hide minimap nodes in continent view
        if data[mapID] and minimap_sizes[mapID] and pfMap:HasMinimap(mapID) then
            for coords, node in pairs(data[mapID]) do
                local x, y
                if coord_cache[coords] then
                    x, y = coord_cache[coords][1], coord_cache[coords][2]
                else
                    local _, _, strx, stry = strfind(coords, "(.*)|(.*)")
                    x, y = strx + 0, stry + 0
                    coord_cache[coords] = { x, y }
                end

                -- Coordinate transformation for Utgarde Pinnacle (zone 1196)
                if mapID == 1196 then
                    -- Convert from DungeonMap coordinates to minimap coordinates
                    -- DungeonMap range: X(-748 to +9), Y(158 to 662)
                    -- Target range: 0-100 for minimap
                    x = ((x - 20) * 1.2) + 20  -- scale and center adjustment
                    y = ((y - 30) * 1.1) + 25  -- scale and center adjustment
                end

                local xPos = ( x - xPlayer) * xDraw
                local yPos = ( y - yPlayer) * yDraw

                if pfQuestCompat.rotateMinimap then
                    -- TODO: this part is broken and does not work yet.
                    local sinFacing = sin(pfQuestCompat.GetPlayerFacing())
                    local cosFacing = cos(pfQuestCompat.GetPlayerFacing())

                    local dx, dy = xPos, -yPos
                    xPos = (dx * cosFacing) + (dy * sinFacing)
                    yPos = -((-dx * sinFacing) + (dy * cosFacing))
                end

                local display = nil
                if pfUI.minimap then
                    display = ( abs(xPos) + 8 < pfMap.drawlayer:GetWidth() / 2 and abs(yPos) + 8 < pfMap.drawlayer:GetHeight()/2 ) and true or nil
                else
                    local distance = sqrt(xPos * xPos + yPos * yPos)
                    display = ( distance + 8 < pfMap.drawlayer:GetWidth() / 2 ) and true or nil
                end

                if display then
                    if not pfMap.mpins[i] then
                        pfMap.mpins[i] = pfMap:BuildNode(nodename .. i, pfMap.drawlayer)
                    end

                    pfMap:UpdateNode(pfMap.mpins[i], node, color, "minimap")

                    pfMap.mpins[i].hl:Hide()

                    if pfQuest_config["showclustermini"] == "0" and pfMap.mpins[i].cluster then
                        pfMap.mpins[i]:Hide()
                    elseif pfQuest_config["showspawnmini"] == "0" and addon == "PFQUEST" and not pfMap.mpins[i].texture then
                        pfMap.mpins[i]:Hide()
                    else
                        pfMap.mpins[i]:ClearAllPoints()
                        pfMap.mpins[i]:SetPoint("CENTER", pfMap.drawlayer, "CENTER", xPos, -yPos)
                        pfMap.mpins[i]:Show()
                    end

                    i = i + 1
                end
            end
        end
    end

    -- hide remaining pins
    for j=i, table.getn(pfMap.mpins) do
        if pfMap.mpins[j] then pfMap.mpins[j]:Hide() end
    end
end

local zone, last_zone
pfMap:RegisterEvent("ZONE_CHANGED")
pfMap:RegisterEvent("ZONE_CHANGED_NEW_AREA")
pfMap:RegisterEvent("MINIMAP_ZONE_CHANGED")
pfMap:RegisterEvent("WORLD_MAP_UPDATE")
pfMap:RegisterEvent("PLAYER_ENTERING_WORLD")
pfMap:RegisterEvent("QUEST_COMPLETE")
pfMap:SetScript("OnEvent", function()
    -- save current zone
    zone = GetCurrentMapZone()

    -- set map to current zone when possible
    if event == "ZONE_CHANGED" or event == "MINIMAP_ZONE_CHANGED" or event == "ZONE_CHANGED_NEW_AREA" then
        if not WorldMapFrame:IsShown() then
            SetMapToCurrentZone()
        end
    end

    -- Enable/disable floor checking based on current zone
    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        local mapAreaID = GetCurrentMapAreaID()
        if mapAreaID == 505 then
            pfMap.checkUnderbelly = true -- Keep legacy Dalaran logic
        else
            pfMap.checkUnderbelly = false
            pfMap.playerIsInUnderbelly = false
        end
    end

    -- update nodes on world map changes
    if event == "WORLD_MAP_UPDATE" and last_zone ~= zone then
        -- Clear cluster highlights when changing maps
        pfMap.clusterHighlights = nil
        pfMap.highlight = nil

        -- Clear cycling data and cache when changing maps
        pfMap.cycleData = nil
        pfMap.cycleIndex = 1
        pfMap.expandedSpawnIndex = 1
        pfMap.rightPressed = false
        pfMap.activeQuestId = nil
        pfMap.activeSpawnName = nil
        pfMap.clusterCache = nil
        pfMap.currentClusterHash = nil
        if pfMap.clearTimer then
            pfMap.clearTimer:SetScript("OnUpdate", nil)
            pfMap.clearTimer = nil
        end
        -- print("Map Change: Cleared all cycling data and cache")

        pfMap:UpdateNodes()
        last_zone = zone
    end

    -- XP Rate Detection Events
    if event == "QUEST_COMPLETE" then
        -- Quest completion dialog opened
        local questID = GetQuestLogSelection()
        if questID and questID > 0 then
            local questTitle = GetQuestLogTitle(questID)
            if questTitle then
                pfMap.xpRateDetector:StartTracking(questID)
            end
        end
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" and pfMap.xpRateDetector.waitingForQuestXP then
        -- Parse XP from combat message
        local receivedXP = pfMap.xpRateDetector:ParseXPMessage(arg1)
        if receivedXP and pfMap.xpRateDetector.currentQuestID then
            -- Add sample and stop tracking
            pfMap.xpRateDetector:AddSample(pfMap.xpRateDetector.currentQuestID, receivedXP)
            pfMap.xpRateDetector.waitingForQuestXP = false  -- Mark that we got quest XP
        end
    elseif event == "PLAYER_XP_UPDATE" and pfMap.xpRateDetector.currentQuestID then
        -- Only unregister if we already got quest XP (waitingForQuestXP = false)
        if not pfMap.xpRateDetector.waitingForQuestXP then
            pfMap.xpRateDetector:StopTracking()
        end
        -- Otherwise ignore (this was kill XP, keep waiting for quest XP)
    elseif event == "GOSSIP_CLOSED" and pfMap.xpRateDetector.waitingForQuestXP then
        -- Player closed dialog without completing quest
        pfMap.xpRateDetector:StopTracking()
    end

end)

local hlstate, shiftstate, transition, hidecluster, fps, resetmap

-- Functions for Ctrl+Map blob switching
function pfMap:ShowBlizzardBlobs()
    if compat.client >= 30300 and WorldMapPOIFrame then
        WorldMapPOIFrame.allowBlobTooltip = true
    end

    -- Store original questPOI setting and enable it
    if pfMap.originalQuestPOI == nil then
        pfMap.originalQuestPOI = GetCVar("questPOI")
        SetCVar("questPOI", "1")
    end

    -- Show blob frame
    if WorldMapBlobFrame then
        WorldMapBlobFrame:Show()
    end

    -- Force refresh quest display
    if WorldMapFrame_DisplayQuests then
        WorldMapFrame_DisplayQuests()
    end
end

function pfMap:HideBlizzardBlobs()
    if compat.client >= 30300 and WorldMapPOIFrame then
        WorldMapPOIFrame.allowBlobTooltip = false
    end

    -- Restore original questPOI setting
    if pfMap.originalQuestPOI ~= nil then
        SetCVar("questPOI", pfMap.originalQuestPOI)
        pfMap.originalQuestPOI = nil
    end

    if WorldMapBlobFrame and WorldMapBlobFrame.Hide then
        WorldMapBlobFrame:Hide()
    end
    if WorldMapFrame_ClearQuestPOIs then
        WorldMapFrame_ClearQuestPOIs()
    end

    -- Hide the swap button that Blizzard leaves visible after quest selection.
    -- WorldMapFrame_ClearQuestPOIs only hides numbered POI buttons but not the
    -- global swap button stored in QUEST_POI_SWAP_BUTTONS, causing it to persist
    -- across map close/reopen.
    if QUEST_POI_SWAP_BUTTONS and QUEST_POI_SWAP_BUTTONS["WorldMapPOIFrame"] then
        QUEST_POI_SWAP_BUTTONS["WorldMapPOIFrame"]:Hide()
    end
end

function pfMap:ShowPfQuestNodes()
    for i, pin in pairs(pfMap.pins) do
        if pin and pin.Show then
            pin:Show()
        end
    end
end

function pfMap:HidePfQuestNodes()
    for i, pin in pairs(pfMap.pins) do
        if pin and pin.Hide then
            pin:Hide()
        end
    end
end

pfMap:SetScript("OnUpdate", function()
    -- Ultra lightweight Alt check
    local alt = IsAltKeyDown()
    if pfMap.lastAlt ~= alt then
        pfMap.lastAlt = alt

        local function rebuildTooltip(tt)
            if pfMap.tooltipCurrentNode and tt then
                -- Check if tooltip is actually visible or can be shown
                local canShow = tt:IsShown() or MouseIsOver(pfMap.tooltipCurrentNode)

                if canShow then
                    -- Don't rebuild if tooltipCurrentNode is GameTooltip itself
                    if pfMap.tooltipCurrentNode == GameTooltip or pfMap.tooltipCurrentNode == WorldMapTooltip then
                        return
                    end

                    tt:ClearLines()
                    pfMap:ShowClusterTooltip(pfMap.tooltipCurrentNode, tt)
                    tt:Show()
                end
            elseif pfMap.tooltipMeta and not pfMap.tooltipMetaList and tt and tt:IsShown() then
                tt:ClearLines()
                pfMap:ShowTooltip(pfMap.tooltipMeta, tt)
                tt:Show()
            elseif pfMap.tooltipMetaList and tt and tt:IsShown() then
                -- Rebuild tooltip using stored metas to preserve all information when Alt is pressed.
                tt:ClearLines()

                -- Restore original Blizzard lines first
                for _, line in ipairs(pfMap._origLines or {}) do
                    tt:AddLine(line, 1, 1, 1, true)
                end

                -- Compute compactness heuristic
                local totalEstimatedChars = 0
                for _, meta in ipairs(pfMap.tooltipMetaList or {}) do
                    if meta.spawn then totalEstimatedChars = totalEstimatedChars + string.len(meta.spawn) end
                    if meta.quest then totalEstimatedChars = totalEstimatedChars + string.len(meta.quest) end
                    if meta.questid then
                        totalEstimatedChars = pfMap:addObjectiveChars(meta.questid, totalEstimatedChars)
                    end
                end
                local shouldCompact = (totalEstimatedChars > 200)
                for _, meta in ipairs(pfMap.tooltipMetaList or {}) do
                    pfMap:ShowTooltip(meta, tt, shouldCompact)
                end
                tt:Show()
            end
        end

        rebuildTooltip(GameTooltip)
        if WorldMapTooltip then
            rebuildTooltip(WorldMapTooltip)
        end
    end

    -- Simple right-click cycling
    if pfMap.cycleData and pfMap.cycleData.currentTooltip and pfMap.cycleData.currentTooltip:IsShown() then
        local isRightDown = IsMouseButtonDown("RightButton")

        -- Detect right-click press
        if isRightDown and not pfMap.rightPressed then
            pfMap.rightPressed = true

            -- Cycle to next spawn (expand in place)
            if pfMap.cycleData.allSpawns and table.getn(pfMap.cycleData.allSpawns) > 1 then
                pfMap.expandedSpawnIndex = pfMap.expandedSpawnIndex + 1
                if pfMap.expandedSpawnIndex > table.getn(pfMap.cycleData.allSpawns) then
                    pfMap.expandedSpawnIndex = 1
                end

                local activeSpawn = pfMap.cycleData.allSpawns[pfMap.expandedSpawnIndex]
                -- print("Cycling: Expanded", activeSpawn.spawn, "(" .. pfMap.expandedSpawnIndex .. "/" .. table.getn(pfMap.cycleData.allSpawns) .. ")")

                -- Store active spawn's questid for Mark as Done functionality
                pfMap.activeQuestId = nil
                pfMap.activeSpawnName = activeSpawn.spawn
                -- Try direct questid field first (new improved structure)
                if activeSpawn.questid then
                    pfMap.activeQuestId = activeSpawn.questid
                    -- print("Cycling: Stored questid", pfMap.activeQuestId, "for Mark as Done")
                elseif activeSpawn.node then
                    for title, meta in pairs(activeSpawn.node) do
                        if meta.questid then
                            pfMap.activeQuestId = meta.questid
                            -- print("Cycling: Stored questid", pfMap.activeQuestId, "for Mark as Done")
                            break
                        end
                    end
                end

                -- Update tooltip and highlight
                pfMap:ShowClusterTooltip(pfMap.cycleData.currentNode, pfMap.cycleData.currentTooltip)

                -- Highlight only active quest during cycling
                if activeSpawn and activeSpawn.title and pfQuest_config["mouseover"] == "1" then
                    pfMap.highlight = activeSpawn.title
                    pfMap.clusterHighlights = nil -- Clear cluster highlights during cycling
                    pfMap.queue_update = GetTime()

                end
            end
        elseif not isRightDown then
            pfMap.rightPressed = false
        end
    end

    -- handle highlights and animations
    if pfMap.queue_update or transition or pfMap.highlight ~= hlstate or shiftstate ~= hidecluster then
        hlstate, shiftstate, transition = pfMap.highlight, hidecluster, nil
        fps = math.max(.2, GetFramerate() / 30)

        for frame, data in pairs(pfMap.highlightdb) do
            local highlight = pfMap.highlightdb[frame][pfMap.highlight] and true or nil

            -- Check for cluster highlights
            local clusterHighlight = nil
            if pfMap.clusterHighlights then
                for questTitle in pairs(pfMap.clusterHighlights) do
                    if pfMap.highlightdb[frame][questTitle] then
                        clusterHighlight = true
                        break
                    end
                end
            end

            if hidecluster and frame.cluster then
                -- hide clusters
                transition = frame:Animate(frame.defsize, 0, fps) or transition
            elseif highlight or clusterHighlight then
                -- zoom node (regular highlight or cluster highlight)
                -- Raise frame level ONLY for the active quest (not cluster highlights)
                if highlight and pfMap.highlight and not pfMap.clusterHighlights then
                    if not frame.originalLevel then
                        frame.originalLevel = frame:GetFrameLevel()
                    end
                    frame:SetFrameLevel(frame.originalLevel + 5)
                else
                    -- Restore level for cluster highlights
                    if frame.originalLevel then
                        frame:SetFrameLevel(frame.originalLevel)
                    end
                end
                transition = frame:Animate((frame.texture and frame.defsize + 4 or frame.defsize), 1, fps) or transition
            elseif not highlight and not clusterHighlight and (pfMap.highlight or pfMap.clusterHighlights) then
                -- fade node (standard dimming for all non-active)
                transition = frame:Animate(frame.defsize, tonumber(pfQuest_config["nodefade"]) or 0.3, fps) or transition
            elseif frame.texture or frame.cluster then
                -- defaults for textured nodes (restore frame level)
                if frame.originalLevel then
                    frame:SetFrameLevel(frame.originalLevel)
                end
                transition = frame:Animate(frame.defsize, 1, fps) or transition
            else
                -- defaults
                transition = frame:Animate(frame.defsize, frame.defalpha, fps) or transition
            end
        end
    end

    -- limit all map updates to once per .05 seconds
    if ( this.throttle or .2) > GetTime() then return else this.throttle = GetTime() + .05 end

    -- process node updates if required
    if pfMap.queue_update and pfMap.queue_update + .25 < GetTime() then
        pfMap.queue_update = nil
        pfMap:UpdateNodes()
    end

    -- reset map to current zone once map is closed
    if WorldMapFrame:IsShown() then
        resetmap = true
    elseif resetmap == true then
        SetMapToCurrentZone()
        resetmap = nil

        -- Reset blob switching state when map closes
        if pfMap.showBlizzardBlobs then
            pfMap.showBlizzardBlobs = false
            pfMap:HideBlizzardBlobs()
            pfMap:ShowPfQuestNodes()
            pfMap:UpdateNodes()
        end
    end

    -- refresh minimap
    pfMap:UpdateMinimap()

    -- update hidecluster detection
    if controlkey.pressed then
        hidecluster = MouseIsOver(WorldMapFrame)

        -- Ctrl+Map blob switching: show Blizzard blobs, hide pfQuest nodes
        if hidecluster and WorldMapFrame:IsShown() and not pfMap.showBlizzardBlobs then
            pfMap.showBlizzardBlobs = true
            pfMap:HidePfQuestNodes()
            pfMap:ShowBlizzardBlobs()
        end
    else
        hidecluster = nil

        -- Restore pfQuest nodes when Ctrl released
        if pfMap.showBlizzardBlobs then
            pfMap.showBlizzardBlobs = false
            pfMap:HideBlizzardBlobs()
            pfMap:ShowPfQuestNodes()
            pfMap:UpdateNodes()
        end
    end
end)

-- only hook for 3.3.5
if compat.client >= 30300 then
    -- Hide swap button on quest selection ONLY when Ctrl is not held.
    -- During active Ctrl hover the swap button shows turn-in icons and should
    -- stay visible. But when the map reopens without Ctrl, the stale swap
    -- button from a previous session persists — this hides it.
    if WorldMapFrame_SelectQuestFrame then
        local origSelect = WorldMapFrame_SelectQuestFrame
        WorldMapFrame_SelectQuestFrame = function(questFrame)
            origSelect(questFrame)
            if not IsControlKeyDown() and QUEST_POI_SWAP_BUTTONS and QUEST_POI_SWAP_BUTTONS["WorldMapPOIFrame"] then
                QUEST_POI_SWAP_BUTTONS["WorldMapPOIFrame"]:Hide()
            end
        end
    end

    -- Initialize a variable to track the previous clicked title
    local previousTitle = nil
    -- Highlight Map Quest Log Selection Nodes
    local pfHookWorldMapQuestFrame_OnMouseUp = WorldMapQuestFrame_OnMouseUp
    WorldMapQuestFrame_OnMouseUp = function(self)
        pfHookWorldMapQuestFrame_OnMouseUp(self)
        WorldMapBlobFrame:Hide()
        WorldMapFrame_ClearQuestPOIs()
        if not IsShiftKeyDown() then
            pfMap.highlight = nil
            local questLogIndex = GetQuestLogSelection()
            local title = GetQuestLogTitle(questLogIndex)

            if title then
                if previousTitle == title then
                    -- Reset the highlight if the same title is clicked again
                    pfMap.highlight = nil
                    previousTitle = nil
                else
                    -- Logic for highlighting nodes associated with the clicked quest
                    pfMap.highlight = title
                    previousTitle = title
                    pfMap.queue_update = GetTime()
                end
            end
        end
    end
end

-- Helper function to count quests unlocked by a given quest
function pfMap:CountUnlockedQuests(questid)
  local count = 0
  if not questid or not pfDB or not pfDB["quests"] or not pfDB["quests"]["data"] then return 0 end

  -- Get chain quest IDs to exclude from unlocks
  local chainQuestIds = self:GetChainQuestIds(questid)

  for id, data in pairs(pfDB["quests"]["data"]) do
    if data and data["pre"] then
      for _, pre in ipairs(data["pre"]) do
        if math.abs(pre) == questid then
          -- Skip if this quest is already in the chain
          if not chainQuestIds[id] then
            count = count + 1
          end
          break
        end
      end
    end
  end
  return count
end

-- Helper function to list quests that become available after the given quest
function pfMap:GetUnlockSummary(questid)
  if not questid or not pfDB or not pfDB["quests"] or not pfDB["quests"]["data"] then return {} end
  local summary = {}

  -- Get chain quest IDs to exclude from unlocks
  local chainQuestIds = self:GetChainQuestIds(questid)

  for id, data in pairs(pfDB["quests"]["data"]) do
    if data and data["pre"] then
      for _, pre in ipairs(data["pre"]) do
        if math.abs(pre) == questid then
          -- Skip if this quest is already in the chain
          if not chainQuestIds[id] then
            local qLoc = pfDB["quests"]["loc"] and pfDB["quests"]["loc"][id]
            if qLoc and qLoc["T"] then table.insert(summary, qLoc["T"]) end
          end
          break
        end
      end
    end
  end
  table.sort(summary)
  return summary
end

-- Helper function to get all quest IDs in the chain
function pfMap:GetChainQuestIds(questid)
  local chainIds = {}
  if not questid or not pfDB or not pfDB["quests"] or not pfDB["quests"]["data"] then
    return chainIds
  end

  local visited = {}

  -- Recursively collect all chain quest IDs
  local function collectChainIds(qid)
    if visited[qid] then return end
    visited[qid] = true

    local qData = pfDB["quests"]["data"][qid]
    if qData and qData["chain"] then
      for _, nextQuestId in ipairs(qData["chain"]) do
        chainIds[nextQuestId] = true
        collectChainIds(nextQuestId)
      end
    end
  end

  collectChainIds(questid)
  return chainIds
end

-- Get FULL chain: forward (via chain field) + backward (via reverse chain lookup)
function pfMap:GetFullChainQuestIds(questid)
  local chainIds = {}
  if not questid or not pfDB or not pfDB["quests"] or not pfDB["quests"]["data"] then
    return chainIds
  end

  local visited = {}

  -- Go FORWARD: follow chain field
  local function collectForward(qid)
    if visited[qid] then return end
    visited[qid] = true
    chainIds[qid] = true

    local qData = pfDB["quests"]["data"][qid]
    if qData and qData["chain"] then
      for _, nextQuestId in ipairs(qData["chain"]) do
        collectForward(nextQuestId)
      end
    end
  end

  -- Go BACKWARD: find quests whose chain field points to this quest
  local function collectBackward(qid)
    if visited[qid] then return end
    visited[qid] = true
    chainIds[qid] = true

    for id, data in pairs(pfDB["quests"]["data"]) do
      if data and data["chain"] then
        for _, chainId in ipairs(data["chain"]) do
          if chainId == qid then
            collectBackward(id)
            break
          end
        end
      end
    end
  end

  visited[questid] = nil
  collectForward(questid)
  visited[questid] = nil
  collectBackward(questid)

  return chainIds
end

-- Store last chain mark for undo
pfMap.lastChainMark = nil

-- Undo the last chain mark
function pfMap:UndoLastChainMark()
  if not pfMap.lastChainMark then
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpf|cffffffffQuest: |cffff6666No chain mark to undo")
    return
  end

  local count = 0
  for questid, _ in pairs(pfMap.lastChainMark) do
    if pfQuest_history[questid] then
      pfQuest_history[questid] = nil
      pfMap:ClearQuestFromCaches(questid)
      count = count + 1
    end
  end

  pfMap.lastChainMark = nil
  pfMap.queue_update = GetTime()
  pfQuest.updateQuestGivers = true
  pfQuest.updateQuestLog = true

  DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpf|cffffffffQuest: |cffffff00Undone " .. count .. " quest(s)")
end

-- Hook SetItemRef to handle pfquestundo and pfquestignore hyperlinks
local pfQuestHookSetItemRef = SetItemRef
SetItemRef = function(link, text, button)
  if link == "pfquestundo" then
    pfMap:UndoLastChainMark()
    return
  end
  local ignoreItemId = string.match(link, "^pfquestignore:(%d+)$")
  if ignoreItemId then
    ignoreItemId = tonumber(ignoreItemId)
    pfQuest_config.ignoredItems = pfQuest_config.ignoredItems or {}
    pfQuest_config.ignoredItems[ignoreItemId] = true
    local _, itemLink = GetItemInfo(ignoreItemId)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpf|cffffffffQuest: |cffff4444Ignored: " .. (itemLink or ("item:" .. ignoreItemId)))
    return
  end
  return pfQuestHookSetItemRef(link, text, button)
end

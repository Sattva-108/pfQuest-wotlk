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

  local name = getglobal("GameTooltipTextLeft1") and getglobal("GameTooltipTextLeft1"):GetText() or "__NONE__"
  local zone = pfMap:GetMapID(GetCurrentMapContinent(), GetCurrentMapZone())

  -- remove all colors from received tooltip text
  name = string.gsub(name, "|c%x%x%x%x%x%x%x%x", "")
  name = string.gsub(name, "|r", "")

  if pfMap.tooltips[name] and pfMap.tooltips[name] then
    -- Calculate total tooltip size first
    local totalEstimatedChars = 0
    for title, obj in pairs(pfMap.tooltips[name]) do
      if obj[zone] and obj[zone]["questid"] then
        totalEstimatedChars = pfMap:addObjectiveChars(obj[zone]["questid"], totalEstimatedChars)
      end
    end
    local shouldCompact = (totalEstimatedChars > 200)
    
    -- Show all tooltips with same compact setting
    for title, obj in pairs(pfMap.tooltips[name]) do
      if obj[zone] then
        pfMap:ShowTooltip(obj[zone], GameTooltip, shouldCompact)
        GameTooltip:Show()
      end
    end
  end
end)

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
  xp = xp * serverRate

  -- Step 6: Final floor (as AzerothCore converts to uint32)
  return math.floor(xp)
end

function pfMap:ShowTooltip(meta, tooltip, forceCompact)
  local catch = nil
  local catch_obj = nil
  local tooltip = tooltip or GameTooltip

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
    if this.questid and this.texture and this.layer < 5 then
      -- mark questnode as done
      print("DEBUG: Marking quest as done - questid:", this.questid, "spawn:", this.spawn or "unknown")
      pfQuest_history[this.questid] = { time(), UnitLevel("player") }
    else
      print("DEBUG: Cannot mark quest as done - questid:", this.questid or "nil", "texture:", this.texture or "nil", "layer:", this.layer or "nil")
    end

    if this.node and this.title and this.node[this.title] then
      -- delete node from map
      pfMap:DeleteNode(this.node[this.title].addon, this.title)
    end

    pfQuest.updateQuestGivers = true
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

  -- Smart anchor: use RIGHT if there's space, fallback to LEFT if near edge
  local mouseX = GetCursorPosition() / UIParent:GetEffectiveScale()
  local screenWidth = GetScreenWidth()
  local useRightAnchor = mouseX < (screenWidth * 0.7) -- Use RIGHT if cursor in left 70% of screen

  tooltip:SetOwner(this, useRightAnchor and "ANCHOR_RIGHT" or "ANCHOR_LEFT")
  this.spawn = this.spawn or UNKNOWN

  -- Use cluster tooltip by default
  pfMap:ShowClusterTooltip(this, tooltip)

  -- Save tooltip context for Alt-cycling
  if pfMap.altCycleData then
    pfMap.altCycleData.currentNode = this
    pfMap.altCycleData.currentTooltip = tooltip
  end

  pfMap.highlight = pfQuest_config["mouseover"] == "1" and this.title
end

-- Helper function to get quest symbol and status
function pfMap:GetQuestSymbol(questTitle)
  local questInLog = false
  local questComplete = false

  for qid=1, GetNumQuestLogEntries() do
    local qtitle, _, _, _, _, complete = compat.GetQuestLogTitle(qid)
    if questTitle == qtitle then
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

-- Global variables for alt-cycling
pfMap.altCycleData = nil
pfMap.altCycleIndex = 1
pfMap.altCycleDebounce = 0 -- Debounce timer for rapid Alt presses

function pfMap:ShowClusterTooltip(currentNode, tooltip)
  -- Early estimation of tooltip size for compact decisions
  local estimatedChars = 0
  estimatedChars = estimatedChars + string.len(currentNode.spawn or "")
  for title, meta in pairs(currentNode.node) do
    if meta.quest then
      estimatedChars = estimatedChars + string.len(meta.quest or "")
    end
    if meta.spawn then
      estimatedChars = estimatedChars + string.len(meta.spawn or "")
    end
    estimatedChars = self:addObjectiveChars(meta.questid, estimatedChars)
  end

  -- Find all nearby nodes within cluster distance
  local nearbyNodes, questTitles
  
  -- Use FROZEN data during active cycling sessions to maintain stable tooltip content
  if pfMap.altCycleData and pfMap.altCheckEnabled and pfMap.altCycleData.frozenNearbyNodes then
    -- Use frozen scan results during cycling
    nearbyNodes = pfMap.altCycleData.frozenNearbyNodes
    questTitles = pfMap.altCycleData.frozenQuestTitles
    print("DEBUG: Using FROZEN nearby data, nodes:", table.getn(nearbyNodes))
  else
    -- Initial scan when not cycling - do full nearby node search
    local map = pfMap:GetMapID(GetCurrentMapContinent(), GetCurrentMapZone())
    local clusterRadius = 1.3 -- Map coordinate units for clustering
    nearbyNodes = {}
    questTitles = {} -- Track quest titles for highlighting

    -- Get current node coordinates from its data
    local currentX, currentY = nil, nil
    if not currentNode.node then
      print("ERROR: currentNode.node is nil in ShowClusterTooltip")
      return
    end
    for title, meta in pairs(currentNode.node) do
      if meta.x and meta.y then
        currentX, currentY = tonumber(meta.x), tonumber(meta.y)
        break -- Use first found coordinates
      end
    end

    -- Get current mouse position for proximity check
    local isOnMinimap = currentNode:GetParent() ~= WorldMapButton
    if isOnMinimap then
      clusterRadius = 0.5 -- smaller radius for minimap
    end

    -- Check if current node is a quest starter/ender
    local isCurrentNodeQuestGiver = false
    for title, meta in pairs(currentNode.node) do
      if meta.QTYPE and (meta.QTYPE == "NPC_START" or meta.QTYPE == "NPC_END" or
                         meta.QTYPE == "OBJECT_START" or meta.QTYPE == "OBJECT_END") then
        isCurrentNodeQuestGiver = true
        break
      end
    end

    -- Only do clustering if current node is a quest giver
    if isCurrentNodeQuestGiver and pfMap.nodes and currentX and currentY then
      local seenSpawns = {} -- Prevent duplicate spawns in cluster scan
      
      for addonName, addonData in pairs(pfMap.nodes) do
        if addonData[map] then
          for coords, coordNodes in pairs(addonData[map]) do
            for title, meta in pairs(coordNodes) do
              if meta.x and meta.y then
                local nodeX, nodeY = tonumber(meta.x), tonumber(meta.y)
                local distance = math.sqrt((nodeX - currentX)^2 + (nodeY - currentY)^2)

                -- Add 10% tolerance to cluster boundaries to reduce edge case sensitivity
                if distance <= clusterRadius * 1.1 then
                  -- Only include nodes that are quest starters/enders
                  local isQuestGiver = meta.QTYPE and (meta.QTYPE == "NPC_START" or meta.QTYPE == "NPC_END" or
                                                       meta.QTYPE == "OBJECT_START" or meta.QTYPE == "OBJECT_END")

                  if isQuestGiver then
                    local spawnKey = (meta.spawn or title) .. ":" .. coords
                    
                    -- Skip if already seen this spawn+coords combination
                    if not seenSpawns[spawnKey] then
                      seenSpawns[spawnKey] = true
                      
                      table.insert(nearbyNodes, {
                        spawn = meta.spawn or title,
                        level = meta.level,
                        spawntype = meta.spawntype,
                        respawn = meta.respawn,
                        spawnid = meta.spawnid,
                        distance = distance,
                        title = title,
                        node = {[title] = meta}
                      })

                      -- Track quest titles for highlighting (use composite keys to prevent collisions)
                      if meta.quest then
                        local titleKey = meta.spawn .. ":" .. meta.quest
                        if questTitles[titleKey] then
                          print("DEBUG: DUPLICATE TITLE KEY:", titleKey)
                        end
                        questTitles[titleKey] = true
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
    
    -- Store frozen data for cycling sessions (will be used later in cycling data init)
    print("DEBUG: SCANNED nearby data, nodes:", table.getn(nearbyNodes), "- will be frozen with cycling data")
    
    -- DEBUG: Show cluster membership details
    print("=== CLUSTER MEMBERSHIP DEBUG ===")
    print("Cluster radius (with tolerance):", clusterRadius * 1.1)
    for i, nodeData in ipairs(nearbyNodes) do
      print(string.format("NPC %d: %s (dist: %.2f)", i, nodeData.spawn, nodeData.distance))
    end
    print("=================================")
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
    for title, meta in pairs(currentNode.node) do
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

      for title, meta in pairs(currentNode.node) do
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
  local mainSpawnData = {spawn = currentNode.spawn, node = currentNode.node, isCurrent = true, level = currentNode.level, spawntype = currentNode.spawntype, respawn = currentNode.respawn, spawnid = currentNode.spawnid}
  local otherSpawns = sortedSpawns

  -- Get current displayed spawn info from mainSpawnData
  local displaySpawn = mainSpawnData.spawn
  local displayLevel = mainSpawnData.level or (mainSpawnData.isCurrent and currentNode.level) or UNKNOWN
  local displayType = mainSpawnData.spawntype or (mainSpawnData.isCurrent and currentNode.spawntype) or UNKNOWN
  local displayRespawn = mainSpawnData.respawn or (mainSpawnData.isCurrent and currentNode.respawn) or UNKNOWN
  local displaySpawnId = mainSpawnData.spawnid or (mainSpawnData.isCurrent and currentNode.spawnid) or ""

  -- Set tooltip header with current main spawn
  local cycleIndicator = (useCompactFormat and pfMap.altCycleData) and " |cffcccccc(" .. pfMap.altCycleIndex .. "/" .. table.getn(pfMap.altCycleData.allSpawns) .. ")|r" or ""
  
  -- VERIFICATION TEST: Check render consistency
  if pfMap.altCycleData and pfMap.altCheckEnabled then
    print(string.format("RENDER CONSISTENCY: %d/%d (Frozen: %s)", 
          pfMap.altCycleIndex, 
          table.getn(pfMap.altCycleData.frozenAllSpawns or {}), 
          tostring(pfMap.altCheckEnabled)))
  end
  
  tooltip:SetText(displaySpawn .. cycleIndicator .. (pfQuest_config.showids == "1" and " |cffcccccc("..displaySpawnId..")|r" or ""), .3, 1, .8)

  tooltip:AddDoubleLine(pfQuest_Loc["Level"] .. ":", displayLevel, .8,.8,.8, 1,1,1)
  tooltip:AddDoubleLine(pfQuest_Loc["Type"] .. ":", displayType, .8,.8,.8, 1,1,1)
  tooltip:AddDoubleLine(pfQuest_Loc["Respawn"] .. ":", displayRespawn, .8,.8,.8, 1,1,1)

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

  -- Use FROZEN sortedSpawns if cycling active, otherwise create new
  local sortedSpawns
  if pfMap.altCycleData and pfMap.altCheckEnabled and pfMap.altCycleData.frozenSortedSpawns then
    sortedSpawns = pfMap.altCycleData.frozenSortedSpawns
    print("DEBUG: Using FROZEN sortedSpawns, count:", table.getn(sortedSpawns))
  else
    -- Sort spawns by priority: starters > enders > vendors > others
    sortedSpawns = {}
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
    print("DEBUG: Created NEW sortedSpawns, count:", table.getn(sortedSpawns))
  end

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
    -- Use FROZEN allSpawns if cycling active, otherwise create new
    local allSpawns
    if pfMap.altCycleData and pfMap.altCheckEnabled and pfMap.altCycleData.frozenAllSpawns then
      allSpawns = pfMap.altCycleData.frozenAllSpawns
      print("DEBUG: Using FROZEN allSpawns, count:", table.getn(allSpawns))
    else
      -- Create all spawns list including current node
      allSpawns = {}
      table.insert(allSpawns, {
        spawn = currentNode.spawn,
        node = currentNode.node,
        isCurrent = true,
        level = currentNode.level,
        spawntype = currentNode.spawntype,
        respawn = currentNode.respawn,
        spawnid = currentNode.spawnid
      })
      for _, spawnData in ipairs(sortedSpawns) do
        -- Get metadata from first node in the group
        local firstNode = spawnData.nodes and spawnData.nodes[1]
        local meta = firstNode and firstNode.meta
        table.insert(allSpawns, {
          spawn = spawnData.spawn,
          nodes = spawnData.nodes,
          isCurrent = false,
          level = meta and meta.level,
          spawntype = meta and meta.spawntype,
          respawn = meta and meta.respawn,
          spawnid = meta and meta.spawnid
        })
      end
      print("DEBUG: Created NEW allSpawns, count:", table.getn(allSpawns))
    end

    -- Initialize or update cycling data
    -- DON'T recreate data if cycling is already active for this tooltip session
    if not pfMap.altCycleData then
      -- Brand new tooltip - initialize everything and freeze ALL render data
      pfMap.altCycleData = {
        allSpawns = allSpawns,
        nodeHash = currentNode.spawn,
        originalSpawn = currentNode.spawn,  -- Store immutable cluster ID for this session
        frozenNearbyNodes = nearbyNodes,    -- Freeze scan results
        frozenQuestTitles = questTitles,    -- Freeze quest highlights  
        frozenSortedSpawns = sortedSpawns,  -- Freeze sorted spawns
        frozenAllSpawns = allSpawns         -- Freeze all spawns list
      }
      pfMap.altCycleIndex = 1
      print("DEBUG: NEW cycling data initialized with ALL FROZEN render data, index:", pfMap.altCycleIndex, "spawns:", table.getn(allSpawns))
      -- Enable OnUpdate for Alt-cycling
      pfMap.altCheckEnabled = true
    elseif not pfMap.altCheckEnabled then
      -- Tooltip reopened - reinitialize for new cluster and freeze ALL new data
      pfMap.altCycleData = {
        allSpawns = allSpawns,
        nodeHash = currentNode.spawn,
        originalSpawn = currentNode.spawn,  
        frozenNearbyNodes = nearbyNodes,    -- New frozen scan results
        frozenQuestTitles = questTitles,    -- New frozen quest highlights
        frozenSortedSpawns = sortedSpawns,  -- New frozen sorted spawns
        frozenAllSpawns = allSpawns         -- New frozen all spawns list
      }
      pfMap.altCycleIndex = 1
      print("DEBUG: REINITIALIZED cycling data with ALL new FROZEN render data, index:", pfMap.altCycleIndex, "spawns:", table.getn(allSpawns))
      pfMap.altCheckEnabled = true
    else
      -- Cycling active - preserve ALL existing frozen data, don't recreate anything
      local oldIndex = pfMap.altCycleIndex
      -- Use existing allSpawns from frozen data
      allSpawns = pfMap.altCycleData.frozenAllSpawns or allSpawns
      pfMap.altCycleData.allSpawns = allSpawns
      -- Validate index is still in bounds
      if pfMap.altCycleIndex > table.getn(allSpawns) then
        pfMap.altCycleIndex = 1
      end
      print("DEBUG: KEPT cycling data with ALL preserved FROZEN render data, index:", oldIndex, "->", pfMap.altCycleIndex, "spawns:", table.getn(allSpawns))
    end
  else
    -- Clear cycling data when no nearby spawns
    pfMap.altCycleData = nil
  end

  -- Update mainSpawnData and otherSpawns based on alt-cycling state
  if pfMap.altCycleData then
    mainSpawnData = pfMap.altCycleData.allSpawns[pfMap.altCycleIndex]
    -- Create otherSpawns in cycling order: next items first, then previous items
    otherSpawns = {}
    local totalSpawns = table.getn(pfMap.altCycleData.allSpawns)

    -- Add items after current index (next in cycle)
    for i = pfMap.altCycleIndex + 1, totalSpawns do
      table.insert(otherSpawns, pfMap.altCycleData.allSpawns[i])
    end

    -- Add items before current index (previous in cycle, now at end)
    for i = 1, pfMap.altCycleIndex - 1 do
      table.insert(otherSpawns, pfMap.altCycleData.allSpawns[i])
    end

    -- Update display info for cycling
    displaySpawn = mainSpawnData.spawn
    displayLevel = mainSpawnData.level or (mainSpawnData.isCurrent and currentNode.level) or UNKNOWN
    displayType = mainSpawnData.spawntype or (mainSpawnData.isCurrent and currentNode.spawntype) or UNKNOWN
    displayRespawn = mainSpawnData.respawn or (mainSpawnData.isCurrent and currentNode.respawn) or UNKNOWN
    displaySpawnId = mainSpawnData.spawnid or (mainSpawnData.isCurrent and currentNode.spawnid) or ""

    -- Update tooltip header for cycling
    local cycleIndicator = " |cffcccccc(" .. pfMap.altCycleIndex .. "/" .. table.getn(pfMap.altCycleData.allSpawns) .. ")|r"
    tooltip:SetText(displaySpawn .. cycleIndicator .. (pfQuest_config.showids == "1" and " |cffcccccc("..displaySpawnId..")|r" or ""), .3, 1, .8)

    -- Update header lines
    tooltip:AddDoubleLine(pfQuest_Loc["Level"] .. ":", displayLevel, .8,.8,.8, 1,1,1)
    tooltip:AddDoubleLine(pfQuest_Loc["Type"] .. ":", displayType, .8,.8,.8, 1,1,1)
    tooltip:AddDoubleLine(pfQuest_Loc["Respawn"] .. ":", displayRespawn, .8,.8,.8, 1,1,1)
  else
    -- For non-compact format, use sortedSpawns directly
    otherSpawns = sortedSpawns
  end

  -- Show main spawn's quests
  local shouldCompact = (estimatedChars > 200) -- Trigger compacting when tooltip exceeds 200 chars
  if mainSpawnData.node then
    -- Current node format
    for title, meta in pairs(mainSpawnData.node) do
      pfMap:ShowTooltip(meta, tooltip, shouldCompact)
    end
  elseif mainSpawnData.nodes then
    -- Other spawn format
    for _, nodeInfo in ipairs(mainSpawnData.nodes) do
      pfMap:ShowTooltip(nodeInfo.meta, tooltip, shouldCompact)
    end
  end

  -- Show other spawns in compact format
  local maxSpawns = 15 -- Show max 15 different spawns with compact format
  local spawnCount = 0
  local remainingCounts = {starters = 0, enders = 0, vendors = 0, others = 0}

  for i, spawnData in ipairs(otherSpawns or {}) do
    if spawnCount < maxSpawns then
      tooltip:AddLine(" ") -- spacer
      tooltip:AddLine("|cff00ff00" .. spawnData.spawn .. "|r", .8, 1, .8)

      -- Show all quests for this spawn
      local nodes = spawnData.nodes or {}
      if spawnData.node then
        -- Convert single node to nodes format
        for title, meta in pairs(spawnData.node) do
          table.insert(nodes, {meta = meta})
        end
      end
      for _, nodeInfo in ipairs(nodes) do
        local meta = nodeInfo.meta or nodeInfo
        if meta.quest then
          if useCompactFormat then
            -- Use compact format for other spawns in compact mode
            local symbol = pfMap:GetQuestSymbol(meta.quest)
            tooltip:AddLine(symbol .. meta.quest, 1, 1, 0)
          else
            -- Use full format in non-compact mode
            pfMap:ShowTooltip(meta, tooltip, shouldCompact)
          end
        else
          -- For non-quest items, show full info
          pfMap:ShowTooltip(meta, tooltip, shouldCompact)
        end
      end

      spawnCount = spawnCount + 1
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

  -- Set up highlighting for all related quests
  if pfQuest_config["mouseover"] == "1" then
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

    -- update tooltip and sizes
    tooltip:AddLine(text, .6, .6, .6)

    -- Add right-click cycling help for tooltips with multiple spawns
    if pfMap.altCycleData then
      tooltip:AddLine("Use <Right>-Click To Cycle Through All " .. table.getn(pfMap.altCycleData.allSpawns) .. " NPCs", .6, .6, .6)
    end

    tooltip:Show()
  end

  tooltip:Show()
end

function pfMap:NodeLeave()
  -- wotlk: re-enable blop tooltips
  if compat.client >= 30300 then
    WorldMapPOIFrame.allowBlobTooltip = true
  end

  local tooltip = this:GetParent() == WorldMapButton and WorldMapTooltip or GameTooltip
  
  -- BLOCK tooltip hiding during cycling updates to prevent premature closure
  if pfMap.suppressLeave then 
    -- Check if suppression has timed out
    if pfMap.suppressUntil and GetTime() > pfMap.suppressUntil then
      pfMap.suppressLeave = nil
      pfMap.suppressUntil = nil
      print("DEBUG: Suppression timed out, allowing tooltip hide")
    else
      print("DEBUG: Blocked tooltip hide during cycling update")
      return 
    end
  end
  
  -- Check if mouse is still over the same frame to prevent premature cleanup
  if pfMap.altCycleData and GetMouseFocus() == this then
    print("DEBUG: Mouse still over cycling frame, preserving altCycleData")
    return
  end
  
  tooltip:Hide()
  pfMap.highlight = nil
  pfMap.clusterHighlights = nil -- Clear cluster highlights

  -- Restore original node data (do NOT clear altCycleData here – cleanup happens on tooltip OnHide)
  if pfMap.altCycleData and pfMap.altCycleData.currentNode and pfMap.altCycleData.originalNode then
    local currentNode = pfMap.altCycleData.currentNode
    currentNode.node     = pfMap.altCycleData.originalNode
    currentNode.spawn    = pfMap.altCycleData.originalSpawn
    currentNode.level    = pfMap.altCycleData.originalLevel
    currentNode.spawntype= pfMap.altCycleData.originalSpawntype
    currentNode.respawn  = pfMap.altCycleData.originalRespawn
    currentNode.spawnid  = pfMap.altCycleData.originalSpawnid
  end

  -- Do not clear altCycleData here – cleanup now handled by tooltip OnHide hook.
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
  local mapZoom = minimap_zoom[minimap_indoor()][mZoom]
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

pfMap:SetScript("OnUpdate", function()
  -- Auto-clear suppression flag after timeout
  if pfMap.suppressLeave and pfMap.suppressUntil and GetTime() > pfMap.suppressUntil then
    pfMap.suppressLeave = nil
    pfMap.suppressUntil = nil
    print("DEBUG: Auto-cleared suppression flag")
  end
  
  -- Right-click cycling check (only when tooltip is active)
  if pfMap.altCheckEnabled then
    local isRightDown = IsMouseButtonDown("RightButton")
    local isCleanClick = not IsShiftKeyDown() and not IsControlKeyDown() and not IsAltKeyDown()
    local tooltipActive = pfMap.altCycleData and pfMap.altCycleData.currentTooltip and pfMap.altCycleData.currentTooltip:IsShown()

    -- DEBUG: Show cycling state (only once per click)
    if isRightDown and isCleanClick and not pfMap.rightPressed then
      print("DEBUG: Right click - TooltipActive:", tooltipActive, "Index:", pfMap.altCycleIndex)
    end

    -- Detect Right-click transition (not pressed → pressed) with clean modifiers and active tooltip
    local now = GetTime()
    if isRightDown and isCleanClick and tooltipActive and not pfMap.rightPressed and (not pfMap.altCycleDebounce or now - pfMap.altCycleDebounce > 0.25) then
      pfMap.altCycleDebounce = now
      pfMap.rightPressed = true
      print("DEBUG: RIGHT CLICK DETECTED - Starting cycling...")

      -- Calculate total tooltip character count (same as original estimatedChars logic)
      local charCount = 0
      local foundB4B = false

      -- Count chars for all spawns in tooltip (not just current one)
      for _, spawnData in ipairs(pfMap.altCycleData.allSpawns) do
        local spawnName = spawnData.spawn or ""
        charCount = charCount + string.len(spawnName)
        if string.find(spawnName, "$B$B") or string.find(spawnName, "$b$b") then foundB4B = true end

        if spawnData.node then
          for title, meta in pairs(spawnData.node) do
            if meta.quest then
              local questText = meta.quest or ""
              charCount = charCount + string.len(questText)
              if string.find(questText, "$B$B") or string.find(questText, "$b$b") then foundB4B = true end
            end
            if meta.spawn then
              local metaSpawn = meta.spawn or ""
              charCount = charCount + string.len(metaSpawn)
              if string.find(metaSpawn, "$B$B") or string.find(metaSpawn, "$b$b") then foundB4B = true end
            end
            -- Check quest objectives text from pfDB
            if meta.questid and pfDB and pfDB["quests"] and pfDB["quests"]["loc"] and pfDB["quests"]["loc"][meta.questid] then
              local questData = pfDB["quests"]["loc"][meta.questid]
              if questData["O"] then
                local objectiveText = questData["O"] or ""
                charCount = charCount + string.len(objectiveText)
                if string.find(objectiveText, "$B$B") or string.find(objectiveText, "$b$b") then
                  foundB4B = true
                end
              end
            end
          end
        elseif spawnData.nodes then
          for _, nodeInfo in ipairs(spawnData.nodes) do
            if nodeInfo.meta then
              if nodeInfo.meta.quest then
                local questText = nodeInfo.meta.quest or ""
                charCount = charCount + string.len(questText)
                if string.find(questText, "$B$B") or string.find(questText, "$b$b") then foundB4B = true end
              end
              if nodeInfo.meta.spawn then
                local metaSpawn = nodeInfo.meta.spawn or ""
                charCount = charCount + string.len(metaSpawn)
                if string.find(metaSpawn, "$B$B") or string.find(metaSpawn, "$b$b") then foundB4B = true end
              end
              -- Check quest objectives text from pfDB
              if nodeInfo.meta.questid and pfDB and pfDB["quests"] and pfDB["quests"]["loc"] and pfDB["quests"]["loc"][nodeInfo.meta.questid] then
                local questData = pfDB["quests"]["loc"][nodeInfo.meta.questid]
                if questData["O"] then
                  local objectiveText = questData["O"] or ""
                  charCount = charCount + string.len(objectiveText)
                  if string.find(objectiveText, "$B$B") or string.find(objectiveText, "$b$b") then
                    foundB4B = true
                  end
                end
              end
            end
          end
        end
      end


      -- Same cycling logic
      if pfMap.altCycleData and pfMap.altCycleData.allSpawns and table.getn(pfMap.altCycleData.allSpawns) > 0 then
        print("DEBUG: Before cycling - index:", pfMap.altCycleIndex, "total:", table.getn(pfMap.altCycleData.allSpawns))
        pfMap.altCycleIndex = pfMap.altCycleIndex + 1
        if pfMap.altCycleIndex > table.getn(pfMap.altCycleData.allSpawns) then
          pfMap.altCycleIndex = 1
        end
        print("DEBUG: After cycling - new index:", pfMap.altCycleIndex)

        -- Update current node properties for mark quest as done functionality and highlight
        local currentSpawn = pfMap.altCycleData.allSpawns[pfMap.altCycleIndex]
        local currentNode = pfMap.altCycleData.currentNode
        
        if currentSpawn and currentNode then
          print("DEBUG: Found currentSpawn:", currentSpawn.spawn, "isCurrent:", currentSpawn.isCurrent)
          -- Clear current highlight
          pfMap.highlight = nil
          
          -- Save original node data
          local originalNode = currentNode.node
          local originalSpawn = currentNode.spawn
          local originalLevel = currentNode.level
          local originalSpawntype = currentNode.spawntype
          local originalRespawn = currentNode.respawn
          local originalSpawnid = currentNode.spawnid
          
          -- Temporarily update current node for tooltip display
          currentNode.spawn = currentSpawn.spawn
          currentNode.level = currentSpawn.level
          currentNode.spawntype = currentSpawn.spawntype  
          currentNode.respawn = currentSpawn.respawn
          currentNode.spawnid = currentSpawn.spawnid
          
          -- Update node properties from current cycling target
          if currentSpawn.isCurrent then
            -- Use original node data - no changes needed to node
            for title, meta in pairs(originalNode) do
              if meta.questid then
                currentNode.questid = meta.questid
                currentNode.title = title  -- Update title for highlight
                if pfQuest_config["mouseover"] == "1" then
                  pfMap.highlight = title  -- Set new highlight
                end
                print("DEBUG: Cycling to original node, questid:", meta.questid, "spawn:", currentSpawn.spawn, "title:", title)
                break
              end
            end
          elseif currentSpawn.node then
            -- Use cycling target data
            currentNode.node = currentSpawn.node
            for title, meta in pairs(currentSpawn.node) do
              if meta.questid then
                currentNode.questid = meta.questid
                currentNode.title = title  -- Update title for highlight
                if pfQuest_config["mouseover"] == "1" then
                  pfMap.highlight = title  -- Set new highlight
                end
                print("DEBUG: Cycling to spawn:", currentSpawn.spawn, "questid:", meta.questid, "title:", title)
                break
              end
            end
          elseif currentSpawn.nodes and currentSpawn.nodes[1] and currentSpawn.nodes[1].meta then
            -- Use first node from nodes array
            local meta = currentSpawn.nodes[1].meta
            local nodeTitle = currentSpawn.nodes[1].title or currentSpawn.spawn
            currentNode.node = {[nodeTitle] = meta}
            currentNode.questid = meta.questid
            currentNode.title = nodeTitle  -- Update title for highlight
            if pfQuest_config["mouseover"] == "1" then
              pfMap.highlight = nodeTitle  -- Set new highlight
            end
            print("DEBUG: Cycling to spawn:", currentSpawn.spawn, "questid:", meta.questid, "from nodes array, title:", nodeTitle)
          end
          
          -- Force update queue to refresh highlights immediately
          pfMap.queue_update = GetTime()
          
          -- Update tooltip with modified current node
          if pfMap.altCycleData.currentTooltip then
            print("DEBUG: Updating tooltip...")
            local tooltip = pfMap.altCycleData.currentTooltip
            
            -- SUPPRESS tooltip hide events during update to prevent premature closure
            pfMap.suppressLeave = true
            pfMap.suppressUntil = GetTime() + 0.5  -- Keep suppression active for 0.5 seconds
            print("DEBUG: SUPPRESSION ACTIVE - blocking tooltip hide events for 0.5s")
            pfMap:ShowClusterTooltip(currentNode, tooltip)
            print("DEBUG: Tooltip updated, suppression will auto-clear at:", pfMap.suppressUntil)
            
            -- Restore tooltip reference if it was cleared
            if pfMap.altCycleData then
              pfMap.altCycleData.currentTooltip = tooltip
              if tooltip:IsShown() then
                print("DEBUG: Tooltip update completed, still active")
              else
                print("DEBUG: WARNING - Tooltip became inactive after update")
              end
            else
              print("DEBUG: ERROR - altCycleData was cleared during ShowClusterTooltip!")
            end
          else
            print("DEBUG: ERROR - No currentTooltip found!")
          end
          
          -- Store cycling info for restoration later
          pfMap.altCycleData.originalNode = originalNode
          pfMap.altCycleData.originalSpawn = originalSpawn
          pfMap.altCycleData.originalLevel = originalLevel
          pfMap.altCycleData.originalSpawntype = originalSpawntype
          pfMap.altCycleData.originalRespawn = originalRespawn
          pfMap.altCycleData.originalSpawnid = originalSpawnid
        else
          print("DEBUG: ERROR - Missing currentSpawn or currentNode!")
        end
      else
        print("DEBUG: ERROR - No altCycleData.allSpawns or empty!")
      end
    elseif not isRightDown then
      if pfMap.rightPressed then
        print("DEBUG: Right button released")
      end
      pfMap.rightPressed = false -- Reset when Right is released
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
        transition = frame:Animate((frame.texture and frame.defsize + 4 or frame.defsize), 1, fps) or transition
      elseif not highlight and not clusterHighlight and (pfMap.highlight or pfMap.clusterHighlights) then
        -- fade node
        transition = frame:Animate(frame.defsize, tonumber(pfQuest_config["nodefade"]) or 0.3, fps) or transition
      elseif frame.texture or frame.cluster then
        -- defaults for textured nodes
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
  end

  -- refresh minimap
  pfMap:UpdateMinimap()

  -- update hidecluster detection
  if controlkey.pressed then
    hidecluster = MouseIsOver(WorldMapFrame)
  else
    hidecluster = nil
  end
end)

-- only hook for 3.3.5
if compat.client >= 30300 then
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

-- Attach cleanup handlers to tooltip hide events
for _, tip in ipairs({ GameTooltip, WorldMapTooltip }) do
  if tip and not tip.pfQuestCleanupHooked then
    tip:HookScript("OnHide", function()
      -- Clear cycling data only when the tooltip is really gone
      pfMap.altCycleData   = nil
      pfMap.altCheckEnabled = false
      pfMap.rightPressed    = false
      pfMap.altCycleDebounce = 0
    end)
    tip.pfQuestCleanupHooked = true
  end
end

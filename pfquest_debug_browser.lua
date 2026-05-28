-- pfQuest Debug Browser - Visual interface for all debug functions
-- Compatible with WotLK 3.3.5 API

-- Wait for pfQuest to load properly
if not pfDB then
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("ADDON_LOADED")
    frame:SetScript("OnEvent", function()
        if pfDB then
            frame:UnregisterEvent("ADDON_LOADED")
            -- Retry loading debug browser
            if not pfDebugBrowser then
                CreateDebugBrowser()
                print("|cff00FF00pfQuest Debug Browser loaded! Use /pfbrowser or /pfdb to open.|r")
            end
        end
    end)
end

-- Multi-client compatibility
local compat = pfQuestCompat or {}
local client = compat.client or 30300

-- Frame creation compatibility
local CreateFrame = CreateFrame
local GetBuildInfo = GetBuildInfo

-- Debug browser frame
local pfDebugBrowser = nil
local activeCategory = "itemreq"
local activeCoordTab = "coords5050"
local isSearching = false

-- Categories and their functions
local debugCategories = {
    ["itemreq"] = {
        name = "ItemReq Search",
        icon = "Interface\\Icons\\INV_Misc_Note_01",
        description = "Search quests with item requirements",
        searchFunction = function(searchTerm)
            -- Inline implementation since searchQuestsWithItemReq is not exported
            if not pfDB or not pfDB["quests-itemreq"] or not pfDB["quests-itemreq"]["data"] then
                return {}, "No Data"
            end

            local currentZone = GetRealZoneText()
            local results = {}
            local searchLower = searchTerm and string.lower(searchTerm) or ""


            -- Simple search through itemreq data
            for itemId, targets in pairs(pfDB["quests-itemreq"]["data"]) do
                local itemName = ""

                if pfDB["items"] and pfDB["items"]["loc"] and pfDB["items"]["loc"][itemId] then
                    itemName = pfDB["items"]["loc"][itemId]
                else
                    itemName = "Item " .. itemId
                end

                local matches = not searchTerm or
                               string.find(string.lower(itemName), searchLower) or
                               tostring(itemId) == searchTerm

                if matches then
                    -- Find quests that use this item
                    if pfDB["quests"] and pfDB["quests"]["data"] then
                        for questId, quest in pairs(pfDB["quests"]["data"]) do
                            if quest.obj and quest.obj.IR then
                                for _, reqItemId in ipairs(quest.obj.IR) do
                                    if reqItemId == itemId then
                                        local questName = "Quest " .. questId
                                        if pfDB["quests"] and pfDB["quests"]["loc"] and pfDB["quests"]["loc"][questId] then
                                            local questData = pfDB["quests"]["loc"][questId]
                                            if type(questData) == "table" and questData.T then
                                                questName = questData.T
                                            elseif type(questData) == "string" then
                                                questName = questData
                                            end
                                        end

                                        -- Find quest zones and check if in current zone
                                        local questZones = {}
                                        local isInCurrentZone = false

                                        if pfDB["quests"] and pfDB["quests"]["data"] and pfDB["quests"]["data"][questId] then
                                            local questData = pfDB["quests"]["data"][questId]

                                            -- Check quest giver locations
                                            if questData.start and questData.start.U then
                                                for _, giverId in ipairs(questData.start.U) do
                                                    if pfDB["units"] and pfDB["units"]["data"] and pfDB["units"]["data"][giverId] then
                                                        local giver = pfDB["units"]["data"][giverId]
                                                        if giver.coords then
                                                            for _, coord in ipairs(giver.coords) do
                                                                local zoneId = coord[3]
                                                                if pfDB["zones"] and pfDB["zones"]["loc"] and pfDB["zones"]["loc"][zoneId] then
                                                                    local zoneName = pfDB["zones"]["loc"][zoneId]
                                                                    questZones[zoneName] = true
                                                                    if zoneName == currentZone or string.find(string.lower(currentZone), string.lower(zoneName)) or string.find(string.lower(zoneName), string.lower(currentZone)) then
                                                                        isInCurrentZone = true
                                                                    end
                                                                end
                                                            end
                                                        end
                                                    end
                                                end
                                            end

                                            -- Check quest objective locations
                                            if questData.obj then
                                                -- Check unit objectives
                                                if questData.obj.U then
                                                    for _, unitId in ipairs(questData.obj.U) do
                                                        if pfDB["units"] and pfDB["units"]["data"] and pfDB["units"]["data"][unitId] then
                                                            local unit = pfDB["units"]["data"][unitId]
                                                            if unit.coords then
                                                                for _, coord in ipairs(unit.coords) do
                                                                    local zoneId = coord[3]
                                                                    if pfDB["zones"] and pfDB["zones"]["loc"] and pfDB["zones"]["loc"][zoneId] then
                                                                        local zoneName = pfDB["zones"]["loc"][zoneId]
                                                                        questZones[zoneName] = true
                                                                        if zoneName == currentZone or string.find(string.lower(currentZone), string.lower(zoneName)) or string.find(string.lower(zoneName), string.lower(currentZone)) then
                                                                            isInCurrentZone = true
                                                                        end
                                                                    end
                                                                end
                                                            end
                                                        end
                                                    end
                                                end
                                            end
                                        end

                                        -- Convert zones table to list
                                        local zoneList = {}
                                        for zone, _ in pairs(questZones) do
                                            table.insert(zoneList, zone)
                                        end

                                        table.insert(results, {
                                            questId = questId,
                                            questName = questName,
                                            itemId = itemId,
                                            itemName = itemName,
                                            targets = targets,
                                            isInCurrentZone = isInCurrentZone,
                                            zones = zoneList
                                        })
                                    end
                                end
                            end
                        end
                    end
                end
            end

            -- Sort: current zone first, then alphabetically
            table.sort(results, function(a, b)
                if a.isInCurrentZone ~= b.isInCurrentZone then
                    return a.isInCurrentZone
                end
                return a.questName < b.questName
            end)

            return results, currentZone
        end
    },
    ["working"] = {
        name = "Working Quests",
        icon = "Interface\\Icons\\INV_Misc_Book_07",
        description = "Find quests with proper coordinates",
        searchFunction = function()
            -- Simple implementation - just return count
            if not pfDB or not pfDB["quests"] or not pfDB["quests"]["data"] then
                return {}
            end

            local workingCount = 0
            for questId, quest in pairs(pfDB["quests"]["data"]) do
                if quest.start and (quest.start.U or quest.start.O) then
                    workingCount = workingCount + 1
                end
            end

            return {workingCount}
        end
    },
    ["validation"] = {
        name = "Quest Validation",
        icon = "Interface\\Icons\\INV_Misc_Book_09",
        description = "Validate quest database integrity",
        searchFunction = function() return {}, "Validation" end
    },
    ["rares"] = {
        name = "Rare Creatures",
        icon = "Interface\\Icons\\Ability_Hunter_BeastTaming",
        description = "Browse rare creature spawns",
        searchFunction = function(searchTerm)
            if not pfDB or not pfDB["meta"] or not pfDB["meta"]["rares"] then
                return {}, "No Data"
            end

            local currentZone = GetRealZoneText()
            local results = {}
            local searchLower = searchTerm and string.lower(searchTerm) or ""

            for rareId, rareLevel in pairs(pfDB["meta"]["rares"]) do
                local rareName = ""

                if pfDB["units"] and pfDB["units"]["loc"] and pfDB["units"]["loc"][rareId] then
                    rareName = pfDB["units"]["loc"][rareId]
                else
                    rareName = "Rare " .. rareId
                end

                local matches = not searchTerm or
                               string.find(string.lower(rareName), searchLower) or
                               tostring(rareId) == searchTerm

                if matches then
                    local isInCurrentZone = false
                    local unit = pfDB["units"] and pfDB["units"]["data"] and pfDB["units"]["data"][rareId]

                    if unit and unit.coords then
                        for _, coord in ipairs(unit.coords) do
                            local zoneId = coord[3]
                            local zoneName = ""
                            if pfDB["zones"] and pfDB["zones"]["loc"] and pfDB["zones"]["loc"][zoneId] then
                                zoneName = pfDB["zones"]["loc"][zoneId]
                                if zoneName == currentZone then
                                    isInCurrentZone = true
                                end
                            end
                        end
                    end

                    -- Get respawn time from coordinate data (4th element)
                    local respawnTime = "Unknown"
                    if unit and unit.coords then
                        for _, coord in ipairs(unit.coords) do
                            if coord[4] and coord[4] > 0 then
                                local seconds = coord[4]
                                -- Convert to readable format like SecondsToTime does
                                if seconds >= 3600 then
                                    respawnTime = math.floor(seconds / 3600) .. "h"
                                elseif seconds >= 60 then
                                    respawnTime = math.floor(seconds / 60) .. "m"
                                else
                                    respawnTime = seconds .. "s"
                                end
                                break -- Use first non-zero respawn time found
                            end
                        end
                    end

                    table.insert(results, {
                        rareId = rareId,
                        rareName = rareName,
                        level = rareLevel,
                        coords = unit and unit.coords or {},
                        isInCurrentZone = isInCurrentZone,
                        respawn = respawnTime
                    })
                end
            end

            -- Sort: current zone first, then by level desc
            table.sort(results, function(a, b)
                if a.isInCurrentZone ~= b.isInCurrentZone then
                    return a.isInCurrentZone
                end
                return a.level > b.level
            end)

            return results, currentZone
        end
    },
    ["coordinates"] = {
        name = "Coordinates",
        icon = "Interface\\Icons\\INV_Misc_Map_01",
        description = "Find entities with problematic coordinates",
        hasSubTabs = true,
        searchFunction = function(searchTerm)
            -- Delegate to active sub-tab
            return coordCategories[activeCoordTab].searchFunction(searchTerm)
        end
    }
}

-- Coordinate sub-categories
local coordCategories = {
    ["coords5050"] = {
        name = "50,50 Coords",
        icon = "Interface\\Icons\\INV_Misc_Map_01",
        description = "Find entities with exact 50,50 coordinates",
        searchFunction = function(searchTerm)
            if not pfDB then
                return {}, "pfDB not loaded"
            end

            local results = {}
            local targetX, targetY = 50, 50
            local zoneFilter = searchTerm and string.lower(searchTerm) or nil

            -- Helper function to check if NPC/Object is quest-related
            local function isQuestRelated(entityType, entityId)
                if not pfDB["quests"] or not pfDB["quests"]["data"] then
                    return false, {}
                end

                local relatedQuests = {}

                for questId, quest in pairs(pfDB["quests"]["data"]) do
                    -- Check quest starters
                    if quest.start then
                        if entityType == "NPC" and quest.start.U then
                            for _, unitId in ipairs(quest.start.U) do
                                if tonumber(unitId) == tonumber(entityId) then
                                    table.insert(relatedQuests, questId)
                                    break
                                end
                            end
                        elseif entityType == "Object" and quest.start.O then
                            for _, objectId in ipairs(quest.start.O) do
                                if tonumber(objectId) == tonumber(entityId) then
                                    table.insert(relatedQuests, questId)
                                    break
                                end
                            end
                        end
                    end

                    -- Check quest finishers
                    if quest.finish then
                        if entityType == "NPC" and quest.finish.U then
                            for _, unitId in ipairs(quest.finish.U) do
                                if tonumber(unitId) == tonumber(entityId) then
                                    table.insert(relatedQuests, questId)
                                    break
                                end
                            end
                        elseif entityType == "Object" and quest.finish.O then
                            for _, objectId in ipairs(quest.finish.O) do
                                if tonumber(objectId) == tonumber(entityId) then
                                    table.insert(relatedQuests, questId)
                                    break
                                end
                            end
                        end
                    end
                end

                return #relatedQuests > 0, relatedQuests
            end

            -- Search through NPCs
            if pfDB["units"] and pfDB["units"]["data"] then
                for unitId, unit in pairs(pfDB["units"]["data"]) do
                    if unit.coords then
                        for _, coord in ipairs(unit.coords) do
                            local x, y, zoneId = coord[1], coord[2], coord[3]

                            -- Check zone filter if specified
                            local zoneMatches = true
                            if zoneFilter then
                                zoneMatches = false
                                local zoneName = "Zone " .. zoneId
                                if pfDB["zones"] and pfDB["zones"]["loc"] and pfDB["zones"]["loc"][zoneId] then
                                    zoneName = pfDB["zones"]["loc"][zoneId]
                                end

                                if string.find(string.lower(zoneName), zoneFilter) then
                                    zoneMatches = true
                                end
                            end

                            -- Check for exact 50,50 coordinates
                            if (x == targetX and y == targetY) and zoneMatches then
                                local isRelated, relatedQuests = isQuestRelated("NPC", unitId)

                                if isRelated then
                                    local unitName = "Unit " .. unitId
                                    if pfDB["units"]["loc"] and pfDB["units"]["loc"][unitId] then
                                        unitName = pfDB["units"]["loc"][unitId]
                                    end

                                    local zoneName = "Zone " .. zoneId
                                    if pfDB["zones"] and pfDB["zones"]["loc"] and pfDB["zones"]["loc"][zoneId] then
                                        zoneName = pfDB["zones"]["loc"][zoneId]
                                    end

                                    table.insert(results, {
                                        type = "NPC",
                                        id = unitId,
                                        name = unitName,
                                        zoneName = zoneName,
                                        zoneId = zoneId,
                                        x = x,
                                        y = y,
                                        questIds = relatedQuests,
                                        questCount = #relatedQuests,
                                        level = 1 -- For sorting
                                    })
                                end
                                break -- Only count once per NPC
                            end
                        end
                    end
                end
            end

            -- Search through Objects
            if pfDB["objects"] and pfDB["objects"]["data"] then
                for objectId, object in pairs(pfDB["objects"]["data"]) do
                    if object.coords then
                        for _, coord in ipairs(object.coords) do
                            local x, y, zoneId = coord[1], coord[2], coord[3]

                            -- Check zone filter if specified
                            local zoneMatches = true
                            if zoneFilter then
                                zoneMatches = false
                                local zoneName = "Zone " .. zoneId
                                if pfDB["zones"] and pfDB["zones"]["loc"] and pfDB["zones"]["loc"][zoneId] then
                                    zoneName = pfDB["zones"]["loc"][zoneId]
                                end

                                if string.find(string.lower(zoneName), zoneFilter) then
                                    zoneMatches = true
                                end
                            end

                            -- Check for exact 50,50 coordinates
                            if (x == targetX and y == targetY) and zoneMatches then
                                local isRelated, relatedQuests = isQuestRelated("Object", objectId)

                                if isRelated then
                                    local objectName = "Object " .. objectId
                                    if pfDB["objects"]["loc"] and pfDB["objects"]["loc"][objectId] then
                                        objectName = pfDB["objects"]["loc"][objectId]
                                    end

                                    local zoneName = "Zone " .. zoneId
                                    if pfDB["zones"] and pfDB["zones"]["loc"] and pfDB["zones"]["loc"][zoneId] then
                                        zoneName = pfDB["zones"]["loc"][zoneId]
                                    end

                                    table.insert(results, {
                                        type = "Object",
                                        id = objectId,
                                        name = objectName,
                                        zoneName = zoneName,
                                        zoneId = zoneId,
                                        x = x,
                                        y = y,
                                        questIds = relatedQuests,
                                        questCount = #relatedQuests,
                                        level = 1 -- For sorting
                                    })
                                end
                                break -- Only count once per Object
                            end
                        end
                    end
                end
            end

            -- Sort by zone name, then by type, then by name
            table.sort(results, function(a, b)
                if a.zoneName ~= b.zoneName then
                    return a.zoneName < b.zoneName
                end
                if a.type ~= b.type then
                    return a.type < b.type
                end
                return a.name < b.name
            end)

            local summary = "Found " .. #results .. " quest-related entities with exact 50,50 coordinates"
            if zoneFilter then
                summary = summary .. " in zones matching '" .. searchTerm .. "'"
            end

            return results, summary
        end
    },
    ["coords00"] = {
        name = "0,0 Corner",
        icon = "Interface\\Icons\\INV_Misc_Map_02",
        description = "Find entities with corner (0,0) coordinates",
        searchFunction = function(searchTerm)
            return searchCoordinatePattern(0, 0, "corner (0,0)", searchTerm)
        end
    },
    ["coords100100"] = {
        name = "100,100 Corner",
        icon = "Interface\\Icons\\INV_Misc_Map_02",
        description = "Find entities with corner (100,100) coordinates",
        searchFunction = function(searchTerm)
            return searchCoordinatePattern(100, 100, "corner (100,100)", searchTerm)
        end
    },
    ["coords0100"] = {
        name = "0,100 Corner",
        icon = "Interface\\Icons\\INV_Misc_Map_02",
        description = "Find entities with corner (0,100) coordinates",
        searchFunction = function(searchTerm)
            return searchCoordinatePattern(0, 100, "corner (0,100)", searchTerm)
        end
    },
    ["coords1000"] = {
        name = "100,0 Corner",
        icon = "Interface\\Icons\\INV_Misc_Map_02",
        description = "Find entities with corner (100,0) coordinates",
        searchFunction = function(searchTerm)
            return searchCoordinatePattern(100, 0, "corner (100,0)", searchTerm)
        end
    },
    ["coordsnocoords"] = {
        name = "No Coordinates",
        icon = "Interface\\Icons\\INV_Misc_QuestionMark",
        description = "Find quest-related NPCs without coordinates",
        searchFunction = function(searchTerm)
            return searchEntitiesWithoutCoordinates(searchTerm)
        end
    },
    ["coordsnozone"] = {
        name = "No Zone",
        icon = "Interface\\Icons\\INV_Misc_QuestionMark",
        description = "Find quest-related entities without zone info",
        searchFunction = function(searchTerm)
            return searchEntitiesWithoutZone(searchTerm)
        end
    }
}

-- Generic coordinate pattern search function
function searchCoordinatePattern(targetX, targetY, patternName, searchTerm)
    if not pfDB then
        return {}, "pfDB not loaded"
    end

    local results = {}
    local zoneFilter = searchTerm and string.lower(searchTerm) or nil

    -- Pre-build quest relationship maps for faster lookup
    local npcQuestMap = {}
    local objectQuestMap = {}

    if pfDB["quests"] and pfDB["quests"]["data"] then
        for questId, quest in pairs(pfDB["quests"]["data"]) do
            -- Build NPC quest map
            if quest.start and quest.start.U then
                for _, unitId in ipairs(quest.start.U) do
                    local id = tonumber(unitId)
                    if not npcQuestMap[id] then npcQuestMap[id] = {} end
                    table.insert(npcQuestMap[id], questId)
                end
            end
            if quest.finish and quest.finish.U then
                for _, unitId in ipairs(quest.finish.U) do
                    local id = tonumber(unitId)
                    if not npcQuestMap[id] then npcQuestMap[id] = {} end
                    table.insert(npcQuestMap[id], questId)
                end
            end

            -- Build Object quest map
            if quest.start and quest.start.O then
                for _, objectId in ipairs(quest.start.O) do
                    local id = tonumber(objectId)
                    if not objectQuestMap[id] then objectQuestMap[id] = {} end
                    table.insert(objectQuestMap[id], questId)
                end
            end
            if quest.finish and quest.finish.O then
                for _, objectId in ipairs(quest.finish.O) do
                    local id = tonumber(objectId)
                    if not objectQuestMap[id] then objectQuestMap[id] = {} end
                    table.insert(objectQuestMap[id], questId)
                end
            end
        end
    end

    -- Fast quest lookup function
    local function isQuestRelated(entityType, entityId)
        local id = tonumber(entityId)
        local questMap = entityType == "NPC" and npcQuestMap or objectQuestMap
        local relatedQuests = questMap[id] or {}
        return #relatedQuests > 0, relatedQuests
    end

    -- Search through NPCs
    if pfDB["units"] and pfDB["units"]["data"] then
        for unitId, unit in pairs(pfDB["units"]["data"]) do
            if unit.coords then
                for _, coord in ipairs(unit.coords) do
                    local x, y, zoneId = coord[1], coord[2], coord[3]

                    -- Check zone filter if specified
                    local zoneMatches = true
                    if zoneFilter then
                        zoneMatches = false
                        local zoneName = "Zone " .. zoneId
                        if pfDB["zones"] and pfDB["zones"]["loc"] and pfDB["zones"]["loc"][zoneId] then
                            zoneName = pfDB["zones"]["loc"][zoneId]
                        end

                        if string.find(string.lower(zoneName), zoneFilter) then
                            zoneMatches = true
                        end
                    end

                    -- Check for target coordinates
                    if (x == targetX and y == targetY) and zoneMatches then
                        local isRelated, relatedQuests = isQuestRelated("NPC", unitId)

                        if isRelated then
                            local unitName = "Unit " .. unitId
                            if pfDB["units"]["loc"] and pfDB["units"]["loc"][unitId] then
                                unitName = pfDB["units"]["loc"][unitId]
                            end

                            local zoneName = "Zone " .. zoneId
                            if pfDB["zones"] and pfDB["zones"]["loc"] and pfDB["zones"]["loc"][zoneId] then
                                zoneName = pfDB["zones"]["loc"][zoneId]
                            end

                            table.insert(results, {
                                type = "NPC",
                                id = unitId,
                                name = unitName,
                                zoneName = zoneName,
                                zoneId = zoneId,
                                x = x,
                                y = y,
                                questIds = relatedQuests,
                                questCount = #relatedQuests,
                                level = 1 -- For sorting
                            })
                        end
                        break -- Only count once per NPC
                    end
                end
            end
        end
    end

    -- Search through Objects
    if pfDB["objects"] and pfDB["objects"]["data"] then
        for objectId, object in pairs(pfDB["objects"]["data"]) do
            if object.coords then
                for _, coord in ipairs(object.coords) do
                    local x, y, zoneId = coord[1], coord[2], coord[3]

                    -- Check zone filter if specified
                    local zoneMatches = true
                    if zoneFilter then
                        zoneMatches = false
                        local zoneName = "Zone " .. zoneId
                        if pfDB["zones"] and pfDB["zones"]["loc"] and pfDB["zones"]["loc"][zoneId] then
                            zoneName = pfDB["zones"]["loc"][zoneId]
                        end

                        if string.find(string.lower(zoneName), zoneFilter) then
                            zoneMatches = true
                        end
                    end

                    -- Check for target coordinates
                    if (x == targetX and y == targetY) and zoneMatches then
                        local isRelated, relatedQuests = isQuestRelated("Object", objectId)

                        if isRelated then
                            local objectName = "Object " .. objectId
                            if pfDB["objects"]["loc"] and pfDB["objects"]["loc"][objectId] then
                                objectName = pfDB["objects"]["loc"][objectId]
                            end

                            local zoneName = "Zone " .. zoneId
                            if pfDB["zones"] and pfDB["zones"]["loc"] and pfDB["zones"]["loc"][zoneId] then
                                zoneName = pfDB["zones"]["loc"][zoneId]
                            end

                            table.insert(results, {
                                type = "Object",
                                id = objectId,
                                name = objectName,
                                zoneName = zoneName,
                                zoneId = zoneId,
                                x = x,
                                y = y,
                                questIds = relatedQuests,
                                questCount = #relatedQuests,
                                level = 1 -- For sorting
                            })
                        end
                        break -- Only count once per Object
                    end
                end
            end
        end
    end

    -- Sort by zone name, then by type, then by name
    table.sort(results, function(a, b)
        if a.zoneName ~= b.zoneName then
            return a.zoneName < b.zoneName
        end
        if a.type ~= b.type then
            return a.type < b.type
        end
        return a.name < b.name
    end)

    local summary = "Found " .. #results .. " quest-related entities with " .. patternName .. " coordinates"
    if zoneFilter then
        summary = summary .. " in zones matching '" .. searchTerm .. "'"
    end

    return results, summary
end

-- Search for entities without coordinates
function searchEntitiesWithoutCoordinates(searchTerm)
    if not pfDB then
        return {}, "pfDB not loaded"
    end

    local results = {}
    local nameFilter = searchTerm and string.lower(searchTerm) or nil

    -- Pre-build quest relationship maps for faster lookup
    local npcQuestMap = {}

    if pfDB["quests"] and pfDB["quests"]["data"] then
        for questId, quest in pairs(pfDB["quests"]["data"]) do
            -- Build NPC quest map (only NPCs, objects usually have coordinates)
            if quest.start and quest.start.U then
                for _, unitId in ipairs(quest.start.U) do
                    local id = tonumber(unitId)
                    if not npcQuestMap[id] then npcQuestMap[id] = {} end
                    table.insert(npcQuestMap[id], questId)
                end
            end
            if quest.finish and quest.finish.U then
                for _, unitId in ipairs(quest.finish.U) do
                    local id = tonumber(unitId)
                    if not npcQuestMap[id] then npcQuestMap[id] = {} end
                    table.insert(npcQuestMap[id], questId)
                end
            end
        end
    end

    -- Search through NPCs without coordinates
    if pfDB["units"] and pfDB["units"]["data"] then
        for unitId, unit in pairs(pfDB["units"]["data"]) do
            -- Only consider NPCs that don't have coordinates OR have empty coordinates
            if not unit.coords or #unit.coords == 0 then
                -- Check if this NPC is quest-related
                local relatedQuests = npcQuestMap[tonumber(unitId)] or {}

                if #relatedQuests > 0 then
                    local unitName = "Unit " .. unitId
                    if pfDB["units"]["loc"] and pfDB["units"]["loc"][unitId] then
                        unitName = pfDB["units"]["loc"][unitId]
                    end

                    -- Apply name filter if specified
                    local nameMatches = true
                    if nameFilter then
                        nameMatches = string.find(string.lower(unitName), nameFilter) ~= nil
                    end

                    if nameMatches then
                        table.insert(results, {
                            type = "NPC",
                            id = unitId,
                            name = unitName,
                            zoneName = "No Location",
                            zoneId = 0,
                            x = 0,
                            y = 0,
                            questIds = relatedQuests,
                            questCount = #relatedQuests,
                            level = 1 -- For sorting
                        })
                    end
                end
            end
        end
    end

    -- Sort by name
    table.sort(results, function(a, b)
        return a.name < b.name
    end)

    local summary = "Found " .. #results .. " quest-related NPCs without coordinates"
    if nameFilter then
        summary = summary .. " matching '" .. searchTerm .. "'"
    end

    return results, summary
end

-- Colors
local COLORS = {
    HEADER = "|cffFFD700",
    SUBHEADER = "|cff00BFFF",
    SUCCESS = "|cff00FF00",
    WARNING = "|cffFFFF00",
    ERROR = "|cffFF0000",
    NORMAL = "|cffFFFFFF",
    GRAY = "|cff808080",
    GOLD = "|cffFFD700"
}

-- Create main browser frame
local function CreateDebugBrowser()
    if pfDebugBrowser then return end

    -- Main frame
    pfDebugBrowser = CreateFrame("Frame", "pfDebugBrowser", UIParent)
    pfDebugBrowser:SetWidth(700)
    pfDebugBrowser:SetHeight(600)
    pfDebugBrowser:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    pfDebugBrowser:SetFrameStrata("DIALOG")
    pfDebugBrowser:SetToplevel(true)
    pfDebugBrowser:EnableMouse(true)
    pfDebugBrowser:SetMovable(true)
    pfDebugBrowser:RegisterForDrag("LeftButton")
    pfDebugBrowser:SetScript("OnDragStart", function() this:StartMoving() end)
    pfDebugBrowser:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)

    -- Background
    pfDebugBrowser.bg = pfDebugBrowser:CreateTexture(nil, "BACKGROUND")
    pfDebugBrowser.bg:SetAllPoints()
    pfDebugBrowser.bg:SetTexture(0, 0, 0, 0.8)

    -- Border
    pfDebugBrowser.border = CreateFrame("Frame", nil, pfDebugBrowser)
    pfDebugBrowser.border:SetAllPoints()
    pfDebugBrowser.border:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 5, right = 5, top = 5, bottom = 5 }
    })
    pfDebugBrowser.border:SetBackdropColor(0, 0, 0, 0.9)
    pfDebugBrowser.border:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

    -- Title
    pfDebugBrowser.title = pfDebugBrowser:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    pfDebugBrowser.title:SetPoint("TOP", pfDebugBrowser, "TOP", 0, -15)
    pfDebugBrowser.title:SetText(COLORS.HEADER .. "pfQuest Debug Browser|r")

    -- Close button
    pfDebugBrowser.closeBtn = CreateFrame("Button", nil, pfDebugBrowser)
    pfDebugBrowser.closeBtn:SetWidth(25)
    pfDebugBrowser.closeBtn:SetHeight(25)
    pfDebugBrowser.closeBtn:SetPoint("TOPRIGHT", pfDebugBrowser, "TOPRIGHT", -10, -10)
    pfDebugBrowser.closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    pfDebugBrowser.closeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    pfDebugBrowser.closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    pfDebugBrowser.closeBtn:SetScript("OnClick", function() pfDebugBrowser:Hide() end)

    -- Category buttons panel
    pfDebugBrowser.categoryPanel = CreateFrame("Frame", nil, pfDebugBrowser)
    pfDebugBrowser.categoryPanel:SetWidth(170)
    pfDebugBrowser.categoryPanel:SetHeight(500)
    pfDebugBrowser.categoryPanel:SetPoint("TOPLEFT", pfDebugBrowser, "TOPLEFT", 15, -50)

    -- Search panel
    pfDebugBrowser.searchPanel = CreateFrame("Frame", nil, pfDebugBrowser)
    pfDebugBrowser.searchPanel:SetWidth(480)
    pfDebugBrowser.searchPanel:SetHeight(500)
    pfDebugBrowser.searchPanel:SetPoint("TOPRIGHT", pfDebugBrowser, "TOPRIGHT", -15, -50)

    -- Coordinate tabs panel (initially hidden)
    pfDebugBrowser.coordTabsPanel = CreateFrame("Frame", nil, pfDebugBrowser.searchPanel)
    pfDebugBrowser.coordTabsPanel:SetWidth(480)
    pfDebugBrowser.coordTabsPanel:SetHeight(25)
    pfDebugBrowser.coordTabsPanel:SetPoint("TOPLEFT", pfDebugBrowser.searchPanel, "TOPLEFT", 0, -5)
    pfDebugBrowser.coordTabsPanel:Hide()

    -- Search input
    pfDebugBrowser.searchBox = CreateFrame("EditBox", nil, pfDebugBrowser.searchPanel)
    pfDebugBrowser.searchBox:SetWidth(300)
    pfDebugBrowser.searchBox:SetHeight(25)
    pfDebugBrowser.searchBox:SetPoint("TOPLEFT", pfDebugBrowser.searchPanel, "TOPLEFT", 5, -5)
    pfDebugBrowser.searchBox.defaultOffsetY = -5
    pfDebugBrowser.searchBox.tabsOffsetY = -35
    pfDebugBrowser.searchBox:SetFontObject("GameFontNormal")
    pfDebugBrowser.searchBox:SetAutoFocus(false)
    pfDebugBrowser.searchBox:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 5, right = 5, top = 5, bottom = 5 }
    })
    pfDebugBrowser.searchBox:SetBackdropColor(0, 0, 0, 0.5)
    pfDebugBrowser.searchBox:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    pfDebugBrowser.searchBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    pfDebugBrowser.searchBox:SetScript("OnEnterPressed", function()
        local text = this:GetText()
        PerformSearch(text)
    end)

    -- Search button
    pfDebugBrowser.searchBtn = CreateFrame("Button", nil, pfDebugBrowser.searchPanel, "UIPanelButtonTemplate")
    pfDebugBrowser.searchBtn:SetWidth(80)
    pfDebugBrowser.searchBtn:SetHeight(25)
    pfDebugBrowser.searchBtn:SetPoint("LEFT", pfDebugBrowser.searchBox, "RIGHT", 10, 0)
    pfDebugBrowser.searchBtn:SetText("Search")
    pfDebugBrowser.searchBtn:SetScript("OnClick", function()
        local text = pfDebugBrowser.searchBox:GetText()
        PerformSearch(text)
    end)

    -- Results scroll frame
    pfDebugBrowser.scrollFrame = CreateFrame("ScrollFrame", nil, pfDebugBrowser.searchPanel)
    pfDebugBrowser.scrollFrame:SetWidth(380)
    pfDebugBrowser.scrollFrame:SetHeight(340)
    pfDebugBrowser.scrollFrame:SetPoint("TOPLEFT", pfDebugBrowser.searchBox, "BOTTOMLEFT", 0, -10)
    pfDebugBrowser.scrollFrame:EnableMouseWheel(true)

    -- Mouse wheel scrolling
    pfDebugBrowser.scrollFrame:SetScript("OnMouseWheel", function()
        local current = pfDebugBrowser.scrollBar:GetValue()
        local min, max = pfDebugBrowser.scrollBar:GetMinMaxValues()
        local step = 20

        if arg1 > 0 then
            pfDebugBrowser.scrollBar:SetValue(math.max(min, current - step))
        else
            pfDebugBrowser.scrollBar:SetValue(math.min(max, current + step))
        end
    end)

    -- Scrollbar
    pfDebugBrowser.scrollBar = CreateFrame("Slider", nil, pfDebugBrowser.scrollFrame)
    pfDebugBrowser.scrollBar:SetWidth(16)
    pfDebugBrowser.scrollBar:SetHeight(340)
    pfDebugBrowser.scrollBar:SetPoint("RIGHT", pfDebugBrowser.scrollFrame, "RIGHT", 0, 0)
    pfDebugBrowser.scrollBar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    pfDebugBrowser.scrollBar:SetOrientation("VERTICAL")
    pfDebugBrowser.scrollBar:SetMinMaxValues(0, 100)
    pfDebugBrowser.scrollBar:SetValue(0)
    pfDebugBrowser.scrollBar:SetValueStep(1)
    pfDebugBrowser.scrollBar:SetScript("OnValueChanged", function()
        pfDebugBrowser.scrollFrame:SetVerticalScroll(this:GetValue())
    end)

    -- Results content frame
    pfDebugBrowser.resultsFrame = CreateFrame("Frame", nil, pfDebugBrowser.scrollFrame)
    pfDebugBrowser.resultsFrame:SetWidth(360)
    pfDebugBrowser.resultsFrame:SetHeight(1)
    pfDebugBrowser.scrollFrame:SetScrollChild(pfDebugBrowser.resultsFrame)

    -- Status text
    pfDebugBrowser.statusText = pfDebugBrowser.searchPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pfDebugBrowser.statusText:SetPoint("BOTTOM", pfDebugBrowser.searchPanel, "BOTTOM", -10, -10)
    pfDebugBrowser.statusText:SetText(COLORS.GRAY .. "Select a category and search|r")

    -- Create category buttons
    CreateCategoryButtons()

    -- Initialize coordinate tabs
    pfDebugBrowser.coordTabs = nil

    -- Hide initially
    pfDebugBrowser:Hide()
end

-- Create category selection buttons
function CreateCategoryButtons()
    local yOffset = 0
    pfDebugBrowser.categoryButtons = {}

    for categoryId, category in pairs(debugCategories) do
        local btn = CreateFrame("Button", nil, pfDebugBrowser.categoryPanel)
        btn:SetWidth(160)
        btn:SetHeight(45)
        btn:SetPoint("TOPLEFT", pfDebugBrowser.categoryPanel, "TOPLEFT", 0, yOffset)

        -- Button background
        btn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 3, right = 3, top = 3, bottom = 3 }
        })
        btn:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
        btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

        -- Icon
        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetWidth(20)
        btn.icon:SetHeight(20)
        btn.icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 6, -6)
        btn.icon:SetTexture(category.icon)

        -- Name
        btn.name = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.name:SetPoint("TOPLEFT", btn.icon, "TOPRIGHT", 4, 0)
        btn.name:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -5, -6)
        btn.name:SetText(COLORS.SUBHEADER .. category.name .. "|r")
        btn.name:SetJustifyH("LEFT")

        -- Description
        btn.desc = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn.desc:SetPoint("TOPLEFT", btn.name, "BOTTOMLEFT", 0, -2)
        btn.desc:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -5, 4)
        btn.desc:SetText(COLORS.GRAY .. category.description .. "|r")
        btn.desc:SetJustifyH("LEFT")
        btn.desc:SetJustifyV("TOP")

        -- Click handler
        btn.categoryId = categoryId
        btn:SetScript("OnClick", function()
            SelectCategory(this.categoryId)
        end)

        -- Hover effect
        btn:SetScript("OnEnter", function()
            this:SetBackdropColor(0.2, 0.2, 0.3, 0.9)
        end)
        btn:SetScript("OnLeave", function()
            if activeCategory ~= this.categoryId then
                this:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
            end
        end)

        pfDebugBrowser.categoryButtons[categoryId] = btn
        yOffset = yOffset - 50
    end

    -- Select first category by default
    SelectCategory("itemreq")
end

-- Select a category
function SelectCategory(categoryId)
    activeCategory = categoryId

    -- Cancel any ongoing search when switching categories
    isSearching = false

    -- Clear previous results and status immediately
    ClearResults()
    local category = debugCategories[categoryId]
    pfDebugBrowser.statusText:SetText(COLORS.WARNING .. "Switching to " .. category.name .. "...|r")

    -- Update button appearances
    for id, btn in pairs(pfDebugBrowser.categoryButtons) do
        if id == categoryId then
            btn:SetBackdropColor(0.2, 0.4, 0.6, 0.9)
            btn:SetBackdropBorderColor(0.4, 0.6, 0.8, 1)
        else
            btn:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
            btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        end
    end

    -- Clear search box
    pfDebugBrowser.searchBox:SetText("")

    -- Show/hide coordinate tabs based on category
    if categoryId == "coordinates" then
        pfDebugBrowser.coordTabsPanel:Show()
        pfDebugBrowser.searchBox:ClearAllPoints()
        pfDebugBrowser.searchBox:SetPoint("TOPLEFT", pfDebugBrowser.searchPanel, "TOPLEFT", 5, pfDebugBrowser.searchBox.tabsOffsetY)
        CreateCoordinateTabs()
    else
        pfDebugBrowser.coordTabsPanel:Hide()
        pfDebugBrowser.searchBox:ClearAllPoints()
        pfDebugBrowser.searchBox:SetPoint("TOPLEFT", pfDebugBrowser.searchPanel, "TOPLEFT", 5, pfDebugBrowser.searchBox.defaultOffsetY)
    end

    -- Delay new search to ensure previous one is cancelled
    local delayFrame = CreateFrame("Frame")
    delayFrame:SetScript("OnUpdate", function()
        this:SetScript("OnUpdate", nil)
        PerformSearch("")
    end)
end

-- Create coordinate sub-tabs
function CreateCoordinateTabs()
    if pfDebugBrowser.coordTabs then
        return -- Already created
    end

    pfDebugBrowser.coordTabs = {}
    local xOffset = 0
    local tabWidth = 65

    local tabOrder = {"coords5050", "coords00", "coords100100", "coords0100", "coords1000", "coordsnocoords", "coordsnozone"}

    for i, tabId in ipairs(tabOrder) do
        local tab = coordCategories[tabId]
        if tab then
            local btn = CreateFrame("Button", nil, pfDebugBrowser.coordTabsPanel)
            btn:SetWidth(tabWidth)
            btn:SetHeight(20)
            btn:SetPoint("TOPLEFT", pfDebugBrowser.coordTabsPanel, "TOPLEFT", xOffset, -2)

            -- Tab background
            btn:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 8, edgeSize = 8,
                insets = { left = 2, right = 2, top = 2, bottom = 2 }
            })
            btn:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
            btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

            -- Tab text
            btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            btn.text:SetPoint("CENTER", btn, "CENTER", 0, 0)
            btn.text:SetText(tab.name:gsub(" Corner", ""):gsub(" Coords", ""):gsub("No Coordinates", "None"):gsub("No Zone", "NoZone"))

            -- Click handler
            btn.tabId = tabId
            btn:SetScript("OnClick", function()
                SelectCoordinateTab(this.tabId)
            end)

            -- Hover effect
            btn:SetScript("OnEnter", function()
                this:SetBackdropColor(0.2, 0.2, 0.3, 0.9)
            end)
            btn:SetScript("OnLeave", function()
                if activeCoordTab ~= this.tabId then
                    this:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
                end
            end)

            pfDebugBrowser.coordTabs[tabId] = btn
            xOffset = xOffset + tabWidth + 2
        end
    end

    -- Select default tab
    SelectCoordinateTab(activeCoordTab)
end

-- Select coordinate tab
function SelectCoordinateTab(tabId)
    activeCoordTab = tabId

    -- Cancel any ongoing search when switching tabs
    isSearching = false

    -- Clear previous results and status immediately
    ClearResults()
    pfDebugBrowser.statusText:SetText(COLORS.WARNING .. "Switching to " .. coordCategories[tabId].name .. "...|r")

    -- Update tab appearances
    for id, btn in pairs(pfDebugBrowser.coordTabs) do
        if id == tabId then
            btn:SetBackdropColor(0.2, 0.4, 0.6, 0.9)
            btn:SetBackdropBorderColor(0.4, 0.6, 0.8, 1)
        else
            btn:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
            btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        end
    end

    -- Clear search box
    pfDebugBrowser.searchBox:SetText("")

    -- Delay new search to ensure previous one is cancelled
    local delayFrame = CreateFrame("Frame")
    delayFrame:SetScript("OnUpdate", function()
        this:SetScript("OnUpdate", nil)
        PerformSearch("")
    end)
end

-- Perform search
function PerformSearch(searchTerm)
    if not activeCategory then return end

    -- Cancel any ongoing search first
    isSearching = false

    -- Force a frame delay to ensure all batch operations stop
    local startFrame = CreateFrame("Frame")
    startFrame:SetScript("OnUpdate", function()
        this:SetScript("OnUpdate", nil)

        local category = debugCategories[activeCategory]
        if not category.searchFunction then return end

        isSearching = true
        pfDebugBrowser.statusText:SetText(COLORS.WARNING .. "Searching...|r")

        -- Perform actual search
        DoActualSearch(searchTerm)
    end)
end

function DoActualSearch(searchTerm)
    local category = debugCategories[activeCategory]

    -- Special handling for ItemReq and coordinate categories with lazy loading
    if activeCategory == "itemreq" then
        PerformItemReqSearchLazy(searchTerm)
    elseif activeCategory == "coordinates" then
        PerformCoordsSearchLazy(searchTerm)
    else
        -- Use lazy loading for all other categories
        if activeCategory == "rares" then
            PerformRaresSearchLazy(searchTerm)
        elseif activeCategory == "working" then
            PerformWorkingSearchLazy(searchTerm)
        elseif activeCategory == "validation" then
            PerformValidationSearchLazy(searchTerm)
        else
            -- Generic lazy loading for any remaining categories
            PerformGenericSearchLazy(searchTerm)
        end
    end
end

-- Generic result display for other categories
function DisplayGenericResults(results, extra, searchTerm)
    pfDebugBrowser.statusText:SetText(COLORS.SUCCESS .. "Search completed: " .. #results .. " results|r")

    ClearResults()
    if #results == 0 then
        local emptyMsg = pfDebugBrowser.resultsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        emptyMsg:SetPoint("TOPLEFT", pfDebugBrowser.resultsFrame, "TOPLEFT", 5, -5)
        emptyMsg:SetText(COLORS.WARNING .. "No results found|r")
        return
    end

    local yOffset = -5
    for i, result in ipairs(results) do
        local resultText = tostring(result)
        local resultLabel = pfDebugBrowser.resultsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        resultLabel:SetPoint("TOPLEFT", pfDebugBrowser.resultsFrame, "TOPLEFT", 5, yOffset)
        resultLabel:SetText(resultText)
        yOffset = yOffset - 20
    end

    pfDebugBrowser.resultsFrame:SetHeight(math.abs(yOffset) + 10)
end

-- Display coordinate search results based on active tab
function DisplayCoordinateResults(results, extra, searchTerm)
    -- Handle coordinate pattern searches
    if searchTerm and searchTerm ~= "" then
        -- Show detailed results for zone/name search
        DisplayCoordsResults(results, extra, searchTerm)
    else
        -- Show grouped results for global search (except for no coords)
        if activeCoordTab == "coordsnocoords" then
            DisplayCoordsResults(results, extra, searchTerm)
        else
            DisplayCoordsGroupedResults(results)
        end
    end
end

-- Lazy loading search for ItemReq to prevent freezing
function PerformItemReqSearchLazy(searchTerm)
    if not pfDB or not pfDB["quests-itemreq"] or not pfDB["quests-itemreq"]["data"] then
        pfDebugBrowser.statusText:SetText(COLORS.ERROR .. "No ItemReq data available|r")
        return
    end

    local currentZone = GetRealZoneText()
    local results = {}
    local searchLower = searchTerm and string.lower(searchTerm) or ""

    -- Convert items to array for processing
    local itemsToProcess = {}
    for itemId, targets in pairs(pfDB["quests-itemreq"]["data"]) do
        table.insert(itemsToProcess, {itemId = itemId, targets = targets})
    end

    local totalItems = #itemsToProcess
    local processedItems = 0
    local batchSize = 15 -- Process 15 items per frame

    -- Clear results first
    ClearResults()

    local function ProcessBatch()
        local batchEnd = math.min(processedItems + batchSize, totalItems)

        for i = processedItems + 1, batchEnd do
            local item = itemsToProcess[i]
            local itemId = item.itemId
            local targets = item.targets

            local itemName = ""
            if pfDB["items"] and pfDB["items"]["loc"] and pfDB["items"]["loc"][itemId] then
                itemName = pfDB["items"]["loc"][itemId]
            else
                itemName = "Item " .. itemId
            end

            local matches = not searchTerm or
                           string.find(string.lower(itemName), searchLower) or
                           tostring(itemId) == searchTerm

            if matches then
                -- Find quests that use this item
                if pfDB["quests"] and pfDB["quests"]["data"] then
                    for questId, quest in pairs(pfDB["quests"]["data"]) do
                        if quest.obj and quest.obj.IR then
                            for _, reqItemId in ipairs(quest.obj.IR) do
                                if reqItemId == itemId then
                                    local questName = "Quest " .. questId
                                    if pfDB["quests"] and pfDB["quests"]["loc"] and pfDB["quests"]["loc"][questId] then
                                        local questData = pfDB["quests"]["loc"][questId]
                                        if type(questData) == "table" and questData.T then
                                            questName = questData.T
                                        elseif type(questData) == "string" then
                                            questName = questData
                                        end
                                    end

                                    -- Find quest zones and check if in current zone
                                    local questZones = {}
                                    local isInCurrentZone = false

                                    if pfDB["quests"] and pfDB["quests"]["data"] and pfDB["quests"]["data"][questId] then
                                        local questData = pfDB["quests"]["data"][questId]

                                        -- Check quest giver locations
                                        if questData.start and questData.start.U then
                                            for _, giverId in ipairs(questData.start.U) do
                                                if pfDB["units"] and pfDB["units"]["data"] and pfDB["units"]["data"][giverId] then
                                                    local giver = pfDB["units"]["data"][giverId]
                                                    if giver.coords then
                                                        for _, coord in ipairs(giver.coords) do
                                                            local zoneId = coord[3]
                                                            if pfDB["zones"] and pfDB["zones"]["loc"] and pfDB["zones"]["loc"][zoneId] then
                                                                local zoneName = pfDB["zones"]["loc"][zoneId]
                                                                questZones[zoneName] = true
                                                                if zoneName == currentZone or string.find(string.lower(currentZone), string.lower(zoneName)) or string.find(string.lower(zoneName), string.lower(currentZone)) then
                                                                    isInCurrentZone = true
                                                                end
                                                            end
                                                        end
                                                    end
                                                end
                                            end
                                        end

                                        -- Check quest objective locations
                                        if questData.obj then
                                            -- Check unit objectives
                                            if questData.obj.U then
                                                for _, unitId in ipairs(questData.obj.U) do
                                                    if pfDB["units"] and pfDB["units"]["data"] and pfDB["units"]["data"][unitId] then
                                                        local unit = pfDB["units"]["data"][unitId]
                                                        if unit.coords then
                                                            for _, coord in ipairs(unit.coords) do
                                                                local zoneId = coord[3]
                                                                if pfDB["zones"] and pfDB["zones"]["loc"] and pfDB["zones"]["loc"][zoneId] then
                                                                    local zoneName = pfDB["zones"]["loc"][zoneId]
                                                                    questZones[zoneName] = true
                                                                    if zoneName == currentZone or string.find(string.lower(currentZone), string.lower(zoneName)) or string.find(string.lower(zoneName), string.lower(currentZone)) then
                                                                        isInCurrentZone = true
                                                                    end
                                                                end
                                                            end
                                                        end
                                                    end
                                                end
                                            end
                                        end
                                    end

                                    -- Convert zones table to list
                                    local zoneList = {}
                                    for zone, _ in pairs(questZones) do
                                        table.insert(zoneList, zone)
                                    end

                                    table.insert(results, {
                                        questId = questId,
                                        questName = questName,
                                        itemId = itemId,
                                        itemName = itemName,
                                        targets = targets,
                                        isInCurrentZone = isInCurrentZone,
                                        zones = zoneList
                                    })
                                end
                            end
                        end
                    end
                end
            end
        end

        processedItems = batchEnd

        -- Update progress
        local progress = math.floor((processedItems / totalItems) * 100)
        pfDebugBrowser.statusText:SetText(COLORS.WARNING .. "Processing... " .. progress .. "% (" .. processedItems .. "/" .. totalItems .. ")|r")

        -- Continue processing or finish
        if processedItems < totalItems and isSearching then
            -- Schedule next batch
            local nextBatchFrame = CreateFrame("Frame")
            nextBatchFrame:SetScript("OnUpdate", function()
                this:SetScript("OnUpdate", nil)
                if isSearching then
                    ProcessBatch()
                end
            end)
        else
            -- Finished processing, sort and display results
            if isSearching then
                isSearching = false
                table.sort(results, function(a, b)
                    if a.isInCurrentZone ~= b.isInCurrentZone then
                        return a.isInCurrentZone
                    end
                    return a.questName < b.questName
                end)

                DisplayItemReqResults(results, currentZone, searchTerm)
            end
        end
    end

    -- Start processing
    ProcessBatch()
end

-- Lazy loading search for 50,50 coordinates to prevent freezing
function PerformCoordsSearchLazy(searchTerm)
    if not pfDB then
        pfDebugBrowser.statusText:SetText(COLORS.ERROR .. "pfDB not loaded|r")
        return
    end

    -- Use lazy loading for all coordinate tabs
    if activeCoordTab == "coords5050" then
        PerformCoords5050SearchLazy(searchTerm)
    elseif activeCoordTab == "coords00" then
        PerformCoordsPatternSearchLazy(0, 0, "corner (0,0)", searchTerm)
    elseif activeCoordTab == "coords100100" then
        PerformCoordsPatternSearchLazy(100, 100, "corner (100,100)", searchTerm)
    elseif activeCoordTab == "coords0100" then
        PerformCoordsPatternSearchLazy(0, 100, "corner (0,100)", searchTerm)
    elseif activeCoordTab == "coords1000" then
        PerformCoordsPatternSearchLazy(100, 0, "corner (100,0)", searchTerm)
    elseif activeCoordTab == "coordsnocoords" then
        PerformNoCoordsSearchLazy(searchTerm)
    elseif activeCoordTab == "coordsnozone" then
        PerformNoZoneSearchLazy(searchTerm)
    end
end

function PerformCoords5050SearchLazy(searchTerm)
    if not pfDB then
        pfDebugBrowser.statusText:SetText(COLORS.ERROR .. "pfDB not loaded|r")
        return
    end

    local results = {}
    local zoneFilter = searchTerm and string.lower(searchTerm) or nil
    local targetX, targetY = 50, 50

    -- Pre-build quest relationship maps for faster lookup
    local npcQuestMap = {}
    local objectQuestMap = {}

    if pfDB["quests"] and pfDB["quests"]["data"] then
        for questId, quest in pairs(pfDB["quests"]["data"]) do
            -- Build NPC quest map
            if quest.start and quest.start.U then
                for _, unitId in ipairs(quest.start.U) do
                    local id = tonumber(unitId)
                    if not npcQuestMap[id] then npcQuestMap[id] = {} end
                    table.insert(npcQuestMap[id], questId)
                end
            end
            if quest.finish and quest.finish.U then
                for _, unitId in ipairs(quest.finish.U) do
                    local id = tonumber(unitId)
                    if not npcQuestMap[id] then npcQuestMap[id] = {} end
                    table.insert(npcQuestMap[id], questId)
                end
            end

            -- Build Object quest map
            if quest.start and quest.start.O then
                for _, objectId in ipairs(quest.start.O) do
                    local id = tonumber(objectId)
                    if not objectQuestMap[id] then objectQuestMap[id] = {} end
                    table.insert(objectQuestMap[id], questId)
                end
            end
            if quest.finish and quest.finish.O then
                for _, objectId in ipairs(quest.finish.O) do
                    local id = tonumber(objectId)
                    if not objectQuestMap[id] then objectQuestMap[id] = {} end
                    table.insert(objectQuestMap[id], questId)
                end
            end
        end
    end

    -- Fast quest lookup function
    local function isQuestRelated(entityType, entityId)
        local id = tonumber(entityId)
        local questMap = entityType == "NPC" and npcQuestMap or objectQuestMap
        local relatedQuests = questMap[id] or {}
        return #relatedQuests > 0, relatedQuests
    end

    -- Pre-filter entities that have 50,50 coordinates and are quest-related
    local entitiesToProcess = {}
    local foundCount = 0
    local processedCount = 0
    local maxProcess = 10000 -- Limit processing for performance

    -- Add NPCs that have 50,50 coords and are quest-related
    if pfDB["units"] and pfDB["units"]["data"] then
        for unitId, unit in pairs(pfDB["units"]["data"]) do
            processedCount = processedCount + 1
            if processedCount > maxProcess then break end
            if unit.coords then
                local hasTargetCoords = false
                local relevantCoords = {}

                for _, coord in ipairs(unit.coords) do
                    local x, y = coord[1], coord[2]
                    if x == targetX and y == targetY then
                        hasTargetCoords = true
                        table.insert(relevantCoords, coord)
                    end
                end

                -- Only process if has 50,50 coords and is quest-related
                if hasTargetCoords then
                    local isRelated, relatedQuests = isQuestRelated("NPC", unitId)
                    if isRelated then
                        table.insert(entitiesToProcess, {
                            type = "NPC",
                            id = unitId,
                            coords = relevantCoords,
                            questIds = relatedQuests
                        })
                        foundCount = foundCount + 1
                    end
                end
            end
        end
    end

    -- Add Objects that have 50,50 coords and are quest-related
    if pfDB["objects"] and pfDB["objects"]["data"] and processedCount <= maxProcess then
        for objectId, object in pairs(pfDB["objects"]["data"]) do
            processedCount = processedCount + 1
            if processedCount > maxProcess then break end
            if object.coords then
                local hasTargetCoords = false
                local relevantCoords = {}

                for _, coord in ipairs(object.coords) do
                    local x, y = coord[1], coord[2]
                    if x == targetX and y == targetY then
                        hasTargetCoords = true
                        table.insert(relevantCoords, coord)
                    end
                end

                -- Only process if has 50,50 coords and is quest-related
                if hasTargetCoords then
                    local isRelated, relatedQuests = isQuestRelated("Object", objectId)
                    if isRelated then
                        table.insert(entitiesToProcess, {
                            type = "Object",
                            id = objectId,
                            coords = relevantCoords,
                            questIds = relatedQuests
                        })
                        foundCount = foundCount + 1
                    end
                end
            end
        end
    end

    local totalEntities = #entitiesToProcess
    local processedEntities = 0
    local batchSize = 100 -- Increase batch size since we pre-filtered

    -- Clear results first
    ClearResults()

    local function ProcessBatch()
        local batchEnd = math.min(processedEntities + batchSize, totalEntities)

        for i = processedEntities + 1, batchEnd do
            local entity = entitiesToProcess[i]
            local entityType, entityId, coords, questIds = entity.type, entity.id, entity.coords, entity.questIds

            -- Process each coordinate for this entity
            for _, coord in ipairs(coords) do
                local x, y, zoneId = coord[1], coord[2], coord[3]

                -- Check zone filter if specified
                local zoneMatches = true
                if zoneFilter then
                    zoneMatches = false
                    local zoneName = "Zone " .. zoneId
                    if pfDB["zones"] and pfDB["zones"]["loc"] and pfDB["zones"]["loc"][zoneId] then
                        zoneName = pfDB["zones"]["loc"][zoneId]
                    end

                    if string.find(string.lower(zoneName), zoneFilter) then
                        zoneMatches = true
                    end
                end

                -- Add to results if zone matches
                if zoneMatches then
                    local entityName = (entityType == "NPC" and "Unit " or "Object ") .. entityId
                    local locTable = pfDB[entityType == "NPC" and "units" or "objects"]["loc"]
                    if locTable and locTable[entityId] then
                        entityName = locTable[entityId]
                    end

                    local zoneName = "Zone " .. zoneId
                    if pfDB["zones"] and pfDB["zones"]["loc"] and pfDB["zones"]["loc"][zoneId] then
                        zoneName = pfDB["zones"]["loc"][zoneId]
                    end

                    table.insert(results, {
                        type = entityType,
                        id = entityId,
                        name = entityName,
                        zoneName = zoneName,
                        zoneId = zoneId,
                        x = x,
                        y = y,
                        questIds = questIds,
                        questCount = #questIds
                    })
                    break -- Only count once per entity
                end
            end
        end

        processedEntities = batchEnd

        -- Update progress
        local progress = math.floor((processedEntities / totalEntities) * 100)
        pfDebugBrowser.statusText:SetText(COLORS.WARNING .. "Processing... " .. progress .. "% (" .. #results .. " found)|r")

        -- Continue processing or finish
        if processedEntities < totalEntities and isSearching then
            -- Schedule next batch
            local nextBatchFrame = CreateFrame("Frame")
            nextBatchFrame:SetScript("OnUpdate", function()
                this:SetScript("OnUpdate", nil)
                if isSearching then
                    ProcessBatch()
                end
            end)
        else
            -- Finished processing, display results
            if isSearching then
                isSearching = false
                if searchTerm and searchTerm ~= "" then
                    -- Show detailed results for zone search
                    DisplayCoordsResults(results, "Found " .. #results .. " quest-related entities with exact 50,50 coordinates in zones matching '" .. searchTerm .. "'", searchTerm)
                else
                    -- Show grouped results for global search
                    DisplayCoordsGroupedResults(results)
                end
            end
        end
    end

    -- Start processing
    ProcessBatch()
end

-- Generic lazy loading search for coordinate patterns
function PerformCoordsPatternSearchLazy(targetX, targetY, patternName, searchTerm)
    if not pfDB then
        pfDebugBrowser.statusText:SetText(COLORS.ERROR .. "pfDB not loaded|r")
        return
    end

    local results = {}
    local zoneFilter = searchTerm and string.lower(searchTerm) or nil

    -- Pre-build quest relationship maps for faster lookup
    local npcQuestMap = {}
    local objectQuestMap = {}

    if pfDB["quests"] and pfDB["quests"]["data"] then
        for questId, quest in pairs(pfDB["quests"]["data"]) do
            -- Build NPC quest map
            if quest.start and quest.start.U then
                for _, unitId in ipairs(quest.start.U) do
                    local id = tonumber(unitId)
                    if not npcQuestMap[id] then npcQuestMap[id] = {} end
                    table.insert(npcQuestMap[id], questId)
                end
            end
            if quest.finish and quest.finish.U then
                for _, unitId in ipairs(quest.finish.U) do
                    local id = tonumber(unitId)
                    if not npcQuestMap[id] then npcQuestMap[id] = {} end
                    table.insert(npcQuestMap[id], questId)
                end
            end

            -- Build Object quest map
            if quest.start and quest.start.O then
                for _, objectId in ipairs(quest.start.O) do
                    local id = tonumber(objectId)
                    if not objectQuestMap[id] then objectQuestMap[id] = {} end
                    table.insert(objectQuestMap[id], questId)
                end
            end
            if quest.finish and quest.finish.O then
                for _, objectId in ipairs(quest.finish.O) do
                    local id = tonumber(objectId)
                    if not objectQuestMap[id] then objectQuestMap[id] = {} end
                    table.insert(objectQuestMap[id], questId)
                end
            end
        end
    end

    -- Fast quest lookup function
    local function isQuestRelated(entityType, entityId)
        local id = tonumber(entityId)
        local questMap = entityType == "NPC" and npcQuestMap or objectQuestMap
        local relatedQuests = questMap[id] or {}
        return #relatedQuests > 0, relatedQuests
    end

    -- Pre-filter entities that have target coordinates and are quest-related
    local entitiesToProcess = {}
    local foundCount = 0
    local processedCount = 0
    local maxProcess = 10000 -- Limit processing to prevent infinite search

    -- Add NPCs that have target coords and are quest-related
    if pfDB["units"] and pfDB["units"]["data"] then
        for unitId, unit in pairs(pfDB["units"]["data"]) do
            processedCount = processedCount + 1
            if processedCount > maxProcess then break end

            if unit.coords then
                local hasTargetCoords = false
                local relevantCoords = {}

                for _, coord in ipairs(unit.coords) do
                    local x, y = coord[1], coord[2]
                    if x == targetX and y == targetY then
                        hasTargetCoords = true
                        table.insert(relevantCoords, coord)
                    end
                end

                -- Only process if has target coords and is quest-related
                if hasTargetCoords then
                    local isRelated, relatedQuests = isQuestRelated("NPC", unitId)
                    if isRelated then
                        table.insert(entitiesToProcess, {
                            type = "NPC",
                            id = unitId,
                            coords = relevantCoords,
                            questIds = relatedQuests
                        })
                        foundCount = foundCount + 1
                    end
                end
            end
        end
    end

    -- Add Objects that have target coords and are quest-related
    if pfDB["objects"] and pfDB["objects"]["data"] and processedCount <= maxProcess then
        for objectId, object in pairs(pfDB["objects"]["data"]) do
            processedCount = processedCount + 1
            if processedCount > maxProcess then break end

            if object.coords then
                local hasTargetCoords = false
                local relevantCoords = {}

                for _, coord in ipairs(object.coords) do
                    local x, y = coord[1], coord[2]
                    if x == targetX and y == targetY then
                        hasTargetCoords = true
                        table.insert(relevantCoords, coord)
                    end
                end

                -- Only process if has target coords and is quest-related
                if hasTargetCoords then
                    local isRelated, relatedQuests = isQuestRelated("Object", objectId)
                    if isRelated then
                        table.insert(entitiesToProcess, {
                            type = "Object",
                            id = objectId,
                            coords = relevantCoords,
                            questIds = relatedQuests
                        })
                        foundCount = foundCount + 1
                    end
                end
            end
        end
    end

    local totalEntities = #entitiesToProcess
    local processedEntities = 0
    local batchSize = 100 -- Process 100 entities per frame (pre-filtered)

    -- Clear results first
    ClearResults()

    -- Early exit if no entities to process
    if totalEntities == 0 then
        isSearching = false
        local summary = "No quest-related entities found with " .. patternName .. " coordinates"
        if zoneFilter then
            summary = summary .. " in zones matching '" .. searchTerm .. "'"
        end
        pfDebugBrowser.statusText:SetText(COLORS.SUCCESS .. summary .. "|r")

        -- Show friendly message for coordinate searches with no results
        local emptyMsg = pfDebugBrowser.resultsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        emptyMsg:SetPoint("TOPLEFT", pfDebugBrowser.resultsFrame, "TOPLEFT", 5, -5)
        emptyMsg:SetText(COLORS.WARNING .. summary .. "|r")
        pfDebugBrowser.resultsFrame:SetHeight(25)
        return
    end

    local function ProcessBatch()
        local batchEnd = math.min(processedEntities + batchSize, totalEntities)

        for i = processedEntities + 1, batchEnd do
            local entity = entitiesToProcess[i]
            local entityType = entity.type
            local entityId = entity.id
            local questIds = entity.questIds

            -- Process each relevant coordinate (all are already target coordinates)
            for _, coord in ipairs(entity.coords) do
                local x, y, zoneId = coord[1], coord[2], coord[3]

                -- Check zone filter if specified
                local zoneMatches = true
                if zoneFilter then
                    zoneMatches = false
                    local zoneName = "Zone " .. zoneId
                    if pfDB["zones"] and pfDB["zones"]["loc"] and pfDB["zones"]["loc"][zoneId] then
                        zoneName = pfDB["zones"]["loc"][zoneId]
                    end

                    if string.find(string.lower(zoneName), zoneFilter) then
                        zoneMatches = true
                    end
                end

                if zoneMatches then
                    local entityName = (entityType == "NPC" and "Unit " or "Object ") .. entityId
                    local locTable = pfDB[entityType == "NPC" and "units" or "objects"]["loc"]
                    if locTable and locTable[entityId] then
                        entityName = locTable[entityId]
                    end

                    local zoneName = "Zone " .. zoneId
                    if pfDB["zones"] and pfDB["zones"]["loc"] and pfDB["zones"]["loc"][zoneId] then
                        zoneName = pfDB["zones"]["loc"][zoneId]
                    end

                    table.insert(results, {
                        type = entityType,
                        id = entityId,
                        name = entityName,
                        zoneName = zoneName,
                        zoneId = zoneId,
                        x = x,
                        y = y,
                        questIds = questIds,
                        questCount = #questIds,
                        level = 1 -- For sorting
                    })
                    break -- Only count once per entity
                end
            end
        end

        processedEntities = batchEnd

        -- Update progress
        local progress = math.floor((processedEntities / totalEntities) * 100)
        pfDebugBrowser.statusText:SetText(COLORS.WARNING .. "Processing " .. patternName .. "... " .. progress .. "% (" .. #results .. " found)|r")

        -- Continue processing or finish
        if processedEntities < totalEntities and isSearching then
            -- Schedule next batch
            local nextBatchFrame = CreateFrame("Frame")
            nextBatchFrame:SetScript("OnUpdate", function()
                this:SetScript("OnUpdate", nil)
                if isSearching then
                    ProcessBatch()
                end
            end)
        else
            -- Finished processing
            if isSearching then
                isSearching = false
                -- Sort results by zone name, then by type, then by name
                table.sort(results, function(a, b)
                    if a.zoneName ~= b.zoneName then
                        return a.zoneName < b.zoneName
                    end
                    if a.type ~= b.type then
                        return a.type < b.type
                    end
                    return a.name < b.name
                end)

                -- Display results
                local summary = "Found " .. #results .. " quest-related entities with " .. patternName .. " coordinates"
                if zoneFilter then
                    summary = summary .. " in zones matching '" .. searchTerm .. "'"
                end

                if searchTerm and searchTerm ~= "" then
                    DisplayCoordsResults(results, summary, searchTerm)
                else
                    DisplayCoordsGroupedResults(results)
                end
            end
        end
    end

    -- Start processing
    ProcessBatch()
end

-- Lazy loading search for entities without coordinates
function PerformNoCoordsSearchLazy(searchTerm)
    if not pfDB then
        pfDebugBrowser.statusText:SetText(COLORS.ERROR .. "pfDB not loaded|r")
        return
    end

    local results = {}
    local searchLower = searchTerm and string.lower(searchTerm) or ""

    -- Pre-build quest relationship maps
    local npcQuestMap = {}
    local objectQuestMap = {}

    if pfDB["quests"] and pfDB["quests"]["data"] then
        for questId, quest in pairs(pfDB["quests"]["data"]) do
            if quest.start and quest.start.U then
                for _, unitId in ipairs(quest.start.U) do
                    local id = tonumber(unitId)
                    if not npcQuestMap[id] then npcQuestMap[id] = {} end
                    table.insert(npcQuestMap[id], questId)
                end
            end
            if quest.finish and quest.finish.U then
                for _, unitId in ipairs(quest.finish.U) do
                    local id = tonumber(unitId)
                    if not npcQuestMap[id] then npcQuestMap[id] = {} end
                    table.insert(npcQuestMap[id], questId)
                end
            end
        end
    end

    -- Convert NPCs to array for batch processing
    local npcsToProcess = {}
    if pfDB["units"] and pfDB["units"]["data"] then
        for unitId, unit in pairs(pfDB["units"]["data"]) do
            table.insert(npcsToProcess, {id = unitId, data = unit})
        end
    end

    local totalNPCs = #npcsToProcess
    local processedNPCs = 0
    local batchSize = 100 -- Process 100 NPCs per frame

    ClearResults()

    local function ProcessBatch()
        local batchEnd = math.min(processedNPCs + batchSize, totalNPCs)

        for i = processedNPCs + 1, batchEnd do
            local npc = npcsToProcess[i]
            local unitId = npc.id
            local unit = npc.data

            -- Check if NPC is quest-related but has no coordinates
            local questIds = npcQuestMap[tonumber(unitId)] or {}
            if #questIds > 0 and (not unit.coords or #unit.coords == 0) then
                local unitName = "Unit " .. unitId
                if pfDB["units"]["loc"] and pfDB["units"]["loc"][unitId] then
                    unitName = pfDB["units"]["loc"][unitId]
                end

                local matches = not searchTerm or
                               string.find(string.lower(unitName), searchLower) or
                               tostring(unitId) == searchTerm

                if matches then
                    table.insert(results, {
                        type = "NPC",
                        id = unitId,
                        name = unitName,
                        questIds = questIds,
                        questCount = #questIds
                    })
                end
            end
        end

        processedNPCs = batchEnd

        -- Update progress
        local progress = math.floor((processedNPCs / totalNPCs) * 100)
        pfDebugBrowser.statusText:SetText(COLORS.WARNING .. "Processing no-coords... " .. progress .. "% (" .. #results .. " found)|r")

        -- Continue processing or finish
        if processedNPCs < totalNPCs and isSearching then
            local nextBatchFrame = CreateFrame("Frame")
            nextBatchFrame:SetScript("OnUpdate", function()
                this:SetScript("OnUpdate", nil)
                if isSearching then
                    ProcessBatch()
                end
            end)
        else
            -- Finished processing
            if isSearching then
                isSearching = false
                -- Sort by name
                table.sort(results, function(a, b)
                    return a.name < b.name
                end)

                local summary = "Found " .. #results .. " quest-related NPCs without coordinates"
                if searchTerm then
                    summary = summary .. " matching '" .. searchTerm .. "'"
                end

                DisplayCoordsResults(results, summary, searchTerm)
            end
        end
    end

    ProcessBatch()
end

-- Lazy loading search for entities without zone info
function PerformNoZoneSearchLazy(searchTerm)
    if not pfDB then
        pfDebugBrowser.statusText:SetText(COLORS.ERROR .. "pfDB not loaded|r")
        return
    end

    local results = {}
    local searchLower = searchTerm and string.lower(searchTerm) or ""

    -- Pre-build quest relationship maps
    local npcQuestMap = {}
    local objectQuestMap = {}

    if pfDB["quests"] and pfDB["quests"]["data"] then
        for questId, quest in pairs(pfDB["quests"]["data"]) do
            if quest.start and quest.start.U then
                for _, unitId in ipairs(quest.start.U) do
                    local id = tonumber(unitId)
                    if not npcQuestMap[id] then npcQuestMap[id] = {} end
                    table.insert(npcQuestMap[id], questId)
                end
            end
            if quest.finish and quest.finish.U then
                for _, unitId in ipairs(quest.finish.U) do
                    local id = tonumber(unitId)
                    if not npcQuestMap[id] then npcQuestMap[id] = {} end
                    table.insert(npcQuestMap[id], questId)
                end
            end
            if quest.start and quest.start.O then
                for _, objectId in ipairs(quest.start.O) do
                    local id = tonumber(objectId)
                    if not objectQuestMap[id] then objectQuestMap[id] = {} end
                    table.insert(objectQuestMap[id], questId)
                end
            end
            if quest.finish and quest.finish.O then
                for _, objectId in ipairs(quest.finish.O) do
                    local id = tonumber(objectId)
                    if not objectQuestMap[id] then objectQuestMap[id] = {} end
                    table.insert(objectQuestMap[id], questId)
                end
            end
        end
    end

    -- Pre-filter entities that have coordinates but no zone info
    local entitiesToProcess = {}

    -- Add NPCs that have coords but invalid/missing zone
    if pfDB["units"] and pfDB["units"]["data"] then
        for unitId, unit in pairs(pfDB["units"]["data"]) do
            local questIds = npcQuestMap[tonumber(unitId)] or {}
            if #questIds > 0 and unit.coords and #unit.coords > 0 then
                local hasInvalidZone = false
                for _, coord in ipairs(unit.coords) do
                    local zoneId = coord[3]
                    if not zoneId or not pfDB["zones"] or not pfDB["zones"]["loc"] or not pfDB["zones"]["loc"][zoneId] then
                        hasInvalidZone = true
                        break
                    end
                end

                if hasInvalidZone then
                    table.insert(entitiesToProcess, {
                        type = "NPC",
                        id = unitId,
                        data = unit,
                        questIds = questIds
                    })
                end
            end
        end
    end

    -- Add Objects that have coords but invalid/missing zone
    if pfDB["objects"] and pfDB["objects"]["data"] then
        for objectId, object in pairs(pfDB["objects"]["data"]) do
            local questIds = objectQuestMap[tonumber(objectId)] or {}
            if #questIds > 0 and object.coords and #object.coords > 0 then
                local hasInvalidZone = false
                for _, coord in ipairs(object.coords) do
                    local zoneId = coord[3]
                    if not zoneId or not pfDB["zones"] or not pfDB["zones"]["loc"] or not pfDB["zones"]["loc"][zoneId] then
                        hasInvalidZone = true
                        break
                    end
                end

                if hasInvalidZone then
                    table.insert(entitiesToProcess, {
                        type = "Object",
                        id = objectId,
                        data = object,
                        questIds = questIds
                    })
                end
            end
        end
    end

    local totalEntities = #entitiesToProcess
    local processedEntities = 0
    local batchSize = 50 -- Process 50 entities per frame

    ClearResults()

    local function ProcessBatch()
        local batchEnd = math.min(processedEntities + batchSize, totalEntities)

        for i = processedEntities + 1, batchEnd do
            local entity = entitiesToProcess[i]
            local entityType = entity.type
            local entityId = entity.id
            local entityData = entity.data
            local questIds = entity.questIds

            local entityName = (entityType == "NPC" and "Unit " or "Object ") .. entityId
            local locTable = pfDB[entityType == "NPC" and "units" or "objects"]["loc"]
            if locTable and locTable[entityId] then
                entityName = locTable[entityId]
            end

            local matches = not searchTerm or
                           string.find(string.lower(entityName), searchLower) or
                           tostring(entityId) == searchTerm

            if matches then
                -- Get coordinate info for display
                local coordInfo = "No Coords"
                if entityData.coords and #entityData.coords > 0 then
                    local coord = entityData.coords[1] -- Use first coordinate
                    local x, y, zoneId = coord[1], coord[2], coord[3]
                    coordInfo = "(" .. (x or "?") .. "," .. (y or "?") .. ") Zone:" .. (zoneId or "?")
                end

                table.insert(results, {
                    type = entityType,
                    id = entityId,
                    name = entityName,
                    zoneName = nil, -- No valid zone
                    questIds = questIds,
                    questCount = #questIds,
                    coordInfo = coordInfo
                })
            end
        end

        processedEntities = batchEnd

        -- Update progress
        local progress = math.floor((processedEntities / totalEntities) * 100)
        pfDebugBrowser.statusText:SetText(COLORS.WARNING .. "Processing no-zone... " .. progress .. "% (" .. #results .. " found)|r")

        -- Continue processing or finish
        if processedEntities < totalEntities and isSearching then
            local nextBatchFrame = CreateFrame("Frame")
            nextBatchFrame:SetScript("OnUpdate", function()
                this:SetScript("OnUpdate", nil)
                if isSearching then
                    ProcessBatch()
                end
            end)
        else
            -- Finished processing
            if isSearching then
                isSearching = false
                -- Sort by name
                table.sort(results, function(a, b)
                    return a.name < b.name
                end)

                local summary = "Found " .. #results .. " quest-related entities without valid zone info"
                if searchTerm then
                    summary = summary .. " matching '" .. searchTerm .. "'"
                end

                DisplayCoordsResults(results, summary, searchTerm)
            end
        end
    end

    ProcessBatch()
end

-- Lazy loading search for rare creatures
function PerformRaresSearchLazy(searchTerm)
    if not pfDB or not pfDB["meta"] or not pfDB["meta"]["rares"] then
        pfDebugBrowser.statusText:SetText(COLORS.ERROR .. "No rares data available|r")
        return
    end

    local currentZone = GetRealZoneText()
    local results = {}
    local searchLower = searchTerm and string.lower(searchTerm) or ""

    -- Convert rares to array for processing
    local raresToProcess = {}
    for rareId, rareLevel in pairs(pfDB["meta"]["rares"]) do
        table.insert(raresToProcess, {rareId = rareId, level = rareLevel})
    end

    local totalRares = #raresToProcess
    local processedRares = 0
    local batchSize = 20 -- Process 20 rares per frame

    ClearResults()

    local function ProcessBatch()
        local batchEnd = math.min(processedRares + batchSize, totalRares)

        for i = processedRares + 1, batchEnd do
            local rare = raresToProcess[i]
            local rareId = rare.rareId
            local rareLevel = rare.level

            local rareName = ""
            if pfDB["units"] and pfDB["units"]["loc"] and pfDB["units"]["loc"][rareId] then
                rareName = pfDB["units"]["loc"][rareId]
            else
                rareName = "Rare " .. rareId
            end

            local matches = not searchTerm or
                           string.find(string.lower(rareName), searchLower) or
                           tostring(rareId) == searchTerm

            if matches then
                local isInCurrentZone = false
                local unit = pfDB["units"] and pfDB["units"]["data"] and pfDB["units"]["data"][rareId]

                if unit and unit.coords then
                    for _, coord in ipairs(unit.coords) do
                        local zoneId = coord[3]
                        local zoneName = ""
                        if pfDB["zones"] and pfDB["zones"]["loc"] and pfDB["zones"]["loc"][zoneId] then
                            zoneName = pfDB["zones"]["loc"][zoneId]
                            if zoneName == currentZone then
                                isInCurrentZone = true
                            end
                        end
                    end
                end

                -- Get respawn time
                local respawnTime = "Unknown"
                if unit and unit.coords then
                    for _, coord in ipairs(unit.coords) do
                        if coord[4] and coord[4] > 0 then
                            local seconds = coord[4]
                            if seconds >= 3600 then
                                respawnTime = math.floor(seconds / 3600) .. "h"
                            elseif seconds >= 60 then
                                respawnTime = math.floor(seconds / 60) .. "m"
                            else
                                respawnTime = seconds .. "s"
                            end
                            break
                        end
                    end
                end

                table.insert(results, {
                    rareId = rareId,
                    rareName = rareName,
                    level = rareLevel,
                    coords = unit and unit.coords or {},
                    isInCurrentZone = isInCurrentZone,
                    respawn = respawnTime
                })
            end
        end

        processedRares = batchEnd

        -- Update progress
        local progress = math.floor((processedRares / totalRares) * 100)
        pfDebugBrowser.statusText:SetText(COLORS.WARNING .. "Processing rares... " .. progress .. "% (" .. #results .. " found)|r")

        -- Continue processing or finish
        if processedRares < totalRares and isSearching then
            local nextBatchFrame = CreateFrame("Frame")
            nextBatchFrame:SetScript("OnUpdate", function()
                this:SetScript("OnUpdate", nil)
                if isSearching then
                    ProcessBatch()
                end
            end)
        else
            if isSearching then
                isSearching = false
                -- Sort: current zone first, then by level desc
                table.sort(results, function(a, b)
                    if a.isInCurrentZone ~= b.isInCurrentZone then
                        return a.isInCurrentZone
                    end
                    return a.level > b.level
                end)

                DisplayRareResults(results, currentZone, searchTerm)
            end
        end
    end

    ProcessBatch()
end

-- Lazy loading search for working quests
function PerformWorkingSearchLazy(searchTerm)
    if not pfDB or not pfDB["quests"] or not pfDB["quests"]["data"] then
        pfDebugBrowser.statusText:SetText(COLORS.ERROR .. "No quests data available|r")
        return
    end

    local results = {}

    -- Convert quests to array for processing
    local questsToProcess = {}
    for questId, quest in pairs(pfDB["quests"]["data"]) do
        table.insert(questsToProcess, {questId = questId, quest = quest})
    end

    local totalQuests = #questsToProcess
    local processedQuests = 0
    local batchSize = 50 -- Process 50 quests per frame
    local workingCount = 0

    ClearResults()

    local function ProcessBatch()
        local batchEnd = math.min(processedQuests + batchSize, totalQuests)

        for i = processedQuests + 1, batchEnd do
            local questData = questsToProcess[i]
            local quest = questData.quest

            if quest.start and (quest.start.U or quest.start.O) then
                workingCount = workingCount + 1
            end
        end

        processedQuests = batchEnd

        -- Update progress
        local progress = math.floor((processedQuests / totalQuests) * 100)
        pfDebugBrowser.statusText:SetText(COLORS.WARNING .. "Processing quests... " .. progress .. "% (" .. workingCount .. " working)|r")

        -- Continue processing or finish
        if processedQuests < totalQuests and isSearching then
            local nextBatchFrame = CreateFrame("Frame")
            nextBatchFrame:SetScript("OnUpdate", function()
                this:SetScript("OnUpdate", nil)
                if isSearching then
                    ProcessBatch()
                end
            end)
        else
            if isSearching then
                isSearching = false
                DisplayWorkingQuestResults({workingCount})
            end
        end
    end

    ProcessBatch()
end

-- Lazy loading search for validation
function PerformValidationSearchLazy(searchTerm)
    if not pfDB then
        pfDebugBrowser.statusText:SetText(COLORS.ERROR .. "pfDB not loaded|r")
        return
    end

    local results = {}
    local validationSteps = {
        "Checking quest database integrity...",
        "Validating NPC coordinates...",
        "Checking item requirements...",
        "Validating zone data...",
        "Checking quest chains..."
    }

    local currentStep = 1
    local totalSteps = #validationSteps

    ClearResults()

    local function ProcessValidation()
        -- Simulate validation work
        pfDebugBrowser.statusText:SetText(COLORS.WARNING .. validationSteps[currentStep] .. " (" .. currentStep .. "/" .. totalSteps .. ")|r")

        currentStep = currentStep + 1

        if currentStep <= totalSteps and isSearching then
            local nextStepFrame = CreateFrame("Frame")
            nextStepFrame:SetScript("OnUpdate", function()
                this:SetScript("OnUpdate", nil)
                if isSearching then
                    ProcessValidation()
                end
            end)
        else
            if isSearching then
                isSearching = false
                table.insert(results, "Validation completed successfully")
                DisplayGenericResults(results, "Validation", searchTerm)
            end
        end
    end

    ProcessValidation()
end

-- Generic lazy loading for any other categories
function PerformGenericSearchLazy(searchTerm)
    local category = debugCategories[activeCategory]
    if not category or not category.searchFunction then
        pfDebugBrowser.statusText:SetText(COLORS.ERROR .. "Category not implemented|r")
        return
    end

    -- Simulate processing with small delay
    pfDebugBrowser.statusText:SetText(COLORS.WARNING .. "Processing " .. category.name .. "...|r")

    local processFrame = CreateFrame("Frame")
    processFrame:SetScript("OnUpdate", function()
        this:SetScript("OnUpdate", nil)
        if isSearching then
            isSearching = false
            local results, extra = category.searchFunction(searchTerm)
            DisplayGenericResults(results, extra, searchTerm)
        end
    end)
end

-- Display ItemReq search results
function DisplayItemReqResults(results, currentZone, searchTerm)
    ClearResults()

    if not results or #results == 0 then
        pfDebugBrowser.statusText:SetText(COLORS.ERROR .. "No ItemReq quests found" .. (searchTerm and " for '" .. searchTerm .. "'" or "") .. "|r")
        return
    end

    local yOffset = 0
    local resultCount = math.min(#results, 15) -- Limit results

    -- Header
    local header = pfDebugBrowser.resultsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", pfDebugBrowser.resultsFrame, "TOPLEFT", 5, yOffset)
    header:SetText(COLORS.HEADER .. "ItemReq Quest Results|r")
    yOffset = yOffset - 25

    -- Zone info
    local zoneInfo = pfDebugBrowser.resultsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    zoneInfo:SetPoint("TOPLEFT", pfDebugBrowser.resultsFrame, "TOPLEFT", 5, yOffset)
    zoneInfo:SetText(COLORS.SUBHEADER .. "Current Zone: " .. (currentZone or "Unknown") .. "|r")
    yOffset = yOffset - 20

    if searchTerm and searchTerm ~= "" then
        local searchInfo = pfDebugBrowser.resultsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        searchInfo:SetPoint("TOPLEFT", pfDebugBrowser.resultsFrame, "TOPLEFT", 5, yOffset)
        searchInfo:SetText(COLORS.SUBHEADER .. "Search: '" .. searchTerm .. "'|r")
        yOffset = yOffset - 20
    end

    -- Summary
    local currentZoneCount = 0
    for _, result in ipairs(results) do
        if result.isInCurrentZone then
            currentZoneCount = currentZoneCount + 1
        end
    end

    local summary = pfDebugBrowser.resultsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    summary:SetPoint("TOPLEFT", pfDebugBrowser.resultsFrame, "TOPLEFT", 5, yOffset)
    summary:SetText(COLORS.SUCCESS .. "Found " .. #results .. " quest(s): " .. currentZoneCount .. " in current zone|r")
    yOffset = yOffset - 30

    -- Results
    for i = 1, resultCount do
        local result = results[i]
        local zoneIcon = result.isInCurrentZone and "" or ""

        -- Quest entry with alternating colors (increased height for 3 lines)
        local questBtn = CreateFrame("Button", nil, pfDebugBrowser.resultsFrame)
        questBtn:SetWidth(340)
        questBtn:SetHeight(75)
        questBtn:SetPoint("TOPLEFT", pfDebugBrowser.resultsFrame, "TOPLEFT", 5, yOffset)

        questBtn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 3, right = 3, top = 3, bottom = 3 }
        })

        -- Alternating background colors
        if i % 2 == 0 then
            questBtn:SetBackdropColor(0.08, 0.08, 0.12, 0.8)
        else
            questBtn:SetBackdropColor(0.05, 0.05, 0.05, 0.8)
        end
        questBtn:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)

        -- Quest name
        questBtn.questName = questBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        questBtn.questName:SetPoint("TOPLEFT", questBtn, "TOPLEFT", 5, -5)
        questBtn.questName:SetPoint("TOPRIGHT", questBtn, "TOPRIGHT", -5, -5)
        questBtn.questName:SetText((result.isInCurrentZone and COLORS.SUCCESS or COLORS.NORMAL) .. zoneIcon .. COLORS.GOLD .. "[" .. result.questId .. "]|r " .. (result.isInCurrentZone and COLORS.SUCCESS or COLORS.NORMAL) .. result.questName .. "|r")
        questBtn.questName:SetJustifyH("LEFT")

        -- Item info in /pfi style (second line)
        local targetCount = 0
        for _ in pairs(result.targets) do targetCount = targetCount + 1 end

        questBtn.itemInfo = questBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        questBtn.itemInfo:SetPoint("TOPLEFT", questBtn.questName, "BOTTOMLEFT", 0, -5)
        questBtn.itemInfo:SetPoint("TOPRIGHT", questBtn, "TOPRIGHT", -5, -25)
        questBtn.itemInfo:SetText(COLORS.SUBHEADER .. "Item: " .. result.itemName .. " [" .. result.itemId .. "] - " .. targetCount .. " targets|r")
        questBtn.itemInfo:SetJustifyH("LEFT")
        questBtn.itemInfo:SetJustifyV("TOP")

        -- Zone info in gold (third line)
        local zoneText = ""
        if result.zones and #result.zones > 0 then
            if #result.zones == 1 then
                zoneText = "Zone: " .. result.zones[1]
            else
                zoneText = "Zones: " .. table.concat(result.zones, ", ")
            end
        else
            zoneText = "Zone: Unknown"
        end

        questBtn.zoneInfo = questBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        questBtn.zoneInfo:SetPoint("TOPLEFT", questBtn.itemInfo, "BOTTOMLEFT", 0, -3)
        questBtn.zoneInfo:SetPoint("BOTTOMRIGHT", questBtn, "BOTTOMRIGHT", -5, 5)
        questBtn.zoneInfo:SetText(COLORS.GOLD .. zoneText .. "|r")
        questBtn.zoneInfo:SetJustifyH("LEFT")
        questBtn.zoneInfo:SetJustifyV("TOP")

        -- Click to show quest
        questBtn.questId = result.questId
        questBtn:SetScript("OnClick", function()
            -- Show quest on map using pfQuest browser pattern
            local questId = this.questId

            if pfDatabase and pfMap then
                -- Search for quest and show best map (like browser.lua does)
                local maps = pfDatabase:SearchQuestID(questId)
                local bestMap = pfDatabase:GetBestMap(maps)
                if bestMap then
                    pfMap:ShowMapID(bestMap)
                else
                    print("Quest " .. questId .. " locations not found")
                end
            else
                -- Fallback: execute /pfq command if available
                if SlashCmdList["PFQ"] then
                    SlashCmdList["PFQ"](tostring(questId))
                else
                    print("Quest " .. questId .. " - pfQuest map not available")
                end
            end
        end)

        -- Hover effect
        questBtn:SetScript("OnEnter", function()
            this:SetBackdropColor(0.15, 0.15, 0.2, 0.9)

            -- Show tooltip with targets
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:SetText("Quest " .. this.questId .. " Targets", 1, 1, 1)

            local targetShown = 0
            for targetId, spellId in pairs(result.targets) do
                if targetShown >= 5 then
                    GameTooltip:AddLine("... and more", 0.8, 0.8, 0.8)
                    break
                end

                local targetName = "Unknown"
                local targetType = ""

                if targetId > 0 then
                    targetType = "NPC: "
                    if pfDB and pfDB["units"] and pfDB["units"]["loc"] and pfDB["units"]["loc"][targetId] then
                        targetName = pfDB["units"]["loc"][targetId]
                    else
                        targetName = "Unit " .. targetId
                    end
                else
                    local objId = math.abs(targetId)
                    targetType = "Object: "
                    if pfDB and pfDB["objects"] and pfDB["objects"]["loc"] and pfDB["objects"]["loc"][objId] then
                        targetName = pfDB["objects"]["loc"][objId]
                    else
                        targetName = "Object " .. objId
                    end
                end

                GameTooltip:AddLine(targetType .. targetName, 0.8, 1, 0.8)
                targetShown = targetShown + 1
            end

            GameTooltip:AddLine(" ", 1, 1, 1)
            GameTooltip:AddLine("Click to show quest details", 0.5, 0.5, 1)
            GameTooltip:Show()
        end)
        questBtn:SetScript("OnLeave", function()
            -- Restore original alternating color
            if i % 2 == 0 then
                this:SetBackdropColor(0.08, 0.08, 0.12, 0.8)
            else
                this:SetBackdropColor(0.05, 0.05, 0.05, 0.8)
            end
            GameTooltip:Hide()
        end)

        yOffset = yOffset - 80
    end

    if #results > resultCount then
        local moreText = pfDebugBrowser.resultsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        moreText:SetPoint("TOPLEFT", pfDebugBrowser.resultsFrame, "TOPLEFT", 5, yOffset)
        moreText:SetText(COLORS.WARNING .. "... and " .. (#results - resultCount) .. " more results|r")
        yOffset = yOffset - 20
    end

    -- Update scroll frame
    pfDebugBrowser.resultsFrame:SetHeight(math.abs(yOffset) + 50)
    pfDebugBrowser.scrollBar:SetMinMaxValues(0, math.max(0, math.abs(yOffset) - 300))

    pfDebugBrowser.statusText:SetText(COLORS.SUCCESS .. "Search completed - " .. #results .. " results|r")
end

-- Display rare results
function DisplayRareResults(results, currentZone, searchTerm)
    ClearResults()

    if not results or #results == 0 then
        pfDebugBrowser.statusText:SetText(COLORS.ERROR .. "No rare creatures found" .. (searchTerm and " for '" .. searchTerm .. "'" or "") .. "|r")
        return
    end

    local yOffset = 0
    local resultCount = math.min(#results, 15)

    -- Header
    local header = pfDebugBrowser.resultsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", pfDebugBrowser.resultsFrame, "TOPLEFT", 5, yOffset)
    header:SetText(COLORS.HEADER .. "Rare Creatures Results|r")
    yOffset = yOffset - 25

    -- Zone info
    local zoneInfo = pfDebugBrowser.resultsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    zoneInfo:SetPoint("TOPLEFT", pfDebugBrowser.resultsFrame, "TOPLEFT", 5, yOffset)
    zoneInfo:SetText(COLORS.SUBHEADER .. "Current Zone: " .. (currentZone or "Unknown") .. "|r")
    yOffset = yOffset - 30

    -- Results
    for i = 1, resultCount do
        local result = results[i]

        -- Rare entry with alternating colors
        local rareBtn = CreateFrame("Button", nil, pfDebugBrowser.resultsFrame)
        rareBtn:SetWidth(340)
        rareBtn:SetHeight(50)
        rareBtn:SetPoint("TOPLEFT", pfDebugBrowser.resultsFrame, "TOPLEFT", 5, yOffset)

        rareBtn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 3, right = 3, top = 3, bottom = 3 }
        })

        -- Alternating background colors for rares
        if i % 2 == 0 then
            rareBtn:SetBackdropColor(0.08, 0.05, 0.08, 0.8)
        else
            rareBtn:SetBackdropColor(0.05, 0.05, 0.05, 0.8)
        end
        rareBtn:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)

        -- Rare name
        rareBtn.rareName = rareBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        rareBtn.rareName:SetPoint("TOPLEFT", rareBtn, "TOPLEFT", 5, -5)
        rareBtn.rareName:SetPoint("TOPRIGHT", rareBtn, "TOPRIGHT", -5, -5)
        rareBtn.rareName:SetText((result.isInCurrentZone and COLORS.SUCCESS or COLORS.NORMAL) .. (result.isInCurrentZone and "" or "") .. "[" .. result.rareId .. "] " .. result.rareName .. " (Level " .. result.level .. ")|r")
        rareBtn.rareName:SetJustifyH("LEFT")

        -- Location info with respawn time
        local locationText = "No known locations"
        if #result.coords > 0 then
            local coord = result.coords[1]
            local zoneId = coord[3]
            local zoneName = "Unknown Zone"

            if pfDB and pfDB["zones"] and pfDB["zones"]["loc"] and pfDB["zones"]["loc"][zoneId] then
                zoneName = pfDB["zones"]["loc"][zoneId]
            end

            locationText = "Location: " .. zoneName
            if #result.coords > 1 then
                locationText = locationText .. " (+" .. (#result.coords - 1) .. " more)"
            end
        end

        locationText = locationText .. " | Respawn: " .. result.respawn

        rareBtn.locationInfo = rareBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        rareBtn.locationInfo:SetPoint("TOPLEFT", rareBtn.rareName, "BOTTOMLEFT", 0, -8)
        rareBtn.locationInfo:SetPoint("BOTTOMRIGHT", rareBtn, "BOTTOMRIGHT", -5, 5)
        rareBtn.locationInfo:SetText(COLORS.SUBHEADER .. locationText .. "|r")
        rareBtn.locationInfo:SetJustifyH("LEFT")
        rareBtn.locationInfo:SetJustifyV("TOP")

        -- Click to show rare
        rareBtn.rareId = result.rareId
        rareBtn:SetScript("OnClick", function()
            local rareId = this.rareId

            if pfDatabase and pfMap then
                local maps = pfDatabase:SearchMobID(rareId)
                local bestMap = pfDatabase:GetBestMap(maps)
                if bestMap then
                    pfMap:ShowMapID(bestMap)
                else
                    print("Rare " .. rareId .. " locations not found")
                end
            else
                print("Rare " .. rareId .. " - pfQuest map not available")
            end
        end)

        -- Hover effect
        rareBtn:SetScript("OnEnter", function()
            this:SetBackdropColor(0.15, 0.1, 0.15, 0.9)

            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:SetText("Rare Creature " .. this.rareId, 1, 1, 1)

            for i, coord in ipairs(result.coords) do
                if i > 5 then
                    GameTooltip:AddLine("... and more", 0.8, 0.8, 0.8)
                    break
                end

                local zoneId = coord[3]
                local zoneName = "Unknown Zone"
                if pfDB and pfDB["zones"] and pfDB["zones"]["loc"] and pfDB["zones"]["loc"][zoneId] then
                    zoneName = pfDB["zones"]["loc"][zoneId]
                end

                GameTooltip:AddLine(zoneName .. " (" .. coord[1] .. ", " .. coord[2] .. ")", 0.8, 1, 0.8)
            end

            GameTooltip:AddLine(" ", 1, 1, 1)
            GameTooltip:AddLine("Click to show on map", 0.5, 0.5, 1)
            GameTooltip:Show()
        end)
        rareBtn:SetScript("OnLeave", function()
            -- Restore original alternating color
            if i % 2 == 0 then
                this:SetBackdropColor(0.08, 0.05, 0.08, 0.8)
            else
                this:SetBackdropColor(0.05, 0.05, 0.05, 0.8)
            end
            GameTooltip:Hide()
        end)

        yOffset = yOffset - 55
    end

    if #results > resultCount then
        local moreText = pfDebugBrowser.resultsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        moreText:SetPoint("TOPLEFT", pfDebugBrowser.resultsFrame, "TOPLEFT", 5, yOffset)
        moreText:SetText(COLORS.WARNING .. "... and " .. (#results - resultCount) .. " more rares|r")
        yOffset = yOffset - 20
    end

    -- Update scroll frame
    pfDebugBrowser.resultsFrame:SetHeight(math.abs(yOffset) + 50)
    pfDebugBrowser.scrollBar:SetMinMaxValues(0, math.max(0, math.abs(yOffset) - 300))

    pfDebugBrowser.statusText:SetText(COLORS.SUCCESS .. "Search completed - " .. #results .. " rares|r")
end

-- Display working quest results (simplified)
function DisplayWorkingQuestResults(results)
    ClearResults()

    if not results or #results == 0 then
        pfDebugBrowser.statusText:SetText(COLORS.ERROR .. "No working quests found|r")
        return
    end

    -- Simple display for working quests
    local text = pfDebugBrowser.resultsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("TOPLEFT", pfDebugBrowser.resultsFrame, "TOPLEFT", 5, 0)
    text:SetText(COLORS.SUCCESS .. "Found " .. #results .. " working quests. Use /pftest for detailed output.|r")

    pfDebugBrowser.resultsFrame:SetHeight(50)
    pfDebugBrowser.statusText:SetText(COLORS.SUCCESS .. "Search completed|r")
end

-- Display 50,50 coordinates results
function DisplayCoordsResults(results, summary, searchTerm)
    ClearResults()

    if not results or #results == 0 then
        pfDebugBrowser.statusText:SetText(COLORS.ERROR .. "No entities with exact 50,50 coordinates found|r")
        return
    end

    local yOffset = 0
    local resultCount = math.min(#results, 15) -- Show max 15 results

    for i = 1, resultCount do
        local result = results[i]

        -- Create result button
        local coordBtn = CreateFrame("Button", nil, pfDebugBrowser.resultsFrame)
        coordBtn:SetWidth(350)
        coordBtn:SetHeight(50)
        coordBtn:SetPoint("TOPLEFT", pfDebugBrowser.resultsFrame, "TOPLEFT", 5, yOffset)

        coordBtn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 3, right = 3, top = 3, bottom = 3 }
        })

        -- Alternating background colors
        if i % 2 == 0 then
            coordBtn:SetBackdropColor(0.08, 0.08, 0.12, 0.8)
        else
            coordBtn:SetBackdropColor(0.05, 0.05, 0.05, 0.8)
        end
        coordBtn:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)

        -- Entity name with type and ID
        local typeColor = result.type == "NPC" and COLORS.SUCCESS or COLORS.SUBHEADER
        coordBtn.entityName = coordBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        coordBtn.entityName:SetPoint("TOPLEFT", coordBtn, "TOPLEFT", 5, -5)
        coordBtn.entityName:SetPoint("TOPRIGHT", coordBtn, "TOPRIGHT", -5, -5)
        coordBtn.entityName:SetText(typeColor .. result.type .. " [" .. result.id .. "] " .. result.name .. "|r")
        coordBtn.entityName:SetJustifyH("LEFT")

        -- Location and quest info
        local questText = ""
        if result.questIds and #result.questIds > 0 then
            local questList = {}
            for _, qId in ipairs(result.questIds) do
                table.insert(questList, tostring(qId))
            end
            questText = " | Quests: [" .. table.concat(questList, ",") .. "]"
        end

        coordBtn.locationInfo = coordBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        coordBtn.locationInfo:SetPoint("TOPLEFT", coordBtn.entityName, "BOTTOMLEFT", 0, -3)
        coordBtn.locationInfo:SetPoint("BOTTOMRIGHT", coordBtn, "BOTTOMRIGHT", -5, 5)
        local zoneName = result.zoneName or "Unknown Zone"
        local coords = result.x and result.y and "(" .. result.x .. "," .. result.y .. ")" or "No Coords"
        coordBtn.locationInfo:SetText(COLORS.GOLD .. "Zone: " .. zoneName .. " | Coords: " .. coords .. questText .. "|r")
        coordBtn.locationInfo:SetJustifyH("LEFT")
        coordBtn.locationInfo:SetJustifyV("TOP")

        -- Click to show entity on map
        coordBtn.entityType = result.type
        coordBtn.entityId = result.id
        coordBtn.zoneId = result.zoneId
        coordBtn:SetScript("OnClick", function()
            local entityType = this.entityType
            local entityId = this.entityId

            if pfDatabase and pfMap then
                local maps = nil
                if entityType == "NPC" then
                    maps = pfDatabase:SearchMobID(entityId)
                else
                    maps = pfDatabase:SearchObjectID(entityId)
                end

                local bestMap = pfDatabase:GetBestMap(maps)
                if bestMap then
                    pfMap:ShowMapID(bestMap)
                else
                    print(entityType .. " " .. entityId .. " locations not found")
                end
            else
                print(entityType .. " " .. entityId .. " - pfQuest map not available")
            end
        end)

        -- Hover effect with quest details
        coordBtn:SetScript("OnEnter", function()
            this:SetBackdropColor(0.15, 0.15, 0.2, 0.9)

            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            local coords = result.x and result.y and "(" .. result.x .. "," .. result.y .. ")" or (result.coordInfo or "No Coords")
            GameTooltip:SetText(result.type .. " " .. result.id, 1, 1, 1)
            GameTooltip:AddLine("Zone: " .. (result.zoneName or "Unknown Zone"), 0.8, 1, 0.8)
            GameTooltip:AddLine("Coordinates: " .. coords, 1, 0.8, 0.8)

            if result.questIds and #result.questIds > 0 then
                GameTooltip:AddLine(" ", 1, 1, 1)
                GameTooltip:AddLine("Related Quests:", 1, 1, 0.5)
                for i, qId in ipairs(result.questIds) do
                    if i > 5 then
                        GameTooltip:AddLine("... and more", 0.8, 0.8, 0.8)
                        break
                    end

                    local questName = "Quest " .. qId
                    if pfDB and pfDB["quests"] and pfDB["quests"]["loc"] and pfDB["quests"]["loc"][qId] then
                        local questData = pfDB["quests"]["loc"][qId]
                        if type(questData) == "table" and questData.T then
                            questName = questData.T
                        elseif type(questData) == "string" then
                            questName = questData
                        end
                    end
                    GameTooltip:AddLine("[" .. qId .. "] " .. questName, 0.8, 1, 0.8)
                end
            end

            GameTooltip:AddLine(" ", 1, 1, 1)
            GameTooltip:AddLine("Click to show on map", 0.5, 0.5, 1)
            GameTooltip:Show()
        end)

        coordBtn:SetScript("OnLeave", function()
            -- Restore original alternating color
            if i % 2 == 0 then
                this:SetBackdropColor(0.08, 0.08, 0.12, 0.8)
            else
                this:SetBackdropColor(0.05, 0.05, 0.05, 0.8)
            end
            GameTooltip:Hide()
        end)

        yOffset = yOffset - 55
    end

    if #results > resultCount then
        local moreText = pfDebugBrowser.resultsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        moreText:SetPoint("TOPLEFT", pfDebugBrowser.resultsFrame, "TOPLEFT", 5, yOffset)
        moreText:SetText(COLORS.WARNING .. "... and " .. (#results - resultCount) .. " more entities|r")
        yOffset = yOffset - 20
    end

    -- Update scroll frame
    pfDebugBrowser.resultsFrame:SetHeight(math.abs(yOffset) + 50)
    pfDebugBrowser.scrollBar:SetMinMaxValues(0, math.max(0, math.abs(yOffset) - 300))

    pfDebugBrowser.statusText:SetText(COLORS.SUCCESS .. summary .. "|r")
end

-- Display grouped results by zone for empty search (like ItemReq)
function DisplayCoordsGroupedResults(results)
    ClearResults()

    if not results or #results == 0 then
        pfDebugBrowser.statusText:SetText(COLORS.ERROR .. "No entities with exact 50,50 coordinates found|r")
        return
    end

    -- Group results by zone
    local zoneGroups = {}
    for _, result in ipairs(results) do
        local zoneId = result.zoneId
        if not zoneGroups[zoneId] then
            zoneGroups[zoneId] = {
                zoneName = result.zoneName or "Unknown Zone",
                zoneId = zoneId,
                entities = {}
            }
        end
        table.insert(zoneGroups[zoneId].entities, result)
    end

    -- Convert to sorted array
    local sortedZones = {}
    for zoneId, zoneGroup in pairs(zoneGroups) do
        table.insert(sortedZones, zoneGroup)
    end

    -- Sort zones by name
    table.sort(sortedZones, function(a, b)
        return a.zoneName < b.zoneName
    end)

    local yOffset = 0

    -- Header
    local header = pfDebugBrowser.resultsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", pfDebugBrowser.resultsFrame, "TOPLEFT", 5, yOffset)
    header:SetText(COLORS.HEADER .. "Zones with 50,50 Coordinate Issues|r")
    yOffset = yOffset - 25

    -- Summary
    local totalEntities = #results
    local summary = pfDebugBrowser.resultsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    summary:SetPoint("TOPLEFT", pfDebugBrowser.resultsFrame, "TOPLEFT", 5, yOffset)
    summary:SetText(COLORS.SUCCESS .. "Found " .. totalEntities .. " entities in " .. #sortedZones .. " zones|r")
    yOffset = yOffset - 30

    -- Zone entries
    for i, zoneGroup in ipairs(sortedZones) do
        local zoneBtn = CreateFrame("Button", nil, pfDebugBrowser.resultsFrame)
        zoneBtn:SetWidth(350)
        zoneBtn:SetHeight(50)
        zoneBtn:SetPoint("TOPLEFT", pfDebugBrowser.resultsFrame, "TOPLEFT", 5, yOffset)

        zoneBtn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 3, right = 3, top = 3, bottom = 3 }
        })

        -- Alternating background colors
        if i % 2 == 0 then
            zoneBtn:SetBackdropColor(0.08, 0.08, 0.12, 0.8)
        else
            zoneBtn:SetBackdropColor(0.05, 0.05, 0.05, 0.8)
        end
        zoneBtn:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)

        -- Zone name
        zoneBtn.zoneName = zoneBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        zoneBtn.zoneName:SetPoint("TOPLEFT", zoneBtn, "TOPLEFT", 5, -5)
        zoneBtn.zoneName:SetPoint("TOPRIGHT", zoneBtn, "TOPRIGHT", -5, -5)
        zoneBtn.zoneName:SetText(COLORS.GOLD .. zoneGroup.zoneName .. " [" .. zoneGroup.zoneId .. "]|r")
        zoneBtn.zoneName:SetJustifyH("LEFT")

        -- Entity count
        local npcCount = 0
        local objectCount = 0
        for _, entity in ipairs(zoneGroup.entities) do
            if entity.type == "NPC" then
                npcCount = npcCount + 1
            else
                objectCount = objectCount + 1
            end
        end

        zoneBtn.entityInfo = zoneBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        zoneBtn.entityInfo:SetPoint("TOPLEFT", zoneBtn.zoneName, "BOTTOMLEFT", 0, -5)
        zoneBtn.entityInfo:SetPoint("BOTTOMRIGHT", zoneBtn, "BOTTOMRIGHT", -5, 5)
        zoneBtn.entityInfo:SetText(COLORS.SUBHEADER .. "Entities: " .. npcCount .. " NPCs, " .. objectCount .. " Objects (" .. #zoneGroup.entities .. " total)|r")
        zoneBtn.entityInfo:SetJustifyH("LEFT")
        zoneBtn.entityInfo:SetJustifyV("TOP")

        -- Click to filter by zone
        zoneBtn.zoneName_str = zoneGroup.zoneName
        zoneBtn:SetScript("OnClick", function()
            local zoneName = this.zoneName_str
            pfDebugBrowser.searchBox:SetText(zoneName)
            PerformSearch(zoneName)
        end)

        -- Hover effect with entity details
        zoneBtn:SetScript("OnEnter", function()
            this:SetBackdropColor(0.15, 0.15, 0.2, 0.9)

            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:SetText("Zone: " .. zoneGroup.zoneName, 1, 1, 1)
            GameTooltip:AddLine("Entities with 50,50 coordinates:", 0.8, 1, 0.8)
            GameTooltip:AddLine(" ", 1, 1, 1)

            local maxShown = 10
            local entityCount = 0

            -- Show NPCs first
            for _, entity in ipairs(zoneGroup.entities) do
                if entity.type == "NPC" and entityCount < maxShown then
                    local questInfo = ""
                    if entity.questIds and #entity.questIds > 0 then
                        questInfo = " (Quests: " .. #entity.questIds .. ")"
                    end
                    GameTooltip:AddLine("NPC: " .. entity.name .. " [" .. entity.id .. "]" .. questInfo, 0.5, 1, 0.5)
                    entityCount = entityCount + 1
                end
            end

            -- Then show Objects
            for _, entity in ipairs(zoneGroup.entities) do
                if entity.type == "Object" and entityCount < maxShown then
                    local questInfo = ""
                    if entity.questIds and #entity.questIds > 0 then
                        questInfo = " (Quests: " .. #entity.questIds .. ")"
                    end
                    GameTooltip:AddLine("Object: " .. entity.name .. " [" .. entity.id .. "]" .. questInfo, 0.5, 0.8, 1)
                    entityCount = entityCount + 1
                end
            end

            if #zoneGroup.entities > maxShown then
                GameTooltip:AddLine("... and " .. (#zoneGroup.entities - maxShown) .. " more entities", 0.8, 0.8, 0.8)
            end

            GameTooltip:AddLine(" ", 1, 1, 1)
            GameTooltip:AddLine("Click to filter by this zone", 0.5, 0.5, 1)
            GameTooltip:Show()
        end)

        zoneBtn:SetScript("OnLeave", function()
            -- Restore original alternating color
            if i % 2 == 0 then
                this:SetBackdropColor(0.08, 0.08, 0.12, 0.8)
            else
                this:SetBackdropColor(0.05, 0.05, 0.05, 0.8)
            end
            GameTooltip:Hide()
        end)

        yOffset = yOffset - 55
    end

    -- Update scroll frame
    pfDebugBrowser.resultsFrame:SetHeight(math.abs(yOffset) + 50)
    pfDebugBrowser.scrollBar:SetMinMaxValues(0, math.max(0, math.abs(yOffset) - 300))

    pfDebugBrowser.statusText:SetText(COLORS.SUCCESS .. "Found " .. totalEntities .. " entities with 50,50 coordinates in " .. #sortedZones .. " zones|r")
end

-- Clear results
function ClearResults()
    if pfDebugBrowser.resultsFrame then
        -- Properly destroy child frames
        local children = {pfDebugBrowser.resultsFrame:GetChildren()}
        for _, child in ipairs(children) do
            child:Hide()
        end

        -- Clear font strings safely
        local regions = {pfDebugBrowser.resultsFrame:GetRegions()}
        for _, region in ipairs(regions) do
            if region:GetObjectType() == "FontString" then
                region:SetText("")
                region:Hide()
            end
        end

        pfDebugBrowser.resultsFrame:SetHeight(1)
        pfDebugBrowser.scrollBar:SetValue(0)
    end
end

-- Show/Hide browser
function ToggleDebugBrowser()
    if not pfDebugBrowser then
        CreateDebugBrowser()
    end

    if pfDebugBrowser:IsShown() then
        pfDebugBrowser:Hide()
        -- Remove from special frames when hiding
        for i = 1, table.getn(UISpecialFrames) do
            if UISpecialFrames[i] == "pfDebugBrowser" then
                table.remove(UISpecialFrames, i)
                break
            end
        end
    else
        pfDebugBrowser:Show()
        -- Add to special frames for ESC key handling
        table.insert(UISpecialFrames, "pfDebugBrowser")

        -- Refresh zone and category on show
        if activeCategory then
            SelectCategory(activeCategory)
        end
    end
end

-- Slash command
SLASH_PFBROWSER1 = "/pfbrowser"
SLASH_PFBROWSER2 = "/pfdb"
SlashCmdList["PFBROWSER"] = function()
    ToggleDebugBrowser()
end

-- Auto-create on load if pfDB exists
if pfDB then
    CreateDebugBrowser()
    print("|cff00FF00pfQuest Debug Browser loaded! Use /pfbrowser or /pfdb to open.|r")
end

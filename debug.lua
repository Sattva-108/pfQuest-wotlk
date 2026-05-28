-- pfQuest Debug Script - Enhanced Analysis
-- Usage: /pftest and /pfq <questID>

local STAR  = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:16:16|t"
local CIRCE  = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_2:16:16|t"
local DIAMOND  = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3:16:16|t"
local TRIANGLE  = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_4:16:16|t"
local MOON  = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_5:16:16|t"
local SQUARE  = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_6:16:16|t"
local CROSS = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_7:16:16|t"
local SKULL  = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:16:16|t"



local function findWorkingQuests()
    if not pfDB then
        print(STAR .. " pfDB not loaded")
        return {}
    end

    if not pfDB["quests"] or not pfDB["quests"]["data"] then
        print(STAR .. " No quest data found")
        return {}
    end

    local workingQuests = {}

    for questId, quest in pairs(pfDB["quests"]["data"]) do
        -- A quest is "working" if it has NPCs/objects with actual coordinates
        local hasStarterWithCoords = false
        local hasFinisherWithCoords = false

        -- Check for quest starters WITH coordinates
        if quest.start then
            -- Check starter NPCs
            if quest.start.U then
                for _, unitId in ipairs(quest.start.U) do
                    local unit = pfDB["units"] and pfDB["units"]["data"] and pfDB["units"]["data"][unitId]
                    if unit and unit.coords and #unit.coords > 0 then
                        hasStarterWithCoords = true
                        break
                    end
                end
            end
            -- Check starter objects (if no NPC with coords found)
            if not hasStarterWithCoords and quest.start.O then
                for _, objectId in ipairs(quest.start.O) do
                    local obj = pfDB["objects"] and pfDB["objects"]["data"] and pfDB["objects"]["data"][objectId]
                    if obj and obj.coords and #obj.coords > 0 then
                        hasStarterWithCoords = true
                        break
                    end
                end
            end
            -- Items always count as valid starters
            if not hasStarterWithCoords and quest.start.I and #quest.start.I > 0 then
                hasStarterWithCoords = true
            end
        end

        -- Check for quest finishers WITH coordinates
        if quest["end"] then
            -- Check finisher NPCs
            if quest["end"].U then
                for _, unitId in ipairs(quest["end"].U) do
                    local unit = pfDB["units"] and pfDB["units"]["data"] and pfDB["units"]["data"][unitId]
                    if unit and unit.coords and #unit.coords > 0 then
                        hasFinisherWithCoords = true
                        break
                    end
                end
            end
            -- Check finisher objects (if no NPC with coords found)
            if not hasFinisherWithCoords and quest["end"].O then
                for _, objectId in ipairs(quest["end"].O) do
                    local obj = pfDB["objects"] and pfDB["objects"]["data"] and pfDB["objects"]["data"][objectId]
                    if obj and obj.coords and #obj.coords > 0 then
                        hasFinisherWithCoords = true
                        break
                    end
                end
            end
        end

        -- Only count as working if BOTH starter and finisher have coordinates
        if hasStarterWithCoords and hasFinisherWithCoords then
            table.insert(workingQuests, questId)
        end
    end

    -- Sort quest IDs
    table.sort(workingQuests)

    return workingQuests
end

local function findWorkingQuestsWithItemDrops()
    if not pfDB then
        print(STAR .. " pfDB not loaded")
        return {}
    end

    if not pfDB["quests"] or not pfDB["quests"]["data"] or not pfDB["items"] or not pfDB["items"]["data"] then
        print(STAR .. " No quest or items data found")
        return {}
    end

    local workingQuestsWithDrops = {}

    for questId, quest in pairs(pfDB["quests"]["data"]) do
        -- First check if quest is working (has starter and finisher with coords)
        local hasStarterWithCoords = false
        local hasFinisherWithCoords = false

        -- Check for quest starters WITH coordinates
        if quest.start then
            -- Check starter NPCs
            if quest.start.U then
                for _, unitId in ipairs(quest.start.U) do
                    local unit = pfDB["units"] and pfDB["units"]["data"] and pfDB["units"]["data"][unitId]
                    if unit and unit.coords and #unit.coords > 0 then
                        hasStarterWithCoords = true
                        break
                    end
                end
            end
            -- Check starter objects (if no NPC with coords found)
            if not hasStarterWithCoords and quest.start.O then
                for _, objectId in ipairs(quest.start.O) do
                    local obj = pfDB["objects"] and pfDB["objects"]["data"] and pfDB["objects"]["data"][objectId]
                    if obj and obj.coords and #obj.coords > 0 then
                        hasStarterWithCoords = true
                        break
                    end
                end
            end
            -- Items always count as valid starters
            if not hasStarterWithCoords and quest.start.I and #quest.start.I > 0 then
                hasStarterWithCoords = true
            end
        end

        -- Check for quest finishers WITH coordinates
        if quest["end"] then
            -- Check finisher NPCs
            if quest["end"].U then
                for _, unitId in ipairs(quest["end"].U) do
                    local unit = pfDB["units"] and pfDB["units"]["data"] and pfDB["units"]["data"][unitId]
                    if unit and unit.coords and #unit.coords > 0 then
                        hasFinisherWithCoords = true
                        break
                    end
                end
            end
            -- Check finisher objects (if no NPC with coords found)
            if not hasFinisherWithCoords and quest["end"].O then
                for _, objectId in ipairs(quest["end"].O) do
                    local obj = pfDB["objects"] and pfDB["objects"]["data"] and pfDB["objects"]["data"][objectId]
                    if obj and obj.coords and #obj.coords > 0 then
                        hasFinisherWithCoords = true
                        break
                    end
                end
            end
        end

        -- Only continue if quest is working (both starter and finisher have coordinates)
        if hasStarterWithCoords and hasFinisherWithCoords then
            -- Check if quest has item objectives that drop from mobs
            if quest.obj and quest.obj.I then
                local hasItemDrops = false
                local itemDropInfo = {}

                for _, itemId in ipairs(quest.obj.I) do
                    local itemData = pfDB["items"]["data"][itemId]
                    if itemData and itemData.U and TableCount(itemData.U) > 0 then
                        hasItemDrops = true
                        -- Store info about this item and its drop sources
                        local itemName = (pfDB["items"]["loc"] and pfDB["items"]["loc"][itemId]) or ("Item " .. itemId)
                        local dropSources = {}

                        for unitId, chanceOrData in pairs(itemData.U) do
                            local unitName = (pfDB["units"]["loc"] and pfDB["units"]["loc"][unitId]) or ("NPC " .. unitId)
                            local chanceStr = type(chanceOrData) == "number" and chanceOrData .. "%" or "complex"
                            table.insert(dropSources, {unitId = unitId, unitName = unitName, chance = chanceStr})
                        end

                        table.insert(itemDropInfo, {itemId = itemId, itemName = itemName, sources = dropSources})
                    end
                end

                if hasItemDrops then
                    table.insert(workingQuestsWithDrops, {questId = questId, quest = quest, itemDropInfo = itemDropInfo})
                end
            end
        end
    end

    -- Sort quest IDs
    table.sort(workingQuestsWithDrops, function(a, b) return a.questId < b.questId end)

    return workingQuestsWithDrops
end

SLASH_PFTEST1 = "/pftest"
SlashCmdList["PFTEST"] = function()
    print("=== pfQuest Enhanced Debug ===")

    -- Check if pfDB is loaded
    if not pfDB then
        print(SKULL .. " pfDB not loaded! Make sure pfQuest addon is running.")
        return
    end

    -- Display loaded data counts
    local questCount = pfDB["quests"] and pfDB["quests"]["data"] and TableCount(pfDB["quests"]["data"]) or 0
    local unitCount = pfDB["units"] and pfDB["units"]["data"] and TableCount(pfDB["units"]["data"]) or 0
    local zoneCount = pfDB["zones"] and pfDB["zones"]["data"] and TableCount(pfDB["zones"]["data"]) or 0

    -- Count units with coordinates
    local unitsWithCoords = 0
    if pfDB["units"] and pfDB["units"]["data"] then
        for unitId, unit in pairs(pfDB["units"]["data"]) do
            if unit.coords and #unit.coords > 0 then
                unitsWithCoords = unitsWithCoords + 1
            end
        end
    end

    print(SQUARE .. " Data loaded:")
    print("   Quests: " .. questCount)
    print("   Units: " .. unitCount .. " (" .. unitsWithCoords .. " with coords)")
    print("   Zones: " .. zoneCount)

    -- Find working quests
    print(DIAMOND .. " Finding working quests...")
    local workingQuests = findWorkingQuests()

    -- Find working quests with item drops for chance testing
    print(DIAMOND .. " Finding working quests with item drops for chance testing...")
    local workingQuestsWithDrops = findWorkingQuestsWithItemDrops()

    -- Get player faction for sorting
    local playerFaction = UnitFactionGroup("player") -- "Alliance" or "Horde"
    local hordeQuests = {}
    local allianceQuests = {}
    local bothFactionsQuests = {}

    -- Separate regular working quests by faction and prerequisite status
    local hordeQuestsNoPre = {}
    local hordeQuestsWithPre = {}
    local allianceQuestsNoPre = {}
    local allianceQuestsWithPre = {}
    local bothFactionsQuestsNoPre = {}
    local bothFactionsQuestsWithPre = {}

    for _, questId in ipairs(workingQuests) do
        local quest = pfDB["quests"]["data"][questId]
        local hasPrerequisite = quest.pre ~= nil

        if quest.race then
            if quest.race == 690 then
                if hasPrerequisite then
                    table.insert(hordeQuestsWithPre, questId)
                else
                    table.insert(hordeQuestsNoPre, questId)
                end
            elseif quest.race == 1101 then
                if hasPrerequisite then
                    table.insert(allianceQuestsWithPre, questId)
                else
                    table.insert(allianceQuestsNoPre, questId)
                end
            end
        else
            -- No race restriction = both factions
            if hasPrerequisite then
                table.insert(bothFactionsQuestsWithPre, questId)
            else
                table.insert(bothFactionsQuestsNoPre, questId)
            end
        end
    end

    -- Combine for counting
    local hordeQuests = {}
    for _, qid in ipairs(hordeQuestsNoPre) do table.insert(hordeQuests, qid) end
    for _, qid in ipairs(hordeQuestsWithPre) do table.insert(hordeQuests, qid) end

    local allianceQuests = {}
    for _, qid in ipairs(allianceQuestsNoPre) do table.insert(allianceQuests, qid) end
    for _, qid in ipairs(allianceQuestsWithPre) do table.insert(allianceQuests, qid) end

    local bothFactionsQuests = {}
    for _, qid in ipairs(bothFactionsQuestsNoPre) do table.insert(bothFactionsQuests, qid) end
    for _, qid in ipairs(bothFactionsQuestsWithPre) do table.insert(bothFactionsQuests, qid) end

    -- Separate item drop quests by faction and prerequisite status
    local hordeDropQuestsNoPre = {}
    local hordeDropQuestsWithPre = {}
    local allianceDropQuestsNoPre = {}
    local allianceDropQuestsWithPre = {}
    local bothFactionsDropQuestsNoPre = {}
    local bothFactionsDropQuestsWithPre = {}

    for _, questInfo in ipairs(workingQuestsWithDrops) do
        local quest = questInfo.quest
        local hasPrerequisite = quest.pre ~= nil

        if quest.race then
            if quest.race == 690 then
                if hasPrerequisite then
                    table.insert(hordeDropQuestsWithPre, questInfo)
                else
                    table.insert(hordeDropQuestsNoPre, questInfo)
                end
            elseif quest.race == 1101 then
                if hasPrerequisite then
                    table.insert(allianceDropQuestsWithPre, questInfo)
                else
                    table.insert(allianceDropQuestsNoPre, questInfo)
                end
            end
        else
            -- No race restriction = both factions
            if hasPrerequisite then
                table.insert(bothFactionsDropQuestsWithPre, questInfo)
            else
                table.insert(bothFactionsDropQuestsNoPre, questInfo)
            end
        end
    end

    -- Combine for counting
    local hordeDropQuests = {}
    for _, questInfo in ipairs(hordeDropQuestsNoPre) do table.insert(hordeDropQuests, questInfo) end
    for _, questInfo in ipairs(hordeDropQuestsWithPre) do table.insert(hordeDropQuests, questInfo) end

    local allianceDropQuests = {}
    for _, questInfo in ipairs(allianceDropQuestsNoPre) do table.insert(allianceDropQuests, questInfo) end
    for _, questInfo in ipairs(allianceDropQuestsWithPre) do table.insert(allianceDropQuests, questInfo) end

    local bothFactionsDropQuests = {}
    for _, questInfo in ipairs(bothFactionsDropQuestsNoPre) do table.insert(bothFactionsDropQuests, questInfo) end
    for _, questInfo in ipairs(bothFactionsDropQuestsWithPre) do table.insert(bothFactionsDropQuests, questInfo) end

    if #workingQuests > 0 then
        print(STAR .. " Found " .. #workingQuests .. " working quests total!")
        print("   Horde only: " .. #hordeQuests)
        print("   Alliance only: " .. #allianceQuests)
        print("   Both factions: " .. #bothFactionsQuests)
        print(CIRCE .. " Found " .. #workingQuestsWithDrops .. " working quests with item drops for chance testing!")
        print("   Horde only (with drops): " .. #hordeDropQuests)
        print("   Alliance only (with drops): " .. #allianceDropQuests)
        print("   Both factions (with drops): " .. #bothFactionsDropQuests)

        -- Create display list prioritizing player faction for regular quests
        -- Priority: 1) Player faction without prerequisites, 2) Both factions without prerequisites, 3) Player faction with prerequisites, 4) Both factions with prerequisites
        local displayQuests = {}
        if playerFaction == "Horde" then
            -- First: Horde quests without prerequisites
            for _, qid in ipairs(hordeQuestsNoPre) do table.insert(displayQuests, qid) end
            -- Second: Both factions quests without prerequisites
            for _, qid in ipairs(bothFactionsQuestsNoPre) do table.insert(displayQuests, qid) end
            -- Third: Horde quests with prerequisites
            for _, qid in ipairs(hordeQuestsWithPre) do table.insert(displayQuests, qid) end
            -- Fourth: Both factions quests with prerequisites
            for _, qid in ipairs(bothFactionsQuestsWithPre) do table.insert(displayQuests, qid) end
        else
            -- First: Alliance quests without prerequisites
            for _, qid in ipairs(allianceQuestsNoPre) do table.insert(displayQuests, qid) end
            -- Second: Both factions quests without prerequisites
            for _, qid in ipairs(bothFactionsQuestsNoPre) do table.insert(displayQuests, qid) end
            -- Third: Alliance quests with prerequisites
            for _, qid in ipairs(allianceQuestsWithPre) do table.insert(displayQuests, qid) end
            -- Fourth: Both factions quests with prerequisites
            for _, qid in ipairs(bothFactionsQuestsWithPre) do table.insert(displayQuests, qid) end
        end

        -- Create display list prioritizing player faction for drop quests
        -- Same priority logic for item drop quests
        local displayDropQuests = {}
        if playerFaction == "Horde" then
            -- First: Horde drop quests without prerequisites
            for _, questInfo in ipairs(hordeDropQuestsNoPre) do table.insert(displayDropQuests, questInfo) end
            -- Second: Both factions drop quests without prerequisites
            for _, questInfo in ipairs(bothFactionsDropQuestsNoPre) do table.insert(displayDropQuests, questInfo) end
            -- Third: Horde drop quests with prerequisites
            for _, questInfo in ipairs(hordeDropQuestsWithPre) do table.insert(displayDropQuests, questInfo) end
            -- Fourth: Both factions drop quests with prerequisites
            for _, questInfo in ipairs(bothFactionsDropQuestsWithPre) do table.insert(displayDropQuests, questInfo) end
        else
            -- First: Alliance drop quests without prerequisites
            for _, questInfo in ipairs(allianceDropQuestsNoPre) do table.insert(displayDropQuests, questInfo) end
            -- Second: Both factions drop quests without prerequisites
            for _, questInfo in ipairs(bothFactionsDropQuestsNoPre) do table.insert(displayDropQuests, questInfo) end
            -- Third: Alliance drop quests with prerequisites
            for _, questInfo in ipairs(allianceDropQuestsWithPre) do table.insert(displayDropQuests, questInfo) end
            -- Fourth: Both factions drop quests with prerequisites
            for _, questInfo in ipairs(bothFactionsDropQuestsWithPre) do table.insert(displayDropQuests, questInfo) end
        end

        -- Show first 15 examples of regular working quests
        local maxToShow = math.min(15, #displayQuests)
        print(TRIANGLE .. " Showing first " .. maxToShow .. " " .. playerFaction .. " working quest examples:")

        for i = 1, maxToShow do
            local questId = displayQuests[i]
            -- Get quest name, handle if it's a table
            local questName = "Quest " .. questId
            if pfDB["quests"] and pfDB["quests"]["loc"] and pfDB["quests"]["loc"][questId] then
                local questData = pfDB["quests"]["loc"][questId]
                if type(questData) == "table" and questData.T then
                    questName = questData.T  -- Title from table
                elseif type(questData) == "string" then
                    questName = questData
                end
            end

            -- Get quest info for race and zones
            local quest = pfDB["quests"]["data"][questId]
            local raceInfo = ""
            local zoneInfo = ""

            if quest then
                -- Race info (fixed codes)
                if quest.race then
                    if quest.race == 1101 then raceInfo = " [Alliance]"
                    elseif quest.race == 690 then raceInfo = " [Horde]"
                    elseif quest.race == 77 then raceInfo = " [Alliance-old]"
                    elseif quest.race == 178 then raceInfo = " [Horde-old]"
                    else raceInfo = " [Race:" .. quest.race .. "]" end
                else
                    raceInfo = " [Both factions]"
                end

                -- Zone info from starter NPCs with names
                if quest.start and quest.start.U then
                    for _, unitId in ipairs(quest.start.U) do
                        if pfDB["units"]["data"][unitId] and pfDB["units"]["data"][unitId].coords then
                            for _, coord in ipairs(pfDB["units"]["data"][unitId].coords) do
                                local zoneId = coord[3]
                                if zoneId == 1519 then zoneInfo = " (Stormwind City)"
                                elseif zoneId == 1637 then zoneInfo = " (Orgrimmar)"
                                elseif zoneId == 14 then zoneInfo = " (Durotar)"
                                elseif zoneId == 3520 then zoneInfo = " (Hellfire Peninsula)"
                                elseif zoneId == 65 then zoneInfo = " (Dragonblight)"
                                else
                                    -- Try to get zone name from pfDB
                                    if pfDB["zones"] and pfDB["zones"]["loc"] and pfDB["zones"]["loc"][zoneId] then
                                        zoneInfo = " (" .. pfDB["zones"]["loc"][zoneId] .. ")"
                                    else
                                        zoneInfo = " (Zone:" .. zoneId .. ")"
                                    end
                                end
                                break
                            end
                            break
                        else
                            zoneInfo = " (Unit " .. unitId .. " no coords)"
                        end
                    end
                else
                    zoneInfo = " (No start NPC)"
                end
            end

            print("   " .. questId .. ": " .. questName .. raceInfo .. zoneInfo)
        end

        -- Show first 10 examples of working quests with item drops for chance testing
        if #displayDropQuests > 0 then
            local maxDropToShow = math.min(10, #displayDropQuests)
            print("")
            print(DIAMOND .. " Showing first " .. maxDropToShow .. " " .. playerFaction .. " working quests with ITEM DROPS for chance testing:")

            for i = 1, maxDropToShow do
                local questInfo = displayDropQuests[i]
                local questId = questInfo.questId
                local quest = questInfo.quest
                local itemDropInfo = questInfo.itemDropInfo

                -- Get quest name, handle if it's a table
                local questName = "Quest " .. questId
                if pfDB["quests"] and pfDB["quests"]["loc"] and pfDB["quests"]["loc"][questId] then
                    local questData = pfDB["quests"]["loc"][questId]
                    if type(questData) == "table" and questData.T then
                        questName = questData.T  -- Title from table
                    elseif type(questData) == "string" then
                        questName = questData
                    end
                end

                -- Get quest info for race and zones
                local raceInfo = ""
                local zoneInfo = ""

                if quest then
                    -- Race info (fixed codes)
                    if quest.race then
                        if quest.race == 1101 then raceInfo = " [Alliance]"
                        elseif quest.race == 690 then raceInfo = " [Horde]"
                        elseif quest.race == 77 then raceInfo = " [Alliance-old]"
                        elseif quest.race == 178 then raceInfo = " [Horde-old]"
                        else raceInfo = " [Race:" .. quest.race .. "]" end
                    else
                        raceInfo = " [Both factions]"
                    end

                    -- Zone info from starter NPCs with names
                    if quest.start and quest.start.U then
                        for _, unitId in ipairs(quest.start.U) do
                            if pfDB["units"]["data"][unitId] and pfDB["units"]["data"][unitId].coords then
                                for _, coord in ipairs(pfDB["units"]["data"][unitId].coords) do
                                    local zoneId = coord[3]
                                    if zoneId == 1519 then zoneInfo = " (Stormwind City)"
                                    elseif zoneId == 1637 then zoneInfo = " (Orgrimmar)"
                                    elseif zoneId == 14 then zoneInfo = " (Durotar)"
                                    elseif zoneId == 3520 then zoneInfo = " (Hellfire Peninsula)"
                                    elseif zoneId == 65 then zoneInfo = " (Dragonblight)"
                                    else
                                        -- Try to get zone name from pfDB
                                        if pfDB["zones"] and pfDB["zones"]["loc"] and pfDB["zones"]["loc"][zoneId] then
                                            zoneInfo = " (" .. pfDB["zones"]["loc"][zoneId] .. ")"
                                        else
                                            zoneInfo = " (Zone:" .. zoneId .. ")"
                                        end
                                    end
                                    break
                                end
                                break
                            else
                                zoneInfo = " (Unit " .. unitId .. " no coords)"
                            end
                        end
                    else
                        zoneInfo = " (No start NPC)"
                    end
                end

                -- Show quest with item drop indicator
                local itemsInfo = ""
                if #itemDropInfo > 0 then
                    itemsInfo = " [Items: " .. #itemDropInfo .. "]"
                end
                print("   " .. questId .. ": " .. questName .. raceInfo .. zoneInfo .. itemsInfo)
            end
        else
            print("")
            print(SKULL .. " No working quests found with item drops for chance testing!")
        end

        print("")
        print(MOON .. " TEST COMMANDS:")
        for i = 1, math.min(3, #displayQuests) do
            print("   /pfq " .. displayQuests[i])
        end
        if #displayDropQuests > 0 then
            print(DIAMOND .. " CHANCE TEST COMMANDS:")
            for i = 1, math.min(3, #displayDropQuests) do
                print("   /pfq " .. displayDropQuests[i].questId .. " (has item drops)")
            end
        end
    else
        print(SKULL .. " No working quests found!")
    end

    print("=== End Debug ===")
end

-- Register slash command for quest testing
SLASH_PFQUESTTEST1 = "/pfq"
SlashCmdList["PFQUESTTEST"] = function(questId)
    questId = tonumber(questId)
    if not questId then
        print(SKULL .. " Usage: /pfq <questID>")
        print("   Example: /pfq 784")
        return
    end

    local quest = pfDB["quests"]["data"][questId]
    if not quest then
        print(SKULL .. " Quest " .. questId .. " not found in database")
        return
    end

    print("=== pfQuest Quest Analysis ===")
    print(DIAMOND .. " Testing Quest " .. questId)

    -- Get quest name, handle if it's a table
    local questName = "Quest " .. questId
    if pfDB["quests"]["loc"] and pfDB["quests"]["loc"][questId] then
        local questData = pfDB["quests"]["loc"][questId]
        if type(questData) == "table" and questData.T then
            questName = questData.T  -- Title from table
        elseif type(questData) == "string" then
            questName = questData
        end
    end

    print(TRIANGLE .. " " .. questName)

    -- Quest level and race info
    print(SQUARE .. " Level: " .. (quest.lvl or "Unknown") .. " (Min: " .. (quest.min or "Unknown") .. ")")
    local raceInfo = ""
    if quest.race then
        if quest.race == 1101 then raceInfo = "Alliance"
        elseif quest.race == 690 then raceInfo = "Horde"
        else raceInfo = "Race " .. quest.race end
    else
        raceInfo = "Both factions"
    end
    print(MOON .. " Faction: " .. raceInfo)

    -- Check quest starters
    if quest.start then
        print(STAR .. " Quest Starters:")
        if quest.start.U then
            for i, unitId in ipairs(quest.start.U) do
                local unit = pfDB["units"]["data"][unitId]
                if unit then
                    local coords_count = unit.coords and #unit.coords or 0
                    print("   NPC " .. unitId .. ": " .. coords_count .. " spawns")
                    if coords_count > 0 then
                        local coord = unit.coords[1]
                        print("     First spawn: " .. coord[1] .. ", " .. coord[2] .. " zone " .. coord[3])
                        -- Check if zone exists in pfQuest zones
                        local zone_names = {
                            [14] = "Durotar",
                            [1519] = "Stormwind City",
                            [1637] = "Orgrimmar",
                            [17] = "The Barrens",
                            [141] = "Teldrassil",
                            [215] = "Mulgore",
                            [3520] = "Hellfire Peninsula",
                            [65] = "Dragonblight"
                        }

                        local zone_name = zone_names[coord[3]]
                        if not zone_name and pfDB["zones"] and pfDB["zones"]["data"] and pfDB["zones"]["data"][coord[3]] then
                            zone_name = "Zone " .. coord[3]  -- We have zone data but no name lookup yet
                        end
                        zone_name = zone_name or "Unknown"

                        print("     Zone: " .. zone_name .. " (ID: " .. coord[3] .. ")")
                    end
                else
                    print("   NPC " .. unitId .. ": NO DATA")
                end
            end
        end
        if quest.start.O then
            for i, objectId in ipairs(quest.start.O) do
                print("   Object " .. objectId .. ": Check objects table")
            end
        end
        if quest.start.I then
            for i, itemId in ipairs(quest.start.I) do
                print("   Item " .. itemId .. ": Quest starting item")
            end
        end
    else
        print(SKULL .. " No quest starters found!")
    end

    -- Check quest finishers
    if quest["end"] then
        print(CROSS .. " Quest Finishers:")
        if quest["end"].U then
            for i, unitId in ipairs(quest["end"].U) do
                local unit = pfDB["units"]["data"][unitId]
                if unit then
                    local coords_count = unit.coords and #unit.coords or 0
                    print("   NPC " .. unitId .. ": " .. coords_count .. " spawns")
                    if coords_count > 0 then
                        local coord = unit.coords[1]
                        print("     Location: " .. coord[1] .. ", " .. coord[2] .. " zone " .. coord[3])
                    end
                else
                    print("   NPC " .. unitId .. ": NO DATA")
                end
            end
        end
        if quest["end"].O then
            for i, objectId in ipairs(quest["end"].O) do
                print("   Object " .. objectId .. ": Check objects table")
            end
        end
    else
        print(SKULL .. " No quest finishers found!")
    end

    -- Check unit objectives
    if quest.obj and quest.obj.U then
        print(SKULL .. " Unit objectives:")
        for i, unitId in ipairs(quest.obj.U) do
            local unit = pfDB["units"]["data"][unitId]
            if unit then
                local coords_count = unit.coords and #unit.coords or 0
                print("   Unit " .. unitId .. ": " .. coords_count .. " spawns")
                if coords_count > 0 then
                    local coord = unit.coords[1]
                    print("     First spawn: " .. coord[1] .. ", " .. coord[2] .. " zone " .. coord[3])
                end
            else
                print("   Unit " .. unitId .. ": NO DATA")
            end
        end
    end

    -- Check item objectives
    if quest.obj and quest.obj.I then
        print(SQUARE .. " Item objectives:")
        for i, itemId in ipairs(quest.obj.I) do
            print("   Item " .. itemId)
        end
    end

    -- pfQuest working quest analysis
    print("")
    print(CIRCE .. " pfQuest Analysis:")
    local hasStarter = (quest.start and (quest.start.U or quest.start.O or quest.start.I))
    local hasFinisher = (quest["end"] and (quest["end"].U or quest["end"].O))

    -- Check if starters have coordinates
    local starterHasCoords = false
    if quest.start then
        if quest.start.U then
            for _, unitId in ipairs(quest.start.U) do
                local unit = pfDB["units"]["data"][unitId]
                if unit and unit.coords and #unit.coords > 0 then
                    starterHasCoords = true
                    break
                end
            end
        end
        if not starterHasCoords and quest.start.O then
            for _, objId in ipairs(quest.start.O) do
                local obj = pfDB["objects"]["data"][objId]
                if obj and obj.coords and #obj.coords > 0 then
                    starterHasCoords = true
                    break
                end
            end
        end
        if not starterHasCoords and quest.start.I and #quest.start.I > 0 then
            starterHasCoords = true -- Items don't need coordinates
        end
    end

    -- Check if finishers have coordinates
    local finisherHasCoords = false
    if quest["end"] then
        if quest["end"].U then
            for _, unitId in ipairs(quest["end"].U) do
                local unit = pfDB["units"]["data"][unitId]
                if unit and unit.coords and #unit.coords > 0 then
                    finisherHasCoords = true
                    break
                end
            end
        end
        if not finisherHasCoords and quest["end"].O then
            for _, objId in ipairs(quest["end"].O) do
                local obj = pfDB["objects"]["data"][objId]
                if obj and obj.coords and #obj.coords > 0 then
                    finisherHasCoords = true
                    break
                end
            end
        end
    end

    print("   Has starter: " .. (hasStarter and STAR .. " YES" or SKULL .. " NO"))
    print("   Starter coords: " .. (starterHasCoords and STAR .. " YES" or SKULL .. " NO"))
    print("   Has finisher: " .. (hasFinisher and STAR .. " YES" or SKULL .. " NO"))
    print("   Finisher coords: " .. (finisherHasCoords and STAR .. " YES" or SKULL .. " NO"))

    if hasStarter and hasFinisher and starterHasCoords and finisherHasCoords then
        print("   Status: " .. STAR .. " WORKING QUEST - should appear on map!")
        print("   " .. TRIANGLE .. " Should appear on map if zone coordinates are correct")

        -- Additional map debugging
        if quest.start and quest.start.U then
            for i, unitId in ipairs(quest.start.U) do
                local unit = pfDB["units"]["data"][unitId]
                if unit and unit.coords and #unit.coords > 0 then
                    local coord = unit.coords[1]
                    local zoneId = coord[3]
                    print("   " .. DIAMOND .. " Map Debug: Quest starter at zone " .. zoneId)
                    if zoneId == 14 then
                        print("      " .. STAR .. " Should appear in Durotar area on Kalimdor map")
                    elseif zoneId == 1519 then
                        print("      " .. STAR .. " Should appear in Stormwind area on Eastern Kingdoms map")
                    elseif zoneId == 1637 then
                        print("      " .. STAR .. " Should appear in Orgrimmar area on Kalimdor map")
                    else
                        print("      " .. STAR .. " Zone mapping available - should appear on map")
                    end
                end
            end
        end
    elseif not hasStarter or not hasFinisher then
        print("   Status: " .. SKULL .. " BROKEN - missing starter or finisher")
    elseif not starterHasCoords or not finisherHasCoords then
        print("   Status: " .. SKULL .. " BROKEN - NPCs/objects have no coordinates!")
        print("   " .. SQUARE .. " This is why quest doesn't show on map")
    else
        print("   Status: " .. SKULL .. " NOT a working quest")
    end

    print("=== End Analysis ===")
end

-- Helper function for counting table entries
function TableCount(t)
    if not t then return 0 end
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

 --print(STAR .. " Enhanced pfQuest debug loaded! Use /pfa, /pftest, /pfq <questID>, and /pfr [rareID]")

-- Register slash command for rares testing
SLASH_PFRARETEST1 = "/pfr"
SlashCmdList["PFRARETEST"] = function(rareId)
    if not pfDB then
        print(SKULL .. " pfDB not loaded! Make sure pfQuest addon is running.")
        return
    end

    -- DEBUG: Check pfDB structure for meta
    print("=== DEBUG pfDB Meta Structure ===")
    print("pfDB type:", type(pfDB))

    if pfDB then
        print("pfDB keys:")
        for k, v in pairs(pfDB) do
            print("  " .. tostring(k) .. " = " .. tostring(type(v)))
        end

        if pfDB["meta"] then
            print("pfDB['meta'] exists, checking contents:")
            for k, v in pairs(pfDB["meta"]) do
                if k == "rares" and type(v) == "table" then
                    local count = 0
                    for _ in pairs(v) do count = count + 1 end
                    print("  Found rares table with " .. count .. " entries")
                    -- Show first few entries
                    local shown = 0
                    for rareId, level in pairs(v) do
                        if shown < 3 then
                            print("    Rare " .. rareId .. " = level " .. level)
                            shown = shown + 1
                        else
                            break
                        end
                    end
                else
                    print("  Key: " .. tostring(k) .. " = " .. tostring(type(v)))
                end
            end
        else
            print("pfDB['meta'] does not exist")
        end
    else
        print("pfDB is nil!")
    end
    print("=== End DEBUG ===")

    -- Check if specific rare ID provided
    if rareId and rareId ~= "" then
        rareId = tonumber(rareId)
        if not rareId then
            print(SKULL .. " Usage: /pfr <rareID> or /pfr for overview")
            return
        end

        -- Detailed rare analysis
        print("=== pfQuest Rare Analysis ===")
        print(DIAMOND .. " Testing Rare " .. rareId)

        -- Check in meta rares
        local rareLevel = nil
        if pfDB["meta"] and pfDB["meta"]["rares"] then
            rareLevel = pfDB["meta"]["rares"][rareId]
        end

        if not rareLevel then
            print(SKULL .. " Rare " .. rareId .. " not found in meta.rares")
            return
        end

        print(TRIANGLE .. " Level: " .. rareLevel)

        -- Check in units data
        local unit = pfDB["units"] and pfDB["units"]["data"] and pfDB["units"]["data"][rareId]
        if unit then
            local coords_count = unit.coords and #unit.coords or 0
            print(STAR .. " Spawn locations: " .. coords_count)

            if coords_count > 0 then
                for i, coord in ipairs(unit.coords) do
                    local zone_names = {
                        [14] = "Durotar", [1519] = "Stormwind City", [1637] = "Orgrimmar",
                        [17] = "The Barrens", [141] = "Teldrassil", [215] = "Mulgore",
                        [3520] = "Hellfire Peninsula", [65] = "Dragonblight"
                    }
                    local zone_name = zone_names[coord[3]] or ("Zone " .. coord[3])
                    print("   " .. MOON .. " Spawn " .. i .. ": " .. coord[1] .. ", " .. coord[2] .. " in " .. zone_name)
                    if i >= 3 then break end -- Limit to first 3 spawns
                end
            else
                print(SKULL .. " No spawn coordinates found!")
            end

            -- Check name from locales
            local rareName = "Rare " .. rareId
            if pfDB["units"]["loc"] and pfDB["units"]["loc"][rareId] then
                rareName = pfDB["units"]["loc"][rareId]
            end
            print(SQUARE .. " Name: " .. rareName)

            -- Additional unit info
            if unit.lvl then print(CROSS .. " Unit level range: " .. unit.lvl) end
            if unit.fac then print(CROSS .. " Faction: " .. unit.fac) end
            if unit.rnk then print(CROSS .. " Rank: " .. unit.rnk) end
        else
            print(SKULL .. " Rare " .. rareId .. " not found in units data!")
        end

        print("=== End Rare Analysis ===")
    else
        -- Overview of all rares
        print("=== pfQuest Rares Overview ===")

        local raresCount = 0
        local raresWithCoords = 0
        local raresList = {}

        if pfDB["meta"] and pfDB["meta"]["rares"] then
            for rareId, level in pairs(pfDB["meta"]["rares"]) do
                raresCount = raresCount + 1

                -- Check if has coordinates
                local unit = pfDB["units"] and pfDB["units"]["data"] and pfDB["units"]["data"][rareId]
                if unit and unit.coords and #unit.coords > 0 then
                    raresWithCoords = raresWithCoords + 1
                    table.insert(raresList, {id = rareId, level = level, unit = unit})
                end
            end
        end

        print(SQUARE .. " Rares total: " .. raresCount .. " | With coords: " .. raresWithCoords)

        if raresWithCoords > 0 then
            -- Sort by level
            table.sort(raresList, function(a, b) return a.level < b.level end)

            print(DIAMOND .. " Level distribution (with coords only):")
            local levelGroups = {}
            for _, rare in ipairs(raresList) do
                local levelRange = math.floor(rare.level / 10) * 10
                levelGroups[levelRange] = (levelGroups[levelRange] or 0) + 1
            end

            for level, count in pairs(levelGroups) do
                print("   Level " .. level .. "-" .. (level + 9) .. ": " .. count .. " rares")
            end

            -- Show examples with zones
            local maxToShow = math.min(10, #raresList)
            print(TRIANGLE .. " First " .. maxToShow .. " rares with coordinates:")

            for i = 1, maxToShow do
                local rare = raresList[i]
                local name = "Rare " .. rare.id

                if pfDB["units"]["loc"] and pfDB["units"]["loc"][rare.id] then
                    name = pfDB["units"]["loc"][rare.id]
                end

                local zoneId = rare.unit.coords[1][3]
                local zone_name = "Zone " .. zoneId

                -- Try to get zone name from pfDB
                if pfDB["zones"] and pfDB["zones"]["loc"] and pfDB["zones"]["loc"][zoneId] then
                    zone_name = pfDB["zones"]["loc"][zoneId]
                else
                    -- Fallback to common zone names
                    local zone_names = {
                        [14] = "Durotar", [1519] = "Stormwind City", [1637] = "Orgrimmar",
                        [17] = "The Barrens", [141] = "Teldrassil", [215] = "Mulgore",
                        [3520] = "Hellfire Peninsula", [65] = "Dragonblight"
                    }
                    zone_name = zone_names[zoneId] or zone_name
                end

                print("   " .. rare.id .. ": " .. name .. " [Lv" .. rare.level .. "] in " .. zone_name .. " (" .. #rare.unit.coords .. " spawns)")
            end

            print("")
            print(MOON .. " TEST COMMANDS:")
            for i = 1, math.min(3, #raresList) do
                print("   /pfr " .. raresList[i].id)
            end
        else
            print(SKULL .. " No rares found in meta database!")
        end

        print("=== End Rares Overview ===")
    end
end

-- === ГЛУБОКАЯ ПРОВЕРКА ДЛЯ /pfq ===
SLASH_PFQDEEP1 = "/pfqdeep"
SlashCmdList["PFQDEEP"] = function(msg)
  local qid = tonumber(msg)
  if not qid then print("Использование: /pfqdeep <questID>") return end
  print("=== pfQuest Deep Map Debug for QuestID:", qid, "===")

  -- 1. Проверка наличия квеста
  local quest = pfDB["quests"] and pfDB["quests"]["loc"] and pfDB["quests"]["loc"][qid]
  if not quest then print(SKULL .. " Quest not found in pfDB[quests][loc]") return end
  print(STAR .. " Quest found:", quest.T or "(no title)")

  -- 2. Проверка стартера/финишера
  local qdata = pfDB["quests"] and pfDB["quests"]["data"] and pfDB["quests"]["data"][qid]
  local starter, finisher = qdata and qdata.start, qdata and qdata["end"]
  if starter then
    print(STAR .. " Starter:", starter.U and starter.U[1] or starter.O and starter.O[1] or starter.I and starter.I[1] or "Unknown")
  else
    print(SKULL .. " No starter info")
  end
  if finisher then
    print(STAR .. " Finisher:", finisher.U and finisher.U[1] or finisher.O and finisher.O[1] or "Unknown")
  else
    print(SKULL .. " No finisher info")
  end

  -- 3. Проверка целей (units/objects/coords)
  local objectives = qdata and qdata.obj or {}
  if objectives.U then
    for _, unitId in ipairs(objectives.U) do
      local unit = pfDB["units"] and pfDB["units"]["data"] and pfDB["units"]["data"][unitId]
      if unit and unit.coords and #unit.coords > 0 then
        print(STAR .. " Unit objective:", unitId, "coords:", unit.coords[1][1], unit.coords[1][2], "zone:", unit.coords[1][3])
      else
        print(SKULL .. " Unit " .. unitId .. " has no coords!")
      end
    end
  end
  if objectives.O then
    for _, objId in ipairs(objectives.O) do
      local obj = pfDB["objects"] and pfDB["objects"]["data"] and pfDB["objects"]["data"][objId]
      if obj and obj.coords and #obj.coords > 0 then
        print(STAR .. " Object objective:", objId, "coords:", obj.coords[1][1], obj.coords[1][2], "zone:", obj.coords[1][3])
      else
        print(SKULL .. " Object " .. objId .. " has no coords!")
      end
    end
  end

  -- 4. Проверка зоны
  local zoneid = nil
  if starter and starter.U and pfDB["units"] and pfDB["units"]["data"] and pfDB["units"]["data"][starter.U[1]] and pfDB["units"]["data"][starter.U[1]].coords then
    zoneid = pfDB["units"]["data"][starter.U[1]].coords[1][3]
  elseif objectives.U and pfDB["units"] and pfDB["units"]["data"] and pfDB["units"]["data"][objectives.U[1]] and pfDB["units"]["data"][objectives.U[1]].coords then
    zoneid = pfDB["units"]["data"][objectives.U[1]].coords[1][3]
  end
  if zoneid then
    local zoneinfo = pfDB["zones"] and pfDB["zones"]["data"] and pfDB["zones"]["data"][zoneid]
    if zoneinfo then
      print(STAR .. " Zone", zoneid, "found in zones.lua:", unpack(zoneinfo))
    else
      print(SKULL .. " Zone " .. zoneid .. " not found in zones.lua!")
    end
  else
    print(SKULL .. " No zoneID found for quest")
  end

  -- 5. Проверка наличия точек в pfMap.nodes после поиска
  if pfDatabase and pfDatabase.SearchQuestID then
    local meta = { ["addon"] = "PFQUEST" }
    pfDatabase:SearchQuestID(qid, meta)
    local nodes = pfMap.nodes["PFQUEST"]
    local found = false
    if nodes then
      for zid, points in pairs(nodes) do
        for coords, node in pairs(points) do
          print(STAR .. " Node in pfMap.nodes: zone", zid, "coords", coords)
          found = true
        end
      end
    end
    if not found then
      print(SKULL .. " No nodes for this quest in pfMap.nodes after SearchQuestID")
    end
  else
    print(SKULL .. " pfDatabase:SearchQuestID not available")
  end

  -- 6. Проверка сопоставления zoneID/mapID
  if zoneid and pfMap and pfMap.GetMapNameByID then
    local name = pfMap:GetMapNameByID(zoneid)
    print("ZoneID", zoneid, "-> MapName:", name or "Unknown")
    local id2 = pfMap:GetMapIDByName(name)
    print("MapName", name, "-> ZoneID:", id2 or "Unknown")
  end

  -- 7. Проверка настроек
  if pfQuest_config then
    print("pfQuest_config: showspawn", pfQuest_config.showspawn, "showcluster", pfQuest_config.showcluster, "minimapnodes", pfQuest_config.minimapnodes)
  end

  print("=== End pfQuest Deep Map Debug ===")
end

-- Вставьте этот ИСПРАВЛЕННЫЙ код в конец вашего debug.lua

local function AnalyzeRefLootQuests(questIdFilter)
    if not pfDB or not pfDB["quests"] or not pfDB["quests"]["data"] or not pfDB["items"] or not pfDB["items"]["data"] then
        print(SKULL .. " pfDB, quests.data, or items.data not loaded!")
        return
    end

    print(DIAMOND .. " === pfQuest RefLoot Analysis === ")

    local questsToAnalyze = {}
    if questIdFilter then
        if pfDB["quests"]["data"][questIdFilter] then
            table.insert(questsToAnalyze, questIdFilter)
            print(TRIANGLE .. " Analyzing specific Quest ID: " .. questIdFilter)
        else
            print(SKULL .. " Quest ID " .. questIdFilter .. " not found.")
            return
        end
    else
        print(TRIANGLE .. " Searching all quests for item objectives...")
        for qId, qData in pairs(pfDB["quests"]["data"]) do
            if qData.obj and qData.obj.I and #qData.obj.I > 0 then
                table.insert(questsToAnalyze, qId)
            end
        end
        table.sort(questsToAnalyze)
        print(STAR .. " Found " .. #questsToAnalyze .. " quests with item objectives.")
        if #questsToAnalyze == 0 then
            print(DIAMOND .. " === End pfQuest RefLoot Analysis === ") -- Добавил вывод конца анализа
            return
        end
        local maxToShow = math.min(15, #questsToAnalyze)
        print(SQUARE .. " Showing first " .. maxToShow .. " quests:")
    end

    local questsWithRefLootInfo = 0
    local questsWithAnyLootInfo = 0
    local displayedCount = 0

    for _, qId in ipairs(questsToAnalyze) do
        if not questIdFilter and displayedCount >= 15 then break end

        local qData = pfDB["quests"]["data"][qId]
        local qLoc = pfDB["quests"]["loc"][qId]
        local qName = (qLoc and qLoc.T) or "Quest " .. qId

        local hasItemObjectives = qData.obj and qData.obj.I and #qData.obj.I > 0

        -- Оборачиваем основную логику в if hasItemObjectives
        if hasItemObjectives then
            if questIdFilter then -- Детальный вывод для одного квеста
                print(MOON .. " Quest: " .. qName .. " (ID: " .. qId .. ")")
                print(CROSS .. " Item Objectives & Sources:")
            end

            local foundLootInfoForThisQuest = false
            local foundRefLootForThisQuest = false

            for _, itemId in ipairs(qData.obj.I) do
                local itemLoc = pfDB["items"]["loc"] and pfDB["items"]["loc"][itemId]
                local itemName = itemLoc or "Item " .. itemId
                if questIdFilter then print("   - Need: " .. itemName .. " (ID: " .. itemId .. ")") end

                local itemData = pfDB["items"]["data"][itemId]
                if itemData then
                    if itemData.U and TableCount(itemData.U) > 0 then
                        foundLootInfoForThisQuest = true
                        if questIdFilter then
                            print("     " .. STAR .. " Drops from Units (NPCs):")
                            for unitId, chanceOrData in pairs(itemData.U) do
                                local unitName = (pfDB["units"]["loc"] and pfDB["units"]["loc"][unitId]) or "NPC " .. unitId
                                local chanceStr = type(chanceOrData) == "number" and chanceOrData .. "%" or "complex data"
                                print("       - " .. unitName .. " (ID: " .. unitId .. "), Chance: " .. chanceStr)
                            end
                        end
                    end
                    if itemData.O and TableCount(itemData.O) > 0 then
                        foundLootInfoForThisQuest = true
                        if questIdFilter then
                            print("     " .. CIRCE .. " Drops from Objects:")
                            for objId, chanceOrData in pairs(itemData.O) do
                                local actualObjId = math.abs(objId)
                                local objName = (pfDB["objects"]["loc"] and pfDB["objects"]["loc"][actualObjId]) or "Object " .. actualObjId
                                local chanceStr = type(chanceOrData) == "number" and chanceOrData .. "%" or "complex data"
                                print("       - " .. objName .. " (ID: " .. actualObjId .. "), Chance: " .. chanceStr)
                            end
                        end
                    end
                    if itemData.R and TableCount(itemData.R) > 0 then
                        foundLootInfoForThisQuest = true
                        foundRefLootForThisQuest = true
                        if questIdFilter then
                            print("     " .. DIAMOND .. " Via Reference Loot Tables (pfDB[items][data][itemID][R]):")
                            for refLootId, chanceOrFlag in pairs(itemData.R) do
                                 print("       - RefLoot Table ID: " .. refLootId .. " (Data: " .. tostring(chanceOrFlag) .. ")")
                                 local refLootTableData = pfDB["refloot"] and pfDB["refloot"]["data"] and pfDB["refloot"]["data"][refLootId]
                                 if refLootTableData then
                                     print("         " .. TRIANGLE .. " Contents of RefLoot Table " .. refLootId .. ":")
                                     for innerItemId, innerItemData in pairs(refLootTableData) do
                                         local innerItemName = (pfDB["items"]["loc"] and pfDB["items"]["loc"][innerItemId]) or "Item " .. innerItemId
                                         print("           - " .. innerItemName .. " (ID: " .. innerItemId .. "), Chance: " .. (innerItemData.chance or "N/A"))
                                         if innerItemData.reference_to_other and innerItemData.reference_to_other > 0 then
                                             print("             (References further to: " .. innerItemData.reference_to_other .. ")")
                                         end
                                     end
                                 else
                                     print("         " .. SKULL .. " RefLoot Table " .. refLootId .. " not found in pfDB['refloot']['data']")
                                 end
                            end
                        end
                    end
                    if not itemData.U and not itemData.O and not itemData.R and questIdFilter then
                        print("     " .. SKULL .. " No specific unit, object, or refloot sources found in pfDB['items']['data'] for this item.")
                    end
                elseif questIdFilter then
                    print("     " .. SKULL .. " Item " .. itemId .. " not found in pfDB['items']['data'].")
                end
            end -- конец цикла по qData.obj.I

            if foundLootInfoForThisQuest then
                questsWithAnyLootInfo = questsWithAnyLootInfo + 1
            end
            if foundRefLootForThisQuest then
                questsWithRefLootInfo = questsWithRefLootInfo + 1
            end

            if not questIdFilter then
                local status_icons = ""
                if foundLootInfoForThisQuest then status_icons = status_icons .. STAR else status_icons = status_icons .. SKULL end
                if foundRefLootForThisQuest then status_icons = status_icons .. DIAMOND end
                print("   " .. qId .. ": " .. qName .. " " .. status_icons)
            elseif not foundLootInfoForThisQuest then
                 print(SKULL .. " No loot information found for any item objectives of this quest.")
            end
        else -- else для if hasItemObjectives
            if questIdFilter then
                print(MOON .. " Quest: " .. qName .. " (ID: " .. qId .. ")")
                print("   No item objectives found for this quest.")
            end
            -- Если нет item objectives, то для общего списка этот квест не будет выведен (он отфильтруется раньше)
            -- Для детального анализа одного квеста мы просто сообщим, что нет item objectives.
        end -- конец if hasItemObjectives
        displayedCount = displayedCount + 1
    end -- конец основного цикла по questsToAnalyze

    if not questIdFilter then
        print(CIRCE .. " Summary: ")
        print("   Quests with any item loot info: " .. questsWithAnyLootInfo .. "/" .. #questsToAnalyze)
        print("   Quests explicitly using RefLoot (via itemData.R): " .. questsWithRefLootInfo .. "/" .. #questsToAnalyze)
    end
    print(DIAMOND .. " === End pfQuest RefLoot Analysis === ")
end

SLASH_PFREFLOOT1 = "/pfrefloot"
SlashCmdList["PFREFLOOT"] = function(msg)
    local questId = nil
    if msg and msg ~= "" then
        questId = tonumber(msg)
        if not questId then
            print(SKULL .. " Invalid Quest ID. Usage: /pfrefloot [questID]")
            return
        end
    end
    AnalyzeRefLootQuests(questId)
end

-- Universal All Validator Command
SLASH_PFALLVALIDATE1 = "/pfa"
SlashCmdList["PFALLVALIDATE"] = function()
    print("=== pfQuest Full Validation - /pfa ===")

    -- Check if pfDB is loaded
    if not pfDB then
        print(SKULL .. " FATAL: pfDB not loaded! pfQuest addon not running.")
        return
    end

    local validationResults = {
        critical_errors = 0,
        warnings = 0,
        info_items = 0
    }

    -- Helper function to safely count table entries
    local function SafeTableCount(tbl)
        if not tbl or type(tbl) ~= "table" then return 0 end
        local count = 0
        for _ in pairs(tbl) do count = count + 1 end
        return count
    end

    -- Helper function to check coordinate presence
    local function CountWithCoords(dataTable)
        if not dataTable then return 0 end
        local count = 0
        for id, entry in pairs(dataTable) do
            if entry and entry.coords and type(entry.coords) == "table" and #entry.coords > 0 then
                count = count + 1
            end
        end
        return count
    end

    print(DIAMOND .. " === Core Database Structure Validation ===")

    -- 1. Check main database categories
    local dbCategories = {
        "quests", "units", "objects", "items", "zones",
        "refloot", "quests-itemreq", "areatrigger", "professions"
    }

    local dbStats = {}
    for _, category in ipairs(dbCategories) do
        local hasData = pfDB[category] and pfDB[category]["data"]
        local hasLoc = pfDB[category] and pfDB[category]["loc"]
        local dataCount = SafeTableCount(hasData and pfDB[category]["data"])
        local locCount = SafeTableCount(hasLoc and pfDB[category]["loc"])

        dbStats[category] = {
            hasData = hasData ~= nil,
            hasLoc = hasLoc ~= nil,
            dataCount = dataCount,
            locCount = locCount
        }

        if not hasData then
            print(SKULL .. " CRITICAL: " .. category .. ".data missing!")
            validationResults.critical_errors = validationResults.critical_errors + 1
        elseif dataCount == 0 then
            print(CROSS .. " WARNING: " .. category .. ".data is empty!")
            validationResults.warnings = validationResults.warnings + 1
        else
            print(STAR .. " " .. category .. ".data: " .. dataCount .. " entries")
            validationResults.info_items = validationResults.info_items + 1
        end

        if category ~= "refloot" and category ~= "quests-itemreq" and category ~= "areatrigger" then
            if not hasLoc then
                print(SKULL .. " CRITICAL: " .. category .. ".loc missing!")
                validationResults.critical_errors = validationResults.critical_errors + 1
            elseif locCount == 0 then
                print(CROSS .. " WARNING: " .. category .. ".loc is empty!")
                validationResults.warnings = validationResults.warnings + 1
            else
                print(CIRCE .. " " .. category .. ".loc: " .. locCount .. " entries")
            end
        end
    end

    print(DIAMOND .. " === Coordinate Validation ===")

    -- 2. Check coordinate data for spatial entities
    local unitsWithCoords = CountWithCoords(pfDB["units"] and pfDB["units"]["data"])
    local objectsWithCoords = CountWithCoords(pfDB["objects"] and pfDB["objects"]["data"])
    local areatriggerWithCoords = CountWithCoords(pfDB["areatrigger"] and pfDB["areatrigger"]["data"])

    print(STAR .. " Units with coordinates: " .. unitsWithCoords .. "/" .. dbStats.units.dataCount)
    print(STAR .. " Objects with coordinates: " .. objectsWithCoords .. "/" .. dbStats.objects.dataCount)
    print(STAR .. " Areatriggers with coordinates: " .. areatriggerWithCoords .. "/" .. dbStats.areatrigger.dataCount)

    if unitsWithCoords == 0 and dbStats.units.dataCount > 0 then
        print(SKULL .. " CRITICAL: No units have coordinates!")
        validationResults.critical_errors = validationResults.critical_errors + 1
    elseif unitsWithCoords < dbStats.units.dataCount * 0.3 then
        print(CROSS .. " WARNING: Less than 30% of units have coordinates")
        validationResults.warnings = validationResults.warnings + 1
    end

    print(DIAMOND .. " === Quest Structure Validation ===")

    -- 3. Quest structure validation
    local questsWithStarters = 0
    local questsWithFinishers = 0
    local questsWithObjectives = 0
    local questsWithValidStarters = 0
    local questsWithValidFinishers = 0
    local questsWorking = 0

    if pfDB["quests"] and pfDB["quests"]["data"] then
        for qid, quest in pairs(pfDB["quests"]["data"]) do
            -- Check starters (exact same logic as findWorkingQuests)
            local hasStarterWithCoords = false
            if quest.start then
                questsWithStarters = questsWithStarters + 1

                -- Check starter NPCs
                if quest.start.U then
                    for _, unitId in ipairs(quest.start.U) do
                        local unit = pfDB["units"] and pfDB["units"]["data"] and pfDB["units"]["data"][unitId]
                        if unit and unit.coords and #unit.coords > 0 then
                            hasStarterWithCoords = true
                            break
                        end
                    end
                end
                -- Check starter objects (if no NPC with coords found)
                if not hasStarterWithCoords and quest.start.O then
                    for _, objectId in ipairs(quest.start.O) do
                        local obj = pfDB["objects"] and pfDB["objects"]["data"] and pfDB["objects"]["data"][objectId]
                        if obj and obj.coords and #obj.coords > 0 then
                            hasStarterWithCoords = true
                            break
                        end
                    end
                end
                -- Items always count as valid starters
                if not hasStarterWithCoords and quest.start.I and #quest.start.I > 0 then
                    hasStarterWithCoords = true
                end

                if hasStarterWithCoords then
                    questsWithValidStarters = questsWithValidStarters + 1
                end
            end

            -- Check finishers (exact same logic as findWorkingQuests)
            local hasFinisherWithCoords = false
            if quest["end"] then
                questsWithFinishers = questsWithFinishers + 1

                -- Check finisher NPCs
                if quest["end"].U then
                    for _, unitId in ipairs(quest["end"].U) do
                        local unit = pfDB["units"] and pfDB["units"]["data"] and pfDB["units"]["data"][unitId]
                        if unit and unit.coords and #unit.coords > 0 then
                            hasFinisherWithCoords = true
                            break
                        end
                    end
                end
                -- Check finisher objects (if no NPC with coords found)
                if not hasFinisherWithCoords and quest["end"].O then
                    for _, objectId in ipairs(quest["end"].O) do
                        local obj = pfDB["objects"] and pfDB["objects"]["data"] and pfDB["objects"]["data"][objectId]
                        if obj and obj.coords and #obj.coords > 0 then
                            hasFinisherWithCoords = true
                            break
                        end
                    end
                end

                if hasFinisherWithCoords then
                    questsWithValidFinishers = questsWithValidFinishers + 1
                end
            end

            -- Check objectives
            if quest.obj and (quest.obj.U or quest.obj.O or quest.obj.I or quest.obj.A or quest.obj.Z) then
                questsWithObjectives = questsWithObjectives + 1
            end

            -- Working quest = BOTH starter and finisher have coordinates (exact same logic as findWorkingQuests)
            if hasStarterWithCoords and hasFinisherWithCoords then
                questsWorking = questsWorking + 1
            end
        end
    end

    print(STAR .. " Quests with starters: " .. questsWithStarters .. "/" .. dbStats.quests.dataCount)
    print(STAR .. " Quests with valid starters: " .. questsWithValidStarters .. "/" .. questsWithStarters)
    print(STAR .. " Quests with finishers: " .. questsWithFinishers .. "/" .. dbStats.quests.dataCount)
    print(STAR .. " Quests with valid finishers: " .. questsWithValidFinishers .. "/" .. questsWithFinishers)
    print(STAR .. " Quests with objectives: " .. questsWithObjectives .. "/" .. dbStats.quests.dataCount)
    print(MOON .. " WORKING QUESTS (starter+finisher coords): " .. questsWorking .. "/" .. dbStats.quests.dataCount)

    if questsWorking == 0 and dbStats.quests.dataCount > 0 then
        print(SKULL .. " CRITICAL: No working quests found!")
        validationResults.critical_errors = validationResults.critical_errors + 1
    end

    print(DIAMOND .. " === Item/Loot System Validation ===")

    -- 4. Item and loot validation
    local itemsWithSources = 0
    local itemsWithVendors = 0
    local itemsWithDrops = 0
    local itemsWithRefLoot = 0

    if pfDB["items"] and pfDB["items"]["data"] then
        for itemId, item in pairs(pfDB["items"]["data"]) do
            local hasSources = false

            if item.U and SafeTableCount(item.U) > 0 then
                itemsWithDrops = itemsWithDrops + 1
                hasSources = true
            end

            if item.V and SafeTableCount(item.V) > 0 then
                itemsWithVendors = itemsWithVendors + 1
                hasSources = true
            end

            if item.O and SafeTableCount(item.O) > 0 then
                hasSources = true
            end

            if item.R and SafeTableCount(item.R) > 0 then
                itemsWithRefLoot = itemsWithRefLoot + 1
                hasSources = true
            end

            if hasSources then
                itemsWithSources = itemsWithSources + 1
            end
        end
    end

    print(STAR .. " Items with any sources: " .. itemsWithSources .. "/" .. dbStats.items.dataCount)
    print(CIRCE .. " Items with NPC drops: " .. itemsWithDrops)
    print(CIRCE .. " Items with vendors: " .. itemsWithVendors)
    print(CIRCE .. " Items with reference loot: " .. itemsWithRefLoot)

    print(DIAMOND .. " === Zone/Map System Validation ===")

    -- 5. Zone system validation
    local zonesWithData = 0
    if pfDB["zones"] and pfDB["zones"]["data"] then
        for zoneId, zoneData in pairs(pfDB["zones"]["data"]) do
            if type(zoneData) == "table" and #zoneData >= 6 then
                zonesWithData = zonesWithData + 1
            end
        end
    end

    print(STAR .. " Zones with complete data: " .. zonesWithData .. "/" .. dbStats.zones.dataCount)

    -- Check if common zones exist
    local commonZones = {
        [14] = "Durotar",
        [1519] = "Stormwind City",
        [1637] = "Orgrimmar",
        [17] = "The Barrens",
        [141] = "Teldrassil"
    }

    local commonZonesFound = 0
    for zoneId, name in pairs(commonZones) do
        if pfDB["zones"] and pfDB["zones"]["data"] and pfDB["zones"]["data"][zoneId] then
            commonZonesFound = commonZonesFound + 1
        end
    end

    print(CIRCE .. " Common starter zones found: " .. commonZonesFound .. "/5")

    print(DIAMOND .. " === Localization Validation ===")

    -- 6. Localization check
    local currentLocale = GetLocale()
    local localeStatus = {}

    for _, category in ipairs({"quests", "units", "objects", "items", "zones"}) do
        if pfDB[category] and pfDB[category][currentLocale] then
            localeStatus[category] = "native"
        elseif pfDB[category] and pfDB[category]["enUS"] then
            localeStatus[category] = "fallback"
        else
            localeStatus[category] = "missing"
        end
    end

    print(STAR .. " Current locale: " .. currentLocale)
    for category, status in pairs(localeStatus) do
        if status == "native" then
            print(STAR .. " " .. category .. ": native locale")
        elseif status == "fallback" then
            print(CIRCE .. " " .. category .. ": using enUS fallback")
        else
            print(SKULL .. " " .. category .. ": no localization!")
            validationResults.critical_errors = validationResults.critical_errors + 1
        end
    end

    print(DIAMOND .. " === Advanced Features Validation ===")

    -- 7. Advanced features
    local hasMetaData = pfDB["meta"] ~= nil
    local hasRares = hasMetaData and pfDB["meta"]["rares"] and SafeTableCount(pfDB["meta"]["rares"]) > 0
    local hasHerbs = hasMetaData and pfDB["meta"]["herbs"] and SafeTableCount(pfDB["meta"]["herbs"]) > 0
    local hasMines = hasMetaData and pfDB["meta"]["mines"] and SafeTableCount(pfDB["meta"]["mines"]) > 0

    print(STAR .. " Meta data: " .. (hasMetaData and "present" or "missing"))
    if hasMetaData then
        print(CIRCE .. " Rare mobs: " .. (hasRares and SafeTableCount(pfDB["meta"]["rares"]) or "0"))
        print(CIRCE .. " Herb nodes: " .. (hasHerbs and SafeTableCount(pfDB["meta"]["herbs"]) or "0"))
        print(CIRCE .. " Mining nodes: " .. (hasMines and SafeTableCount(pfDB["meta"]["mines"]) or "0"))
    end

    -- 8. Item requirements validation
    local hasItemReq = pfDB["quests-itemreq"] and pfDB["quests-itemreq"]["data"]
    local itemReqCount = SafeTableCount(hasItemReq and pfDB["quests-itemreq"]["data"])
    print(STAR .. " Item requirements: " .. itemReqCount .. " entries")

    -- 9. Reference loot validation
    local hasRefLoot = pfDB["refloot"] and pfDB["refloot"]["data"]
    local refLootCount = SafeTableCount(hasRefLoot and pfDB["refloot"]["data"])
    print(STAR .. " Reference loot tables: " .. refLootCount .. " entries")

    print(DIAMOND .. " === Final Summary ===")

    -- Collect critical issues for detailed reporting
    local criticalIssues = {}
    local warningIssues = {}

    -- Check specific issues and categorize them
    if questsWorking == 0 and dbStats.quests.dataCount > 0 then
        table.insert(criticalIssues, "No working quests found (0/" .. dbStats.quests.dataCount .. ")")
    end

    if unitsWithCoords == 0 and dbStats.units.dataCount > 0 then
        table.insert(criticalIssues, "No units have coordinates (0/" .. dbStats.units.dataCount .. ")")
    elseif unitsWithCoords < dbStats.units.dataCount * 0.3 then
        table.insert(warningIssues, "Low unit coordinate coverage (" .. unitsWithCoords .. "/" .. dbStats.units.dataCount .. " = " .. math.floor(unitsWithCoords/dbStats.units.dataCount*100) .. "%)")
    end

    -- Check missing core components
    for _, category in ipairs({"quests", "units", "objects", "items", "zones"}) do
        if not dbStats[category].hasData then
            table.insert(criticalIssues, category .. ".data completely missing")
        elseif dbStats[category].dataCount == 0 then
            table.insert(warningIssues, category .. ".data is empty")
        end

        if category ~= "refloot" and category ~= "quests-itemreq" and category ~= "areatrigger" then
            if not dbStats[category].hasLoc then
                table.insert(criticalIssues, category .. ".loc completely missing")
            elseif dbStats[category].locCount == 0 then
                table.insert(warningIssues, category .. ".loc is empty")
            end
        end
    end

    -- Check localization issues
    for category, status in pairs(localeStatus) do
        if status == "missing" then
            table.insert(criticalIssues, "No localization for " .. category .. " (locale: " .. currentLocale .. ")")
        end
    end

    -- Overall assessment
    local totalIssues = validationResults.critical_errors + validationResults.warnings
    local overallStatus = ""

    if validationResults.critical_errors > 0 then
        overallStatus = SKULL .. " CRITICAL ISSUES FOUND"
        print(SKULL .. " Critical errors: " .. validationResults.critical_errors)

        if #criticalIssues > 0 then
            print(CROSS .. " Critical Issues Summary:")
            for i, issue in ipairs(criticalIssues) do
                print("   " .. SKULL .. " " .. issue)
            end
        end
    elseif validationResults.warnings > 0 then
        overallStatus = CROSS .. " WARNINGS PRESENT"
        print(CROSS .. " Warnings: " .. validationResults.warnings)

        if #warningIssues > 0 then
            print(TRIANGLE .. " Warning Issues Summary:")
            for i, issue in ipairs(warningIssues) do
                print("   " .. CROSS .. " " .. issue)
            end
        end
    else
        overallStatus = STAR .. " ALL SYSTEMS VALIDATED"
    end

    print(overallStatus)
    print(TRIANGLE .. " Working quests: " .. questsWorking .. " | Items with sources: " .. itemsWithSources)
    print(TRIANGLE .. " Units with coords: " .. unitsWithCoords .. " | Objects with coords: " .. objectsWithCoords)

    -- Recommendations
    if validationResults.critical_errors == 0 and questsWorking > 0 then
        print(DIAMOND .. " RECOMMENDATIONS:")
        print("   " .. STAR .. " Database appears functional for pfQuest")
        print("   " .. CIRCE .. " Try: /pftest to see example working quests")
        print("   " .. MOON .. " Try: /pfq <questID> to analyze specific quests")

        if questsWorking < 50 then
            print("   " .. CROSS .. " Consider running full extraction for more quests")
        end
        if questsWorking < 10 then
            print("   " .. SKULL .. " Very low quest count - may need database fixes")
        end
    elseif validationResults.critical_errors > 0 then
        print(DIAMOND .. " TROUBLESHOOTING:")
        print("   " .. SKULL .. " Critical issues detected - extraction may be incomplete")
        print("   " .. TRIANGLE .. " Check extractor.lua configuration and re-run")
        print("   " .. SQUARE .. " Verify database connection and permissions")

        if questsWorking == 0 and questsWithStarters > 0 and questsWithFinishers > 0 then
            print("   " .. MOON .. " Quest data exists but lacks coordinates - check coordinate extraction")
        end

        if #criticalIssues > 0 then
            print("   " .. CROSS .. " Focus on fixing the " .. #criticalIssues .. " critical issue(s) listed above")
        end
    end

    print("=== End pfQuest Full Validation ===")
end

-- === ITEMREQ QUEST SEARCH ===
local function searchQuestsWithItemReq(searchTerm)
    if not pfDB or not pfDB["quests-itemreq"] or not pfDB["quests-itemreq"]["data"] then
        print(SKULL .. " No itemreq data found!")
        return {}
    end

    local currentZone = GetRealZoneText()
    local currentZoneId = nil

    -- Find current zone ID from zones database (try multiple approaches)
    if pfDB["zones"] and pfDB["zones"]["loc"] then
        for zoneId, zoneName in pairs(pfDB["zones"]["loc"]) do
            if zoneName == currentZone then
                currentZoneId = zoneId
                break
            end
        end
    end

    -- Debug: print zone matching
    print("DEBUG: Current zone '" .. currentZone .. "' -> Zone ID: " .. (currentZoneId or "NOT FOUND"))

    -- If no exact match, try partial matching
    if not currentZoneId and pfDB["zones"] and pfDB["zones"]["loc"] then
        local currentZoneLower = string.lower(currentZone)
        for zoneId, zoneName in pairs(pfDB["zones"]["loc"]) do
            if string.find(string.lower(zoneName), currentZoneLower) or string.find(currentZoneLower, string.lower(zoneName)) then
                currentZoneId = zoneId
                print("DEBUG: Partial match found: '" .. zoneName .. "' -> Zone ID: " .. zoneId)
                break
            end
        end
    end

    local results = {}
    local searchLower = searchTerm and string.lower(searchTerm) or ""

    -- Search through all items with itemreq
    for itemId, targets in pairs(pfDB["quests-itemreq"]["data"]) do
        local itemName = ""

        -- Get item name
        if pfDB["items"] and pfDB["items"]["loc"] and pfDB["items"]["loc"][itemId] then
            itemName = pfDB["items"]["loc"][itemId]
        else
            itemName = "Item " .. itemId
        end

        -- Check if item matches search term
        local matches = not searchTerm or
                       string.find(string.lower(itemName), searchLower) or
                       tostring(itemId) == searchTerm

        if matches then
            -- Find quests that use this item
            local questsUsingItem = {}

            if pfDB["quests"] and pfDB["quests"]["data"] then
                for questId, quest in pairs(pfDB["quests"]["data"]) do
                    if quest.obj and quest.obj.IR then
                        for _, reqItemId in ipairs(quest.obj.IR) do
                            if reqItemId == itemId then
                                table.insert(questsUsingItem, questId)
                            end
                        end
                    end
                end
            end

            -- Check zones for each quest
            for _, questId in ipairs(questsUsingItem) do
                local quest = pfDB["quests"]["data"][questId]
                local questName = "Quest " .. questId
                local isInCurrentZone = false
                local questZones = {}

                -- Get quest name
                if pfDB["quests"] and pfDB["quests"]["loc"] and pfDB["quests"]["loc"][questId] then
                    local questData = pfDB["quests"]["loc"][questId]
                    if type(questData) == "table" and questData.T then
                        questName = questData.T
                    elseif type(questData) == "string" then
                        questName = questData
                    end
                end

                -- Check quest starter zones and objective zones
                if quest then
                    -- Check quest starters
                    if quest.start then
                        if quest.start.U then
                            for _, unitId in ipairs(quest.start.U) do
                                local unit = pfDB["units"] and pfDB["units"]["data"] and pfDB["units"]["data"][unitId]
                                if unit and unit.coords then
                                    for _, coord in ipairs(unit.coords) do
                                        local zoneId = coord[3]
                                        questZones[zoneId] = true
                                        if zoneId == currentZoneId then
                                            isInCurrentZone = true
                                            print("DEBUG: Quest " .. questId .. " starter NPC " .. unitId .. " found in current zone " .. zoneId)
                                        end
                                    end
                                end
                            end
                        end

                        if quest.start.O then
                            for _, objectId in ipairs(quest.start.O) do
                                local obj = pfDB["objects"] and pfDB["objects"]["data"] and pfDB["objects"]["data"][objectId]
                                if obj and obj.coords then
                                    for _, coord in ipairs(obj.coords) do
                                        local zoneId = coord[3]
                                        questZones[zoneId] = true
                                        if zoneId == currentZoneId then
                                            isInCurrentZone = true
                                            print("DEBUG: Quest " .. questId .. " starter Object " .. objectId .. " found in current zone " .. zoneId)
                                        end
                                    end
                                end
                            end
                        end
                    end

                    -- Also check quest objectives for items that might be used in current zone
                    if quest.obj then
                        if quest.obj.U then
                            for _, unitId in ipairs(quest.obj.U) do
                                local unit = pfDB["units"] and pfDB["units"]["data"] and pfDB["units"]["data"][unitId]
                                if unit and unit.coords then
                                    for _, coord in ipairs(unit.coords) do
                                        local zoneId = coord[3]
                                        questZones[zoneId] = true
                                        if zoneId == currentZoneId then
                                            isInCurrentZone = true
                                            print("DEBUG: Quest " .. questId .. " objective NPC " .. unitId .. " found in current zone " .. zoneId)
                                        end
                                    end
                                end
                            end
                        end

                        if quest.obj.O then
                            for _, objectId in ipairs(quest.obj.O) do
                                local obj = pfDB["objects"] and pfDB["objects"]["data"] and pfDB["objects"]["data"][objectId]
                                if obj and obj.coords then
                                    for _, coord in ipairs(obj.coords) do
                                        local zoneId = coord[3]
                                        questZones[zoneId] = true
                                        if zoneId == currentZoneId then
                                            isInCurrentZone = true
                                            print("DEBUG: Quest " .. questId .. " objective Object " .. objectId .. " found in current zone " .. zoneId)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end

                table.insert(results, {
                    questId = questId,
                    questName = questName,
                    itemId = itemId,
                    itemName = itemName,
                    targets = targets,
                    isInCurrentZone = isInCurrentZone,
                    zones = questZones
                })
            end
        end
    end

    -- Sort results: current zone first, then by quest name
    table.sort(results, function(a, b)
        if a.isInCurrentZone ~= b.isInCurrentZone then
            return a.isInCurrentZone
        end
        return a.questName < b.questName
    end)

    return results, currentZone
end

-- Command: /pfi [search_term]
SLASH_PFI1 = "/pfi"
SlashCmdList["PFI"] = function(msg)
    local searchTerm = msg and msg ~= "" and msg or nil
    local results, currentZone = searchQuestsWithItemReq(searchTerm)

    print("=== pfQuest ItemReq Debug ===")
    print("Zone: " .. (currentZone or "Unknown"))
    print("Quests: " .. #results)
    print("")

    if #results == 0 then
        print("No quests found with itemreq data" .. (searchTerm and " matching '" .. searchTerm .. "'" or ""))
        print("=== End Debug ===")
        return
    end

    -- Limit to 15 results
    local maxResults = math.min(#results, 15)

    for i = 1, maxResults do
        local result = results[i]

        print("[" .. result.questId .. "] " .. result.questName)
        print(" - Item: " .. result.itemName .. " (" .. result.itemId .. ")")

        -- Show targets
        local targetCount = 0
        for targetId, spellId in pairs(result.targets) do
            targetCount = targetCount + 1
            if targetCount > 3 then -- Limit targets per quest
                break
            end

            local targetName = "Unknown"

            if targetId > 0 then
                -- NPC target
                if pfDB["units"] and pfDB["units"]["loc"] and pfDB["units"]["loc"][targetId] then
                    targetName = pfDB["units"]["loc"][targetId]
                else
                    targetName = "Unit " .. targetId
                end
            else
                -- GameObject target
                local objId = math.abs(targetId)
                if pfDB["objects"] and pfDB["objects"]["loc"] and pfDB["objects"]["loc"][objId] then
                    targetName = pfDB["objects"]["loc"][objId]
                else
                    targetName = "Object " .. objId
                end
            end

            print("   -> Target: " .. targetName)
            print("      SpellID: " .. spellId)
        end

        print("")
    end

    if #results > maxResults then
        print("... and " .. (#results - maxResults) .. " more results")
        print("")
    end

    print("Use /pfq <ID> for full quest info")
    print("=== End Debug ===")
end

-- === RARE CREATURES SEARCH ===
local function searchRareCreatures(searchTerm)
    if not pfDB or not pfDB["meta"] or not pfDB["meta"]["rares"] then
        return {}, "No Data"
    end

    local currentZone = GetRealZoneText()
    local currentZoneId = nil

    -- Find current zone ID
    if pfDB["zones"] and pfDB["zones"]["loc"] then
        for zoneId, zoneName in pairs(pfDB["zones"]["loc"]) do
            if zoneName == currentZone then
                currentZoneId = zoneId
                break
            end
        end
    end

    local results = {}
    local searchLower = searchTerm and string.lower(searchTerm) or ""

    -- Search through rares
    for rareId, rareLevel in pairs(pfDB["meta"]["rares"]) do
        local rareName = ""

        -- Get rare name
        if pfDB["units"] and pfDB["units"]["loc"] and pfDB["units"]["loc"][rareId] then
            rareName = pfDB["units"]["loc"][rareId]
        else
            rareName = "Rare " .. rareId
        end

        -- Check if rare matches search term
        local matches = not searchTerm or
                       string.find(string.lower(rareName), searchLower) or
                       tostring(rareId) == searchTerm

        if matches then
            local isInCurrentZone = false
            local rareZones = {}

            -- Check rare locations
            local unit = pfDB["units"] and pfDB["units"]["data"] and pfDB["units"]["data"][rareId]
            if unit and unit.coords then
                for _, coord in ipairs(unit.coords) do
                    local zoneId = coord[3]
                    rareZones[zoneId] = true
                    if zoneId == currentZoneId then
                        isInCurrentZone = true
                    end
                end
            end

            table.insert(results, {
                rareId = rareId,
                rareName = rareName,
                level = rareLevel,
                coords = unit and unit.coords or {},
                isInCurrentZone = isInCurrentZone,
                zones = rareZones
            })
        end
    end

    -- Sort results: current zone first, then by level desc, then by name
    table.sort(results, function(a, b)
        if a.isInCurrentZone ~= b.isInCurrentZone then
            return a.isInCurrentZone
        end
        if a.level ~= b.level then
            return a.level > b.level
        end
        return a.rareName < b.rareName
    end)

    return results, currentZone
end

-- Command: /pfr [search_term]
SLASH_PFR1 = "/pfr"
SlashCmdList["PFR"] = function(msg)
    local searchTerm = msg and msg ~= "" and msg or nil
    local results, currentZone = searchRareCreatures(searchTerm)

    print("=== pfQuest Rares Debug ===")
    print("Zone: " .. (currentZone or "Unknown"))
    print("Rares: " .. #results)
    print("")

    if #results == 0 then
        print("No rare creatures found" .. (searchTerm and " matching '" .. searchTerm .. "'" or ""))
        print("=== End Debug ===")
        return
    end

    -- Limit to 15 results
    local maxResults = math.min(#results, 15)

    for i = 1, maxResults do
        local result = results[i]

        print("[" .. result.rareId .. "] " .. result.rareName .. " (Level " .. result.level .. ")")

        -- Show first few spawn locations
        local coordCount = 0
        for _, coord in ipairs(result.coords) do
            coordCount = coordCount + 1
            if coordCount > 2 then -- Limit locations per rare
                break
            end

            local zoneId = coord[3]
            local zoneName = "Unknown Zone"

            if pfDB["zones"] and pfDB["zones"]["loc"] and pfDB["zones"]["loc"][zoneId] then
                zoneName = pfDB["zones"]["loc"][zoneId]
            end

            print("   -> Location: " .. zoneName .. " (" .. coord[1] .. ", " .. coord[2] .. ")")
        end

        if #result.coords > 2 then
            print("   -> ... and " .. (#result.coords - 2) .. " more locations")
        end

        print("")
    end

    if #results > maxResults then
        print("... and " .. (#results - maxResults) .. " more rares")
        print("")
    end

    print("Use /pfq rare_id for more info")
    print("=== End Debug ===")
end

-- Helper function to check if NPC/Object is related to quests
local function isQuestRelated(entityType, entityId)
    if not pfDB["quests"] or not pfDB["quests"]["data"] then
        return false, {}
    end

    local relatedQuests = {}

    for questId, quest in pairs(pfDB["quests"]["data"]) do
        local isRelated = false

        -- Check quest starters
        if quest.start then
            if entityType == "NPC" and quest.start.U then
                for _, unitId in ipairs(quest.start.U) do
                    if tonumber(unitId) == tonumber(entityId) then
                        isRelated = true
                        table.insert(relatedQuests, {questId = questId, role = "starter"})
                        break
                    end
                end
            elseif entityType == "Object" and quest.start.O then
                for _, objectId in ipairs(quest.start.O) do
                    if tonumber(objectId) == tonumber(entityId) then
                        isRelated = true
                        table.insert(relatedQuests, {questId = questId, role = "starter"})
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
                        isRelated = true
                        table.insert(relatedQuests, {questId = questId, role = "finisher"})
                        break
                    end
                end
            elseif entityType == "Object" and quest.finish.O then
                for _, objectId in ipairs(quest.finish.O) do
                    if tonumber(objectId) == tonumber(entityId) then
                        isRelated = true
                        table.insert(relatedQuests, {questId = questId, role = "finisher"})
                        break
                    end
                end
            end
        end

        -- Check quest objectives (for objects mainly)
        if entityType == "Object" and quest.objectives then
            for _, objective in ipairs(quest.objectives) do
                if objective.type == "object" and tonumber(objective.id) == tonumber(entityId) then
                    isRelated = true
                    table.insert(relatedQuests, {questId = questId, role = "objective"})
                    break
                end
            end
        end
    end

    return #relatedQuests > 0, relatedQuests
end

-- Lazy search state for /pfc command
local pfcSearchState = {
    isSearching = false,
    results = {},
    totalFound = 0,
    questRelatedFound = 0,
    currentStep = 0,
    totalSteps = 0,
    searchParams = {}
}

-- Frame for OnUpdate processing
local pfcFrame = CreateFrame("Frame")
pfcFrame:Hide()

-- OnUpdate handler for lazy processing
pfcFrame:SetScript("OnUpdate", function(self, elapsed)
    if not pfcSearchState.isSearching then
        self:Hide()
        return
    end

    local batchSize = 50  -- Process 50 entities per frame
    local processed = 0
    local targetX, targetY = pfcSearchState.searchParams.targetX, pfcSearchState.searchParams.targetY

    -- Continue from where we left off
    while processed < batchSize and pfcSearchState.currentStep < pfcSearchState.totalSteps do
        pfcSearchState.currentStep = pfcSearchState.currentStep + 1
        processed = processed + 1

        local entityData = pfcSearchState.searchParams.entityQueue[pfcSearchState.currentStep]
        if entityData then
            local entityType, entityId, coords = entityData.type, entityData.id, entityData.coords

            for _, coord in ipairs(coords) do
                local x, y, zoneId = coord[1], coord[2], coord[3]

                -- Check zone filter if specified
                local zoneMatches = true
                if pfcSearchState.searchParams.zoneFilter then
                    zoneMatches = false
                    local zoneName = "Zone " .. zoneId
                    if pfDB["zones"] and pfDB["zones"]["loc"] and pfDB["zones"]["loc"][zoneId] then
                        zoneName = pfDB["zones"]["loc"][zoneId]
                    end

                    local zoneFilterLower = string.lower(pfcSearchState.searchParams.zoneFilter)
                    if string.find(string.lower(zoneName), zoneFilterLower) then
                        zoneMatches = true
                    end
                end

                -- Check for exact 50,50 coordinates (or very close due to rounding)
                if (x == targetX and y == targetY) and zoneMatches then
                    pfcSearchState.totalFound = pfcSearchState.totalFound + 1

                    -- Check if quest-related
                    local isRelated, relatedQuests = isQuestRelated(entityType, entityId)

                    if isRelated then
                        pfcSearchState.questRelatedFound = pfcSearchState.questRelatedFound + 1

                        local entityName = (entityType == "NPC" and "Unit " or "Object ") .. entityId
                        local locTable = pfDB[entityType == "NPC" and "units" or "objects"]["loc"]
                        if locTable and locTable[entityId] then
                            entityName = locTable[entityId]
                        end

                        local zoneName = "Zone " .. zoneId
                        if pfDB["zones"] and pfDB["zones"]["loc"] and pfDB["zones"]["loc"][zoneId] then
                            zoneName = pfDB["zones"]["loc"][zoneId]
                        end

                        -- Compact quest info
                        local questIds = {}
                        for _, qInfo in ipairs(relatedQuests) do
                            table.insert(questIds, qInfo.questId)
                        end

                        table.insert(pfcSearchState.results, {
                            type = entityType,
                            id = entityId,
                            name = entityName,
                            x = x,
                            y = y,
                            zoneId = zoneId,
                            zoneName = zoneName,
                            distance = math.sqrt((x - targetX)^2 + (y - targetY)^2),
                            questIds = questIds,
                            questCount = #relatedQuests
                        })
                    end
                end
            end
        end
    end

    -- Show progress every 10% or if found quest-related items
    local progress = math.floor((pfcSearchState.currentStep / pfcSearchState.totalSteps) * 100)
    local lastProgress = pfcSearchState.lastProgress or 0
    if progress >= lastProgress + 10 or pfcSearchState.questRelatedFound > (pfcSearchState.lastQuestFound or 0) then
        print("   Searching... " .. progress .. "% (" .. pfcSearchState.questRelatedFound .. " exact 50,50 quest-related found)")
        pfcSearchState.lastProgress = progress
        pfcSearchState.lastQuestFound = pfcSearchState.questRelatedFound
    end

    -- Continue or finish
    if pfcSearchState.currentStep >= pfcSearchState.totalSteps then
        -- Search complete - show results
        pfcShowResults()
        pfcSearchState.isSearching = false
        self:Hide()
    end
end)


-- Function to show final results
function pfcShowResults()
    local results = pfcSearchState.results
    local totalFound = pfcSearchState.totalFound
    local questRelatedFound = pfcSearchState.questRelatedFound
    local targetX, targetY = pfcSearchState.searchParams.targetX, pfcSearchState.searchParams.targetY
    local zoneFilter = pfcSearchState.searchParams.zoneFilter

    -- Sort by distance
    table.sort(results, function(a, b) return a.distance < b.distance end)

    print("")
    if zoneFilter then
        print(TRIANGLE .. " |cffFFD700Summary in '" .. zoneFilter .. "':|r " .. totalFound .. " with exact 50,50, |cff00FF00" .. questRelatedFound .. " quest-related|r")
    else
        print(TRIANGLE .. " |cffFFD700Summary:|r " .. totalFound .. " with exact 50,50, |cff00FF00" .. questRelatedFound .. " quest-related|r")
    end

    if #results > 0 then
        print(STAR .. " |cff00BFFFQuest-Related with EXACT 50,50:|r")

        local maxResults = 15
        for i = 1, math.min(maxResults, #results) do
            local r = results[i]
            local typeColor = r.type == "NPC" and "|cffFFFF00" or "|cff00FFFF"
            local questList = "[" .. table.concat(r.questIds, ",") .. "]"
            print(string.format("   %s%s %d|r: %s |cff888888@%s (%.1f,%.1f) d:%.1f|r %s",
                typeColor, r.type, r.id, r.name, r.zoneName, r.x, r.y, r.distance, questList))
        end

        if #results > maxResults then
            print("   |cff888888... and " .. (#results - maxResults) .. " more|r")
        end

        -- Compact zone summary
        print("")
        print(CIRCE .. " |cff00BFFFZone Summary:|r")
        local zoneGroups = {}
        for _, r in ipairs(results) do
            if not zoneGroups[r.zoneId] then
                zoneGroups[r.zoneId] = {name = r.zoneName, npcs = 0, objects = 0, quests = 0}
            end
            if r.type == "NPC" then
                zoneGroups[r.zoneId].npcs = zoneGroups[r.zoneId].npcs + 1
            else
                zoneGroups[r.zoneId].objects = zoneGroups[r.zoneId].objects + 1
            end
            zoneGroups[r.zoneId].quests = zoneGroups[r.zoneId].quests + r.questCount
        end

        for zoneId, data in pairs(zoneGroups) do
            print(string.format("   |cffFFD700%s|r: %dN/%dO affecting %d quests",
                data.name, data.npcs, data.objects, data.quests))
        end
    else
        if totalFound > 0 then
            print(SKULL .. " |cffFF6600Found " .. totalFound .. " entities but none are quest-related|r")
        else
            print(SKULL .. " |cffFF0000No entities found - try /pfc 10|r")
        end
    end
    print("|cff888888=== Search Complete ===|r")
end

-- Command: /pfc - Find zones with coordinates close to 50,50 OR search by zone name
SLASH_PFC1 = "/pfc"
SlashCmdList["PFC"] = function(msg)
    if not pfDB then
        print(SKULL .. " pfDB not loaded! Make sure pfQuest addon is running.")
        return
    end

    if pfcSearchState.isSearching then
        print(SKULL .. " Search already in progress! Please wait...")
        return
    end

    -- Parse the message - can be: "Azure", "Stormwind", etc.
    local zoneFilter = nil

    if msg and msg ~= "" and string.match(msg, "%S") then
        zoneFilter = msg
    end

    if zoneFilter then
        print("|cff00FF00=== pfQuest EXACT 50,50 Search in Zone ===|r")
        print(DIAMOND .. " |cffFFD700Searching EXACT (50,50) coordinates in zones matching '" .. zoneFilter .. "'|r")
    else
        print("|cff00FF00=== pfQuest EXACT 50,50 Coordinate Search ===|r")
        print(DIAMOND .. " |cffFFD700Searching quest-related entities with EXACT (50,50) coordinates|r")
    end

    local targetX, targetY = 50, 50

    -- Reset search state
    pfcSearchState = {
        isSearching = true,
        results = {},
        totalFound = 0,
        questRelatedFound = 0,
        currentStep = 0,
        totalSteps = 0,
        searchParams = {
            targetX = targetX,
            targetY = targetY,
            zoneFilter = zoneFilter,
            entityQueue = {}
        }
    }

    -- Build entity queue for lazy processing
    local entityQueue = pfcSearchState.searchParams.entityQueue

    -- Add NPCs to queue
    if pfDB["units"] and pfDB["units"]["data"] then
        for unitId, unit in pairs(pfDB["units"]["data"]) do
            if unit.coords then
                table.insert(entityQueue, {
                    type = "NPC",
                    id = unitId,
                    coords = unit.coords
                })
            end
        end
    end

    -- Add Objects to queue
    if pfDB["objects"] and pfDB["objects"]["data"] then
        for objectId, object in pairs(pfDB["objects"]["data"]) do
            if object.coords then
                table.insert(entityQueue, {
                    type = "Object",
                    id = objectId,
                    coords = object.coords
                })
            end
        end
    end

    pfcSearchState.totalSteps = #entityQueue

    if pfcSearchState.totalSteps == 0 then
        print(SKULL .. " No entities found in database!")
        pfcSearchState.isSearching = false
        return
    end

    print("   |cff888888Processing " .. pfcSearchState.totalSteps .. " entities...|r")

    -- Start lazy processing with OnUpdate
    pfcSearchState.lastProgress = 0
    pfcSearchState.lastQuestFound = 0
    pfcFrame:Show()
end

--print("|cff00FF00pfQuest Debug Commands:|r")
--print("|cff00BFFF/pfi [search]|r - Search quests with item requirements")
--print("|cff00BFFF/pfr [search]|r - Search rare creatures")
--print("|cff00BFFF/pfc [zone]|r - Find EXACT 50,50 coordinates globally or in specific zone")
--print("|cff00BFFF/pfbrowser|r - Open visual debug browser")
--print("|cff00BFFF/pftest|r - Test working quests")
--print("|cff00BFFF/pfq <ID>|r - Show specific quest")


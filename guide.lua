pfGuide = CreateFrame("Frame", "pfGuideFrame", UIParent)

pfGuide.STATE = {
    UNAVAILABLE = "UNAVAILABLE",
    AVAILABLE = "AVAILABLE",
    ACTIVE_INCOMPLETE = "ACTIVE_INCOMPLETE",
    ACTIVE_COMPLETE = "ACTIVE_COMPLETE"
}

-- Простая команда для теста
SLASH_PFGUIDE1 = "/guide"
SlashCmdList["PFGUIDE"] = function(msg)
    pfGuide:UpdateArrow()
end

function pfGuide:TestCurrentQuests()
    print("|cff00ff00[pfGuide]|r Анализ текущих квестов:")
    local activeQuests = 0

    for questid, data in pairs(pfQuest.questlog) do
        local qtitle = data.title
        local state = self:GetQuestState(questid)

        if state == self.STATE.ACTIVE_INCOMPLETE then
            print(" - В процессе: " .. qtitle .. " (ID: " .. questid .. ")")
            activeQuests = activeQuests + 1
        elseif state == self.STATE.ACTIVE_COMPLETE then
            print(" - Готов к сдаче: " .. qtitle .. " (ID: " .. questid .. ")")
            activeQuests = activeQuests + 1
        end
    end

    if activeQuests == 0 then
        print("Нет активных квестов или квестов, готовых к сдаче.")
    end
end

function pfGuide:GetQuestState(questid)
    local data = pfQuest.questlog[questid]
    if not data or not data.qlogid then
        return self.STATE.UNAVAILABLE
    end

    local qlogid = data.qlogid
    local objectives = GetNumQuestLeaderBoards(qlogid) or 0

    if objectives == 0 then
        return self.STATE.ACTIVE_COMPLETE
    end

    for i = 1, objectives do
        local _, _, done = GetQuestLogLeaderBoard(i, qlogid)
        if not done then
            return self.STATE.ACTIVE_INCOMPLETE
        end
    end

    return self.STATE.ACTIVE_COMPLETE
end

function pfGuide:GetQuestPOIs(questid, state)
    local quest = pfDB.quests.data[questid]
    if not quest then return {} end

    local pois = {}
    local seen = {}

    local function addPOI(x, y, zone, action, targetName)
        if not x or not y or not zone or zone <= 0 then return end
        local title = targetName or "Unknown"
        local key = tostring(zone) .. ":" .. tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(action) .. ":" .. tostring(title)
        if seen[key] then return end
        seen[key] = true
        table.insert(pois, { x = x, y = y, zone = zone, action = action, targetName = title })
    end

    local function addUnitPOIs(unit, action)
        if not pfDB.units.data[unit] or not pfDB.units.data[unit].coords then return end
        local name = pfDB.units.loc[unit] or "Unknown"
        for _, coord in pairs(pfDB.units.data[unit].coords) do
            local x, y, zone = unpack(coord)
            addPOI(x, y, zone, action, name)
        end
    end

    local function addObjectPOIs(object, action)
        if not pfDB.objects.data[object] or not pfDB.objects.data[object].coords then return end
        local name = pfDB.objects.loc[object] or "Unknown"
        for _, coord in pairs(pfDB.objects.data[object].coords) do
            local x, y, zone = unpack(coord)
            addPOI(x, y, zone, action, name)
        end
    end

    local function addItemPOIs(item, action)
        if not pfDB.items.data[item] then return end
        local title = pfDB.items.loc[item] or "Unknown"

        if pfDB.items.data[item]["U"] then
            for unit in pairs(pfDB.items.data[item]["U"]) do
                addUnitPOIs(unit, action .. " (drop for " .. title .. ")")
            end
        end

        if pfDB.items.data[item]["O"] then
            for object in pairs(pfDB.items.data[item]["O"]) do
                addObjectPOIs(object, action .. " (drop for " .. title .. ")")
            end
        end

        if pfDB.items.data[item]["R"] then
            for ref in pairs(pfDB.items.data[item]["R"]) do
                if refloot[ref] then
                    if refloot[ref]["U"] then
                        for unit in pairs(refloot[ref]["U"]) do
                            addUnitPOIs(unit, action .. " (drop for " .. title .. ")")
                        end
                    end
                    if refloot[ref]["O"] then
                        for object in pairs(refloot[ref]["O"]) do
                            addObjectPOIs(object, action .. " (drop for " .. title .. ")")
                        end
                    end
                end
            end
        end

        if pfDB.items.data[item]["V"] then
            for unit in pairs(pfDB.items.data[item]["V"]) do
                addUnitPOIs(unit, action .. " (vendor for " .. title .. ")")
            end
        end
    end

    local parse_obj = {
        ["U"] = {},
        ["O"] = {},
        ["I"] = {},
    }

    if state == self.STATE.ACTIVE_INCOMPLETE then
        local data = pfQuest.questlog[questid]
        if data and data.qlogid then
            local objectives = GetNumQuestLeaderBoards(data.qlogid) or 0
            for i = 1, objectives do
                local text, type, done = GetQuestLogLeaderBoard(i, data.qlogid)

                if type == "monster" then
                    local _, _, monsterName, objNum, objNeeded = strfind(text, pfUI.api.SanitizePattern(QUEST_MONSTERS_KILLED))
                    for id in pairs(pfDatabase:GetIDByName(monsterName, "units")) do
                        parse_obj["U"][id] = (objNum + 0 >= objNeeded + 0 or done) and "DONE" or "PROG"
                    end
                    for id in pairs(pfDatabase:GetIDByName(monsterName, "objects")) do
                        parse_obj["O"][id] = (objNum + 0 >= objNeeded + 0 or done) and "DONE" or "PROG"
                    end
                elseif type == "item" then
                    local _, _, itemName, objNum, objNeeded = strfind(text, pfUI.api.SanitizePattern(QUEST_OBJECTS_FOUND))
                    for id in pairs(pfDatabase:GetIDByName(itemName, "items")) do
                        parse_obj["I"][id] = (objNum + 0 >= objNeeded + 0 or done) and "DONE" or "PROG"
                    end
                end
            end
        end
    end

    if state == self.STATE.AVAILABLE then
        if quest["start"] then
            if quest["start"]["U"] then
                for _, unit in pairs(quest["start"]["U"]) do
                    addUnitPOIs(unit, "Accept")
                end
            end
            if quest["start"]["O"] then
                for _, object in pairs(quest["start"]["O"]) do
                    addObjectPOIs(object, "Accept")
                end
            end
        end
    elseif state == self.STATE.ACTIVE_COMPLETE then
        if quest["end"] then
            if quest["end"]["U"] then
                for _, unit in pairs(quest["end"]["U"]) do
                    addUnitPOIs(unit, "TurnIn")
                end
            end
            if quest["end"]["O"] then
                for _, object in pairs(quest["end"]["O"]) do
                    addObjectPOIs(object, "TurnIn")
                end
            end
            if quest["end"]["I"] then
                for _, item in pairs(quest["end"]["I"]) do
                    addItemPOIs(item, "TurnIn")
                end
            end
        end
    elseif state == self.STATE.ACTIVE_INCOMPLETE then
        if quest["obj"] then
            if quest["obj"]["U"] then
                for _, unit in pairs(quest["obj"]["U"]) do
                    if not parse_obj["U"][unit] or parse_obj["U"][unit] ~= "DONE" then
                        addUnitPOIs(unit, "Objective")
                    end
                end
            end
            if quest["obj"]["O"] then
                for _, object in pairs(quest["obj"]["O"]) do
                    if not parse_obj["O"][object] or parse_obj["O"][object] ~= "DONE" then
                        addObjectPOIs(object, "Objective")
                    end
                end
            end
            if quest["obj"]["I"] then
                for _, item in pairs(quest["obj"]["I"]) do
                    if not parse_obj["I"][item] or parse_obj["I"][item] ~= "DONE" then
                        addItemPOIs(item, "Objective")
                    end
                end
            end
        end
    end

    return pois
end

function pfGuide:IsQuestTurnInReady(qlogid)
    local objectives = GetNumQuestLeaderBoards(qlogid) or 0
    if objectives == 0 then
        return true
    end

    for i = 1, objectives do
        local _, _, done = GetQuestLogLeaderBoard(i, qlogid)
        if not done then
            return false
        end
    end

    return true
end

function pfGuide:GetFirstTarget()
    local map = pfMap:GetMapID(GetCurrentMapContinent(), GetCurrentMapZone())
    
    for questid, data in pairs(pfQuest.questlog) do
        if self:GetQuestState(questid) == self.STATE.ACTIVE_INCOMPLETE then
            -- 1. Симулируем запрос к базе (как это делает клик в трекере)
            local meta = { ["addon"] = "PFGUIDE", ["qlogid"] = data.qlogid }
            pfMap:DeleteNode("PFGUIDE") -- чистим старые
            pfDatabase:SearchQuestID(questid, meta)
            
            -- 2. Достаем сгенерированные точки из pfMap
            if pfMap.nodes["PFGUIDE"] and pfMap.nodes["PFGUIDE"][map] then
                for coords, nodeData in pairs(pfMap.nodes["PFGUIDE"][map]) do
                    local _, _, x, y = string.find(coords, "(.*)|(.*)")
                    if x and y then
                        print("|cff00ff00[pfGuide]|r Иди сюда: " .. data.title .. " -> X: " .. x .. " Y: " .. y)
                        return tonumber(x), tonumber(y), data.title
                    end
                end
            end
        end
    end
    print("|cff00ff00[pfGuide]|r Целей в этой локации нет.")
end

function pfGuide:PointArrowToTarget()
    local targetX, targetY, title = self:GetFirstTarget()
    
    if targetX and targetY then
        -- Сбрасываем старые маршруты
        pfQuest.route:Reset()
        
        -- Создаем "фейковую" метку для стрелки
        local targetNode = {
            [1] = targetX,
            [2] = targetY,
            [3] = {
                title = title,
                texture = pfQuestConfig.path.."\\img\\cluster_mob"
            }
        }
        
        -- Кидаем в route.lua
        pfQuest.route:AddPoint(targetNode)
        pfQuest.route.SetTarget(targetNode[3])
        pfQuest.route.arrow:Show()
        
        print("|cff00ff00[pfGuide]|r Стрелка указывает на: " .. title)
    end
end

function pfGuide:GetBestTarget()
    local map = pfMap:GetMapID(GetCurrentMapContinent(), GetCurrentMapZone())
    local pX, pY = GetPlayerMapPosition("player")
    pX, pY = pX * 100, pY * 100 -- переводим в 0-100
    
    if pX == 0 and pY == 0 then return end -- Мы в инсте или карты нет
    
    local bestDist = 999999
    local bestX, bestY, bestTitle = nil, nil, nil
    
    pfMap:DeleteNode("PFGUIDE")
    
    -- Запрашиваем точки для всех активных незавершенных квестов
    for questid, data in pairs(pfQuest.questlog) do
        if self:GetQuestState(questid) == self.STATE.ACTIVE_INCOMPLETE then
            local meta = { ["addon"] = "PFGUIDE", ["qlogid"] = data.qlogid }
            pfDatabase:SearchQuestID(questid, meta)
        end
    end
    
    -- Ищем самую ближнюю точку
    if pfMap.nodes["PFGUIDE"] and pfMap.nodes["PFGUIDE"][map] then
        for coords, nodeData in pairs(pfMap.nodes["PFGUIDE"][map]) do
            local _, _, x, y = string.find(coords, "(.*)|(.*)")
            x, y = tonumber(x), tonumber(y)
            
            for title, meta in pairs(nodeData) do
                -- Считаем дистанцию
                local dist = math.sqrt((pX - x)^2 + (pY - y)^2)
                if dist < bestDist then
                    bestDist = dist
                    bestX, bestY, bestTitle = x, y, title
                end
            end
        end
    end
    
    return bestX, bestY, bestTitle
end

function pfGuide:UpdateArrow()
    local x, y, title = self:GetBestTarget()
    if x and y then
        pfQuest.route:Reset()
        local node = { [1] = x, [2] = y, [3] = { title = title, texture = pfQuestConfig.path.."\\img\\cluster_mob" } }
        pfQuest.route:AddPoint(node)
        pfQuest.route.SetTarget(node[3])
        pfQuest.route.arrow:Show()
    end
end

-- ============================================================================
-- ОКНО ГАЙДА (UI)
-- ============================================================================

-- Создаём основное окно
pfGuideWindow = CreateFrame("Frame", "pfQuestGuideWindow", UIParent)
pfGuideWindow:SetWidth(420)
pfGuideWindow:SetHeight(350)
pfGuideWindow:SetPoint("CENTER", -200, 0)
pfGuideWindow:SetFrameStrata("HIGH")
pfGuideWindow:SetMovable(true)
pfGuideWindow:EnableMouse(true)
pfGuideWindow:RegisterForDrag("LeftButton")
pfGuideWindow:SetScript("OnDragStart", function() this:StartMoving() end)
pfGuideWindow:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)

-- Backdrop (рамка и фон)
pfGuideWindow.backdrop = CreateFrame("Frame", nil, pfGuideWindow)
pfGuideWindow.backdrop:SetFrameLevel(0)
pfGuideWindow.backdrop:SetAllPoints(pfGuideWindow)
pfGuideWindow.backdrop:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
})
pfGuideWindow.backdrop:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
pfGuideWindow.backdrop:SetBackdropBorderColor(0.4, 0.8, 1, 1)

-- Заголовок
pfGuideWindow.title = pfGuideWindow:CreateFontString(nil, "OVERLAY", "GameFontWhite")
pfGuideWindow.title:SetPoint("TOPLEFT", pfGuideWindow, "TOPLEFT", 10, -10)
pfGuideWindow.title:SetText("|cff00ff00[pfGuide]|r Active Quests")

-- Кнопка закрыть
pfGuideWindow.close = CreateFrame("Button", nil, pfGuideWindow)
pfGuideWindow.close:SetPoint("TOPRIGHT", pfGuideWindow, "TOPRIGHT", -5, -5)
pfGuideWindow.close:SetWidth(20)
pfGuideWindow.close:SetHeight(20)
pfGuideWindow.close.texture = pfGuideWindow.close:CreateTexture(nil)
pfGuideWindow.close.texture:SetTexture(pfQuestConfig.path.."\\compat\\close")
pfGuideWindow.close.texture:ClearAllPoints()
pfGuideWindow.close.texture:SetVertexColor(1, 0.25, 0.25, 1)
pfGuideWindow.close.texture:SetPoint("TOPLEFT", pfGuideWindow.close, "TOPLEFT", 2, -2)
pfGuideWindow.close.texture:SetPoint("BOTTOMRIGHT", pfGuideWindow.close, "BOTTOMRIGHT", -2, 2)
pfGuideWindow.close:SetScript("OnClick", function()
    this:GetParent():Hide()
end)

pfGuideWindow.emptyLabel = pfGuideWindow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
pfGuideWindow.emptyLabel:SetPoint("CENTER", pfGuideWindow, "CENTER", 0, -20)
pfGuideWindow.emptyLabel:SetText("Нет квестов для сдачи на этой карте.")
pfGuideWindow.emptyLabel:Hide()

-- ScrollFrame для списка квестов
pfGuideWindow.scroll = CreateFrame("ScrollFrame", nil, pfGuideWindow)
pfGuideWindow.scroll:SetPoint("TOPLEFT", pfGuideWindow, "TOPLEFT", 8, -35)
pfGuideWindow.scroll:SetPoint("BOTTOMRIGHT", pfGuideWindow, "BOTTOMRIGHT", -8, 8)

pfGuideWindow.list = CreateFrame("Frame", nil, pfGuideWindow.scroll)
pfGuideWindow.list:SetWidth(400)
pfGuideWindow.scroll:SetScrollChild(pfGuideWindow.list)

pfGuideWindow.buttons = {}

-- Функция создания кнопки квеста
local function CreateQuestButton(i)
    local btn = CreateFrame("Button", nil, pfGuideWindow.list)
    btn:SetPoint("TOPLEFT", pfGuideWindow.list, "TOPLEFT", 0, -i * 45)
    btn:SetWidth(400)
    btn:SetHeight(40)
    
    -- Фоновая текстура
    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints(btn)
    btn.bg:SetTexture(1, 1, 1, (i % 2 == 0) and 0.05 or 0.02)
    
    -- Название квеста
    btn.name = btn:CreateFontString(nil, "OVERLAY", "GameFontWhite")
    btn.name:SetPoint("TOPLEFT", btn, "TOPLEFT", 10, -5)
    btn.name:SetJustifyH("LEFT")
    btn.name:SetWidth(350)
    
    -- Координаты и дистанция
    btn.info = btn:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    btn.info:SetPoint("TOPLEFT", btn.name, "BOTTOMLEFT", 0, -3)
    btn.info:SetJustifyH("LEFT")
    btn.info:SetText("X: -- Y: -- Dist: -- m")
    
    -- Кнопка Track
    btn.track = CreateFrame("Button", nil, btn)
    btn.track:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -8, -8)
    btn.track:SetWidth(70)
    btn.track:SetHeight(25)
    btn.track:SetText("Track")
    btn.track.bg = btn.track:CreateTexture(nil, "BACKGROUND")
    btn.track.bg:SetAllPoints(btn.track)
    btn.track.bg:SetTexture(0.2, 0.6, 0.2, 0.6)
    
    btn.track:SetScript("OnClick", function()
        if btn.questid then
            pfGuide:PointToQuest(btn.questid)
        end
    end)
    
    btn:SetScript("OnEnter", function()
        btn.bg:SetTexture(1, 1, 1, 0.2)
    end)
    
    btn:SetScript("OnLeave", function()
        btn.bg:SetTexture(1, 1, 1, (i % 2 == 0) and 0.05 or 0.02)
    end)
    
    return btn
end

-- Функция обновления окна
function pfGuide:RefreshWindow()
    local map = pfMap:GetMapID(GetCurrentMapContinent(), GetCurrentMapZone())
    local pX, pY = GetPlayerMapPosition("player")
    pX, pY = pX * 100, pY * 100
    
    pfMap:DeleteNode("PFGUIDE")
    
    -- Собираем все квесты, готовые к сдаче
    local questList = {}
    for questid, data in pairs(pfQuest.questlog) do
        if self:GetQuestState(questid) == self.STATE.ACTIVE_COMPLETE then
            table.insert(questList, {questid = questid, title = data.title, qlogid = data.qlogid})
        end
    end
    
    -- Запрашиваем координаты для всех
    for _, quest in ipairs(questList) do
        local meta = { ["addon"] = "PFGUIDE", ["qlogid"] = quest.qlogid }
        pfDatabase:SearchQuestID(quest.questid, meta)
    end
    
    -- Обновляем кнопки
    local btnIndex = 1
    if pfMap.nodes["PFGUIDE"] and pfMap.nodes["PFGUIDE"][map] then
        for _, data in ipairs(questList) do
            local dist = 999999
            local bestX, bestY, bestTitle = nil, nil, nil
            
            for coords_str, nodeData in pairs(pfMap.nodes["PFGUIDE"][map]) do
                local _, _, x, y = string.find(coords_str, "(.*)|(.*)")
                x, y = tonumber(x), tonumber(y)
                
                for title, meta in pairs(nodeData) do
                    local d = math.sqrt((pX - x)^2 + (pY - y)^2)
                    if d < dist then
                        dist = d
                        bestX, bestY, bestTitle = x, y, title
                    end
                end
            end
            
            if bestX and bestY then
                if not pfGuideWindow.buttons[btnIndex] then
                    pfGuideWindow.buttons[btnIndex] = CreateQuestButton(btnIndex)
                end
                
                local btn = pfGuideWindow.buttons[btnIndex]
                btn.questid = data.questid
                btn.name:SetText(data.title)
                btn.info:SetText(string.format("X: %.1f Y: %.1f Dist: %.0f m", bestX/100, bestY/100, dist))
                btn:Show()
                
                btnIndex = btnIndex + 1
            end
        end
    end
    
    if btnIndex == 1 then
        pfGuideWindow.emptyLabel:Show()
    else
        pfGuideWindow.emptyLabel:Hide()
    end
    
    -- Скрываем неиспользованные кнопки
    for i = btnIndex, #pfGuideWindow.buttons do
        pfGuideWindow.buttons[i]:Hide()
    end
    
    -- Обновляем высоту списка
    pfGuideWindow.list:SetHeight((btnIndex - 1) * 45 + 10)
end

-- Функция отправить стрелку на конкретный квест
function pfGuide:PointToQuest(questid)
    local map = pfMap:GetMapID(GetCurrentMapContinent(), GetCurrentMapZone())
    pfMap:DeleteNode("PFGUIDE")
    
    local meta = { ["addon"] = "PFGUIDE" }
    pfDatabase:SearchQuestID(questid, meta)
    
    if pfMap.nodes["PFGUIDE"] and pfMap.nodes["PFGUIDE"][map] then
        for coords, nodeData in pairs(pfMap.nodes["PFGUIDE"][map]) do
            local _, _, x, y = string.find(coords, "(.*)|(.*)")
            if x and y then
                pfQuest.route:Reset()
                local node = { [1] = tonumber(x), [2] = tonumber(y), [3] = { title = pfQuest.questlog[questid].title, texture = pfQuestConfig.path.."\\img\\cluster_mob" } }
                pfQuest.route:AddPoint(node)
                pfQuest.route.SetTarget(node[3])
                pfQuest.route.arrow:Show()
                break
            end
        end
    end
end

-- Команда /guide открывает/закрывает окно
SlashCmdList["PFGUIDE"] = function(msg)
    if pfGuideWindow:IsShown() then
        pfGuideWindow:Hide()
    else
        pfGuideWindow:Show()
        pfGuide:RefreshWindow()
    end
end

-- Скрываем окно по умолчанию
pfGuideWindow:Hide()

-- Автоматическое обновление при изменении квестлога
pfGuide:RegisterEvent("QUEST_LOG_UPDATE")
pfGuide:RegisterEvent("QUEST_WATCH_UPDATE")
pfGuide:SetScript("OnEvent", function()
    if pfGuideWindow:IsShown() then
        pfGuide.timer = GetTime() + 0.3
    end
end)

pfGuide:SetScript("OnUpdate", function()
    if pfGuideWindow:IsShown() then
        if this.timer and GetTime() > this.timer then
            this.timer = nil
            pfGuide:RefreshWindow()
        elseif not this.timer then
            this.timer = GetTime() + 1
        end
    end
end)

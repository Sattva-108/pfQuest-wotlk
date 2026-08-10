-- ============================================================================
-- ИНИЦИАЛИЗАЦИЯ И ПЕРЕХВАТ УПРАВЛЕНИЯ СТРЕЛКОЙ (HIJACK ROUTE.LUA)
-- ============================================================================
pfGuide = CreateFrame("Frame", "pfGuideFrame", UIParent)

-- Сохраняем оригинальные функции маршрута внутрь pfGuide
pfGuide.RouteReset = pfQuest.route.Reset
pfGuide.RouteAddPoint = pfQuest.route.AddPoint
pfGuide.RouteSetTarget = pfQuest.route.SetTarget

-- Ломаем их для оригинального аддона, чтобы pfMap не сбрасывал нашу стрелку
pfQuest.route.Reset = function() end
pfQuest.route.AddPoint = function() end
pfQuest.route.SetTarget = function() end

pfGuide.STATE = {
    UNAVAILABLE = "UNAVAILABLE",
    AVAILABLE = "AVAILABLE",
    ACTIVE_INCOMPLETE = "ACTIVE_INCOMPLETE",
    ACTIVE_COMPLETE = "ACTIVE_COMPLETE"
}

pfGuide.poiCacheDuration = 2
pfGuide.lastPoisUpdate = 0
pfGuide.cachedPois = nil
pfGuide.needsFullRefresh = false
pfGuide.refreshTimer = nil
pfGuide.xpCache = {}

-- Вспомогательная функция поиска ближайшего распорядителя полетов вашей фракции в текущей зоне
local function GetClosestFlightMaster(currentZone, pX, pY)
    local faction = UnitFactionGroup("player")
    local factionCode = (faction == "Horde") and "H" or "A"
    local bestFM = nil
    local bestScore = math.huge

    if pfDB.meta and pfDB.meta.flight then
        for npcId, fac in pairs(pfDB.meta.flight) do
            if string.find(fac, factionCode) or fac == "AH" then
                local unit = pfDB.units.data[npcId]
                if unit and unit.coords then
                    for _, coord in ipairs(unit.coords) do
                        if coord[3] == currentZone then
                            local dist = math.sqrt((pX - coord[1])^2 + (pY - coord[2])^2)
                            if dist < bestScore then
                                bestScore = dist
                                bestFM = { x = coord[1], y = coord[2], name = pfDB.units.loc[npcId] or "Flight Master" }
                            end
                        end
                    end
                end
            end
        end
    end
    return bestFM
end

-- Метод поиска лучшей зоны для перехода на основе доступных по уровню квестов
function pfGuide:GetNextZoneSuggestion(plevel, pclass, prace)
    local zoneScores = {}
    if not pfDB.quests or not pfDB.quests.data then return nil, 0 end

    for questid, quest in pairs(pfDB.quests.data) do
        if not pfQuest_config.guideBlacklist[questid] and not pfQuest.questlog[questid] then
            if pfDatabase:QuestFilter(questid, plevel, pclass, prace) then
                local xp = pfGuide:GetQuestXP(questid)
                local start_zones = {}

                if quest.start then
                    if quest.start.U then
                        for _, unit in pairs(quest.start.U) do
                            local uData = pfDB.units.data[unit]
                            if uData and uData.coords then
                                for _, coord in pairs(uData.coords) do
                                    start_zones[coord[3]] = true
                                end
                            end
                        end
                    end
                    if quest.start.O then
                        for _, object in pairs(quest.start.O) do
                            local oData = pfDB.objects.data[object]
                            if oData and oData.coords then
                                for _, coord in pairs(oData.coords) do
                                    start_zones[coord[3]] = true
                                end
                            end
                        end
                    end
                end

                for zoneId in pairs(start_zones) do
                    if not zoneScores[zoneId] then
                        zoneScores[zoneId] = { count = 0, totalXP = 0 }
                    end
                    zoneScores[zoneId].count = zoneScores[zoneId].count + 1
                    zoneScores[zoneId].totalXP = zoneScores[zoneId].totalXP + xp
                end
            end
        end
    end

    local bestZoneId = nil
    local bestScore = -1

    for zoneId, data in pairs(zoneScores) do
        if zoneId > 0 then
            local score = data.totalXP * 0.7 + data.count * 15
            if score > bestScore then
                bestScore = score
                bestZoneId = zoneId
            end
        end
    end

    return bestZoneId, bestScore
end

-- ============================================================================
-- ЛОГИКА СОСТОЯНИЙ И ПОЛУЧЕНИЯ ТОЧЕК (POIs)
-- ============================================================================
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

function pfGuide:GetQuestXP(questid)
    if self.xpCache[questid] then
        return self.xpCache[questid]
    end

    local questData = pfDB.quests.data[questid]
    if not questData then
        self.xpCache[questid] = 0
        return 0
    end

    local xp = pfMap:GetQuestXP(questData)
    self.xpCache[questid] = xp
    return xp
end

function pfGuide:EnrichPOIWithXP(poi, questid)
    if not questid or questid == 0 then return end
    poi.xpReward = self:GetQuestXP(questid)
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

    local function addUnitPOIs(unit, action, extraText)
        if not pfDB.units.data[unit] or not pfDB.units.data[unit].coords then return end
        local name = pfDB.units.loc[unit] or "Unknown"
        if extraText then name = name .. " (" .. extraText .. ")" end

        for _, coord in pairs(pfDB.units.data[unit].coords) do
            local x, y, zone = unpack(coord)
            addPOI(x, y, zone, action, name)
        end
    end

    local function addObjectPOIs(object, action, extraText)
        if not pfDB.objects.data[object] or not pfDB.objects.data[object].coords then return end
        local name = pfDB.objects.loc[object] or "Unknown"
        if extraText then name = name .. " (" .. extraText .. ")" end

        for _, coord in pairs(pfDB.objects.data[object].coords) do
            local x, y, zone = unpack(coord)
            addPOI(x, y, zone, action, name)
        end
    end

    local function addItemPOIs(item, action)
        if not pfDB.items.data[item] then return end
        local title = pfDB.items.loc[item] or "Unknown"
        local extraText = "Drop: " .. title

        if pfDB.items.data[item]["U"] then
            for unit in pairs(pfDB.items.data[item]["U"]) do
                addUnitPOIs(unit, action, extraText)
            end
        end

        if pfDB.items.data[item]["O"] then
            for object in pairs(pfDB.items.data[item]["O"]) do
                addObjectPOIs(object, action, extraText)
            end
        end

        if pfDB.items.data[item]["R"] then
            for ref in pairs(pfDB.items.data[item]["R"]) do
                -- Исправлен путь к базе refloot
                if pfDB.refloot and pfDB.refloot.data and pfDB.refloot.data[ref] then
                    local refData = pfDB.refloot.data[ref]
                    if refData["U"] then
                        for unit in pairs(refData["U"]) do
                            addUnitPOIs(unit, action, extraText)
                        end
                    end
                    if refData["O"] then
                        for object in pairs(refData["O"]) do
                            addObjectPOIs(object, action, extraText)
                        end
                    end
                end
            end
        end

        if pfDB.items.data[item]["V"] then
            for unit in pairs(pfDB.items.data[item]["V"]) do
                addUnitPOIs(unit, action, "Vendor: " .. title)
            end
        end
    end

    local parse_obj = { ["U"] = {}, ["O"] = {}, ["I"] = {} }

    if state == self.STATE.ACTIVE_INCOMPLETE then
        local data = pfQuest.questlog[questid]
        if data and data.qlogid then
            local objectives = GetNumQuestLeaderBoards(data.qlogid) or 0
            for i = 1, objectives do
                local text, type, done = GetQuestLogLeaderBoard(i, data.qlogid)

                if type == "monster" then
                    local _, _, monsterName, objNum, objNeeded = strfind(text, pfUI.api.SanitizePattern(QUEST_MONSTERS_KILLED))
                    if monsterName then
                        for id in pairs(pfDatabase:GetIDByName(monsterName, "units") or {}) do
                            parse_obj["U"][id] = ((tonumber(objNum) or 0) >= (tonumber(objNeeded) or 0) or done) and "DONE" or "PROG"
                        end
                        for id in pairs(pfDatabase:GetIDByName(monsterName, "objects") or {}) do
                            parse_obj["O"][id] = ((tonumber(objNum) or 0) >= (tonumber(objNeeded) or 0) or done) and "DONE" or "PROG"
                        end
                    end
                elseif type == "item" then
                    local _, _, itemName, objNum, objNeeded = strfind(text, pfUI.api.SanitizePattern(QUEST_OBJECTS_FOUND))
                    if itemName then
                        for id in pairs(pfDatabase:GetIDByName(itemName, "items") or {}) do
                            parse_obj["I"][id] = ((tonumber(objNum) or 0) >= (tonumber(objNeeded) or 0) or done) and "DONE" or "PROG"
                        end
                    end
                end
            end
        end
    end

    -- Собираем точки (action передаем строгий, без примесей)
    if state == self.STATE.AVAILABLE then
        if quest["start"] then
            if quest["start"]["U"] then
                for _, unit in pairs(quest["start"]["U"]) do addUnitPOIs(unit, "Accept") end
            end
            if quest["start"]["O"] then
                for _, object in pairs(quest["start"]["O"]) do addObjectPOIs(object, "Accept") end
            end
        end
    elseif state == self.STATE.ACTIVE_COMPLETE then
        if quest["end"] then
            if quest["end"]["U"] then
                for _, unit in pairs(quest["end"]["U"]) do addUnitPOIs(unit, "TurnIn") end
            end
            if quest["end"]["O"] then
                for _, object in pairs(quest["end"]["O"]) do addObjectPOIs(object, "TurnIn") end
            end
            if quest["end"]["I"] then
                for _, item in pairs(quest["end"]["I"]) do addItemPOIs(item, "TurnIn") end
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

function pfGuide:ScorePOI(poi, playerX, playerY)
    local dist = math.sqrt((playerX - poi.x)^2 + (playerY - poi.y)^2)
    local score = dist * dist  -- базовый штраф расстояния

    -- === XP EFFICIENCY ===
    if poi.xpReward and poi.xpReward > 0 then
        local xpPerDist = poi.xpReward / (dist + 30)
        score = score - (poi.xpReward * 0.12)
        score = score - (xpPerDist * 12)
    end

    -- Приоритеты действий
    if poi.action == "TurnIn" then
        score = score - 28
    elseif poi.action == "Accept" then
        score = score - 15

        -- Бонус за начало цепочки
        if poi.questid and poi.questid > 0 then
            local qData = pfDB.quests.data[poi.questid]
            if qData and qData.chain and #qData.chain > 1 then
                score = score - 8
            end
        end
    end

    if poi.zone == pfMap:GetMapID(GetCurrentMapContinent(), GetCurrentMapZone()) then
        score = score - 5
    end

    return score
end

function pfGuide:GetActivePOIs(forceRefresh)
    pfQuest_config.guideBlacklist = pfQuest_config.guideBlacklist or {}

    local now = GetTime()
    if not forceRefresh and self.cachedPois and (now - self.lastPoisUpdate) < self.poiCacheDuration then
        return self.cachedPois
    end

    local bestPois = {}
    local currentZone = pfMap:GetMapID(GetCurrentMapContinent(), GetCurrentMapZone())
    if not currentZone then return {} end

    local pX, pY = GetPlayerMapPosition("player")
    pX, pY = pX * 100, pY * 100

    -- Не можем построить маршрут, если нет координат игрока (инст/отсутствие карты)
    if pX == 0 and pY == 0 then return {} end

    local plevel = UnitLevel("player")
    local _, race = UnitRace("player")
    local prace = pfDatabase:GetBitByRace(race)
    local _, class = UnitClass("player")
    local pclass = pfDatabase:GetBitByClass(class)

    -- Вспомогательная функция для дедупликации (оставляем только ближайшую точку)
    local function addBestPOI(poi)
        if poi.zone ~= currentZone then return end
        poi.score = self:ScorePOI(poi, pX, pY)
        local key = tostring(poi.questid) .. "_" .. tostring(poi.action) .. "_" .. tostring(poi.targetName)

        local existing = bestPois[key]
        if not existing or poi.score < existing.score then
            bestPois[key] = poi
        end
    end

    -- 1. Добавляем точки активных квестов (в процессе и на сдачу)
    for questid, data in pairs(pfQuest.questlog) do
        if not pfQuest_config.guideBlacklist[questid] then
            local state = self:GetQuestState(questid)
            if state ~= self.STATE.UNAVAILABLE then
                local questPOIs = self:GetQuestPOIs(questid, state)
                for _, poi in ipairs(questPOIs) do
                    poi.questid = questid
                    poi.state = state
                    poi.questTitle = data.title
                    pfGuide:EnrichPOIWithXP(poi, questid)
                    addBestPOI(poi)
                end
            end
        end
    end

    -- 2. Добавляем точки для ВЗЯТИЯ новых квестов
    if pfDB.quests and pfDB.quests.data then
        for questid in pairs(pfDB.quests.data) do
            -- Проверяем, что квеста нет в логе, он не в черном списке и он нам доступен по уровню/расе
            if not pfQuest_config.guideBlacklist[questid] and not pfQuest.questlog[questid] and pfDatabase:QuestFilter(questid, plevel, pclass, prace) then
                local questPOIs = self:GetQuestPOIs(questid, self.STATE.AVAILABLE)
                if next(questPOIs) then
                    -- ИСПРАВЛЕНИЕ: Правильно достаем локализованное название квеста
                    local locData = pfDB["quests"]["loc"][questid]
                    local title = (locData and locData["T"]) or "Unknown"

                    for _, poi in ipairs(questPOIs) do
                        poi.questid = questid
                        poi.state = self.STATE.AVAILABLE
                        poi.questTitle = title
                        pfGuide:EnrichPOIWithXP(poi, questid)
                        addBestPOI(poi)
                    end
                end
            end
        end
    end

    -- Перекладываем в обычный массив для сортировки
    local pois = {}
    for _, poi in pairs(bestPois) do
        table.insert(pois, poi)
    end

    -- Сортируем от самого низкого (лучшего) к самому высокому (худшему) score
    table.sort(pois, function(a, b)
        return a.score < b.score
    end)

    -- МЕЖЗОНАЛЬНАЯ НАВИГАЦИЯ (FALLBACK)
    -- Если в текущей локации не осталось целей, ищем следующую подходящую зону
    if #pois == 0 then
        local nextZoneId, questCount = self:GetNextZoneSuggestion(plevel, pclass, prace)
        if nextZoneId and questCount > 0 then
            local nextZoneName = pfMap:GetMapNameByID(nextZoneId) or ("Zone " .. nextZoneId)
            local targetName = "Walk or Use Hearthstone"

            -- Пытаемся найти полетчика в текущей локации для навигации
            local fm = GetClosestFlightMaster(currentZone, pX, pY)
            if fm then
                targetName = "Flight Master: " .. fm.name
            end

            table.insert(pois, {
                x = fm and fm.x or 50,
                y = fm and fm.y or 50,
                zone = fm and currentZone or nextZoneId,
                action = "Accept",
                targetName = targetName,
                questid = 0,
                questTitle = "Proceed to " .. nextZoneName .. " (" .. questCount .. " quests available)",
                isTransition = true,
                fmFound = fm ~= nil
            })
        end
    end

    self.cachedPois = pois
    self.lastPoisUpdate = GetTime()
    return pois
end


-- ============================================================================
-- ИНИЦИАЛИЗАЦИЯ UI И КНОПКИ
-- ============================================================================

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
pfGuideWindow:Hide()

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

pfGuideWindow.title = pfGuideWindow:CreateFontString(nil, "OVERLAY", "GameFontWhite")
pfGuideWindow.title:SetPoint("TOPLEFT", pfGuideWindow, "TOPLEFT", 10, -10)
pfGuideWindow.title:SetText("|cff00ff00[pfGuide]|r Dynamic Route")

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
pfGuideWindow.close:SetScript("OnClick", function() this:GetParent():Hide() end)

pfGuideWindow.emptyLabel = pfGuideWindow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
pfGuideWindow.emptyLabel:SetPoint("CENTER", pfGuideWindow, "CENTER", 0, -20)
pfGuideWindow.emptyLabel:SetText("Нет целей в этой локации.")
pfGuideWindow.emptyLabel:Hide()

pfGuideWindow.scroll = CreateFrame("ScrollFrame", nil, pfGuideWindow)
pfGuideWindow.scroll:SetPoint("TOPLEFT", pfGuideWindow, "TOPLEFT", 8, -35)
pfGuideWindow.scroll:SetPoint("BOTTOMRIGHT", pfGuideWindow, "BOTTOMRIGHT", -8, 8)

pfGuideWindow.list = CreateFrame("Frame", nil, pfGuideWindow.scroll)
pfGuideWindow.list:SetWidth(400)
pfGuideWindow.scroll:SetScrollChild(pfGuideWindow.list)

pfGuideWindow.buttons = {}

local function CreateQuestButton(i)
    local btn = CreateFrame("Button", nil, pfGuideWindow.list)
    btn:SetPoint("TOPLEFT", pfGuideWindow.list, "TOPLEFT", 0, -i * 45)
    btn:SetWidth(400)
    btn:SetHeight(40)

    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints(btn)
    btn.bg:SetTexture(1, 1, 1, (i % 2 == 0) and 0.05 or 0.02)

    btn.name = btn:CreateFontString(nil, "OVERLAY", "GameFontWhite")
    btn.name:SetPoint("TOPLEFT", btn, "TOPLEFT", 10, -5)
    btn.name:SetJustifyH("LEFT")
    btn.name:SetWidth(350)

    btn.info = btn:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    btn.info:SetPoint("TOPLEFT", btn.name, "BOTTOMLEFT", 0, -3)
    btn.info:SetJustifyH("LEFT")
    btn.info:SetText("X: -- Y: -- Dist: -- m")

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function(self, button)
        if button == "RightButton" and self.poi then
            pfQuest_config.guideBlacklist[self.poi.questid] = true
            print("|cff00ff00[pfGuide]|r Квест пропущен: " .. self.poi.questTitle)
            pfGuide:RefreshWindow()
            pfGuide:UpdateArrow()
        end
    end)

    btn:SetScript("OnEnter", function()
        btn.bg:SetTexture(1, 1, 1, 0.2)
        if btn.poi then
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            GameTooltip:SetText(btn.poi.questTitle, 1, 1, 1)
            GameTooltip:AddLine("Правый клик - пропустить квест", 1, 0, 0)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function()
        btn.bg:SetTexture(1, 1, 1, (i % 2 == 0) and 0.05 or 0.02)
        GameTooltip:Hide()
    end)

    return btn
end


-- ============================================================================
-- ВЗАИМОДЕЙСТВИЕ И СОБЫТИЯ
-- ============================================================================

function pfGuide:RefreshWindow()
    local pois = self:GetActivePOIs(true)
    local btnIndex = 1

    -- Показываем не более 20 целей (чтобы не перегружать интерфейс)
    local maxPois = math.min(#pois, 20)

    for i = 1, maxPois do
        local poi = pois[i]
        if not pfGuideWindow.buttons[btnIndex] then
            pfGuideWindow.buttons[btnIndex] = CreateQuestButton(btnIndex)
        end

        local btn = pfGuideWindow.buttons[btnIndex]
        btn.poi = poi

        -- Цветное действие
        local actionText = poi.action
        if actionText == "TurnIn" then actionText = "|cff00ff00[Сдать]|r"
        elseif actionText == "Accept" then actionText = "|cffffff00[Взять]|r"
        else actionText = "|cffff0000[Цель]|r" end

        btn.name:SetText(actionText .. " " .. poi.questTitle)

        -- Вычисляем реальную дистанцию (score может быть искажен приоритетами)
        local pX, pY = GetPlayerMapPosition("player")
        pX, pY = pX * 100, pY * 100
        local dist = math.sqrt((pX - poi.x)^2 + (pY - poi.y)^2)

        btn.info:SetText(string.format("К: %s | Dist: %.1f", poi.targetName, dist))
        btn:Show()

        btnIndex = btnIndex + 1
    end

    if btnIndex == 1 then
        pfGuideWindow.emptyLabel:Show()
    else
        pfGuideWindow.emptyLabel:Hide()
    end

    for i = btnIndex, #pfGuideWindow.buttons do
        pfGuideWindow.buttons[i]:Hide()
    end

    pfGuideWindow.list:SetHeight((btnIndex - 1) * 45 + 10)
end

function pfGuide:UpdateWindowDistances()
    local pX, pY = GetPlayerMapPosition("player")
    pX, pY = pX * 100, pY * 100
    if pX == 0 and pY == 0 then return end

    for _, btn in ipairs(pfGuideWindow.buttons) do
        if btn.poi and btn:IsShown() then
            local dist = math.sqrt((pX - btn.poi.x)^2 + (pY - btn.poi.y)^2)
            btn.info:SetText(string.format("К: %s | Dist: %.1f", btn.poi.targetName, dist))
        end
    end
end

function pfGuide:PointToQuest(poi)
    if not poi or not poi.x or not poi.y then return end

    -- Если это переход в другую локацию и полетчик в текущей зоне не найден,
    -- скрываем стрелку, чтобы не дезориентировать игрока (оставляем только текст в окне)
    if poi.isTransition and not poi.fmFound then
        self.RouteReset(pfQuest.route)
        if pfQuest.route.arrow then
            pfQuest.route.arrow:Hide()
        end
        return
    end

    local node = {
        [1] = poi.x,
        [2] = poi.y,
        [3] = {
            title = poi.targetName or "Unknown",
            texture = pfQuestConfig.path.."\\img\\cluster_mob"
        }
    }

    self.RouteReset(pfQuest.route)
    self.RouteAddPoint(pfQuest.route, node)
    self.RouteSetTarget(pfQuest.route, node[3])

    if pfQuest.route.arrow then
        pfQuest.route.arrow:Show()
    end
end

function pfGuide:UpdateArrow(forceRefresh)
    local pois = self.cachedPois
    if not pois or forceRefresh then
        pois = self:GetActivePOIs(forceRefresh)
    end

    if pois[1] then
        local poiKey = tostring(pois[1].questid) .. "_" .. tostring(pois[1].action) .. "_" .. tostring(pois[1].targetName)
        if poiKey ~= self.activeTargetKey or not (pfQuest.route.arrow and pfQuest.route.arrow:IsShown()) then
            self:PointToQuest(pois[1])
        end
        self.activeTargetKey = poiKey
    else
        self.activeTargetKey = nil
    end
end

-- Слэш команды
SLASH_PFGUIDE1 = "/guide"
SlashCmdList["PFGUIDE"] = function(msg)
    msg = string.lower(msg or "")
    if msg == "reset" then
        pfQuest_config.guideBlacklist = {}
        print("|cff00ff00[pfGuide]|r Черный список квестов очищен.")
        pfGuide:RefreshWindow()
        pfGuide:UpdateArrow()
        return
    end

    if pfGuideWindow:IsShown() then
        pfGuideWindow:Hide()
    else
        pfGuideWindow:Show()
        pfGuide:RefreshWindow()
        pfGuide:UpdateArrow() -- Автоматически вешаем стрелку на Топ-1 цель
    end
end

-- События обновления
pfGuide:RegisterEvent("QUEST_LOG_UPDATE")
pfGuide:RegisterEvent("QUEST_WATCH_UPDATE")
pfGuide:RegisterEvent("BAG_UPDATE") -- важно для квестов на лут
pfGuide:RegisterEvent("ZONE_CHANGED")
pfGuide:RegisterEvent("ZONE_CHANGED_NEW_AREA")
pfGuide:RegisterEvent("MINIMAP_ZONE_CHANGED")
pfGuide:SetScript("OnEvent", function()
    if pfGuideWindow:IsShown() then
        pfGuide.needsFullRefresh = true
        pfGuide.refreshTimer = GetTime() + 0.5
    end
end)

pfGuide:SetScript("OnUpdate", function()
    if pfGuideWindow:IsShown() then
        if this.refreshTimer and GetTime() > this.refreshTimer then
            this.refreshTimer = nil
            if pfGuide.needsFullRefresh then
                pfGuide:RefreshWindow()
                pfGuide.needsFullRefresh = false
            else
                pfGuide:UpdateWindowDistances()
            end
            pfGuide:UpdateArrow()
        elseif not this.refreshTimer then
            -- В фоне обновляем только расстояния и стрелку каждые 2 секунды
            this.refreshTimer = GetTime() + 2
        end
    end
end)
--
--
--
---- ============================================================================
---- SIMULATED DUROTAR MAP WITH FOGCLEAR & PFQUEST PINS (FIXED DEBOUNCE/DELAY)
---- ============================================================================
--
--local DUROTAR_OVERLAYS = {
--    {"drygulchravine", 427, 78, 210, 160},
--    {"echoisles", 549, 427, 200, 240},
--    {"kolkarcrag", 413, 476, 160, 120},
--    {"orgrimmar", 244, 0, 445, 160},
--    {"razorhill", 432, 170, 220, 230},
--    {"razormanegrounds", 301, 189, 230, 230},
--    {"senjinvillage", 474, 384, 160, 190},
--    {"skullrock", 464, 33, 128, 110},
--    {"thunderridge", 327, 60, 190, 200},
--    {"tiragardekeep", 462, 286, 190, 180},
--    {"valleyoftrials", 355, 320, 215, 215},
--}
--
--local DUROTAR_ZONE_ID = 14
--local MAP_SCALE = 0.5 -- 512x384
--
---- 1. Главное окно симулированной карты
--local durotarMap = CreateFrame("Frame", "DurotarMapFrame", UIParent)
--durotarMap:SetSize(1024 * MAP_SCALE, 768 * MAP_SCALE)
--durotarMap:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
--durotarMap:SetFrameStrata("HIGH")
--durotarMap:SetClampedToScreen(true)
--
--durotarMap:EnableMouse(true)
--durotarMap:SetMovable(true)
--durotarMap:RegisterForDrag("LeftButton")
--durotarMap:SetScript("OnDragStart", durotarMap.StartMoving)
--durotarMap:SetScript("OnDragStop", durotarMap.StopMovingOrSizing)
--
--durotarMap:SetBackdrop({
--    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
--    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
--    tile = true, tileSize = 16, edgeSize = 16,
--    insets = { left = 3, right = 3, top = 3, bottom = 3 }
--})
--durotarMap:SetBackdropColor(0, 0, 0, 0.85)
--durotarMap:SetBackdropBorderColor(0.2, 0.8, 1, 1)
--
--durotarMap.title = durotarMap:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
--durotarMap.title:SetPoint("TOPLEFT", durotarMap, "TOPLEFT", 10, 18)
--durotarMap.title:SetText("|cff00ff00[pfQuest]|r Durotar Map (Zone 14)")
--
--durotarMap.closeBtn = CreateFrame("Button", nil, durotarMap)
--durotarMap.closeBtn:SetSize(18, 18)
--durotarMap.closeBtn:SetPoint("TOPRIGHT", durotarMap, "TOPRIGHT", -5, 18)
--durotarMap.closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
--durotarMap.closeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
--durotarMap.closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
--durotarMap.closeBtn:SetScript("OnClick", function() durotarMap:Hide() end)
--
--durotarMap:SetScript("OnMouseDown", function(self, button)
--    if button == "RightButton" then self:Hide() end
--end)
--
---- 2. Базовые плитки фона (BACKGROUND)
--for i = 1, 12 do
--    local col = (i - 1) % 4
--    local row = math.floor((i - 1) / 4)
--    local tile = durotarMap:CreateTexture(nil, "BACKGROUND")
--    tile:SetSize(256 * MAP_SCALE, 256 * MAP_SCALE)
--    tile:SetTexture("Interface\\WorldMap\\Durotar\\Durotar" .. i)
--    tile:SetPoint("TOPLEFT", durotarMap, "TOPLEFT", col * 128, -row * 128)
--end
--
---- 3. Оверлеи субзон (ARTWORK)
--for _, data in ipairs(DUROTAR_OVERLAYS) do
--    local name, oX, oY, w, h = data[1], data[2], data[3], data[4], data[5]
--    local numWide = math.ceil(w / 256)
--    local numTall = math.ceil(h / 256)
--    local texCount = 1
--
--    for j = 1, numTall do
--        local tileH = (j < numTall) and 256 or (h % 256 == 0 and 256 or h % 256)
--        local fileH = 16
--        while fileH < tileH do fileH = fileH * 2 end
--
--        for k = 1, numWide do
--            local tileW = (k < numWide) and 256 or (w % 256 == 0 and 256 or w % 256)
--            local fileW = 16
--            while fileW < tileW do fileW = fileW * 2 end
--
--            local overlay = durotarMap:CreateTexture(nil, "ARTWORK")
--            overlay:SetSize(tileW * MAP_SCALE, tileH * MAP_SCALE)
--            overlay:SetTexCoord(0, tileW / fileW, 0, tileH / fileH)
--            overlay:SetPoint("TOPLEFT", durotarMap, "TOPLEFT", (oX + 256 * (k - 1)) * MAP_SCALE, -(oY + 256 * (j - 1)) * MAP_SCALE)
--            overlay:SetTexture("Interface\\WorldMap\\Durotar\\" .. name .. texCount)
--
--            texCount = texCount + 1
--        end
--    end
--end
--
---- 4. Контейнер для пинов (высокий FrameLevel для кликабельности)
--durotarMap.nodeLayer = CreateFrame("Frame", nil, durotarMap)
--durotarMap.nodeLayer:SetAllPoints(durotarMap)
--durotarMap.nodeLayer:SetFrameLevel(durotarMap:GetFrameLevel() + 10)
--
--durotarMap.pins = {}
--
---- 5. Метод принудительного заполнения данных pfQuest, если база пустая
--function durotarMap:EnsureNodesPopulated()
--    if not pfMap or not pfDatabase then return end
--
--    -- Если нодов для зоны 14 еще нет в памяти, принудительно запрашиваем их у pfQuest
--    local hasNodes = pfMap.nodes and pfMap.nodes["PFQUEST"] and pfMap.nodes["PFQUEST"][DUROTAR_ZONE_ID] and next(pfMap.nodes["PFQUEST"][DUROTAR_ZONE_ID])
--    if not hasNodes then
--        local meta = { ["addon"] = "PFQUEST" }
--        -- Ищем доступные квесты
--        pfDatabase:SearchQuests(meta)
--
--        -- Ищем активные цели квестов из журнала
--        if pfQuest and pfQuest.questlog then
--            for qid, qData in pairs(pfQuest.questlog) do
--                local qmeta = { ["addon"] = "PFQUEST", ["qlogid"] = qData.qlogid }
--                pfDatabase:SearchQuestID(qid, qmeta)
--            end
--        end
--    end
--end
--
---- 6. Отрисовка пинов
--function durotarMap:UpdatePfQuestPins()
--    for _, pin in ipairs(self.pins) do
--        pin:Hide()
--    end
--
--    if not pfMap or not pfMap.nodes then return end
--
--    local pinIndex = 1
--    local frameW = self:GetWidth()
--    local frameH = self:GetHeight()
--
--    local addons = { "PFQUEST", "PFDB" }
--
--    for _, addonName in ipairs(addons) do
--        if pfMap.nodes[addonName] and pfMap.nodes[addonName][DUROTAR_ZONE_ID] then
--            for coordsKey, nodeGroup in pairs(pfMap.nodes[addonName][DUROTAR_ZONE_ID]) do
--                local _, _, strX, strY = string.find(coordsKey, "(.*)|(.*)")
--                local x = tonumber(strX)
--                local y = tonumber(strY)
--
--                if x and y then
--                    local pin = self.pins[pinIndex]
--                    if not pin then
--                        pin = pfMap:BuildNode("pfDurotarCustomPin" .. pinIndex, self.nodeLayer)
--                        self.pins[pinIndex] = pin
--                    end
--
--                    pfMap:UpdateNode(pin, nodeGroup, "title", "worldmap")
--
--                    local posX = (x / 100) * frameW
--                    local posY = (y / 100) * frameH
--
--                    pin:ClearAllPoints()
--                    pin:SetPoint("CENTER", self.nodeLayer, "TOPLEFT", posX, -posY)
--                    pin:Show()
--
--                    pinIndex = pinIndex + 1
--                end
--            end
--        end
--    end
--end
--
---- 7. Таймер задержки для компенсации debounce задержек pfQuest
--local delayTimer = CreateFrame("Frame")
--delayTimer:Hide()
--
--function durotarMap:ScheduleDeferredUpdate(delay)
--    delayTimer.elapsed = 0
--    delayTimer.delay = delay or 0.3
--    delayTimer:SetScript("OnUpdate", function(self, elapsed)
--        self.elapsed = self.elapsed + elapsed
--        if self.elapsed >= self.delay then
--            self:Hide()
--            if durotarMap:IsShown() then
--                durotarMap:EnsureNodesPopulated()
--                durotarMap:UpdatePfQuestPins()
--            end
--        end
--    end)
--    delayTimer:Show()
--end
--
---- 8. События и Хуки
--durotarMap:SetScript("OnShow", function(self)
--    -- Мгновенное обновление + запуск поиска если нужно
--    self:EnsureNodesPopulated()
--    self:UpdatePfQuestPins()
--
--    -- Отложенное повторное обновление через 300 мс (снимет проблему первого открытия)
--    self:ScheduleDeferredUpdate(0.3)
--end)
--
---- ХУК: Когда pfMap пересчитывает ноды карты мира, мы автоматически обновляем карту Дуротара
--if pfMap and pfMap.UpdateNodes then
--    hooksecurefunc(pfMap, "UpdateNodes", function()
--        if durotarMap:IsShown() then
--            durotarMap:UpdatePfQuestPins()
--        end
--    end)
--end
--
---- 9. Слэш-команда
--SLASH_PFDUROTARMAP1 = "/durotar"
--SlashCmdList["PFDUROTARMAP"] = function()
--    if durotarMap:IsShown() then
--        durotarMap:Hide()
--    else
--        durotarMap:Show()
--    end
--end
--
---- Показать окно
--durotarMap:Show()

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
    local score = math.sqrt((playerX - poi.x)^2 + (playerY - poi.y)^2)
    -- Бонусы за приоритет действий (вычитаем из дистанции)
    if poi.action == "TurnIn" then
        score = score - 30
    elseif poi.action == "Accept" then
        score = score - 15
    end
    return score
end

function pfGuide:GetActivePOIs()
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

    local function addBestPOI(poi)
        if poi.zone ~= currentZone then return end
        poi.score = self:ScorePOI(poi, pX, pY)
        local key = tostring(poi.questid) .. "_" .. tostring(poi.action) .. "_" .. tostring(poi.targetName)

        local existing = bestPois[key]
        if not existing or poi.score < existing.score then
            bestPois[key] = poi
        end
    end

    for questid, data in pairs(pfQuest.questlog) do
        local state = self:GetQuestState(questid)
        if state ~= self.STATE.UNAVAILABLE then
            local questPOIs = self:GetQuestPOIs(questid, state)
            for _, poi in ipairs(questPOIs) do
                poi.questid = questid
                poi.state = state
                poi.questTitle = data.title
                addBestPOI(poi)
            end
        end
    end

    for questid in pairs(pfDB.quests.data) do
        if not pfQuest.questlog[questid] and pfDatabase:QuestFilter(questid, plevel, pclass, prace) then
            local questPOIs = self:GetQuestPOIs(questid, self.STATE.AVAILABLE)
            if next(questPOIs) then
                local quest = pfDB.quests.data[questid]
                local title = quest.title or "Unknown"
                for _, poi in ipairs(questPOIs) do
                    poi.questid = questid
                    poi.state = self.STATE.AVAILABLE
                    poi.questTitle = title
                    addBestPOI(poi)
                end
            end
        end
    end

    local pois = {}
    for _, poi in pairs(bestPois) do
        table.insert(pois, poi)
    end

    table.sort(pois, function(a, b)
        return a.score < b.score
    end)

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

    btn.track = CreateFrame("Button", nil, btn)
    btn.track:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -8, -8)
    btn.track:SetWidth(70)
    btn.track:SetHeight(25)
    btn.track:SetText("Track")
    btn.track.bg = btn.track:CreateTexture(nil, "BACKGROUND")
    btn.track.bg:SetAllPoints(btn.track)
    btn.track.bg:SetTexture(0.2, 0.6, 0.2, 0.6)

    btn.track:SetScript("OnClick", function()
        if btn.poi then
            pfGuide:PointToQuest(btn.poi)
        end
    end)

    btn:SetScript("OnEnter", function() btn.bg:SetTexture(1, 1, 1, 0.2) end)
    btn:SetScript("OnLeave", function() btn.bg:SetTexture(1, 1, 1, (i % 2 == 0) and 0.05 or 0.02) end)

    return btn
end


-- ============================================================================
-- ВЗАИМОДЕЙСТВИЕ И СОБЫТИЯ
-- ============================================================================

function pfGuide:RefreshWindow()
    local pois = self:GetActivePOIs()
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

        btn.info:SetText(string.format("К: %s | X: %.1f Y: %.1f | Dist: %.1f", poi.targetName, poi.x, poi.y, dist))
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

function pfGuide:PointToQuest(poi)
    if not poi or not poi.x or not poi.y then return end

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

function pfGuide:UpdateArrow()
    local pois = self:GetActivePOIs()
    if pois[1] then
        self:PointToQuest(pois[1])
    end
end

-- Слэш команды
SLASH_PFGUIDE1 = "/guide"
SlashCmdList["PFGUIDE"] = function(msg)
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
pfGuide:SetScript("OnEvent", function()
    if pfGuideWindow:IsShown() then
        pfGuide.timer = GetTime() + 0.5
    end
end)

pfGuide:SetScript("OnUpdate", function()
    if pfGuideWindow:IsShown() then
        if this.timer and GetTime() > this.timer then
            this.timer = nil
            pfGuide:RefreshWindow()
            pfGuide:UpdateArrow() -- Обновляем стрелку, если что-то сдали/выполнили
        elseif not this.timer then
            -- Тик обновления дистанции раз в 2 секунды
            this.timer = GetTime() + 2
        end
    end
end)
pfGuide = CreateFrame("Frame", "pfGuideFrame", UIParent)

-- Простая команда для теста
SLASH_PFGUIDE1 = "/guide"
SlashCmdList["PFGUIDE"] = function(msg)
    pfGuide:TestCurrentQuests()
end

function pfGuide:TestCurrentQuests()
    print("|cff00ff00[pfGuide]|r Анализ текущих квестов:")
    
    -- pfQuest.questlog уже хранит состояние твоего журнала!
    local activeQuests = 0
    for questid, data in pairs(pfQuest.questlog) do
        local qtitle = data.title
        local state = data.state -- строка вроде "track1todo2done"
        
        -- Если стейт содержит "todo", значит квест не завершен
        if string.find(state or "", "todo") then
            print(" - Нужно сделать: " .. qtitle .. " (ID: " .. questid .. ")")
            activeQuests = activeQuests + 1
        end
    end
    
    if activeQuests == 0 then
        print("Нет активных незавершенных квестов.")
    end
end

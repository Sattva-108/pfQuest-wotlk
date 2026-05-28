-- pfQuest Diagnostic Function
-- Add this to pfQuest addon or run as standalone script

function pfQuestDiagnostic()
    local report = {}

    -- Header
    print("=== pfQuest Diagnostic Report ===")
    print(string.format("Date: %s", date()))
    print("")

    -- 1. Check if pfDB exists
    if not pfDB then
        print("❌ CRITICAL: pfDB global table not found!")
        print("   - pfQuest addon not loaded or failed to initialize")
        return
    else
        print("✅ pfDB global table found")
    end

    -- 2. Check main database categories
    local categories = {"quests", "units", "objects", "items", "zones", "areatrigger"}
    local stats = {}

    print("")
    print("📊 DATABASE STATISTICS:")
    print("=======================")

    for _, cat in ipairs(categories) do
        if pfDB[cat] then
            -- Count data entries
            local dataCount = 0
            if pfDB[cat]["data"] then
                for _ in pairs(pfDB[cat]["data"]) do
                    dataCount = dataCount + 1
                end
            end

            -- Count locale entries
            local localeCount = 0
            if pfDB[cat]["loc"] then
                for _ in pairs(pfDB[cat]["loc"]) do
                    localeCount = localeCount + 1
                end
            end

            stats[cat] = {data = dataCount, locale = localeCount}

            if dataCount > 0 then
                print(string.format("✅ %-12s: %5d data, %5d locale", cat, dataCount, localeCount))
            else
                print(string.format("⚠️  %-12s: %5d data, %5d locale", cat, dataCount, localeCount))
            end
        else
            print(string.format("❌ %-12s: missing", cat))
        end
    end

    -- 3. Check localization
    print("")
    print("🌍 LOCALIZATION CHECK:")
    print("======================")

    local locale = GetLocale()
    print("Current locale: " .. locale)

    if pfDB.locales then
        print("Available locales:")
        for loc, name in pairs(pfDB.locales) do
            print("  " .. loc .. ": " .. name)
        end
    end

    -- Check if quest locales are properly loaded
    if pfDB["quests"] and pfDB["quests"]["loc"] then
        local locCount = 0
        for _ in pairs(pfDB["quests"]["loc"]) do locCount = locCount + 1 end
        if locCount > 0 then
            print("✅ Quest locales loaded: " .. locCount .. " entries")
        else
            print("❌ Quest locales empty!")
        end
    else
        print("❌ Quest locales not found!")
    end

    -- 4. Sample data validation
    print("")
    print("🔍 DATA VALIDATION:")
    print("===================")

    -- Check some quest samples
    if stats.quests and stats.quests.data > 0 then
        local questSamples = 0
        local validQuests = 0
        local invalidLevels = 0

        for id, quest in pairs(pfDB["quests"]["data"]) do
            questSamples = questSamples + 1
            if questSamples > 100 then break end -- Sample first 100

            if quest.lvl and quest.min then
                if tonumber(quest.lvl) and tonumber(quest.min) then
                    validQuests = validQuests + 1
                    if tonumber(quest.lvl) < 0 then
                        invalidLevels = invalidLevels + 1
                    end
                end
            end
        end

        print(string.format("Quest samples checked: %d", questSamples))
        print(string.format("Valid quest structure: %d/%d", validQuests, questSamples))
        if invalidLevels > 0 then
            print(string.format("⚠️  Quests with level < 0: %d", invalidLevels))
        end
    end

    -- 5. Memory usage check
    print("")
    print("💾 MEMORY USAGE:")
    print("================")

    local memBefore = collectgarbage("count")
    collectgarbage("collect")
    local memAfter = collectgarbage("count")

    print(string.format("Lua memory usage: %.2f MB", memAfter / 1024))
    print(string.format("Garbage collected: %.2f KB", memBefore - memAfter))

    -- 6. Functionality test
    print("")
    print("🧪 FUNCTIONALITY TEST:")
    print("======================")

    -- Test database access
    local testsPassed = 0
    local totalTests = 0

    -- Test 1: Can access quest data
    totalTests = totalTests + 1
    if pfDB["quests"] and pfDB["quests"]["data"] then
        local firstQuest = next(pfDB["quests"]["data"])
        if firstQuest then
            print("✅ Quest data access: PASS")
            testsPassed = testsPassed + 1
        else
            print("❌ Quest data access: FAIL (no quests)")
        end
    else
        print("❌ Quest data access: FAIL (no data table)")
    end

    -- Test 2: Can access locale data
    totalTests = totalTests + 1
    if pfDB["quests"] and pfDB["quests"]["loc"] then
        local firstLocale = next(pfDB["quests"]["loc"])
        if firstLocale then
            print("✅ Locale data access: PASS")
            testsPassed = testsPassed + 1
        else
            print("❌ Locale data access: FAIL (no locales)")
        end
    else
        print("❌ Locale data access: FAIL (no locale table)")
    end

    -- Test 3: pfDatabase string exists
    totalTests = totalTests + 1
    if pfDatabase and pfDatabase.dbstring then
        print("✅ Database string: PASS")
        print("   " .. pfDatabase.dbstring)
        testsPassed = testsPassed + 1
    else
        print("❌ Database string: FAIL")
    end

    -- 7. Final summary
    print("")
    print("📋 SUMMARY:")
    print("===========")
    print(string.format("Tests passed: %d/%d", testsPassed, totalTests))

    if stats.quests then
        print(string.format("Total quests loaded: %d", stats.quests.data))
    end

    if testsPassed == totalTests and stats.quests and stats.quests.data > 0 then
        print("🎉 pfQuest appears to be working correctly!")
        print("")
        print("🚀 RECOMMENDED NEXT STEPS:")
        print("- Open world map (M) to see quest markers")
        print("- Try quest search: /run pfBrowser:Show()")
        print("- Check quest tracker for coordinates")
    else
        print("⚠️  pfQuest has issues that need to be resolved.")
        print("")
        print("🔧 TROUBLESHOOTING:")
        if not stats.quests or stats.quests.data == 0 then
            print("- Re-run extraction with FAST_MODE = true")
            print("- Check that files were copied to db/ folder")
            print("- Restart WoW client to reload addon")
        end
    end

    print("")
    print("=== End of Diagnostic Report ===")
end

-- Auto-run if called directly
if pfDB then
    pfQuestDiagnostic()
else
    print("Run this function in-game after pfQuest loads: /run pfQuestDiagnostic()")
end

#!/usr/bin/lua

-- Script to load DBC CSV files into acore_world database (matching load-client-data.sh)
luasql = require("luasql.mysql")

local env = luasql.mysql()
mysql = env:connect("acore_world", "acore", "acore", "127.0.0.1", 3306)

mysql:execute("SET NAMES utf8")
mysql:execute("SET CHARACTER SET utf8")

if not mysql then
  print("ERROR: Failed to connect to database")
  return
end

print("Loading DBC data into acore_world database...")

-- Function to parse CSV line properly
function parse_csv_line(line)
  local values = {}
  local i = 1
  local start = 1
  local in_quotes = false

  while i <= #line do
    local char = line:sub(i, i)

    if char == '"' then
      in_quotes = not in_quotes
    elseif char == ',' and not in_quotes then
      local value = line:sub(start, i-1)
      -- Remove quotes but keep original for numbers
      value = value:gsub('^"', ''):gsub('"$', '')
      table.insert(values, value)
      start = i + 1
    end

    i = i + 1
  end

  -- Add the last value
  local value = line:sub(start)
  value = value:gsub('^"', ''):gsub('"$', '')
  table.insert(values, value)

  return values
end

-- Function to read CSV file and create table
function load_dbc_csv(filename, table_name, create_sql, custom_insert)
    print("Processing: " .. filename)

    if create_sql then
        -- Drop table if exists
        mysql:execute("DROP TABLE IF EXISTS `" .. table_name .. "`")

        -- Create table
        local result = mysql:execute(create_sql)
        if not result then
            print("ERROR: Failed to create table " .. table_name)
            return false
        end
    end

    -- Read CSV file
    local file = io.open(filename, "r")
    if not file then
        print("ERROR: Cannot open file " .. filename)
        return false
    end

    -- Skip header line
    local header = file:read("*line")
    print("  Header: " .. header)

    local count = 0
    for line in file:lines() do
        if line and line ~= "" then
            local values = parse_csv_line(line)

            if #values > 0 then
                local sql = custom_insert(values)
                if sql then
                    local result = mysql:execute(sql)
                    if result then
                        count = count + 1
                    else
                        print("  ERROR inserting row: " .. line)
                    end
                end
            end
        end
    end

    file:close()
    print("  SUCCESS: Loaded " .. count .. " rows into " .. table_name)
    return true
end

-- Check if file exists
function file_exists(name)
  local f = io.open(name, "r")
  if f ~= nil then
    io.close(f)
    return true
  else
    return false
  end
end

local version = "wotlk"

-- AreaTrigger_wotlk (matching load-client-data.sh structure)
load_dbc_csv("DBC/wotlk/AreaTrigger.dbc.csv", "AreaTrigger_" .. version,
  "CREATE TABLE `AreaTrigger_" .. version .. "` (" ..
  "`ID` smallint(3) unsigned NOT NULL," ..
  "`MapID` smallint(3) unsigned NOT NULL," ..
  "`X` float NOT NULL DEFAULT 0.0," ..
  "`Y` float NOT NULL DEFAULT 0.0," ..
  "`Z` float NOT NULL DEFAULT 0.0," ..
  "`Size` float NOT NULL DEFAULT 0.0" ..
  ") ENGINE=MyISAM DEFAULT CHARSET=utf8 ROW_FORMAT=FIXED COMMENT='AreaTrigger'",
  function(values)
    local id = values[1]
    local map = values[2]
    local x = values[3]:gsub(',', '.')
    local y = values[4]:gsub(',', '.')
    local z = values[5]:gsub(',', '.')
    local size = values[6]:gsub(',', '.')
    return "INSERT INTO `AreaTrigger_" .. version .. "` VALUES (" .. id .. ", " .. map .. ", " .. x .. ", " .. y .. ", " .. z .. ", " .. size .. ")"
  end)

-- DungeonMap_wotlk (needed for boundary fallback mechanism)
load_dbc_csv("DBC/wotlk/DungeonMap.dbc.csv", "DungeonMap_" .. version,
  "CREATE TABLE `DungeonMap_" .. version .. "` (" ..
  "`ID` smallint(3) unsigned NOT NULL," ..
  "`MapID` smallint(3) unsigned NOT NULL," ..
  "`FloorIndex` smallint(3) unsigned NOT NULL," ..
  "`MinX` float NOT NULL DEFAULT 0.0," ..
  "`MaxX` float NOT NULL DEFAULT 0.0," ..
  "`MinY` float NOT NULL DEFAULT 0.0," ..
  "`MaxY` float NOT NULL DEFAULT 0.0," ..
  "`ParentWorldMapID` smallint(3) unsigned NOT NULL," ..
  "PRIMARY KEY (`ID`)" ..
  ") ENGINE=MyISAM DEFAULT CHARSET=utf8 ROW_FORMAT=FIXED COMMENT='DungeonMap'",
  function(values)
    local id = values[1]
    local mapID = values[2]
    local floorIndex = values[3]
    local minX = values[4]:gsub(',', '.')
    local maxX = values[5]:gsub(',', '.')
    local minY = values[6]:gsub(',', '.')
    local maxY = values[7]:gsub(',', '.')
    local parentWorldMapID = values[8]
    return "INSERT INTO `DungeonMap_" .. version .. "` VALUES (" .. id .. ", " .. mapID .. ", " .. floorIndex .. ", " .. minX .. ", " .. maxX .. ", " .. minY .. ", " .. maxY .. ", " .. parentWorldMapID .. ")"
  end)

-- WorldMapArea_wotlk (matching load-client-data.sh structure)
load_dbc_csv("DBC/wotlk/WorldMapArea.dbc.csv", "WorldMapArea_" .. version,
  "CREATE TABLE `WorldMapArea_" .. version .. "` (" ..
  "`zoneID` smallint(3) unsigned NOT NULL," ..
  "`mapID` smallint(3) unsigned NOT NULL," ..
  "`areatableID` smallint(3) unsigned NOT NULL," ..
  "`name` varchar(255) NOT NULL," ..
  "`x_min` float NOT NULL DEFAULT 0.0," ..
  "`y_min` float NOT NULL DEFAULT 0.0," ..
  "`x_max` float NOT NULL DEFAULT 0.0," ..
  "`y_max` float NOT NULL DEFAULT 0.0" ..
  ") ENGINE=MyISAM DEFAULT CHARSET=utf8 ROW_FORMAT=FIXED COMMENT='WorldMapArea'",
  function(values)
    local zone = values[1]
    local map = values[2]
    local area = values[3]
    local name = "\"" .. (values[4] or "") .. "\""

    -- Convert coordinates safely
    local loc_left_str = (values[5] or "0"):gsub(',', '.')
    local loc_right_str = (values[6] or "0"):gsub(',', '.')
    local loc_top_str = (values[7] or "0"):gsub(',', '.')
    local loc_bottom_str = (values[8] or "0"):gsub(',', '.')

    local loc_left = tonumber(loc_left_str) or 0
    local loc_right = tonumber(loc_right_str) or 0
    local loc_top = tonumber(loc_top_str) or 0
    local loc_bottom = tonumber(loc_bottom_str) or 0

    local x_min = math.min(loc_left, loc_right)
    local x_max = math.max(loc_left, loc_right)
    local y_min = math.min(loc_top, loc_bottom)
    local y_max = math.max(loc_top, loc_bottom)

    return "INSERT INTO `WorldMapArea_" .. version .. "` VALUES (" .. zone .. ", " .. map .. ", " .. area .. ", " .. name .. ", " .. x_min .. ", " .. y_min .. ", " .. x_max .. ", " .. y_max .. ")"
  end)

-- FactionTemplate_wotlk (matching load-client-data.sh logic)
load_dbc_csv("DBC/wotlk/FactionTemplate.dbc.csv", "FactionTemplate_" .. version,
  "CREATE TABLE `FactionTemplate_" .. version .. "` (" ..
  "`factiontemplateID` smallint(3) unsigned NOT NULL," ..
  "`factionID` smallint(3) unsigned NOT NULL," ..
  "`A` smallint(1) NOT NULL," ..
  "`H` smallint(1) NOT NULL" ..
  ") ENGINE=MyISAM DEFAULT CHARSET=utf8 ROW_FORMAT=FIXED COMMENT='FactionTemplate'",
  function(values)
    local factiontemplate = values[1]
    local faction = values[2]
    local friendly = tonumber(values[5]) or 0
    local hostile = tonumber(values[6]) or 0

    local alliance = 0
    local horde = 0

    -- Horde logic (bit 2 = 4)
    if (hostile % 8 >= 4) or hostile == 1 then
      horde = -1
    elseif (friendly % 8 >= 4) or friendly == 1 then
      horde = 1
    end

    -- Alliance logic (bit 1 = 2)
    if (hostile % 4 >= 2) or hostile == 1 then
      alliance = -1
    elseif (friendly % 4 >= 2) or friendly == 1 then
      alliance = 1
    end

    return "INSERT INTO `FactionTemplate_" .. version .. "` VALUES (" .. factiontemplate .. ", " .. faction .. ", " .. alliance .. ", " .. horde .. ")"
  end)

-- Lock_wotlk (matching load-client-data.sh structure)
load_dbc_csv("DBC/wotlk/Lock.dbc.csv", "Lock_" .. version,
  "CREATE TABLE `Lock_" .. version .. "` (" ..
  "`id` smallint(3) unsigned NOT NULL," ..
  "`locktype` smallint(3) NOT NULL," ..
  "`data` smallint(3) unsigned NOT NULL," ..
  "`skill` smallint(3) unsigned NOT NULL" ..
  ") ENGINE=MyISAM DEFAULT CHARSET=utf8 ROW_FORMAT=FIXED COMMENT='Lock'",
  function(values)
    local id = values[1]
    local locktype = values[2]
    -- Extract hex part after 'x' if present
    if locktype:find("x") then
      locktype = locktype:sub(locktype:find("x") + 1)
    end
    local data = values[10] or "0"
    local skill = values[18] or "0"

    -- Special case for chest (hackfix from original script)
    if id == "57" then
      return "INSERT INTO `Lock_" .. version .. "` VALUES (57, 2, 1, 0)"
    else
      return "INSERT INTO `Lock_" .. version .. "` VALUES (" .. id .. ", " .. locktype .. ", " .. data .. ", " .. skill .. ")"
    end
  end)

-- AreaTable_wotlk (CORRECTED schema and parsing)
load_dbc_csv("DBC/wotlk/enUS/AreaTable.dbc.csv", "AreaTable_" .. version,
  "CREATE TABLE `AreaTable_" .. version .. "` (" ..
  "`id` int(3) unsigned NOT NULL," ..
  "`continentID` smallint(3) unsigned NOT NULL," ..
  "`parentAreaID` smallint(3) unsigned NOT NULL," ..
  "`flags` int(10) unsigned NOT NULL," ..
  "`name_loc0` varchar(255) NOT NULL," ..
  "`name_loc1` varchar(255) NOT NULL," ..
  "`name_loc2` varchar(255) NOT NULL," ..
  "`name_loc3` varchar(255) NOT NULL," ..
  "`name_loc4` varchar(255) NOT NULL," ..
  "`name_loc5` varchar(255) NOT NULL," ..
  "`name_loc6` varchar(255) NOT NULL," ..
  "`name_loc7` varchar(255) NOT NULL," ..
  "`name_loc8` varchar(255) NOT NULL," ..
  "`name_loc10` varchar(255) NOT NULL," ..
  "PRIMARY KEY (`id`)" ..
  ") ENGINE=MyISAM DEFAULT CHARSET=utf8 ROW_FORMAT=FIXED COMMENT='AreaTable'",
  function(values)
    local id = values[1]
    local continentID = values[2] or "0"     -- ContinentID
    local parentAreaID = values[3] or "0"    -- ParentAreaID
    local flags = values[5] or "0"           -- Flags
    local name = values[12] or ""            -- AreaName_Lang_enUS

    -- Handle quotes in name
    name = name:gsub('""', '\\"')
    if name ~= "" and name ~= '""' then
      name = '"' .. name:gsub('"', '') .. '"'
    else
      name = '""'
    end

    return "INSERT INTO `AreaTable_" .. version .. "` VALUES (" .. id .. ", " .. continentID .. ", " .. parentAreaID .. ", " .. flags .. ", " .. name .. ", '', '', '', '', '', '', '', '', '')"
  end)

-- AreaTable_wotlk (ruRU) - UPDATE existing rows, write into name_loc8
load_dbc_csv("DBC/wotlk/ruRU/AreaTable.dbc.csv", "AreaTable_" .. version,
    nil,  -- no CREATE, table already exists
    function(values)
        local id = values[1]
        local name = values[20] or ""

        -- strip surrounding CSV quotes
        name = name:gsub('^"', ''):gsub('"$', '')
        -- convert escaped double-quotes "" to single quote for display
        name = name:gsub('""', '"')
        -- escape single quotes for MySQL
        name = name:gsub("'", "\\'")

        return "UPDATE `AreaTable_" .. version .. "` SET `name_loc8` = '" .. name .. "' WHERE `id` = " .. id
    end)

-- SkillLine_wotlk (only enUS for now, matching load-client-data.sh)
load_dbc_csv("DBC/wotlk/enUS/SkillLine.dbc.csv", "SkillLine_" .. version,
  "CREATE TABLE `SkillLine_" .. version .. "` (" ..
  "`id` smallint(3) unsigned NOT NULL," ..
  "`name_loc0` varchar(255) NOT NULL," ..
  "`name_loc1` varchar(255) NOT NULL," ..
  "`name_loc2` varchar(255) NOT NULL," ..
  "`name_loc3` varchar(255) NOT NULL," ..
  "`name_loc4` varchar(255) NOT NULL," ..
  "`name_loc5` varchar(255) NOT NULL," ..
  "`name_loc6` varchar(255) NOT NULL," ..
  "`name_loc7` varchar(255) NOT NULL," ..
  "`name_loc8` varchar(255) NOT NULL," ..
  "`name_loc10` varchar(255) NOT NULL" ..
  ") ENGINE=MyISAM DEFAULT CHARSET=utf8 ROW_FORMAT=FIXED COMMENT='SkillLine'",
  function(values)
    local id = values[1]
    local name = values[4] or "" -- enUS is at position 4
    if name ~= "" and name ~= '""' then
      name = '"' .. name:gsub('"', '') .. '"'
    else
      name = '""'
    end
    return "INSERT INTO `SkillLine_" .. version .. "` VALUES (" .. id .. ", " .. name .. ", '', '', '', '', '', '', '', '', '')"
  end)

-- SkillLine_wotlk (ruRU) - UPDATE existing rows, write into name_loc8
load_dbc_csv("DBC/wotlk/ruRU/SkillLine.dbc.csv", "SkillLine_" .. version,
    nil,  -- no CREATE, table already exists
    function(values)
        local id = values[1]
        local name = values[12] or ""

        -- strip surrounding CSV quotes
        name = name:gsub('^"', ''):gsub('"$', '')
        -- convert escaped double-quotes "" to single quote for display
        name = name:gsub('""', '"')
        -- escape single quotes for MySQL
        name = name:gsub("'", "\\'")

        return "UPDATE `SkillLine_" .. version .. "` SET `name_loc8` = '" .. name .. "' WHERE `id` = " .. id
    end)

-- WorldMapOverlay_wotlk (if file exists)
if file_exists("DBC/wotlk/WorldMapOverlay.dbc.csv") then
  load_dbc_csv("DBC/wotlk/WorldMapOverlay.dbc.csv", "WorldMapOverlay_" .. version,
    "CREATE TABLE `WorldMapOverlay_" .. version .. "` (" ..
    "`areaID` smallint(3) unsigned NOT NULL," ..
    "`zoneID` smallint(3) unsigned NOT NULL," ..
    "`texture` varchar(255)," ..
    "`textureWidth` smallint(3) unsigned NOT NULL," ..
    "`textureHeight` smallint(3) unsigned NOT NULL," ..
    "`offsetX` smallint(3) unsigned NOT NULL," ..
    "`offsetY` smallint(3) unsigned NOT NULL," ..
    "`hitRectTop` smallint(3) unsigned NOT NULL," ..
    "`hitRectLeft` smallint(3) unsigned NOT NULL," ..
    "`hitRectBottom` smallint(3) unsigned NOT NULL," ..
    "`hitRectRight` smallint(3) unsigned NOT NULL" ..
    ") ENGINE=MyISAM DEFAULT CHARSET=utf8 ROW_FORMAT=FIXED COMMENT='WorldMapOverlay'",
    function(values)
      local areaID = values[3] or "0"
      local zoneID = values[2] or "0"
      local texture = '"' .. (values[9] or "") .. '"'
      local textureWidth = values[10] or "0"
      local textureHeight = values[11] or "0"
      local offsetX = values[12] or "0"
      local offsetY = values[13] or "0"
      local top = values[14] or "0"
      local left = values[15] or "0"
      local bottom = values[16] or "0"
      local right = values[17] or "0"

      return "INSERT INTO `WorldMapOverlay_" .. version .. "` VALUES (" .. areaID .. ", " .. zoneID .. ", " .. texture .. ", " .. textureWidth .. ", " .. textureHeight .. ", " .. offsetX .. ", " .. offsetY .. ", " .. top .. ", " .. left .. ", " .. bottom .. ", " .. right .. ")"
    end)
end

-- Spell_dbc_full (for itemreq extraction)
if file_exists("DBC/wotlk/Spell.dbc.csv") then
  load_dbc_csv("DBC/wotlk/Spell.dbc.csv", "spell_dbc_full",
    "CREATE TABLE `spell_dbc_full` (" ..
    "`ID` int(10) unsigned NOT NULL," ..
    "`RequiresSpellFocus` int(10) unsigned NOT NULL DEFAULT 0," ..
    "`Name_Lang_enUS` varchar(255) NOT NULL DEFAULT ''," ..
    "PRIMARY KEY (`ID`)" ..
    ") ENGINE=MyISAM DEFAULT CHARSET=utf8 ROW_FORMAT=FIXED COMMENT='Spell DBC Full'",
    function(values)
      local id = values[1] or "0"
      local requiresSpellFocus = values[17] or "0"  -- RequiresSpellFocus field position
      local name = values[136] or ""  -- SpellName_Lang_enUS field position

      -- Handle quotes in name
      name = name:gsub('""', '\\"')
      if name ~= "" and name ~= '""' then
        name = '"' .. name:gsub('"', '') .. '"'
      else
        name = '""'
      end

      return "INSERT INTO `spell_dbc_full` VALUES (" .. id .. ", " .. requiresSpellFocus .. ", " .. name .. ")"
    end)
  print("SUCCESS: spell_dbc_full table created with full Spell.dbc data")
else
  print("WARNING: DBC/wotlk/Spell.dbc.csv not found - skipping spell_dbc_full creation")
  print("Place Spell.dbc.csv in DBC/wotlk/ folder to enable enhanced itemreq extraction")
end

-- QuestXP_wotlk (needed for quest experience calculation)
if file_exists("DBC/wotlk/QuestXP.dbc.csv") then
  load_dbc_csv("DBC/wotlk/QuestXP.dbc.csv", "questxp_dbc",
    "CREATE TABLE `questxp_dbc` (" ..
    "`ID` smallint(3) unsigned NOT NULL," ..
    "`Difficulty_1` int(10) unsigned NOT NULL DEFAULT 0," ..
    "`Difficulty_2` int(10) unsigned NOT NULL DEFAULT 0," ..
    "`Difficulty_3` int(10) unsigned NOT NULL DEFAULT 0," ..
    "`Difficulty_4` int(10) unsigned NOT NULL DEFAULT 0," ..
    "`Difficulty_5` int(10) unsigned NOT NULL DEFAULT 0," ..
    "`Difficulty_6` int(10) unsigned NOT NULL DEFAULT 0," ..
    "`Difficulty_7` int(10) unsigned NOT NULL DEFAULT 0," ..
    "`Difficulty_8` int(10) unsigned NOT NULL DEFAULT 0," ..
    "`Difficulty_9` int(10) unsigned NOT NULL DEFAULT 0," ..
    "`Difficulty_10` int(10) unsigned NOT NULL DEFAULT 0," ..
    "PRIMARY KEY (`ID`)" ..
    ") ENGINE=MyISAM DEFAULT CHARSET=utf8 ROW_FORMAT=FIXED COMMENT='QuestXP'",
    function(values)
      local id = values[1]
      local diff1 = values[2] or "0"
      local diff2 = values[3] or "0"
      local diff3 = values[4] or "0"
      local diff4 = values[5] or "0"
      local diff5 = values[6] or "0"
      local diff6 = values[7] or "0"
      local diff7 = values[8] or "0"
      local diff8 = values[9] or "0"
      local diff9 = values[10] or "0"
      local diff10 = values[11] or "0"
      return "INSERT INTO `questxp_dbc` VALUES (" .. id .. ", " .. diff1 .. ", " .. diff2 .. ", " .. diff3 .. ", " .. diff4 .. ", " .. diff5 .. ", " .. diff6 .. ", " .. diff7 .. ", " .. diff8 .. ", " .. diff9 .. ", " .. diff10 .. ")"
    end)
  print("SUCCESS: questxp_dbc table created with QuestXP.dbc data")
else
  print("WARNING: DBC/wotlk/QuestXP.dbc.csv not found - skipping questxp_dbc creation")
end

mysql:close()
env:close()
print("DBC data loading completed!")
print("")
print("Now you can run: lua extractor.lua")

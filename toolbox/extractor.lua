#!/usr/bin/lua
-- depends on luasql
-- map pngs with alpha channel generated with:
-- `convert $file  -transparent white -resize '100x100!' $file`

-- BACKUP CREATED: Branch 4 Emergency Fallback Implementation
-- Date: June 5, 2025

-- ================================================================
-- EXTRACTION CONTROL PANEL
-- ================================================================

-- БЫСТРАЯ НАСТРОЙКА - просто укажи что нужно тестировать и лимиты:

local FOCUS_ON = {"quests"}        -- Что тестируем: {"quests"}, {"units"}, {"items"}, {"objects"}, {"quests", "units"}, etc
local FOCUS_LIMIT = 30000           -- Лимит для того что тестируем
local OTHER_LIMIT = 1             -- Лимит для всего остального
local FULL_EXTRACTION = true       -- true = игнорировать все лимиты

-- ================================================================
-- QUEST 784 DEBUG MODE - легко включить/выключить
-- ================================================================
local QUEST_784_TEST = false        -- true = тестируем только квест 784 и его данные
local QUEST_784_IDS = {12790, 13158, 12974, 2202, 962, 12593, 4811} -- securing the lines + additional test quest
local QUEST_784_NPCS = {29156, 16128, 31080, 30137, 30007, 7057, 100, 3652, 3672, 5768, 3419, 25462, 28357, 2930}  -- NPCs из анализа квеста 784 + тесты зон
local QUEST_784_ITEMS = {5339, 8047}  -- Items для тестирования (quest items, rewards)
local QUEST_784_OBJECTS = {13891, 126049, 128293}  -- Objects для тестирования (примеры)


-- ================================================================
-- АВТОМАТИЧЕСКАЯ НАСТРОЙКА (не трогай)
-- ================================================================

-- Категории данных и их зависимости
local CATEGORIES = {
  quests = {
    name = "Quests",
    deps = {"units"},  -- Квестам нужны только NPC и предметы, НЕ объекты
        priority = 1
  },
  units = {
    name = "Units/NPCs",
    deps = {},
    priority = 2
  },
  items = {
    name = "Items",
    deps = {},
    priority = 3
  },
  objects = {
    name = "Objects",
    deps = {},
    priority = 4
  },
  areatrigger = {
    name = "AreaTriggers",
    deps = {},
    priority = 5
  },
  refloot = {
    name = "Reference Loot",
    deps = {},
    priority = 6
  }
}

-- Функция определения лимита
function get_limit(category)
  if FULL_EXTRACTION then return nil end

  -- Проверяем если категория в фокусе
  for _, focus in ipairs(FOCUS_ON) do
    if category == focus then
      return FOCUS_LIMIT
    end
    -- Проверяем зависимости фокусной категории
    local focus_cat = CATEGORIES[focus]
    if focus_cat then
      for _, dep in ipairs(focus_cat.deps) do
        if category == dep then
          return FOCUS_LIMIT  -- Зависимости тоже получают focus лимит
        end
      end
    end
  end

  return OTHER_LIMIT
end

-- Применяем лимиты
local QUEST_LIMIT = get_limit("quests")
local UNITS_LIMIT = get_limit("units")
local OBJECTS_LIMIT = get_limit("objects")
local ITEMS_LIMIT = get_limit("items")
local AREATRIGGER_LIMIT = get_limit("areatrigger")
local REFLOOT_LIMIT = get_limit("refloot")

-- Логика экстракции
local DEBUG_EXTRACTION = not FULL_EXTRACTION

-- Progress display settings
local SHOW_PROGRESS = true
local PROGRESS_STEP = 100

-- Вывод настроек
print("================================================================")
print("pfQuest Extraction Settings:")
if QUEST_784_TEST then
  print("   Mode: QUEST 784 DEBUG - Quest IDs: " .. table.concat(QUEST_784_IDS, ", "))
  print("   NPCs: " .. table.concat(QUEST_784_NPCS, ", "))
  print("   Objects: " .. table.concat(QUEST_784_OBJECTS, ", "))
elseif FULL_EXTRACTION then
  print("   Mode: FULL EXTRACTION")
else
  print("   Focus: " .. table.concat(FOCUS_ON, ", ") .. " (" .. FOCUS_LIMIT .. ")")
  print("   Others: " .. OTHER_LIMIT)
end
print("   Quests: " .. (QUEST_LIMIT or "UNLIMITED") .. (QUEST_LIMIT == FOCUS_LIMIT and " [FOCUS]" or ""))
print("   Units: " .. (UNITS_LIMIT or "UNLIMITED") .. (UNITS_LIMIT == FOCUS_LIMIT and " [FOCUS]" or ""))
print("   Objects: " .. (OBJECTS_LIMIT or "UNLIMITED") .. (OBJECTS_LIMIT == FOCUS_LIMIT and " [FOCUS]" or ""))
print("   Items: " .. (ITEMS_LIMIT or "UNLIMITED") .. (ITEMS_LIMIT == FOCUS_LIMIT and " [FOCUS]" or ""))
print("   AreaTriggers: " .. (AREATRIGGER_LIMIT or "UNLIMITED"))
print("   RefLoot: " .. (REFLOOT_LIMIT or "UNLIMITED"))
print("================================================================")

-- ================================================================
-- END CONTROL PANEL - Script continues below
-- ================================================================

-- path to the modules
package.path = package.path .. ';./lua-sql-mysql/src/?.lua;./sha1/?.lua'

-- Initialize execution times table
local execution_times = {}

---@diagnostic disable-next-line: undefined-global
local jit = jit

local jit_version = jit and jit.version or "Not available"
-- print("JIT version: " .. jit_version)

-- Определение версии Lua (исправлено)
local lua_version_string = "Lua 5.1" -- Используем английское имя переменной
local major, minor = string.match(jit and jit.version or _VERSION, "(%d)%.(%d)")

if major and minor and tonumber(major) >= 5 and tonumber(minor) >= 2 then
    lua_version_string = "Lua 5.2" -- Обновляем ту же переменную
    -- basic LUA 5.2 compatibility definitions
    unpack = table.unpack          -- Эта глобальная переменная может быть не нужна, если unpack уже есть в Lua 5.2+
    -- но для обратной совместимости скрипт ее определяет.
    -- Если 'unpack' уже глобально определен в Lua 5.2+, эта строка его просто переопределит тем же значением.
end

-- Вывод версии для отладки (можно потом убрать)
-- -------------------------------------------------------------------
-- Compatibility: guarantee global `bit.band` even on plain Lua 5.1
-- -------------------------------------------------------------------
if not _G.bit then
  local ok, lib = pcall(require, "bit") -- LuaJIT BitOp
  if ok and lib then
    _G.bit = lib
  else
    ok, lib = pcall(require, "bit32")   -- Lua 5.2 bit32 library
    if ok and lib then
      _G.bit = lib
    else
      -- Minimal fallback implementing only band
      _G.bit = {}
      function _G.bit.band(a, b)
        local res, mul = 0, 1
        while a > 0 or b > 0 do
          if (a % 2 == 1) and (b % 2 == 1) then res = res + mul end
          a = math.floor(a / 2)
          b = math.floor(b / 2)
          mul = mul * 2
        end
        return res
      end
    end
  end
end
-- -------------------------------------------------------------------
 -- print("Detected Lua version string: " .. lua_version_string)
if jit then
--     print("JIT version: " .. jit.version)
else
--     print("Standard Lua _VERSION: " .. _VERSION)
end
if major and minor then
--     print("Parsed major.minor: " .. major .. "." .. minor)
else
    print("Could not parse major.minor from Lua version string.")
end

-- global definitions
luasql = require("luasql.mysql")

-- Simple sanitize function to replace iconv dependency
function sanitize(text)
  if not text then return "" end
  -- Remove control characters and normalize whitespace
  local clean = tostring(text):gsub("%c", ""):gsub("%s+", " ")
  return clean:match("^%s*(.-)%s*$") or ""
end

-- Function to remove duplicate entries from coordinate arrays
function removedupes(coords)
  if not coords or #coords == 0 then return {} end

  local seen = {}
  local result = {}

  for _, coord in ipairs(coords) do
    local key = table.concat(coord, ",")
    if not seen[key] then
      seen[key] = true
      table.insert(result, coord)
    end
  end

  return result
end

-- Canvas constants for zone coordinate calculation
local CANVAS_WIDTH = 1002
local CANVAS_HEIGHT = 668

-- Round function for floating point numbers
function round(num, decimals)
  local mult = 10^(decimals or 0)
  return math.floor(num * mult + 0.5) / mult
end

-- Serialize function to write Lua data to files with memory optimization
function serialize(filename, varname, data, indent, raw)
  indent = indent or 0
  if not data then return end

  local file = io.open(filename, "w")
  if not file then
    print("Error: Cannot open file " .. filename .. " for writing")
    return
  end

  -- Try to set larger buffer for better I/O performance (Lua 5.1+ only)
  if file.setvbuf then
    file:setvbuf("full", 8192)
  end

  if raw then
    -- For raw mode, write variable name and serialize the data structure properly
    file:write(varname .. " = ")
    serialize_value(file, data, indent)
    file:write("\n")
  else
    file:write(varname .. " = ")
    serialize_value(file, data, indent)
    file:write("\n")
  end

  file:close()

  -- Force immediate garbage collection after file write
  collectgarbage("collect")
end

-- Helper function for serialize
function serialize_value(file, value, indent)
  local t = type(value)
  indent = indent or 0

  if t == "table" then
    -- Check if this is a small table that can be serialized compactly
    local is_small = smalltable(value)
    local is_coords = is_coords_table(value)
    local is_unit = is_unit_table(value)
    local is_quest = is_quest_table(value)

    if is_small then
      local init
      local line = "{ "
      for _, v in ipairs(value) do  -- Use ipairs for array-like tables
        line = line .. (init and ", " or "") .. (type(v) == "string" and string.format("%q", v) or tostring(v))
        if not init then
          init = true
        end
      end
      line = line .. " }"
      file:write(line)
    elseif is_coords then
      -- Serialize coords table compactly: {[1]={x,y,z},[2]={x,y,z}}
      local init
      local line = "{"
      for i = 1, tblsize(value) do
        if value[i] then
          line = line .. (init and "," or "") .. "[" .. i .. "]="
          local coord_line = "{"
          local coord_init
          for _, v in ipairs(value[i]) do
            coord_line = coord_line .. (coord_init and "," or "") .. (type(v) == "string" and string.format("%q", v) or tostring(v))
            if not coord_init then
              coord_init = true
            end
          end
          coord_line = coord_line .. "}"
          line = line .. coord_line
          if not init then
            init = true
          end
        end
      end
      line = line .. "}"
      file:write(line)
    elseif is_unit or is_quest then
      -- Serialize unit/quest table compactly: {["coords"]={...},["lvl"]="...",["fac"]="..."}
      local init
      local line = "{"
      local keys = {}
      for k in pairs(value) do
        table.insert(keys, k)
      end
      table.sort(keys)

      for _, k in ipairs(keys) do
        local v = value[k]
        line = line .. (init and "," or "") .. "[" .. string.format("%q", k) .. "]="
        if type(v) == "table" then
          -- Handle nested tables recursively but compactly
          if is_coords_table(v) then
            local coord_line = "{"
            local coord_init
            for i = 1, tblsize(v) do
              if v[i] then
                coord_line = coord_line .. (coord_init and "," or "") .. "[" .. i .. "]="
                local inner_coord = "{"
                local inner_init
                for _, coord_val in ipairs(v[i]) do
                  inner_coord = inner_coord .. (inner_init and "," or "") .. tostring(coord_val)
                  if not inner_init then inner_init = true end
                end
                inner_coord = inner_coord .. "}"
                coord_line = coord_line .. inner_coord
                if not coord_init then coord_init = true end
              end
            end
            coord_line = coord_line .. "}"
            line = line .. coord_line
          elseif smalltable(v) then
            -- Handle small arrays like {20000} or {16305,16305}
            local small_line = "{"
            local small_init
            for _, sv in ipairs(v) do
              small_line = small_line .. (small_init and "," or "") .. tostring(sv)
              if not small_init then small_init = true end
            end
            small_line = small_line .. "}"
            line = line .. small_line
          elseif is_simple_array_of_primitives(v) then
            -- Handle simple arrays of primitives that are too large for smalltable (>10 elements)
            local medium_line = "{"
            local medium_init
            for _, sv in ipairs(v) do
              medium_line = medium_line .. (medium_init and "," or "") .. tostring(sv)
              if not medium_init then medium_init = true end
            end
            medium_line = medium_line .. "}"
            line = line .. medium_line
          else
            -- Handle other nested tables compactly
            local nested_line = "{"
            local nested_init
            local nested_keys = {}
            for nk in pairs(v) do table.insert(nested_keys, nk) end
            table.sort(nested_keys)
            for _, nk in ipairs(nested_keys) do
              local nv = v[nk]
              nested_line = nested_line .. (nested_init and "," or "") .. "[" .. string.format("%q", tostring(nk)) .. "]="
              if type(nv) == "table" then
                if smalltable(nv) then -- Use fixed/simplified smalltable
                  local inner_small = "{"
                  local inner_init
                  for _, isv in ipairs(nv) do
                    inner_small = inner_small .. (inner_init and "," or "") .. tostring(isv)
                    if not inner_init then inner_init = true end
                  end
                  inner_small = inner_small .. "}"
                  nested_line = nested_line .. inner_small
                elseif is_simple_array_of_primitives(nv) then
                  -- Handle simple arrays of primitives that are too large for smalltable (>10 elements)
                  local medium_array = "{"
                  local medium_init
                  for _, isv in ipairs(nv) do
                    medium_array = medium_array .. (medium_init and "," or "") .. tostring(isv)
                    if not medium_init then medium_init = true end
                  end
                  medium_array = medium_array .. "}"
                  nested_line = nested_line .. medium_array
                else
                  -- Fallback for complex tables that aren't smalltables or simple arrays
                  nested_line = nested_line .. "{}"
                end
              else
                nested_line = nested_line .. (type(nv) == "string" and string.format("%q", nv) or tostring(nv))
              end
              if not nested_init then nested_init = true end
            end
            nested_line = nested_line .. "}"
            line = line .. nested_line
          end
        else
          -- Debug: log when we encounter unhandled table structures
          if type(v) == "table" then
            ---@diagnostic disable-next-line: undefined-global
            print("WARNING: Unhandled table structure in quest " .. (entry or "unknown") .. ", field '" .. tostring(k) .. "' - using empty table fallback")
            -- Optional: print more details about the problematic table
            local table_info = "Table size: " .. tblsize(v) .. ", keys: "
            local key_sample = {}
            local count = 0
            for tk, tv in pairs(v) do
              count = count + 1
              if count <= 3 then -- Show first 3 keys
                table.insert(key_sample, tostring(tk) .. "=" .. type(tv))
              end
            end
            print("  " .. table_info .. table.concat(key_sample, ", ") .. (count > 3 and "..." or ""))
          end
          line = line .. (type(v) == "string" and string.format("%q", tostring(v)) or (type(v) == "boolean" and tostring(v) or (type(v) == "table" and "{}" or tostring(v))))
        end
        if not init then
          init = true
        end
      end
      line = line .. "}"
      file:write(line)
    else
      -- Use the standard multi-line format for complex tables
      file:write("{\n")
      local keys = {}
      for k in pairs(value) do
        table.insert(keys, k)
      end
      table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta == tb then
          return tostring(a) < tostring(b)
        else
          return ta < tb
        end
      end)

      for _, k in ipairs(keys) do
        local v = value[k]
        for i = 1, indent + 1 do file:write("  ") end

        if type(k) == "string" and k:match("^[%a_][%w_]*$") then
          file:write(k)
        else
          file:write("[")
          serialize_value(file, k, indent + 1)
          file:write("]")
        end

        file:write(" = ")
        serialize_value(file, v, indent + 1)
        file:write(",\n")
      end

      for i = 1, indent do file:write("  ") end
      file:write("}")
    end
  elseif t == "string" then
    file:write(string.format("%q", value))
  elseif t == "number" or t == "boolean" then
    file:write(tostring(value))
  else
    file:write("nil")
  end
end

-- Helper functions for compact serialization
function tblsize(tbl)
  local count = 0
  for _ in pairs(tbl) do
    count = count + 1
  end
  return count
end

function smalltable(tbl)
  local size = tblsize(tbl)
  if size > 10 or size < 1 then return false end

  for i=1, size do
    if not tbl[i] or type(tbl[i]) == "table" then return false end
  end

  return true
end

-- Check if table is a simple array of primitives (numbers, strings, booleans)
-- without nested tables, regardless of size
function is_simple_array_of_primitives(tbl)
  local size = tblsize(tbl)
  if size < 1 then return false end

  -- Check if all keys are sequential numbers starting from 1
  for i = 1, size do
    if tbl[i] == nil then return false end
    if type(tbl[i]) == "table" then return false end
  end

  -- Verify no extra non-sequential keys exist
  local count = 0
  for _ in pairs(tbl) do
    count = count + 1
  end

  return count == size
end

-- Check if table is coords-like structure: {[1]={...}, [2]={...}, ...}
-- where all values are smalltables and all keys are sequential numbers
function is_coords_table(tbl)
  local size = tblsize(tbl)
  if size < 1 then return false end

  -- Check if all keys are sequential numbers starting from 1
  for i = 1, size do
    if not tbl[i] then return false end
    if type(tbl[i]) ~= "table" then return false end
    if not smalltable(tbl[i]) then return false end
  end

  return true
end

-- Check if table is unit-like structure: { coords = {...}, lvl = "...", fac = "..." }
-- Should be serialized compactly on one line
function is_unit_table(tbl)
  local size = tblsize(tbl)
  if size < 1 or size > 5 then return false end

  -- Check that it only contains known unit fields
  for k, v in pairs(tbl) do
    if k ~= "coords" and k ~= "lvl" and k ~= "fac" and k ~= "rnk" and k ~= "name" then
      return false
    end
    -- coords should be a table, others should be strings or numbers
    if k == "coords" and type(v) ~= "table" then return false end
    if k ~= "coords" and type(v) ~= "string" and type(v) ~= "number" then return false end
  end

  return true
end

-- Check if table is quest-like structure: { class = ..., lvl = ..., obj = {...}, etc }
-- Should be serialized compactly on one line
function is_quest_table(tbl)
  local size = tblsize(tbl)
  if size < 1 then return false end

  -- Check that it only contains known quest fields
  for k, v in pairs(tbl) do
    if k ~= "class" and k ~= "lvl" and k ~= "min" and k ~= "obj" and k ~= "race" and
       k ~= "skill" and k ~= "end" and k ~= "start" and k ~= "pre" and k ~= "chain" and
       k ~= "event" and k ~= "repeatable" and k ~= "srcitem" and k ~= "xp_diff" then
      return false
    end
  end

  return true
end

-- Table subtraction function
function tablesubstract(t1, t2)
  if not t1 or not t2 then return t1 or {} end
  local result = {}
  for k, v in pairs(t1) do

    if not t2[k] or (type(v) == "table" and type(t2[k]) == "table") then
      if type(v) == "table" and type(t2[k]) == "table" then
        local sub = tablesubstract(v, t2[k])

        if next(sub) then
          result[k] = sub
        end
      elseif not t2[k] then
        result[k] = v
      end
    elseif v ~= t2[k] then
      result[k] = v
    end
  end
  return result
end

-- Map validation function (placeholder)
function isValidMap(zone, x, y, expansion)
  -- Basic validation - always return true for now
  return zone and x and y and x >= 0 and x <= 100 and y >= 0 and y <= 100
end

-- Cross-platform directory creation
function mkdir(path)
  local isWindows = package.config:sub(1,1) == '\\'
  local cmd = isWindows and ("mkdir \"" .. path:gsub("/", "\\") .. "\" 2>nul") or ("mkdir -p \"" .. path .. "\"")
  os.execute(cmd)
end

-- Count table entries
function TableCount(t)
  if not t then return 0 end
  local count = 0
  for _ in pairs(t) do count = count + 1 end
  return count
end

-- begin of configuration
local config = {
  expansion = "vanilla", -- Force use vanilla config for base files
  output = "../db/", -- output folder for database files
  debug = false,       -- false = process all data, true = limit to 1000 entries for testing

  mysql = {           -- database settings
    live = {
      username = "acore",
      password = "acore",
      address = "127.0.0.1",
      port = 3306,
    },
    pfquest = {
      db = "acore_world",  -- Use acore_world for DBC tables
      username = "acore",
      password = "acore",
      address = "127.0.0.1",
      port = 3306,
    },
  },

  expansions = {      -- list of available expansions
    -- vanilla is the main database, all further versions will only store the difference to vanilla
    -- you should always generate 'vanilla' first
    ["vanilla"] = {
      version = "vanilla",
      client = "1.12.1",
      core = "acore", -- Use AzerothCore for this project
      name = "Vanilla (AzerothCore WotLK data as base)",
      locales = { ["enUS"]=0, ["ruRU"]=8 },
      database = "acore_world", -- Specify the world database name for AzerothCore
      prior = nil,      -- version this one is based on (nil for vanilla)
    },
    ["tbc"] = {
      version = "tbc",
      client = "2.4.3",
      core = "cmangos",
      name = "The Burning Crusade",
      locales = { ["deDE"]=3, ["enUS"]=0, ["frFR"]=2 },
      prior = "vanilla",
    },
    ["wotlk"] = {
      version = "wotlk",
      client = "3.3.5",
      core = "cmangos", -- This would be the setting for a CMaNGOS WotLK core
      name = "Wrath of the Lich King",
      locales = { ["deDE"]=3, ["enUS"]=0, ["frFR"]=2, ["esES"]=6, ["ruRU"]=8 },
      prior = "vanilla",
    },
    ["wotlk_ac"] = { -- Added for AzerothCore
      version = "wotlk", -- The pfQuest DB structure will be for WotLK
      client = "3.3.5",
      core = "acore",   -- Use the new AzerothCore config
      name = "Wrath of the Lich King (AzerothCore)",
      locales = { ["enUS"]=0, ["ruRU"]=8 },
      prior = "vanilla", -- WotLK data is diffed against Vanilla
      database = "acore_world", -- Specify the world database name for AzerothCore
    },
  },

  cores = {           -- list of available core configurations
    -- define your table and column names here if they are different from cmangos
    -- all fields are optional, script will use default names if not defined here.
    -- a full list of default names can be found in the 'Script Internals' part of the readme.
    ["vmangos"] = {
      ["dbscripts_on_event"] = "event_scripts",
      ["item_template_reagent"] = "item_template_reagents",
      ["spell_bonus_data"] = "spell_bonus_data",
      ["spell_required"] = "spell_required",
      ["spell_template"] = "spell_dbc",
      ["spell_chain"] = "spell_chain",
      ["spell_area"] = "spell_area",
      ["spell_script_target"] = "spell_script_target",
      ["spell_effect_override"] = "spell_effect_override",
      ["Entry"] = "entry",
      ["Name"] = "name",
      ["MinLevel"] = "level_min",
      ["MaxLevel"] = "level_max",
      ["Rank"] = "rank",
      ["Faction"] = "faction",
      ["NpcFlags"] = "npcflag",
      ["VendorTemplateId"] = "vendor_template_id",
      ["RequiresSpellFocus"] = "requires_spell_focus",
      ["EffectTriggerSpell1"] = "effect_trigger_spell_1",
      ["EffectTriggerSpell2"] = "effect_trigger_spell_2",
      ["EffectTriggerSpell3"] = "effect_trigger_spell_3",
      ["Map"] = "map_id",
      ["startquest"] = "start_quest",
      ["targetEntry"] = "target_entry",
      ["dbscripts_on_event_datalong_is_target"] = true, -- if datalong on dbscripts_on_event is a target or count
    },
    ["cmangos"] = {
      -- cmangos uses the default names, so this section is almost empty
      ["dbscripts_on_event_datalong_is_target"] = true,
    },
    ["acore"] = { -- Added for AzerothCore
      ["world_db_name"] = "acore_world", -- Default AC world DB name, can be overridden by expansion's 'db' setting
      -- Table Mappings
      ["spell_template"] = "spell_dbc", -- AzerothCore uses spell_dbc instead of spell_template
      -- General Mappings
      ["Entry"] = "entry", -- creature_template.entry in AzerothCore (quest_template uses ID)
      ["Id"] = "ID", -- For spell_template.ID, quest_template.ID etc. when C.Id is used.
      ["Name"] = "name",
      ["MinLevel"] = "minlevel", -- creature_template.minlevel in AzerothCore
      ["MaxLevel"] = "maxlevel", -- creature_template.maxlevel
      ["QuestLevel"] = "QuestLevel", -- quest_template.QuestLevel
      ["Rank"] = "rank", -- creature_template.rank
      ["Faction"] = "faction", -- creature_template.faction, gameobject_template.faction
      ["NpcFlags"] = "npcflag", -- creature_template.npcflag
      -- VendorTemplateId: cmangos default is npc_vendor.entry, if AC is different, map here. pfQuest doesn't seem to use C.VendorTemplateId.
      ["RequiresSpellFocus"] = "RequiresSpellFocus", -- spell_dbc.RequiresSpellFocus (likely same name)
      ["EffectTriggerSpell1"] = "EffectTriggerSpell_1", -- spell_dbc.EffectTriggerSpell_1, etc. (AC uses 1-3 with underscores)
      ["EffectTriggerSpell2"] = "EffectTriggerSpell_2",
      ["EffectTriggerSpell3"] = "EffectTriggerSpell_3",
      ["AreaId_spell"] = "RequiredAreasID", -- spell_dbc.RequiredAreasID contains zone/area group ID
      ["Map"] = "map", -- item_template.map (for map-bound items)
      ["startquest"] = "startquest", -- item_template.startquest (AC uses this name)

      -- Quest Specific Mappings that differ from script's direct use or cmangos defaults if C.xxx is used
      ["RequiredClasses"] = "AllowableClasses", -- AC quest_template uses AllowableClasses (bitmask)
      ["RequiredRaces"] = "AllowableRaces",   -- AC quest_template uses AllowableRaces (bitmask)
      ["RequiredSkill"] = "RequiredSkillId",  -- AC quest_template uses RequiredSkillId (and RequiredSkillValue)
      ["SrcItemId"] = "StartItem",          -- AC quest_template.StartItem is the item that starts the quest
      ["PrevQuestId"] = "PrevQuestId",      -- AC quest_template.PrevQuestId
      -- NextQuestInChain: Not present in AC. Logic relying on this needs core-specific handling.

      ["ReqCreatureOrGOId"] = "RequiredNpcOrGo", -- Base name for ReqCreatureOrGOId1 -> RequiredNpcOrGo1
      ["ReqItemId"] = "RequiredItemId",       -- Base name for ReqItemId1 -> RequiredItemId1

      -- Table name mappings
      ["dbscripts_on_event"] = "smart_scripts", -- AC uses smart_scripts. This will require specific query logic changes.
      ["creature_ai_scripts"] = "smart_scripts", -- AI logic is in smart_scripts
      ["creature_ai_summons"] = "smart_scripts", -- Summons are actions in smart_scripts
      ["spell_script_target"] = "spell_scripts", -- Or potentially handled by spell_template effects / smart_scripts
      ["locales_creature"] = "creature_template_locale",
      ["locales_gameobject"] = "gameobject_template_locale",
      ["locales_item"] = "item_template_locale",
      ["locales_quest"] = "quest_template_locale",
      ["creature_questrelation"] = "creature_queststarter",
      ["gameobject_questrelation"] = "gameobject_queststarter",
      ["creature_involvedrelation"] = "creature_questender",
      ["gameobject_involvedrelation"] = "gameobject_questender",
      ["smart_scripts"] = "smart_scripts", -- Explicitly add smart_scripts itself

      -- pfQuest DBC table mappings for lowercase names
      ["AreaTrigger"] = "areatrigger",
      ["WorldMapArea"] = "worldmaparea",
      ["FactionTemplate"] = "factiontemplate",
      ["Lock"] = "lock",
      ["SkillLine"] = "skillline",
      ["AreaTable"] = "areatable",
      ["WorldMapOverlay"] = "worldmapoverlay",
    },
  },

  expansion = "vanilla", -- define the expansion to build (use vanilla to avoid -wotlk suffix) (must be a key of 'expansions' table)
  dbc_expansion = "wotlk", -- define expansion for DBC table names (AzerothCore uses wotlk DBC data)

  -- ignore list for object types. These types will not be included into the database
  -- usually these are herbs, minerals, chests because they have a too wide spawn area
  object_ignore_types = {
    -- Add any additional object types you want to ignore here
  },
}

-- Initialize debugsql table for debug tracking
debugsql = {}

-- Missing function placeholders for AzerothCore compatibility
function removedupes(tab)
  local _vals = {}
  local result = {}
  for _, k in pairs(tab) do
    -- Check if coordinate array is valid (no nil values)
    if k and #k >= 3 and k[1] and k[2] and k[3] then
      -- Create unique key using only coordinate values (x, y, zone, respawn)
      -- Skip boolean fields for key generation
      local keyParts = {tostring(k[1]), tostring(k[2]), tostring(k[3])}
      if k[4] then
        table.insert(keyParts, tostring(k[4]))
      end
      local key = table.concat(keyParts, ",")
      if not _vals[key] then
        _vals[key] = true
        table.insert(result, k)
      end
    else
      -- Skip invalid coordinates with safer error reporting
      if k then
        print("WARNING: Skipping invalid coordinate array, length:", #k, "values:", tostring(k[1]), tostring(k[2]), tostring(k[3]))
      else
        print("WARNING: Skipping nil coordinate")
      end
    end
  end
  return result
end



-- Ordered pairs function for consistent iteration
function opairs(t)
  local keys = {}
  for k in pairs(t) do
    table.insert(keys, k)
  end
  table.sort(keys)
  local i = 0
  return function()
    i = i + 1
    if keys[i] then
      return keys[i], t[keys[i]]
    end
  end
end

-- Table size function to count elements in table
function tblsize(t)
  local count = 0
  for _ in pairs(t) do
    count = count + 1
  end
  return count
end

-- limit all sql loops using new control panel settings
local limit = nil  -- Removed old ENTRY_LIMIT logic - use specific limits instead
-- print("Applied limit: " .. (limit and tostring(limit) or "NONE"))

function debug(name)
  -- count sql debugs
  if not debugsql[name] then debugsql[name] = {name, 0} end
  debugsql[name][2] = (debugsql[name][2] or 0) + 1

  -- abort here when no debug limit is set
  if not limit then return nil end
  return debugsql[name][2] > limit or nil
end

function debug_statistics()
  for name, data in pairs(debugsql) do
    local count = data[2] or 0
    if count == 0 then
--       print("WARNING: \27[1m\27[31m" .. count .. "\27[0m \27[1m" .. name .. "\27[0m \27[2m-- " .. data[1] .. "\27[0m")
    end
    debugsql[name][2] = nil
  end
end

-- local associations
local all_locales = {
  ["enUS"] = 0,
  ["koKR"] = 1,
  ["frFR"] = 2,
  ["deDE"] = 3,
  ["zhCN"] = 4,
  ["zhTW"] = 5,
  ["esES"] = 6,
  ["ruRU"] = 8,
  ["ptBR"] = 10,
}

-- Convert locale key to AzerothCore locale code
function GetLocaleCode(locale)
  return locale or "enUS"
end

-- Convert locale key to MaNGOS locale number
function GetLocaleNumber(locale)
  return all_locales[locale] or 0
end

local pfDB = {}
-- Process only the specific expansion defined in config.expansion
local expansion_to_process = config.expansion or "vanilla"

-- Глобальные переменные для патча
locales = nil
expansion = nil
exp = nil
output = nil

if config.expansions[expansion_to_process] then
  local id = expansion_to_process
  local settings = config.expansions[id]
  print("Extracting: " .. settings.name)

  expansion = settings.version
  local db = settings.database
  local core = settings.core
  locales = settings.locales

  local C = config.cores[core]

  local idcolumns = core == "vmangos" and { "id", "id2", "id3", "id4" } or { "id" }
  exp = expansion == "vanilla" and "" or "-"..expansion
  local data = "data".. exp

    do -- database connection
--         print("Attempting to connect to database...")
        local env = luasql.mysql()
        if not env then
            error("Failed to create MySQL environment")
        end
--         print("MySQL environment created successfully")

        local db_name = settings.database or config.mysql.live.db or "acore_world"
--         print("Connecting to database: " .. db_name)
--         print("Host: " .. config.mysql.live.address .. ":" .. config.mysql.live.port)
--         print("User: " .. config.mysql.live.username)

        mysql, err = env:connect(db_name, config.mysql.live.username, config.mysql.live.password, config.mysql.live.address, config.mysql.live.port)
        mysql:execute("SET NAMES utf8")
        mysql:execute("SET CHARACTER SET utf8")
        if not mysql then
            error("Database connection failed: " .. (err or "unknown error"))
        end
--         print("Database connection successful!")
    end

  do -- database query functions
    -- ENHANCED: Adaptive GPS compensation function
    function GetAdaptiveCompensation(mapid, zone_id, x, y)
      -- Map-level corrections
      local map_compensations = {
        [0] = {x_offset = 0.5, y_offset = -0.3}, -- Eastern Kingdoms
        [1] = {x_offset = -0.2, y_offset = 0.4}, -- Kalimdor
        [530] = {x_offset = 0.1, y_offset = 0.1} -- Outland
      }

      -- Zone-specific adjustments
      local zone_adjustments = {
        [12] = {x_factor = 1.0, y_factor = 1.0, x_add = 0, y_add = 0},     -- Elwynn Forest
        [40] = {x_factor = 0.9, y_factor = 0.95, x_add = 2, y_add = -1},   -- Westfall
        [1] = {x_factor = 1.1, y_factor = 1.05, x_add = -1, y_add = 1},    -- Dun Morogh
        [14] = {x_factor = 0.8, y_factor = 0.85, x_add = 5, y_add = 3},    -- Durotar
      }

      local map_comp = map_compensations[mapid] or {x_offset = 0, y_offset = 0}
      local zone_adj = zone_adjustments[zone_id] or {x_factor = 1.0, y_factor = 1.0, x_add = 0, y_add = 0}

      return {
        x_offset = map_comp.x_offset + (x * (zone_adj.x_factor - 1.0)) + zone_adj.x_add,
        y_offset = map_comp.y_offset + (y * (zone_adj.y_factor - 1.0)) + zone_adj.y_add
      }
    end

    function GetAreaTriggerCoords(id)
      local areatrigger = {}
      local ret = {}

      -- Enable areatrigger coordinates for AzerothCore
      if core == "acore" then
        -- AzerothCore with DBC tables (without pfquest prefix)
        -- FIXED: X и Y переставлены в areatrigger_wotlk
        local sql = [[
          SELECT at.*, wma.areatableID, wma.x_min, wma.x_max, wma.y_min, wma.y_max
          FROM areatrigger_wotlk at
          LEFT JOIN WorldMapArea_wotlk wma
          ON ( wma.mapID = at.MapID
            AND wma.areatableID > 0
            AND at.Y BETWEEN wma.x_min AND wma.x_max
            AND at.X BETWEEN wma.y_min AND wma.y_max )
          WHERE at.ID = ]] .. id .. [[
          ORDER BY POW(((wma.y_min + wma.y_max)/2 - at.X),2)
                 + POW(((wma.x_min + wma.x_max)/2 - at.Y),2) ASC
          LIMIT 1 ]]

        local query = mysql:execute(sql)
        if query then
          while query:fetch(areatrigger, "a") do
            if debug("areatrigger_coords") then break end
            local zone_id = tonumber(areatrigger.areatableID) or 0
            -- FIXED: X и Y переставлены
            local world_x = tonumber(areatrigger.Y) or 0  -- at.Y = world X
            local world_y = tonumber(areatrigger.X) or 0  -- at.X = world Y

            local wma_x_min = tonumber(areatrigger.x_min) or 0
            local wma_x_max = tonumber(areatrigger.x_max) or 0
            local wma_y_min = tonumber(areatrigger.y_min) or 0
            local wma_y_max = tonumber(areatrigger.y_max) or 0

            if zone_id > 0 and wma_x_min ~= 0 and wma_x_max ~= 0 and wma_y_min ~= 0 and wma_y_max ~= 0 then
              -- Правильный расчет координат зоны
              local zone_x = ((wma_y_max - world_y) / (wma_y_max - wma_y_min)) * 100
              local zone_y = 100 - ((world_x - wma_x_min) / (wma_x_max - wma_x_min)) * 100
              zone_x = math.max(0, math.min(100, zone_x))
              zone_y = math.max(0, math.min(100, zone_y))

              local coord = { round(zone_y,2), round(zone_x,2), zone_id, 0 }
              table.insert(ret, coord)
            end
          end
        end
        return ret
      end

      local sql = [[
        SELECT * FROM pfquest.AreaTrigger_]]..expansion..[[ LEFT JOIN pfquest.WorldMapArea_]]..expansion..[[
        ON ( pfquest.WorldMapArea_]]..expansion..[[.mapID = pfquest.AreaTrigger_]]..expansion..[[.MapID
          AND pfquest.WorldMapArea_]]..expansion..[[.x_min < pfquest.AreaTrigger_]]..expansion..[[.X
          AND pfquest.WorldMapArea_]]..expansion..[[.x_max > pfquest.AreaTrigger_]]..expansion..[[.X
          AND pfquest.WorldMapArea_]]..expansion..[[.y_min < pfquest.AreaTrigger_]]..expansion..[[.Y
          AND pfquest.WorldMapArea_]]..expansion..[[.y_max > pfquest.AreaTrigger_]]..expansion..[[.Y
          AND pfquest.WorldMapArea_]]..expansion..[[.areatableID > 0)
        WHERE pfquest.AreaTrigger_]]..expansion..[[.ID = ]] .. id .. [[ ORDER BY areatableID ]]

      local query = mysql:execute(sql)
      while query:fetch(areatrigger, "a") do
        local zone = areatrigger.areatableID
        local x = areatrigger.X
        local y = areatrigger.Y
        local x_max = areatrigger.x_max
        local x_min = areatrigger.x_min
        local y_max = areatrigger.y_max
        local y_min = areatrigger.y_min
        local px, py = 0, 0

        if x and y and x_min and y_min then
          px = round(100 - (y - y_min) / ((y_max - y_min)/100),1)
          py = round(100 - (x - x_min) / ((x_max - x_min)/100),1)
          if isValidMap(zone, round(px), round(py), expansion) then
            local coord = { px, py, tonumber(zone) }
            table.insert(ret, coord)
          end
        end
      end

      return ret
    end

    function GetCustomCoords(m, x, y)
        -- DEBUG: Показываем, какие координаты пришли в функцию
        if m == 0 and (math.floor(x) == -6272 or math.floor(y) == -2939) then
          print(string.format("[GetCustomCoords DEBUG] Analyzing coords for map %d: x=%f, y=%f", m, x, y))
        end

        local ret = {}

        if core == "acore" then

            -- FIXED: Add direct SQL query for continental maps to find zone by coordinates
            if m == 0 or m == 1 or m == 530 or m == 571 or m == 609 then
                local sql_zone_by_coords = string.format([[
                    SELECT wma.areatableID, wma.x_min, wma.x_max, wma.y_min, wma.y_max
                    FROM WorldMapArea_wotlk wma
                    WHERE wma.mapID = %d
                      AND wma.areatableID > 0
                      AND %f BETWEEN LEAST(wma.y_min, wma.y_max) AND GREATEST(wma.y_min, wma.y_max)
                      AND %f BETWEEN LEAST(wma.x_min, wma.x_max) AND GREATEST(wma.x_min, wma.x_max)
                    ORDER BY ( POW(((wma.y_min + wma.y_max)/2 - %f),2)
                             + POW(((wma.x_min + wma.x_max)/2 - %f),2) ) ASC
                    LIMIT 1
                ]], m, x, y, x, y)

                local cursor_zone = mysql:execute(sql_zone_by_coords)
                if cursor_zone then
                    local zone_data = {}
                    if cursor_zone:fetch(zone_data, "a") then
                        local zone_id = tonumber(zone_data.areatableID)
                        local x_min = tonumber(zone_data.x_min)
                        local x_max = tonumber(zone_data.x_max)
                        local y_min = tonumber(zone_data.y_min)
                        local y_max = tonumber(zone_data.y_max)

                        if zone_id and x_min and x_max and y_min and y_max then
                            -- Calculate zone-relative coordinates
                            local zone_map_world_width = x_max - x_min
                            local zone_map_world_height = y_max - y_min

                            local zone_x_pct = 50 -- Default
                            local zone_y_pct = 50 -- Default

                            if zone_map_world_width > 0 and zone_map_world_height > 0 then
                                zone_x_pct = ((y_max - y) / zone_map_world_height) * 100
                                zone_y_pct = 100 - (((x - x_min) / zone_map_world_width) * 100)
                            end

                            zone_x_pct = math.max(0, math.min(100, zone_x_pct))
                            zone_y_pct = math.max(0, math.min(100, zone_y_pct))

                            table.insert(ret, { round(zone_x_pct, 2), round(zone_y_pct, 2), zone_id, 0 })
                            cursor_zone:close()
                            return ret
                        end
                    end
                    cursor_zone:close()
                end
            end

            -- DEBUG: No coordinates found - return empty to expose the issue
--             print(string.format("[GetCustomCoords DEBUG] No coordinates found for map=%d x=%.2f y=%.2f", m, x, y))
            return ret
        end

        -- Старая логика для других ядер ...
        local worldmap = {}
        local sql = string.format([[ SELECT * FROM pfquest.WorldMapArea_wotlk WHERE mapID = %d AND x_min < %f AND x_max > %f AND y_min < %f AND y_max > %f AND areatableID > 0 ]], m, x, x, y, y)
        local query = mysql:execute(sql)
        while query and query:fetch(worldmap, "a") do
            local zone = worldmap.areatableID
            table.insert(ret, { 50, 50, tonumber(zone), 0 }) -- Упрощено для ясности
        end
        return ret
    end

    function GetCreatureCoordsPool(id)
      -- Temporarily disabled due to DBC data issues
      return {}
    end



    -- Continental zones cache for performance optimization
    local continental_zones_cache = {}
    local continental_zones_loaded = false

    -- Load continental zones cache once at startup
    function LoadContinentalZonesCache()
        if continental_zones_loaded then
            return
        end

        print("  Loading continental zones cache...")
        local sql_query = [[
            SELECT DISTINCT areatableID FROM WorldMapArea_wotlk
            WHERE mapID IN (0,1,530,571,609) AND areatableID > 0
        ]]

        local cursor = mysql:execute(sql_query)
        if cursor then
            local result = {}
            local count = 0
            while cursor:fetch(result, "a") do
                local zone_id = tonumber(result.areatableID)
                if zone_id then
                    continental_zones_cache[zone_id] = true
                    count = count + 1
                end
            end
            cursor:close()
            print("  Loaded " .. count .. " continental zones into cache")
        end

        continental_zones_loaded = true
    end

    -- Function to check if a zone ID represents a continental zone (not an instance) - CACHED VERSION
    function IsContinentalZone(zone_id)
        if not zone_id or zone_id == 0 then
            return false
        end

        -- Use cache for instant lookup
        LoadContinentalZonesCache()
        return continental_zones_cache[zone_id] == true
    end

    -- Кэш для границ зон из WorldMapArea_wotlk
    local zone_map_world_boundaries_cache = {}

    -- DungeonMap fallback cache
    local dungeonmap_fallback_cache = {}

    function GetDungeonMapBoundariesFallback(target_areatable_id, continent_map_id)
        local cache_key = tostring(target_areatable_id) .. "_" .. tostring(continent_map_id) .. "_dungeon"
        if dungeonmap_fallback_cache[cache_key] then
            return dungeonmap_fallback_cache[cache_key]
        end

        -- Try to find DungeonMap entry by MapID (for dungeons/instances)
        local sql = string.format(
            "SELECT MinY, MaxY, MaxX, MinX FROM DungeonMap_wotlk WHERE MapID = %d ORDER BY FloorIndex LIMIT 1",
            continent_map_id
        )
        local cursor = mysql:execute(sql)
        if cursor then
            local row = cursor:fetch({}, "a")
            cursor:close()
            if row and row.MinY and row.MaxY and row.MaxX and row.MinX then
                local bounds = {
                    x_left = tonumber(row.MinY),    -- DungeonMap MinY -> WorldX_Left
                    x_right = tonumber(row.MaxY),   -- DungeonMap MaxY -> WorldX_Right
                    y_top = tonumber(row.MaxX),     -- DungeonMap MaxX -> WorldY_Top
                    y_bottom = tonumber(row.MinX)   -- DungeonMap MinX -> WorldY_Bottom
                }
                dungeonmap_fallback_cache[cache_key] = bounds
                return bounds
            end
        end

        dungeonmap_fallback_cache[cache_key] = false
        return nil
    end

    function GetWorldMapAreaBoundariesForZone(target_areatable_id, continent_map_id)

        local cache_key = tostring(target_areatable_id) .. "_" .. tostring(continent_map_id)
        if zone_map_world_boundaries_cache[cache_key] then
            return zone_map_world_boundaries_cache[cache_key]
        end

        if not target_areatable_id or not continent_map_id then
            print(string.format("ERROR: Missing target_areatable_id (%s) or continent_map_id (%s) in GetWorldMapAreaBoundariesForZone", tostring(target_areatable_id), tostring(continent_map_id)))
            return nil
        end

        local sql = string.format(
            "SELECT y_min, y_max, x_max, x_min FROM WorldMapArea_wotlk WHERE mapID = %d AND areatableID = %d LIMIT 1",
            continent_map_id, target_areatable_id
        )
        local cursor = mysql:execute(sql)
        if cursor then
            local row = cursor:fetch({}, "a")
            cursor:close()
            if row and row.y_min and row.y_max and row.x_max and row.x_min then
                -- Check if boundaries are all zeros (0,0,0,0)
                if tonumber(row.y_min) == 0 and tonumber(row.y_max) == 0 and
                   tonumber(row.x_max) == 0 and tonumber(row.x_min) == 0 then
                    -- Try DungeonMap fallback for zones with empty boundaries
                    local dungeon_bounds = GetDungeonMapBoundariesFallback(target_areatable_id, continent_map_id)
                    if dungeon_bounds then
                        zone_map_world_boundaries_cache[cache_key] = dungeon_bounds
                        print(string.format("🗺️  [DUNGEONMAP FALLBACK] Used DungeonMap boundaries for AreaID: %d (MapID: %d)", target_areatable_id, continent_map_id))
                        return dungeon_bounds
                    end
                end

                local bounds = {
                    x_left = tonumber(row.y_min),   -- WorldX_Left
                    x_right = tonumber(row.y_max),  -- WorldX_Right
                    y_top = tonumber(row.x_max),    -- WorldY_Top (большее значение Y в мире)
                    y_bottom = tonumber(row.x_min)  -- WorldY_Bottom (меньшее значение Y в мире)
                }
                zone_map_world_boundaries_cache[cache_key] = bounds
                return bounds
            end
        end

        -- Try DungeonMap fallback if WorldMapArea query failed completely
        local dungeon_bounds = GetDungeonMapBoundariesFallback(target_areatable_id, continent_map_id)
        if dungeon_bounds then
            zone_map_world_boundaries_cache[cache_key] = dungeon_bounds
            print(string.format("🗺️  [DUNGEONMAP FALLBACK] Used DungeonMap boundaries for missing AreaID: %d (MapID: %d)", target_areatable_id, continent_map_id))
            return dungeon_bounds
        end

        -- print(string.format("WARNING: Could not fetch WorldMapArea boundaries for AreaTable.ID: %d on MapID: %d", target_areatable_id, continent_map_id))
        zone_map_world_boundaries_cache[cache_key] = false -- Кэшируем неудачу, чтобы не повторять запрос
        return nil
    end

    -- Кэш для ParentAreaID из AreaTable_wotlk
    local area_table_parent_cache = {}
    function GetParentAreaFromAreaTable(child_area_id)
        if not child_area_id or child_area_id == 0 then return 0 end -- или nil
        if area_table_parent_cache[child_area_id] then
            return area_table_parent_cache[child_area_id]
        end
        local sql = string.format("SELECT parentAreaID FROM AreaTable_wotlk WHERE ID = %d LIMIT 1", child_area_id)
        local cursor = mysql:execute(sql)
        if cursor then
            local row = cursor:fetch({}, "a")
            cursor:close()
            if row and row.parentAreaID then
                local parent_id = tonumber(row.parentAreaID)
                area_table_parent_cache[child_area_id] = parent_id
                return parent_id
            end
        end
        -- print(string.format("WARNING: Could not fetch parentAreaID for AreaTable.ID: %d", child_area_id))
        area_table_parent_cache[child_area_id] = 0 -- Кэшируем неудачу (0 означает нет родителя или ошибка)
        return 0
    end

-- ================================================================
-- Helper functions for proper zone selection on world map
-- ================================================================

local continent_zone_cache = {}

-- REMOVED: IsZoneOnContinentMap - replaced with IsContinentalZone

function NormalizeDisplayZone(initial_zone, map_id, world_x, world_y)
  if not initial_zone then return map_id or 1 end -- Защита от nil

  -- Special cases: Dungeon antechambers → correct zones
  if initial_zone == 719 then -- Blackfathom Deeps → Ashenvale
    return 331
  elseif initial_zone == 2557 then -- Dire Maul → Feralas
    return 357
  end

  -- DEBUG: Uncomment for troubleshooting specific zones
  -- if initial_zone == 1337 or initial_zone == 718 then
  --     print(string.format("[NDZ] Normalizing zone %s for map %s at %s,%s", tostring(initial_zone), tostring(map_id), tostring(world_x), tostring(world_y)))
  -- end

  if IsContinentalZone(initial_zone) then
    return initial_zone
  end

  -- Try GetCustomCoords first since GetParentAreaFromAreaTable is not working reliably
  if world_x and world_y and map_id then
    local c = GetCustomCoords(map_id, world_x, world_y)
    if c and c[1] and c[1][3] and c[1][3] ~= 0 and IsContinentalZone(c[1][3]) then
      -- DEBUG: Uncomment for debugging
      -- if initial_zone == 1337 or initial_zone == 718 then print("[NDZ] Found geometric zone:", c[1][3]) end
      return c[1][3]
    end
    -- DEBUG: Uncomment for debugging
    -- if initial_zone == 1337 or initial_zone == 718 then print("[NDZ] GetCustomCoords returned empty or invalid") end
  end

  -- Fallback: try parent area lookup (keeping for compatibility)
  local safety, candidate = 0, initial_zone
  while candidate and candidate ~= 0 and safety < 5 do
    candidate = GetParentAreaFromAreaTable(candidate)
    -- DEBUG: Uncomment for debugging
    -- if initial_zone == 1337 or initial_zone == 718 then print(string.format("[NDZ] Parent step %d: %d -> %d", safety, initial_zone, candidate or 0)) end
    if candidate and candidate ~= 0 and IsContinentalZone(candidate) then
      -- DEBUG: Uncomment for debugging
      -- if initial_zone == 1337 or initial_zone == 718 then print("[NDZ] Found parent zone:", candidate) end
      return candidate
    end
    safety = safety + 1
  end

  -- DEBUG: Uncomment for debugging
  -- if initial_zone == 1337 or initial_zone == 718 then print("[NDZ] Failed to normalize, returning original:", initial_zone) end
  return initial_zone
end
    function GetCreatureCoords(id1_template) -- id1_template это creature_template.entry
        local ret = {}
        if core == "acore" then
            local creature_spawn_data_cache = {}
            local sql_get_creatures = string.format(
                "SELECT guid, map, position_x, position_y, zoneId, spawntimesecs FROM creature WHERE id1 = %d ORDER BY map ASC, guid ASC", -- map ASC ensures continent spawns are first
                id1_template
            )
            local cursor_creatures = mysql:execute(sql_get_creatures)

            if not cursor_creatures then return ret end

            while true do
                local temp_row = {}
                if not cursor_creatures:fetch(temp_row, "a") then break end
                table.insert(creature_spawn_data_cache, {
                    guid = temp_row.guid, map = tonumber(temp_row.map),
                    position_x = tonumber(temp_row.position_x), position_y = tonumber(temp_row.position_y),
                    zoneId = tonumber(temp_row.zoneId),
                    spawntimesecs = tonumber(temp_row.spawntimesecs)
                })
            end
            cursor_creatures:close()

            for _, creature_data in ipairs(creature_spawn_data_cache) do
                local npc_world_x, npc_world_y = creature_data.position_x, creature_data.position_y
                local map_id, db_zoneId = creature_data.map, creature_data.zoneId

                -- FIXED: Use NormalizeDisplayZone first, then fallback to geometric calculation
                local display_zone_for_units_lua = NormalizeDisplayZone(db_zoneId, map_id, npc_world_x, npc_world_y)

                -- DEBUG: Uncomment for zone debugging
                -- if id1_template == 7057 or id1_template == 100 or id1_template == 3652 or id1_template == 3672 or id1_template == 5768 then
                --     print(string.format("[GC NORMALIZE] NPC %d normalized zone: %d -> %d", id1_template, db_zoneId, display_zone_for_units_lua))
                -- end

                -- Fallback to geometric calculation if still not continental
                if not IsContinentalZone(display_zone_for_units_lua) then
                    if map_id == 0 or map_id == 1 or map_id == 530 or map_id == 571 or map_id == 609 then
                        local geo_sql = string.format([[ SELECT wma.areatableID FROM WorldMapArea_wotlk wma WHERE wma.mapID = %d AND wma.areatableID > 0 AND %f BETWEEN LEAST(wma.y_min, wma.y_max) AND GREATEST(wma.y_min, wma.y_max) AND %f BETWEEN LEAST(wma.x_min, wma.x_max) AND GREATEST(wma.x_min, wma.x_max) ORDER BY ( POW(((wma.y_min + wma.y_max)/2 - %f),2) + POW(((wma.x_min + wma.x_max)/2 - %f),2) ) ASC LIMIT 1 ]], map_id, npc_world_x, npc_world_y, npc_world_x, npc_world_y)
                        local query = mysql:execute(geo_sql)
                        if query then
                            local result = {}
                            if query:fetch(result, "a") then
                                display_zone_for_units_lua = tonumber(result.areatableID)
                                -- DEBUG: Uncomment for debugging
                                -- if id1_template == 7057 or id1_template == 100 or id1_template == 3652 or id1_template == 3672 or id1_template == 5768 then
                                --     print(string.format("[GC CALCULATED] NPC %d calculated zone by coords: %d", id1_template, display_zone_for_units_lua))
                                -- end
                            end
                            query:close()
                        end
                    end
                end

                -- Final fallback
                if not display_zone_for_units_lua or display_zone_for_units_lua == 0 then
                    display_zone_for_units_lua = db_zoneId
                end

                if id1_template == 7057 or id1_template == 100 then
                    print(string.format("[DEBUG GetCreatureCoords] ID %d, OriginalZone %d -> FinalZone %d", id1_template, db_zoneId, display_zone_for_units_lua))
                end

                local zone_x, zone_y = 50, 50
                local zone_bounds = GetWorldMapAreaBoundariesForZone(display_zone_for_units_lua, map_id)
                if npc_world_x and npc_world_y and zone_bounds then
                    local Z_WorldX_L, Z_WorldX_R = zone_bounds.x_left, zone_bounds.x_right
                    local Z_WorldY_T, Z_WorldY_B = zone_bounds.y_top, zone_bounds.y_bottom
                    local zone_map_world_width = Z_WorldX_R - Z_WorldX_L
                    local zone_map_world_height = Z_WorldY_T - Z_WorldY_B
                    if zone_map_world_width > 0 and zone_map_world_height > 0 then
                        zone_x = ((Z_WorldY_T - npc_world_y) / zone_map_world_height) * 100
                        zone_y = 100 - (((npc_world_x - Z_WorldX_L) / zone_map_world_width) * 100)
                    end
                end
                table.insert(ret, { round(zone_x,2), round(zone_y,2), display_zone_for_units_lua, creature_data.spawntimesecs or 0 })
            end
        end
        return ret
    end

    function GetGameObjectCoords(id1_template) -- id1_template это gameobject_template.entry
        local ret = {}
        if core == "acore" then
            local gameobject_spawn_data_cache = {}
            -- ВАЖНО: Проверьте, какое поле в таблице 'gameobject' соответствует 'gameobject_template.entry'.
            -- Обычно это 'id', но может быть 'entry' или 'id1' в зависимости от вашей схемы.
            -- Я использую 'id' согласно вашему предыдущему коду для GetGameObjectCoords.
            local sql_get_gameobjects = string.format(
                "SELECT guid, map, position_x, position_y, zoneId, areaId, spawntimesecs FROM gameobject WHERE id = %d",
                id1_template
            )
            local cursor_gameobjects = mysql:execute(sql_get_gameobjects)

            if not cursor_gameobjects then
                print("ERROR: Failed to query gameobject spawns for template ID: " .. id1_template)
                return ret
            end

            local temp_row = {}
            while cursor_gameobjects:fetch(temp_row, "a") do
                table.insert(gameobject_spawn_data_cache, {
                    guid = temp_row.guid, map = tonumber(temp_row.map),
                    position_x = tonumber(temp_row.position_x), position_y = tonumber(temp_row.position_y),
                    zoneId = tonumber(temp_row.zoneId), areaId = tonumber(temp_row.areaId),
                    spawntimesecs = tonumber(temp_row.spawntimesecs)
                })
                temp_row = {}
            end
            cursor_gameobjects:close()

            -- Опционально: отладочный вывод, если для тестовых объектов не найдено спавнов
            -- if #gameobject_spawn_data_cache == 0 and DEBUG_EXTRACTION and QUEST_784_TEST then
            --     -- print(string.format("WARNING: No spawns found in 'gameobject' table for template ID: %d", id1_template))
            -- end

            for _, gobject_data in ipairs(gameobject_spawn_data_cache) do
                local gobj_world_x = gobject_data.position_x
                local gobj_world_y = gobject_data.position_y
                local map_id = gobject_data.map -- Это continent_id

                local db_zoneId = gobject_data.zoneId
                local db_areaId = gobject_data.areaId

                -- FIXED: Use NormalizeDisplayZone first (same logic as creatures)
                local display_map_areatable_id = NormalizeDisplayZone(db_zoneId, map_id, gobj_world_x, gobj_world_y)

                -- Fallback to geometric calculation if still not continental
                if not IsContinentalZone(display_map_areatable_id) then
                    if map_id == 0 or map_id == 1 or map_id == 530 or map_id == 571 or map_id == 609 then
                        local coords_data = GetCustomCoords(map_id, gobj_world_x, gobj_world_y)
                        if coords_data and coords_data[1] and coords_data[1][3] and coords_data[1][3] ~= 0 and IsContinentalZone(coords_data[1][3]) then
                            display_map_areatable_id = coords_data[1][3]
                        end
                    end
                end

                -- Final fallback (same as creatures)
                if not display_map_areatable_id or display_map_areatable_id == 0 then
                    display_map_areatable_id = db_zoneId
                end

                local zone_x, zone_y = 50, 50 -- Default

                -- Специальная обработка для карты Даларана (MapID 571)
                if map_id == 571 and display_map_areatable_id == 4395 and gobj_world_x and gobj_world_y then
                    -- Эффективные границы для Даларана
                    local X_MIN_eff = 5513.33
                    local X_MAX_eff = 6066.67
                    local Y_MIN_eff = 222.495
                    local Y_MAX_eff = 1052.51

                    local DALARAN_EFFECTIVE_WIDTH = X_MAX_eff - X_MIN_eff
                    local DALARAN_EFFECTIVE_HEIGHT = Y_MAX_eff - Y_MIN_eff

                    -- Расчет координат для pfQuest используя эффективные границы
                    local zone_x_percent = ((Y_MAX_eff - gobj_world_y) / DALARAN_EFFECTIVE_HEIGHT) * 100
                    local zone_y_percent = 100 - (((gobj_world_x - X_MIN_eff) / DALARAN_EFFECTIVE_WIDTH) * 100)

                    zone_x = math.max(0, math.min(100, zone_x_percent))
                    zone_y = math.max(0, math.min(100, zone_y_percent))
                else
                    local zone_bounds = GetWorldMapAreaBoundariesForZone(display_map_areatable_id, map_id)

                    if gobj_world_x and gobj_world_y and zone_bounds then
                    local Z_WorldX_L = zone_bounds.x_left
                    local Z_WorldX_R = zone_bounds.x_right
                    local Z_WorldY_T = zone_bounds.y_top
                    local Z_WorldY_B = zone_bounds.y_bottom

                    local zone_map_world_width = Z_WorldX_R - Z_WorldX_L
                    local zone_map_world_height = Z_WorldY_T - Z_WorldY_B

                    if zone_map_world_width > 0 and zone_map_world_height > 0 then
                        local pfQuest_X_pct = ((Z_WorldY_T - gobj_world_y) / zone_map_world_height) * 100
                        local pfQuest_Y_pct = 100 - (((gobj_world_x - Z_WorldX_L) / zone_map_world_width) * 100)

                        zone_x = pfQuest_X_pct
                        zone_y = pfQuest_Y_pct
                    else
                        -- print(string.format("WARNING: Invalid zone map dimensions for GObject AreaTable.ID %d. GObject GUID %s defaulting to 50,50.", display_map_areatable_id, gobject_data.guid or "N/A"))
                    end
                else
                    -- Логирование предупреждений, если нужно
                    -- if not gobj_world_x or not gobj_world_y then
                    --     print(string.format("WARNING: GObject GUID %s (template %s) missing world coordinates. Defaulting to 50,50.", gobject_data.guid or "N/A", id1_template))
                    -- end
                    -- if not zone_bounds then
                    --      print(string.format("WARNING: No WMA boundaries for GObject AreaTable.ID %d on MapID %d. GObject GUID %s defaulting to 50,50.", display_map_areatable_id, map_id, gobject_data.guid or "N/A"))
                    -- end
                    end
                end

                zone_x = math.max(0, math.min(100, zone_x))
                zone_y = math.max(0, math.min(100, zone_y))

                -- display_map_areatable_id здесь используется как ID карты, на которой объект будет показан
                local object_respawn_time = gobject_data.spawntimesecs or 0
                table.insert(ret, { round(zone_x,2), round(zone_y,2), display_map_areatable_id, object_respawn_time })
            end
        end
        return ret
    end
  end

  local start_time_areatrigger = os.clock()
  do -- areatrigger
    print("- loading areatrigger...")

    pfDB["areatrigger"] = pfDB["areatrigger"] or {}
    pfDB["areatrigger"][data] = {}

    -- Enable areatrigger for AzerothCore with DBC tables
    if core == "acore" then
      -- Use areatrigger_wotlk to get all triggers
      local areatrigger_ids_query = mysql:execute("SELECT ID AS id FROM areatrigger_wotlk")
      if areatrigger_ids_query then
        local areatrigger_row = {}
        while areatrigger_ids_query:fetch(areatrigger_row, "a") do
          if debug("areatrigger") then break end
          local entry = tonumber(areatrigger_row.id)
          if entry then
            pfDB["areatrigger"][data][entry] = {}

            do -- coordinates
              pfDB["areatrigger"][data][entry]["coords"] = {}
              for id, coords in pairs(GetAreaTriggerCoords(entry)) do
                local x, y, zone, respawn = unpack(coords)
                table.insert(pfDB["areatrigger"][data][entry]["coords"], { x, y, zone, respawn })
              end
            end
          end
        end
      else
        print("  Skipping areatrigger extraction (areatrigger_involvedrelation table not found)")
      end
    else
      -- iterate over all areatriggers
      local areatrigger = {}
      local table_name = (C.AreaTrigger or "AreaTrigger") .. "_" .. settings.version
      print("Querying table: pfquest." .. table_name)
      local query, err = mysql:execute('SELECT * FROM pfquest.' .. table_name .. ' ORDER BY ID')
      if not query then
          print("ERROR: Failed to execute query for table: pfquest." .. table_name)
          if err then print("MySQL Error: " .. err) end
          print("Possible causes:")
          print("1. Table pfquest." .. table_name .. " does not exist")
          print("2. User 'acore' does not have access to pfquest database")
          print("3. pfquest database does not exist")
          error("Query failed for pfquest." .. table_name)
      end
      while query:fetch(areatrigger, "a") do
        if debug("areatrigger") then break end

        local entry = tonumber(areatrigger.ID)
        pfDB["areatrigger"][data][entry] = {}

        do -- coordinates
          pfDB["areatrigger"][data][entry]["coords"] = {}
          for id, coords in pairs(GetAreaTriggerCoords(entry)) do
            local x, y, zone, respawn = unpack(coords)
            table.insert(pfDB["areatrigger"][data][entry]["coords"], { x, y, zone, respawn })
          end
        end
      end
    end
    local end_time_areatrigger = os.clock()
    if pfDB and pfDB["areatrigger"] then
      table.insert(execution_times, {name = "areatrigger", time = end_time_areatrigger - start_time_areatrigger})
    end
    -- ДОБАВЬТЕ:
    collectgarbage("collect")
    print("  Memory cleanup after areatriggers: " .. math.floor(collectgarbage("count")) .. " KB")
  end

    local start_time_zones = os.clock()
    do -- zones
      print("- loading zones (new logic)...")
      pfDB["zones"] = pfDB["zones"] or {}
      pfDB["zones"]["data"] = {} -- Очищаем или создаем таблицу для данных

      -- В блоке do -- zones (new logic)...
      local zones_query_sql = [[
  SELECT
      at.ID AS SourceAreaID,
      at.name_loc0 AS SourceAreaName,
      at.continentID,
      COALESCE(parent_map_at.ID, at.ID) AS ParentZoneIdForMapTexture,
      parent_map_at.name_loc0 AS ParentZoneName,
      wmo.HitRectLeft AS WMO_HR_Left,
      wmo.HitRectTop AS WMO_HR_Top,
      wmo.HitRectRight AS WMO_HR_Right,
      wmo.HitRectBottom AS WMO_HR_Bottom,
      (CASE WHEN wmo.areaID IS NOT NULL AND wmo.HitRectLeft IS NOT NULL AND wmo.HitRectRight IS NOT NULL AND wmo.HitRectTop IS NOT NULL AND wmo.HitRectBottom IS NOT NULL THEN 1 ELSE 0 END) AS IsRealOverlay
  FROM
      AreaTable_wotlk at
  LEFT JOIN
      WorldMapOverlay_wotlk wmo ON at.ID = wmo.areaID
  LEFT JOIN
      WorldMapArea_wotlk wma_parent_for_overlay ON wmo.zoneID = wma_parent_for_overlay.zoneID
  LEFT JOIN
      AreaTable_wotlk parent_map_at ON wma_parent_for_overlay.areatableID = parent_map_at.ID AND parent_map_at.continentID = at.continentID
  WHERE
      at.ID != 0
  ORDER BY
      at.ID ASC;
  ]]

      local query_cursor = mysql:execute(zones_query_sql)
      if not query_cursor then
          print("ERROR: Failed to execute SQL query for zones!")
      else
          local row = {}
          local processed_zones_count = 0
          while query_cursor:fetch(row, "a") do
              processed_zones_count = processed_zones_count + 1
              local sourceAreaID = tonumber(row.SourceAreaID)
              local parentZoneIdForMapTexture = tonumber(row.ParentZoneIdForMapTexture)
              local isRealOverlay = (tonumber(row.IsRealOverlay) == 1)

              local hrLeft, hrTop, hrRight, hrBottom

              if isRealOverlay and row.WMO_HR_Left ~= nil then -- Добавил проверку на nil для WMO_HR_Left как индикатор
                  hrLeft = tonumber(row.WMO_HR_Left)
                  hrTop = tonumber(row.WMO_HR_Top)
                  hrRight = tonumber(row.WMO_HR_Right)
                  hrBottom = tonumber(row.WMO_HR_Bottom)

                  -- Дополнительная проверка на валидность HitRect для оверлея
                  if not hrRight or not hrBottom or hrLeft >= hrRight or hrTop >= hrBottom then
                      -- print(string.format("WARNING: Invalid HitRect for overlay AreaID: %d. Reverting to full canvas for this entry.", sourceAreaID))
                      parentZoneIdForMapTexture = sourceAreaID -- Использует свою карту, так как хитбокс оверлея некорректен
                      hrLeft = 0
                      hrTop = 0
                      hrRight = CANVAS_WIDTH
                      hrBottom = CANVAS_HEIGHT
                  end
              else -- Основная зона или подзона без валидного/полного оверлея в WMO
                  parentZoneIdForMapTexture = sourceAreaID -- Использует свою карту
                  hrLeft = 0
                  hrTop = 0
                  hrRight = CANVAS_WIDTH
                  hrBottom = CANVAS_HEIGHT
              end

              local pixelWidth = hrRight - hrLeft
              local pixelHeight = hrBottom - hrTop

              if pixelWidth <= 0 then pixelWidth = CANVAS_WIDTH; hrLeft = 0; hrRight = CANVAS_WIDTH; end
              if pixelHeight <= 0 then pixelHeight = CANVAS_HEIGHT; hrTop = 0; hrBottom = CANVAS_HEIGHT; end

              local pixelCX = hrLeft + pixelWidth / 2
              local pixelCY = hrTop + pixelHeight / 2

              local width_pct = (pixelWidth / CANVAS_WIDTH) * 100
              local height_pct = (pixelHeight / CANVAS_HEIGHT) * 100
              local centerX_pct = (pixelCX / CANVAS_WIDTH) * 100
              local centerY_pct = (pixelCY / CANVAS_HEIGHT) * 100

              width_pct = math.max(1, math.min(100, width_pct))
              height_pct = math.max(1, math.min(100, height_pct))
              centerX_pct = math.max(0, math.min(100, centerX_pct))
              centerY_pct = math.max(0, math.min(100, centerY_pct))

              pfDB["zones"][data][sourceAreaID] = {
                  parentZoneIdForMapTexture,
                  round(width_pct, 2),
                  round(height_pct, 2),
                  round(centerX_pct, 2),
                  round(centerY_pct, 2)
              }
          end
          query_cursor:close()
--           print("  SUCCESS: zones.lua data generated with new logic. Total zones processed from SQL: " .. processed_zones_count .. ", Populated in pfDB: " .. TableCount(pfDB["zones"][data]))
      end
    local end_time_zones = os.clock()
    if pfDB and pfDB["zones"] then
      table.insert(execution_times, {name = "zones", time = end_time_zones - start_time_zones})
    end
    -- ДОБАВЬТЕ:
    collectgarbage("collect")
    print("  Memory cleanup after zones: " .. math.floor(collectgarbage("count")) .. " KB")
    end -- конец do -- zones



  local start_time_units = os.clock()
  do -- units
    print("- loading units...")

    pfDB["units"] = pfDB["units"] or {}
    pfDB["units"][data] = {}

    -- STEP 1/3: Pass 1 - Collect all creature entry IDs first (MAJOR OPTIMIZATION)
    print("  Pass 1: Collecting all creature entry IDs...")
    local all_creature_ids = {}
    local limit_clause = ""
    local where_clause = ""

    -- QUEST 784 DEBUG MODE - фильтруем только нужных NPC
    if QUEST_784_TEST then
      local npc_list = table.concat(QUEST_784_NPCS, ",")
      where_clause = " WHERE entry IN (" .. npc_list .. ") "
      print("🎯 QUEST 784 DEBUG: Processing only NPCs " .. npc_list)
    else
      limit_clause = (DEBUG_EXTRACTION and not FULL_EXTRACTION) and (' LIMIT ' .. UNITS_LIMIT) or ''
    end

    local pass1_query = mysql:execute('SELECT entry FROM creature_template' .. where_clause .. ' GROUP BY entry ORDER BY entry' .. limit_clause)
    if pass1_query then
        local temp_creature = {}
        while pass1_query:fetch(temp_creature, "a") do
            if debug("units_pass1") then break end
            table.insert(all_creature_ids, tonumber(temp_creature.entry))
        end
    end
    print("  Pass 1 complete: Collected " .. #all_creature_ids .. " creature IDs for batch processing")

    -- STEP 2/3: Pass 2a - Batch load all creature coordinates (eliminates 46k+ individual queries!)
    print("  Pass 2a: Batch loading creature coordinates...")
    local creature_coords_cache = {}

    if #all_creature_ids > 0 then
        local chunk_size = 5000  -- Process 5000 creatures at a time for optimal performance
        local total_chunks = math.ceil(#all_creature_ids / chunk_size)

        for chunk = 1, total_chunks do
            local start_idx = (chunk - 1) * chunk_size + 1
            local end_idx = math.min(chunk * chunk_size, #all_creature_ids)
            local chunk_ids = {}
            for i = start_idx, end_idx do
                table.insert(chunk_ids, all_creature_ids[i])
            end
            local creature_ids_string = table.concat(chunk_ids, ",")

            print("  Processing coordinate chunk " .. chunk .. "/" .. total_chunks .. " (" .. #chunk_ids .. " creatures)")
            local batch_query = mysql:execute("SELECT id1, guid, map, position_x, position_y, zoneId, areaId, spawntimesecs FROM creature WHERE id1 IN (" .. creature_ids_string .. ") ORDER BY id1, map, guid")
            if batch_query then
                local temp_data = {}
                while batch_query:fetch(temp_data, "a") do
                    if debug("units_batch_coords") then break end

                    local creature_id = tonumber(temp_data.id1)
                    creature_coords_cache[creature_id] = creature_coords_cache[creature_id] or {}

                    -- Apply same coordinate conversion logic as GetCreatureCoords function
                    local npc_world_x = tonumber(temp_data.position_x)
                    local npc_world_y = tonumber(temp_data.position_y)
                    local map_id = tonumber(temp_data.map)

                    -- DEBUG: Uncomment for coordinate debugging
                    -- if creature_id == 7057 then
                    --     print(string.format("[BATCH DEBUG] NPC 7057 guid=%s map=%d x=%.2f y=%.2f", temp_data.guid or "N/A", map_id, npc_world_x, npc_world_y))
                    -- end
                    local db_zoneId = tonumber(temp_data.zoneId)
                    local db_areaId = tonumber(temp_data.areaId)

                    -- Use NormalizeDisplayZone for proper zone detection (now with cached IsContinentalZone)
                    local display_zone_for_units_lua = NormalizeDisplayZone(db_zoneId, map_id, npc_world_x, npc_world_y)

                    -- Final fallback
                    if not display_zone_for_units_lua or display_zone_for_units_lua == 0 then
                        display_zone_for_units_lua = db_zoneId
                    end

                    local zone_x, zone_y = 50, 50 -- Default
                    local zone_bounds = GetWorldMapAreaBoundariesForZone(display_zone_for_units_lua, map_id)

                    if npc_world_x and npc_world_y and zone_bounds then
                        local Z_WorldX_L = zone_bounds.x_left
                        local Z_WorldX_R = zone_bounds.x_right
                        local Z_WorldY_T = zone_bounds.y_top
                        local Z_WorldY_B = zone_bounds.y_bottom

                        local zone_map_world_width = Z_WorldX_R - Z_WorldX_L
                        local zone_map_world_height = Z_WorldY_T - Z_WorldY_B

                        if zone_map_world_width > 0 and zone_map_world_height > 0 then
                            local pfQuest_X_pct = ((Z_WorldY_T - npc_world_y) / zone_map_world_height) * 100
                            local pfQuest_Y_pct = 100 - (((npc_world_x - Z_WorldX_L) / zone_map_world_width) * 100)
                            zone_x = pfQuest_X_pct
                            zone_y = pfQuest_Y_pct
                        end
                    end

                    zone_x = math.max(0, math.min(100, zone_x))
                    zone_y = math.max(0, math.min(100, zone_y))

                    local creature_respawn_time = tonumber(temp_data.spawntimesecs) or 0

                    -- DIAGNOSTIC: Check for problematic coordinates
                    local final_x, final_y = round(zone_x,2), round(zone_y,2)
                    if (final_x == 0 and final_y == 100) or (final_x == 100 and final_y == 0) or final_x < 0 or final_x > 100 or final_y < 0 or final_y > 100 then
--                         print(string.format("  WARNING: Creature %d got invalid coordinates [%.2f,%.2f] zone=%d original_zone=%d world=[%.2f,%.2f] map=%d",
--                             creature_id, final_x, final_y, display_zone_for_units_lua, db_zoneId, npc_world_x, npc_world_y, map_id))
                    end

                    table.insert(creature_coords_cache[creature_id], {final_x, final_y, display_zone_for_units_lua, creature_respawn_time})
                end
            end
            collectgarbage("collect")  -- Memory cleanup between chunks
        end
    end
    print("  Pass 2a complete: Cached coordinates for " .. #all_creature_ids .. " creatures")

    -- DIAGNOSTIC: Check if cache was populated correctly
    local cache_entries = 0
    local total_coords = 0
    for creature_id, coords_list in pairs(creature_coords_cache) do
        cache_entries = cache_entries + 1
        total_coords = total_coords + #coords_list
    end
    print("  DIAGNOSTIC: creature_coords_cache has " .. cache_entries .. " entries with " .. total_coords .. " total coordinates")

    -- MEMORY OPTIMIZATION: Force garbage collection after batch loading
    collectgarbage("collect")
--     print("  Memory after batch loading: " .. math.floor(collectgarbage("count")) .. " KB")

    -- STEP 3/3: Pass 2b - Original processing (now using cached coordinate data)
    print("  Pass 2b: Processing creature templates with cached coordinates...")
    local processed = 0
    local creature_template = {}

    local template_query = mysql:execute('SELECT * FROM creature_template' .. where_clause .. ' GROUP BY creature_template.entry ORDER BY creature_template.entry' .. limit_clause)
    while template_query:fetch(creature_template, "a") do
      if debug("units") then break end
      processed = processed + 1

      -- Show progress every 1000 creatures
      if processed % 1000 == 0 then
        print("  Processed " .. processed .. "/" .. #all_creature_ids .. " creatures (" .. math.floor(processed/#all_creature_ids*100) .. "%)")
        -- MEMORY OPTIMIZATION: Force garbage collection every 1000 creatures
        collectgarbage("collect")
--         print("    Memory after GC: " .. math.floor(collectgarbage("count")) .. " KB")
      end

      local entry   = tonumber(creature_template[C.Entry])
      local name    = creature_template[C.Name]
      local minlvl  = tonumber(creature_template[C.MinLevel]) or 1
      local maxlvl  = tonumber(creature_template[C.MaxLevel]) or minlvl or 1
      local rnk     = tonumber(creature_template[C.Rank]) or 0
      local lvl     = (minlvl == maxlvl) and tostring(minlvl) or tostring(minlvl) .. "-" .. tostring(maxlvl)

      pfDB["units"][data][entry] = {}
      pfDB["units"][data][entry]["lvl"] = lvl
      if tonumber(rnk) > 0 then
        pfDB["units"][data][entry]["rnk"] = rnk
      end

      do -- detect faction
        local fac = ""
        local faction = {}
        local sql = [[
          SELECT A, H FROM creature_template, pfquest.factiontemplate_wotlk
          WHERE pfquest.factiontemplate_wotlk.factiontemplateID = creature_template.]] .. C.Faction .. [[
          AND creature_template.]] .. C.Entry .. [[ = ]] .. creature_template[C.Entry] .. [[
        ]]

        local query = mysql:execute(sql)
        if query then
          while query:fetch(faction, "a") do
            if debug("units_faction") then break end
            local A, H = faction.A, faction.H
            if A == "1" and not string.find(fac, "A") then fac = fac .. "A" end
            if H == "1" and not string.find(fac, "H") then fac = fac .. "H" end
          end
        end

        if fac ~= "" then
          pfDB["units"][data][entry]["fac"] = fac
        end
      end

      do -- coordinates
        pfDB["units"][data][entry]["coords"] = {}

        -- USE BATCH DATA - MAJOR OPTIMIZATION! (eliminates 46k+ individual queries!)
        if creature_coords_cache[entry] then
            for _, coords in ipairs(creature_coords_cache[entry]) do
                if debug("units_coords") then break end
                table.insert(pfDB["units"][data][entry]["coords"], coords)
            end
            -- MEMORY OPTIMIZATION: Clear processed data immediately to free memory
            creature_coords_cache[entry] = nil
        end

        if core ~= "vmangos" then
          for id, coords in pairs(GetCreatureCoordsPool(entry)) do
            local x, y, zone, respawn = unpack(coords)
            if debug("units_coords_pool") then break end
            table.insert(pfDB["units"][data][entry]["coords"], { x, y, zone, respawn })
          end
        end

        -- search for Event summons (fixed position) - DISABLED for AzerothCore compatibility
        -- [Gazban:2624, Maraudine Khan Guard:6069, Echeyakee:3475]
        if core ~= "acore" then
          local dbscripts_on_event = {}
          local query = mysql:execute('SELECT id as event, x as x, y as y FROM '..C.dbscripts_on_event..' WHERE command = 10 AND datalong = ' .. entry)
          while query:fetch(dbscripts_on_event, "a") do
            if debug("units_event") then break end
            local event = tonumber(dbscripts_on_event.event)
            local x = tonumber(dbscripts_on_event.x)
            local y = tonumber(dbscripts_on_event.y)
            local map = nil

            -- guess map based on gameobject relation
            -- [Gazban:2624]
            local map_object = {}
            local query = mysql:execute([[
              SELECT map AS map FROM gameobject_template, gameobject
              WHERE gameobject_template.type = 10
                AND gameobject_template.data2 = ]]..event..[[
                AND gameobject.id = gameobject_template.entry
              GROUP BY gameobject.map
            ]])
            while query:fetch(map_object, "a") do
              if debug("units_event_map_object") then break end
              map = map or tonumber(map_object.map)
            end

            -- guess map based on spell relation
            local spell_template = {}
            local query = mysql:execute([[
              SELECT ]]..C.Id..[[ AS spell, ]]..C.RequiresSpellFocus..[[ AS focus FROM ]]..C.spell_template..[[
              WHERE ( EffectMiscValue1 = ]]..event..[[ AND effect1 = 61 )
                 OR ( EffectMiscValue2 = ]]..event..[[ AND effect2 = 61 )
                 OR ( EffectMiscValue3 = ]]..event..[[ AND effect3 = 61 )
            ]])
            while query:fetch(spell_template, "a") do
              if debug("units_event_spell") then break end
              local spell = tonumber(spell_template.spell)
              local focus = tonumber(spell_template.focus)

              -- guess map based on gameobject target
              -- [Echeyakee:3475]
              local gameobject_template = {}
              local query = mysql:execute([[
                SELECT map as map FROM gameobject_template, gameobject
                WHERE gameobject.id = gameobject_template.entry
                  AND gameobject_template.data0 > 0
                  AND gameobject_template.type = 8
                  AND gameobject_template.data0 = ]]..focus..[[
                GROUP BY map
              ]])
              while query:fetch(gameobject_template, "a") do
                if debug("units_event_spell_map_object") then break end
                map = map or tonumber(gameobject_template.map)
              end

              -- guess map based on item map/area bond
              -- [Maraudine Khan Guard:6069]
              local item_template = {}
              local query = mysql:execute([[
                SELECT ]]..C.Map..[[ as map FROM item_template
                WHERE spelltrigger_1 = 0 AND spellid_1 = ]]..spell..[[
                GROUP BY map
              ]])
              while query:fetch(item_template, "a") do
                if debug("units_event_spell_map_item") then break end
                -- Zul'Farrak Executioner Key is not bound to map.
                -- Ignoring its unlocking spell that spawns sandfuries.
                if spell == 10738 then break end
                map = map or tonumber(item_template.map)
              end
            end

            if map then -- in case we found a map, add the coordinates
              for id, coords in pairs(GetCustomCoords(map, x, y)) do
                local x, y, zone, respawn = unpack(coords)
                table.insert(pfDB["units"][data][entry]["coords"], { x, y, zone, respawn })
              end
            end
          end
        end

        -- search for AI summons (fixed position) - DISABLED for AzerothCore compatibility
        -- [Verog Derwisch:3395]
        if core ~= "acore" then
          local creature_ai_scripts = {}
          local sql = core == "vmangos" and [[
            SELECT creature.map AS map, x AS x, y AS y FROM creature_ai_scripts, creature_ai_events, creature
            WHERE creature.id = creature_ai_events.creature_id
              AND creature_ai_scripts.command = 10
              AND creature_ai_scripts.id = creature_ai_events.id
              AND creature_ai_scripts.datalong = ]]..entry..[[
              AND x != 0 AND y != 0
            GROUP BY map
          ]] or [[
            SELECT creature.map as map, creature_ai_summons.position_x AS x, creature_ai_summons.position_y AS y FROM creature_ai_scripts
            LEFT JOIN creature_ai_summons ON creature_ai_scripts.action2_type = 32 AND creature_ai_scripts.action2_param3 = creature_ai_summons.id
            LEFT JOIN creature ON creature_ai_scripts.creature_id = creature.id
            WHERE action2_type = 32
              AND action2_param1 = ]]..entry..[[
            GROUP BY map
          ]]

          print("DEBUG: Executing AI summons query for entry " .. entry .. " with core " .. core)
          local query = mysql:execute(sql)
          if query then
            while query:fetch(creature_ai_scripts, "a") do
              if debug("units_summon_fixed") then break end
              for id, coords in pairs(GetCustomCoords(tonumber(creature_ai_scripts.map), tonumber(creature_ai_scripts.x), tonumber(creature_ai_scripts.y))) do
                local x, y, zone, respawn = unpack(coords)
                table.insert(pfDB["units"][data][entry]["coords"], { x, y, zone, respawn })
              end
            end
          else
            print("DEBUG: AI summons query failed for entry " .. entry)
          end
        else
          -- Skip AI summons for AzerothCore (no debug message needed)
        end

        -- search for AI summons (summoner position) - DISABLED for AzerothCore compatibility
        -- [Darrowshire Spirit:11064]
        if core ~= "acore" then
          local creature_ai_scripts = {}
          local query = mysql:execute(core == "vmangos" and [[
            SELECT creature_ai_events.creature_id AS summoner FROM creature_ai_scripts, creature_ai_events
            WHERE creature_ai_scripts.command = 10
              AND creature_ai_scripts.id = creature_ai_events.id
              AND creature_ai_scripts.datalong = ]]..entry..[[
              AND x = 0 AND y = 0
          ]] or [[
            SELECT creature_id AS summoner FROM ]]..C.spell_template..[[
            LEFT JOIN creature_ai_scripts ON action1_type = 11 AND action1_param1 = ]]..C.spell_template..[[.]]..C.Id..[[
            WHERE ]]..C.spell_template..[[.Effect1 = 28 AND creature_id > 0 AND ]]..C.spell_template..[[.EffectMiscValue1 = ]]..entry..[[
          ]])
          if query then
            while query:fetch(creature_ai_scripts, "a") do
              if debug("units_summon_unknown") then break end
              for id, coords in pairs(GetCreatureCoords(tonumber(creature_ai_scripts.summoner))) do
                local x, y, zone, respawn = unpack(coords)
                table.insert(pfDB["units"][data][entry]["coords"], { x, y, zone, respawn })
              end

              if core ~= "vmangos" then
                for id, coords in pairs(GetCreatureCoordsPool(tonumber(creature_ai_scripts.summoner))) do
                  local x, y, zone, respawn = unpack(coords)
                  table.insert(pfDB["units"][data][entry]["coords"], { x, y, zone, respawn })
                end
              end
            end
          end
        end

        -- clear duplicates
        pfDB["units"][data][entry]["coords"] = removedupes(pfDB["units"][data][entry]["coords"])
      end
    end

    do -- Patch creature table with manual entries
      -- Only use this method of adding creatures if there is REALLY no way
      -- to extract data out of the databases of the mangos cores. If the list
      -- becomes too big, this should be separated to another file.
      pfDB["units"][data][420] = {
        ["coords"] = { [1] = { 69, 21, 148, 300 } },
        ["fac"] = "H", ["lvl"] = "60",
      }

      do -- Sentinel Selarin:3694
        -- taken from https://classic.wowhead.com/npc=3694/sentinel-selarin
        if pfDB["units"][data][3694] then
          pfDB["units"][data][3694]["coords"] = { [1] = { 39.2, 43.4, 42, 0 } }
        end
      end

      do -- Mokk the Savage:1514
        -- taken from https://classic.wowhead.com/npc=1514/mokk-the-savage
        if pfDB["units"][data][1514] then
          pfDB["units"][data][1514]["coords"] = { [1] = { 35.2, 60.4, 33, 0 } }
        end
      end
    end
    local end_time_units = os.clock()
    if pfDB and pfDB["units"] then
      table.insert(execution_times, {name = "units", time = end_time_units - start_time_units})
    end
    -- FINAL MEMORY CLEANUP: Clear all creature cache data
    creature_coords_cache = nil
    all_creature_ids = nil
    -- Clear continental zones cache as coordinate processing is done
    continental_zones_cache = nil
    continental_zones_loaded = false
    collectgarbage("collect")
    collectgarbage("collect")
    print("  Memory cleanup after units: " .. math.floor(collectgarbage("count")) .. " KB")
  end

  local start_time_objects = os.clock()
  do -- objects
    print("- loading objects...")

    pfDB["objects"] = pfDB["objects"] or {}
    pfDB["objects"][data] = {}

    -- Count total objects first
    local count_query = mysql:execute('SELECT COUNT(*) as total FROM gameobject_template')
    local count_result = {}
    count_query:fetch(count_result, "a")
    local total_objects = tonumber(count_result.total) or 0
    print("  Processing " .. total_objects .. " objects...")

    -- STEP 1/3: Pass 1 - Collect all object entry IDs first
    local gameobject_template = {}
    local limit_clause = ""
    local where_clause = ""

    -- QUEST 784 DEBUG MODE - фильтруем только нужные объекты
    if QUEST_784_TEST then
      local object_list = table.concat(QUEST_784_OBJECTS, ",")
      where_clause = " WHERE entry IN (" .. object_list .. ") "
      print("🎯 QUEST 784 DEBUG: Processing only Objects " .. object_list)
    else
      limit_clause = (DEBUG_EXTRACTION and not FULL_EXTRACTION) and (' LIMIT ' .. OBJECTS_LIMIT) or ''
    end

    print("  Pass 1: Collecting all object entry IDs...")
    local all_object_ids = {}
    local pass1_query = mysql:execute('SELECT entry FROM gameobject_template' .. where_clause .. ' ORDER BY entry ASC' .. limit_clause)
    if pass1_query then
      local temp_object = {}
      while pass1_query:fetch(temp_object, "a") do
        if debug("objects_pass1") then break end
        table.insert(all_object_ids, tonumber(temp_object.entry))
      end
    end
    print("  Pass 1 complete: Collected " .. #all_object_ids .. " object IDs for batch processing")

    -- STEP 2/3: Pass 2a - Batch load all gameobject coordinates with proper conversion
    print("  Pass 2a: Batch loading gameobject coordinates...")
    local gameobject_coords_cache = {}

    if #all_object_ids > 0 then
        local chunk_size = 5000  -- Process 5000 objects at a time for optimal performance
        local total_chunks = math.ceil(#all_object_ids / chunk_size)
        local coords_loaded = 0

        for chunk = 1, total_chunks do
            local start_idx = (chunk - 1) * chunk_size + 1
            local end_idx = math.min(chunk * chunk_size, #all_object_ids)
            local chunk_ids = {}
            for i = start_idx, end_idx do
                table.insert(chunk_ids, all_object_ids[i])
            end
            local object_ids_string = table.concat(chunk_ids, ",")

            print("  Processing coordinate chunk " .. chunk .. "/" .. total_chunks .. " (" .. #chunk_ids .. " objects)")
            local batch_coords_query = mysql:execute("SELECT id, map, position_x, position_y, zoneId, areaId, spawntimesecs FROM gameobject WHERE id IN (" .. object_ids_string .. ") ORDER BY id, map")

            if batch_coords_query then
                local coord_data = {}
        while batch_coords_query:fetch(coord_data, "a") do
          if debug("objects_batch_coords") then break end

          local object_id = tonumber(coord_data.id)
          local map_id = tonumber(coord_data.map)
          local world_x = tonumber(coord_data.position_x)
          local world_y = tonumber(coord_data.position_y)
          local db_zoneId = tonumber(coord_data.zoneId)
          local db_areaId = tonumber(coord_data.areaId)
          local respawn = tonumber(coord_data.spawntimesecs)

          -- Use NormalizeDisplayZone for proper zone detection (same as units - with cached IsContinentalZone)
          local display_map_areatable_id = NormalizeDisplayZone(db_zoneId, map_id, world_x, world_y)

          -- Final fallback
          if not display_map_areatable_id or display_map_areatable_id == 0 then
            display_map_areatable_id = db_zoneId
          end

          local zone_x = 50  -- Default coordinates same as GetGameObjectCoords
          local zone_y = 50

          -- Convert world coordinates to zone coordinates (same as GetGameObjectCoords)
          local zone_bounds = GetWorldMapAreaBoundariesForZone(display_map_areatable_id, map_id)
          if world_x and world_y and zone_bounds then
            local Z_WorldX_L = zone_bounds.x_left
            local Z_WorldX_R = zone_bounds.x_right
            local Z_WorldY_T = zone_bounds.y_top
            local Z_WorldY_B = zone_bounds.y_bottom

            local zone_map_world_width = Z_WorldX_R - Z_WorldX_L
            local zone_map_world_height = Z_WorldY_T - Z_WorldY_B

            if zone_map_world_width > 0 and zone_map_world_height > 0 then
              local pfQuest_X_pct = ((Z_WorldY_T - world_y) / zone_map_world_height) * 100
              local pfQuest_Y_pct = 100 - (((world_x - Z_WorldX_L) / zone_map_world_width) * 100)

              zone_x = pfQuest_X_pct
              zone_y = pfQuest_Y_pct

              -- Clamp coordinates to 0-100 range
              zone_x = math.max(0, math.min(100, zone_x))
              zone_y = math.max(0, math.min(100, zone_y))

              -- Round to 2 decimal places for consistency with original output
              zone_x = math.floor(zone_x * 100 + 0.5) / 100
              zone_y = math.floor(zone_y * 100 + 0.5) / 100
            end
          end

          if not gameobject_coords_cache[object_id] then
            gameobject_coords_cache[object_id] = {}
          end

          table.insert(gameobject_coords_cache[object_id], {zone_x, zone_y, display_map_areatable_id, respawn})
          coords_loaded = coords_loaded + 1
        end
            end
            collectgarbage("collect")  -- Memory cleanup between chunks
        end
    end
    print("  Pass 2a complete: Cached coordinates for " .. #all_object_ids .. " objects")

    -- DIAGNOSTIC: Check if cache was populated correctly
    local cache_entries = 0
    local total_coords = 0
    for object_id, coords_list in pairs(gameobject_coords_cache) do
        cache_entries = cache_entries + 1
        total_coords = total_coords + #coords_list
    end
    print("  DIAGNOSTIC: gameobject_coords_cache has " .. cache_entries .. " entries with " .. total_coords .. " total coordinates")

    -- MEMORY OPTIMIZATION: Force garbage collection after batch loading
    collectgarbage("collect")

    -- Pass 2a2: Batch load faction data for all objects
    print("  Pass 2a2: Batch loading faction data for objects...")
    local gameobject_faction_cache = {}

    if #all_object_ids > 0 then
        local chunk_size = 1000  -- Process 1000 objects at a time for faction data
        local total_chunks = math.ceil(#all_object_ids / chunk_size)

        for chunk = 1, total_chunks do
            local start_idx = (chunk - 1) * chunk_size + 1
            local end_idx = math.min(chunk * chunk_size, #all_object_ids)
            local chunk_ids = {}
            for i = start_idx, end_idx do
                table.insert(chunk_ids, all_object_ids[i])
            end
            local object_ids_string = table.concat(chunk_ids, ",")

            print("  Processing faction chunk " .. chunk .. "/" .. total_chunks .. " (" .. #chunk_ids .. " objects)")

            -- Try modern schema first (gameobject_template_addon)
            local batch_faction_query = mysql:execute([[
                SELECT gta.entry, f.A, f.H FROM gameobject_template_addon gta
                JOIN pfquest.factiontemplate_wotlk f ON f.factiontemplateID = gta.faction
                WHERE gta.entry IN (]] .. object_ids_string .. [[) AND gta.faction > 0
            ]])

            if batch_faction_query then
                local faction_data = {}
                while batch_faction_query:fetch(faction_data, "a") do
                    local object_id = tonumber(faction_data.entry)
                    local A, H = faction_data.A, faction_data.H
                    local fac = ""
                    if A == "1" then fac = fac .. "A" end
                    if H == "1" then fac = fac .. "H" end
                    if fac ~= "" then
                        gameobject_faction_cache[object_id] = fac
                    end
                end
            end

            -- Fallback to legacy schema for objects without faction
            local missing_faction_ids = {}
            for _, object_id in ipairs(chunk_ids) do
                if not gameobject_faction_cache[object_id] then
                    table.insert(missing_faction_ids, object_id)
                end
            end

            if #missing_faction_ids > 0 then
                local missing_ids_string = table.concat(missing_faction_ids, ",")
                local legacy_faction_query = mysql:execute([[
                    SELECT gt.entry, f.A, f.H FROM gameobject_template gt
                    JOIN pfquest.factiontemplate_wotlk f ON f.factiontemplateID = gt.faction
                    WHERE gt.entry IN (]] .. missing_ids_string .. [[) AND gt.faction > 0
                ]])

                if legacy_faction_query then
                    local faction_data = {}
                    while legacy_faction_query:fetch(faction_data, "a") do
                        local object_id = tonumber(faction_data.entry)
                        local A, H = faction_data.A, faction_data.H
                        local fac = ""
                        if A == "1" then fac = fac .. "A" end
                        if H == "1" then fac = fac .. "H" end
                        if fac ~= "" then
                            gameobject_faction_cache[object_id] = fac
                        end
                    end
                end
            end

            collectgarbage("collect")  -- Memory cleanup between chunks
        end
    end
    print("  Pass 2a2 complete: Cached faction data for " .. #all_object_ids .. " objects")

    -- Pass 2a3: Quest-based faction inference for objects without direct faction
    print("  Pass 2a3: Inferring faction from quest requirements...")
    local objects_without_faction = {}

    -- Collect objects that don't have faction from direct lookup
    for _, object_id in ipairs(all_object_ids) do
        if not gameobject_faction_cache[object_id] then
            table.insert(objects_without_faction, object_id)
        end
    end

    if #objects_without_faction > 0 then
        print("  Found " .. #objects_without_faction .. " objects without direct faction, checking quest requirements...")

        -- Process in chunks to avoid too large SQL queries
        local quest_chunk_size = 1000
        local total_quest_chunks = math.ceil(#objects_without_faction / quest_chunk_size)

        for chunk = 1, total_quest_chunks do
            local start_idx = (chunk - 1) * quest_chunk_size + 1
            local end_idx = math.min(chunk * quest_chunk_size, #objects_without_faction)
            local chunk_ids = {}
            for i = start_idx, end_idx do
                table.insert(chunk_ids, objects_without_faction[i])
            end
            local object_ids_string = table.concat(chunk_ids, ",")

            print("  Processing quest faction chunk " .. chunk .. "/" .. total_quest_chunks .. " (" .. #chunk_ids .. " objects)")

            -- Alliance & Horde race bitmasks (WotLK)
            local RACE_MASK_ALLIANCE = 1101  -- Human(1) + NightElf(4) + Gnome(64) + Draenei(1024) + Dwarf(8) = 1 + 4 + 8 + 64 + 1024 = 1101
            local RACE_MASK_HORDE = 690      -- Orc(2) + Undead(16) + Tauren(32) + Troll(128) + BloodElf(512) = 2 + 16 + 32 + 128 + 512 = 690

            -- Use correct primary key column based on core type
            local quest_pk_column = (core == "acore" and "ID" or "entry")

            local quest_faction_query = mysql:execute([[
                SELECT ABS(obj_id) AS object_entry,
                       BIT_OR(AllowableRaces & ]] .. RACE_MASK_ALLIANCE .. [[) AS hasA,
                       BIT_OR(AllowableRaces & ]] .. RACE_MASK_HORDE .. [[) AS hasH
                FROM (
                    SELECT ]] .. quest_pk_column .. [[, RequiredNpcOrGo1 AS obj_id, AllowableRaces FROM quest_template
                    WHERE RequiredNpcOrGo1 != 0
                    UNION ALL
                    SELECT ]] .. quest_pk_column .. [[, RequiredNpcOrGo2 AS obj_id, AllowableRaces FROM quest_template
                    WHERE RequiredNpcOrGo2 != 0
                    UNION ALL
                    SELECT ]] .. quest_pk_column .. [[, RequiredNpcOrGo3 AS obj_id, AllowableRaces FROM quest_template
                    WHERE RequiredNpcOrGo3 != 0
                    UNION ALL
                    SELECT ]] .. quest_pk_column .. [[, RequiredNpcOrGo4 AS obj_id, AllowableRaces FROM quest_template
                    WHERE RequiredNpcOrGo4 != 0
                ) q
                WHERE ABS(obj_id) IN (]] .. object_ids_string .. [[)
                GROUP BY object_entry
                HAVING object_entry > 0
            ]])

            if quest_faction_query then
                local quest_data = {}
                while quest_faction_query:fetch(quest_data, "a") do
                    local object_id = tonumber(quest_data.object_entry)
                    local hasA = tonumber(quest_data.hasA) or 0
                    local hasH = tonumber(quest_data.hasH) or 0

                    if object_id and object_id > 0 then
                        local fac = ""
                        -- Only assign faction if quests are clearly faction-specific
                        if hasA > 0 and hasH == 0 then
                            fac = "A"  -- Alliance only
                        elseif hasH > 0 and hasA == 0 then
                            fac = "H"  -- Horde only
                        end
                        -- If both or neither, leave empty (neutral/both factions)

                        if fac ~= "" then
                            gameobject_faction_cache[object_id] = fac
                        end
                    end
                end
            end

            collectgarbage("collect")  -- Memory cleanup between chunks
        end
    end
    print("  Pass 2a3 complete: Quest-based faction inference finished")

    -- Pass 2b: Original processing (now optimized with pre-loaded coordinate and faction data)
    local processed = 0
    local query = mysql:execute('SELECT * FROM gameobject_template' .. where_clause .. ' ORDER BY gameobject_template.entry ASC' .. limit_clause)
    if query then
      while query:fetch(gameobject_template, "a") do
      if debug("objects") then break end
      processed = processed + 1

      -- Show progress every 1000 objects
      if processed % 1000 == 0 then
        print("  Processed " .. processed .. "/" .. #all_object_ids .. " objects (" .. math.floor(processed/#all_object_ids*100) .. "%)")
        -- MEMORY OPTIMIZATION: Force garbage collection every 1000 objects
        collectgarbage("collect")
      end

      local entry  = tonumber(gameobject_template.entry)
      local name   = gameobject_template.name

      pfDB["objects"][data][entry] = {}

      do -- detect faction - USE CACHED DATA
        local fac = gameobject_faction_cache[entry] or ""
        if fac ~= "" then
          pfDB["objects"][data][entry]["fac"] = fac
        end
      end

      do -- coordinates - STEP 3/3: Use pre-loaded coordinate data
        pfDB["objects"][data][entry]["coords"] = {}

        -- USE BATCH DATA - MAJOR OPTIMIZATION! (eliminates individual GetGameObjectCoords calls!)
        if gameobject_coords_cache[entry] then
          for _, coords in ipairs(gameobject_coords_cache[entry]) do
            if debug("objects_coords") then break end
            table.insert(pfDB["objects"][data][entry]["coords"], coords)
          end
          -- MEMORY OPTIMIZATION: Clear processed data immediately to free memory
          gameobject_coords_cache[entry] = nil
        end
      end

        -- clear duplicates
        pfDB["objects"][data][entry]["coords"] = removedupes(pfDB["objects"][data][entry]["coords"])
      end
    end
    local end_time_objects = os.clock()
    if pfDB and pfDB["objects"] then
      table.insert(execution_times, {name = "objects", time = end_time_objects - start_time_objects})
    end
    -- FINAL MEMORY CLEANUP: Clear all object cache data
    gameobject_coords_cache = nil
    all_object_ids = nil
    collectgarbage("collect")
    collectgarbage("collect")
    print("  Memory cleanup after objects: " .. math.floor(collectgarbage("count")) .. " KB")
  end

  local start_time_items = os.clock()
  do -- items
    print("- loading items...")

    pfDB["items"] = pfDB["items"] or {}
    pfDB["items"][data] = {}

    -- Get total count for progress tracking
    local total_items = 0
    local count_where_clause = ""
    if QUEST_784_TEST then
      local item_list = table.concat(QUEST_784_ITEMS, ",")
      count_where_clause = " WHERE entry IN (" .. item_list .. ") "
    end
    local count_query = mysql:execute('SELECT COUNT(*) as total FROM item_template' .. count_where_clause)
    if count_query then
      local count_result = {}
      count_query:fetch(count_result, "a")
      total_items = tonumber(count_result.total) or 0
    end
    print("Processing " .. total_items .. " items...")

    -- STEP 1/3: Pass 1 - Collect all item IDs first
    local item_template = {}
    local limit_clause = ITEMS_LIMIT and (' LIMIT ' .. ITEMS_LIMIT) or ''
    local where_clause = ""

    -- QUEST 784 DEBUG MODE - фильтруем только нужные предметы
    if QUEST_784_TEST then
      local item_list = table.concat(QUEST_784_ITEMS, ",")
      where_clause = " WHERE entry IN (" .. item_list .. ") "
      print("🎯 QUEST 784 DEBUG: Processing only items " .. item_list)
    end

    print("  Pass 1: Collecting all item IDs...")
    local all_item_ids = {}
    local pass1_query = mysql:execute('SELECT entry FROM item_template' .. where_clause .. ' ORDER BY entry ASC' .. limit_clause)
    if pass1_query then
      local temp_item = {}
      while pass1_query:fetch(temp_item, "a") do
        if debug("items_pass1") then break end
        table.insert(all_item_ids, tonumber(temp_item.entry))
      end
    end
    print("  Pass 1 complete: Collected " .. #all_item_ids .. " item IDs for batch processing")

    -- STEP 2/3: Pass 2a - Batch load all relationships
    local creature_loot_data = {}      -- item_id -> {creature1, creature2, ...}
    local object_loot_data = {}        -- item_id -> {object1, object2, ...}
    local reference_loot_data = {}     -- item_id -> {ref1, ref2, ...}
    local vendor_data = {}             -- item_id -> {vendor1, vendor2, ...}
    local vendor_template_data = {}    -- item_id -> {vendor1, vendor2, ...}
    local item_loot_data = {}          -- item_id -> {container1, container2, ...}
    local gameobject_loot_data = {}    -- item_id -> {gameobject1, gameobject2, ...}

    if #all_item_ids > 0 then
      print("  Pass 2a: Batch loading relationships for " .. #all_item_ids .. " items...")

      -- Optimized chunked processing to avoid huge IN clauses
      local chunk_size = 2000  -- Process 2000 items at a time for optimal performance
      local total_chunks = math.ceil(#all_item_ids / chunk_size)

      -- Batch load creature drops (chunked)
      print("    Loading creature drops...")
      for chunk = 1, total_chunks do
        local start_idx = (chunk - 1) * chunk_size + 1
        local end_idx = math.min(chunk * chunk_size, #all_item_ids)
        local chunk_ids = {}
        for i = start_idx, end_idx do
          table.insert(chunk_ids, all_item_ids[i])
        end
        local item_ids_string = table.concat(chunk_ids, ",")

        local batch_query = mysql:execute("SELECT Entry, Item, Chance FROM creature_loot_template WHERE Item IN (" .. item_ids_string .. ") AND Reference = 0 ORDER BY Item, Entry")
        if batch_query then
          local temp_data = {}
          while batch_query:fetch(temp_data, "a") do
            if debug("items_creature_batch") then break end
            local item_id = tonumber(temp_data.Item)
            local creature_id = tonumber(temp_data.Entry)
            local chance = math.abs(tonumber(temp_data.Chance) or 0)

            if chance > 0 then
              creature_loot_data[item_id] = creature_loot_data[item_id] or {}
              table.insert(creature_loot_data[item_id], {entry = creature_id, chance = chance})
            end
          end
        end
        collectgarbage("collect")  -- Memory cleanup between chunks
      end

      -- Batch load reference loot (chunked)
      print("    Loading reference loot...")
      for chunk = 1, total_chunks do
        local start_idx = (chunk - 1) * chunk_size + 1
        local end_idx = math.min(chunk * chunk_size, #all_item_ids)
        local chunk_ids = {}
        for i = start_idx, end_idx do
          table.insert(chunk_ids, all_item_ids[i])
        end
        local item_ids_string = table.concat(chunk_ids, ",")

        local batch_query = mysql:execute("SELECT entry, item, Chance FROM reference_loot_template WHERE item IN (" .. item_ids_string .. ") ORDER BY item, entry")
        if batch_query then
          local temp_data = {}
          while batch_query:fetch(temp_data, "a") do
            if debug("items_reference_batch") then break end
            local item_id = tonumber(temp_data.item)
            local ref_id = tonumber(temp_data.entry)
            local chance = math.abs(tonumber(temp_data.Chance) or 0)

            reference_loot_data[item_id] = reference_loot_data[item_id] or {}
            table.insert(reference_loot_data[item_id], {entry = ref_id, chance = chance})
          end
        end
        collectgarbage("collect")
      end

      -- Batch load vendors (chunked)
      print("    Loading vendors...")
      for chunk = 1, total_chunks do
        local start_idx = (chunk - 1) * chunk_size + 1
        local end_idx = math.min(chunk * chunk_size, #all_item_ids)
        local chunk_ids = {}
        for i = start_idx, end_idx do
          table.insert(chunk_ids, all_item_ids[i])
        end
        local item_ids_string = table.concat(chunk_ids, ",")

        local batch_query = mysql:execute("SELECT entry, item, maxcount FROM npc_vendor WHERE item IN (" .. item_ids_string .. ") ORDER BY item, entry")
        if batch_query then
          local temp_data = {}
          while batch_query:fetch(temp_data, "a") do
            if debug("items_vendor_batch") then break end
            local item_id = tonumber(temp_data.item)
            local vendor_id = tonumber(temp_data.entry)
            local maxcount = tonumber(temp_data.maxcount)

            vendor_data[item_id] = vendor_data[item_id] or {}
            table.insert(vendor_data[item_id], {vendor = vendor_id, maxcount = maxcount})
          end
        end
        collectgarbage("collect")
      end

      -- Batch load item containers (item_loot_template) - this was the major bottleneck!
      print("    Loading item containers...")
      for chunk = 1, total_chunks do
        local start_idx = (chunk - 1) * chunk_size + 1
        local end_idx = math.min(chunk * chunk_size, #all_item_ids)
        local chunk_ids = {}
        for i = start_idx, end_idx do
          table.insert(chunk_ids, all_item_ids[i])
        end
        local item_ids_string = table.concat(chunk_ids, ",")

        local batch_query = mysql:execute("SELECT entry, item, ChanceOrQuestChance FROM item_loot_template WHERE item IN (" .. item_ids_string .. ") ORDER BY item, entry")
        if batch_query then
          local temp_data = {}
          while batch_query:fetch(temp_data, "a") do
            if debug("items_container_batch") then break end
            local item_id = tonumber(temp_data.item)
            local container_id = tonumber(temp_data.entry)
            local chance = math.abs(tonumber(temp_data.ChanceOrQuestChance) or 0)

            if chance > 0 then
              item_loot_data[item_id] = item_loot_data[item_id] or {}
              table.insert(item_loot_data[item_id], {entry = container_id, chance = chance})
            end
          end
        end
        collectgarbage("collect")
      end

      -- Batch load gameobject drops (another major bottleneck!)
      print("    Loading gameobject drops...")
      local chance_field = core == "acore" and "Chance" or "ChanceOrQuestChance"
      local item_field = core == "acore" and "Item" or "item"
      local loot_entry_field = core == "acore" and "Entry" or "entry"

      for chunk = 1, total_chunks do
        local start_idx = (chunk - 1) * chunk_size + 1
        local end_idx = math.min(chunk * chunk_size, #all_item_ids)
        local chunk_ids = {}
        for i = start_idx, end_idx do
          table.insert(chunk_ids, all_item_ids[i])
        end
        local item_ids_string = table.concat(chunk_ids, ",")

        local sql_query = "SELECT gameobject_template.entry, gameobject_loot_template." .. chance_field .. " as chance_value, gameobject_loot_template." .. item_field .. " as item_id FROM gameobject_loot_template INNER JOIN gameobject_template ON gameobject_template.data1 = gameobject_loot_template." .. loot_entry_field .. " WHERE (gameobject_template.type = 3 OR gameobject_template.type = 25) AND gameobject_loot_template." .. item_field .. " IN (" .. item_ids_string .. ") ORDER BY gameobject_loot_template." .. item_field .. ", gameobject_template.entry"

        local batch_query = mysql:execute(sql_query)
        if batch_query then
          local temp_data = {}
          while batch_query:fetch(temp_data, "a") do
            if debug("items_gameobject_batch") then break end
            local item_id = tonumber(temp_data.item_id)
            local gameobject_id = tonumber(temp_data.entry)
            local chance = math.abs(tonumber(temp_data.chance_value) or 0)

            if chance > 0 then
              gameobject_loot_data[item_id] = gameobject_loot_data[item_id] or {}
              table.insert(gameobject_loot_data[item_id], {entry = gameobject_id, chance = chance})
            end
          end
        end
        collectgarbage("collect")
      end

      print("  Pass 2a complete: Batch data loaded")
    end

    -- Pass 2b: Original processing (will use batch data in step 3)
    local query = mysql:execute('SELECT entry, name FROM item_template' .. where_clause .. ' ORDER BY entry ASC' .. limit_clause)
    if query then
      local processed = 0
      while query:fetch(item_template, "a") do
        processed = processed + 1
        if processed % 1000 == 0 then
          print("  Processed " .. processed .. "/" .. total_items .. " items (" .. math.floor(processed/total_items*100) .. "%)")
        end
      if debug("items") then break end

      local entry = tonumber(item_template.entry)
      local scans = { [0] = { entry, nil } }

      -- add items that contain the actual item to the itemlist (USE BATCH DATA - MAJOR OPTIMIZATION!)
      if not item_template.entry then
        print("Warning: Skipping item with nil entry")
      else
        -- Use pre-loaded batch data instead of SQL query (eliminates 46k individual queries!)
        if item_loot_data[entry] then
          for _, container_info in ipairs(item_loot_data[entry]) do
            if debug("items_container") then break end
            local chance = container_info.chance
            chance = chance < 0.01 and round(chance, 5) or round(chance, 2)
            table.insert(scans, { container_info.entry, chance })
          end
        end
      end

      -- recursively read U, O, V, R blocks of the item
      for id, item in pairs(scans) do
        local entry = tonumber(item[1])
        local chance = item[2] and item[2] / 100 or 1
        pfDB["items"][data][entry] = pfDB["items"][data][entry] or {}

        -- fill unit table (STEP 3/3: Use batch data instead of SQL)
        if creature_loot_data[entry] then
          for _, creature_info in ipairs(creature_loot_data[entry]) do
            if debug("items_unit") then break end
            local final_chance = creature_info.chance * chance
            final_chance = final_chance < 0.01 and round(final_chance, 5) or round(final_chance, 2)

            if final_chance > 0 then
              pfDB["items"][data][entry]["U"] = pfDB["items"][data][entry]["U"] or {}
              pfDB["items"][data][entry]["U"][creature_info.entry] = final_chance
            end
          end
        end

        -- fill object table (USE BATCH DATA - ELIMINATES ANOTHER 46K QUERIES!)
        if gameobject_loot_data[entry] then
          for _, gameobject_info in ipairs(gameobject_loot_data[entry]) do
            if debug("items_object") then break end
            local final_chance = gameobject_info.chance * chance
            final_chance = final_chance < 0.01 and round(final_chance, 5) or round(final_chance, 2)

            if final_chance > 0 then
              pfDB["items"][data][entry]["O"] = pfDB["items"][data][entry]["O"] or {}
              pfDB["items"][data][entry]["O"][gameobject_info.entry] = final_chance
            end
          end
        end

        -- fill reference table (STEP 3/3: Use batch data instead of SQL)
        if reference_loot_data[entry] then
          for _, ref_info in ipairs(reference_loot_data[entry]) do
            if debug("items_reference") then break end
            local chance = ref_info.chance
            chance = chance < 0.01 and round(chance, 5) or round(chance, 2)

            pfDB["items"][data][entry]["R"] = pfDB["items"][data][entry]["R"] or {}
            pfDB["items"][data][entry]["R"][ref_info.entry] = chance
          end
        end

        -- fill vendor table (STEP 3/3: Use batch data instead of SQL)
        if vendor_data[entry] then
          for _, vendor_info in ipairs(vendor_data[entry]) do
            if debug("items_vendor") then break end
            pfDB["items"][data][entry]["V"] = pfDB["items"][data][entry]["V"] or {}
            pfDB["items"][data][entry]["V"][vendor_info.vendor] = vendor_info.maxcount
          end
        end

        -- handle vendor template tables (STEP 3/3: Use batch data instead of SQL)
        if vendor_template_data[entry] then
          for _, vendor_info in ipairs(vendor_template_data[entry]) do
            if debug("items_vendortemplate") then break end
            pfDB["items"][data][entry]["V"] = pfDB["items"][data][entry]["V"] or {}
            pfDB["items"][data][entry]["V"][vendor_info.vendor] = vendor_info.maxcount
          end
        end
      end
    end
    local end_time_items = os.clock()
    if pfDB and pfDB["items"] then
      table.insert(execution_times, {name = "items", time = end_time_items - start_time_items})
    end
    -- ДОБАВЬТЕ:
    collectgarbage("collect")
    print("  Memory cleanup after items: " .. math.floor(collectgarbage("count")) .. " KB")
  end

  local start_time_refloot = os.clock()
  do -- refloot
    print("- loading refloot...")

    pfDB["refloot"] = pfDB["refloot"] or {}
    pfDB["refloot"][data] = {}

    -- iterate over all reference loots (LIMITED FOR TESTING)
    local reference_loot_template = {}
    local limit_clause = REFLOOT_LIMIT and (' LIMIT ' .. REFLOOT_LIMIT) or ''
    local query = mysql:execute('SELECT Entry, Item, Chance FROM reference_loot_template ORDER BY Entry' .. limit_clause)
    if query then
      while query:fetch(reference_loot_template, "a") do
        if debug("refloot") then break end

        local entry = tonumber(reference_loot_template.Entry)
        local item = tonumber(reference_loot_template.Item)
        local chance = tonumber(reference_loot_template.Chance)

        if item and item > 0 then
          local chance_value = (chance and chance < 0.01) and round(chance, 5) or round(chance, 2)
          pfDB["refloot"][data][entry] = pfDB["refloot"][data][entry] or {}
          pfDB["refloot"][data][entry][item] = chance_value
        end
      end
    end

    -- Build reference usage maps
    local ref_to_creatures = {}
    local ref_to_objects = {}

    -- Map references to creatures
    local creature_ref_query = mysql:execute('SELECT Reference as ref_id, Entry as creature_id FROM creature_loot_template WHERE Reference > 0')
    if creature_ref_query then
      while creature_ref_query:fetch(reference_loot_template, "a") do
        if debug("refloot_unit") then break end
        local ref_id = tonumber(reference_loot_template.ref_id)
        local creature_id = tonumber(reference_loot_template.creature_id)

        if ref_id and creature_id then
          ref_to_creatures[ref_id] = ref_to_creatures[ref_id] or {}
          ref_to_creatures[ref_id][creature_id] = 1
        end
      end
    end

    -- Map references to gameobjects
    local object_ref_query = mysql:execute('SELECT Reference as ref_id, Entry as object_id FROM gameobject_loot_template WHERE Reference > 0')
    if object_ref_query then
      while object_ref_query:fetch(reference_loot_template, "a") do
        if debug("refloot_object") then break end
        local ref_id = tonumber(reference_loot_template.ref_id)
        local object_id = tonumber(reference_loot_template.object_id)

        if ref_id and object_id then
          ref_to_objects[ref_id] = ref_to_objects[ref_id] or {}
          ref_to_objects[ref_id][object_id] = 1
        end
      end
    end

    -- Add creature/object mappings to refloot entries
    for ref_entry, items in pairs(pfDB["refloot"][data]) do
      if type(items) == "table" then
        if ref_to_creatures[ref_entry] then
          pfDB["refloot"][data][ref_entry]["U"] = pfDB["refloot"][data][ref_entry]["U"] or {}
          for creature_id, _ in pairs(ref_to_creatures[ref_entry]) do
            pfDB["refloot"][data][ref_entry]["U"][creature_id] = 1
          end
        end

        if ref_to_objects[ref_entry] then
          pfDB["refloot"][data][ref_entry]["O"] = pfDB["refloot"][data][ref_entry]["O"] or {}
          for object_id, _ in pairs(ref_to_objects[ref_entry]) do
            pfDB["refloot"][data][ref_entry]["O"][object_id] = 1
          end
        end
      end
    end
    local end_time_refloot = os.clock()
    if pfDB and pfDB["refloot"] then
      table.insert(execution_times, {name = "refloot", time = end_time_refloot - start_time_refloot})
    end
    -- ДОБАВЬТЕ:
    collectgarbage("collect")
    print("  Memory cleanup after refloot: " .. math.floor(collectgarbage("count")) .. " KB")
  end

  -- ================================================================
  -- CLASS AND QUEST CHAIN HELPERS
  -- ================================================================

  -- Class masks for AllowableClasses field (WoW class bit flags)
  local CLASS_MASKS = {
    [1] = 1,     -- Warrior
    [2] = 2,     -- Paladin
    [3] = 4,     -- Hunter
    [4] = 8,     -- Rogue
    [5] = 16,    -- Priest
    [7] = 64,    -- Shaman
    [8] = 128,   -- Mage
    [9] = 256,   -- Warlock
    [11] = 1024, -- Druid
  }

  -- Check if bit is set using arithmetic (no bitop needed)
  local function isBitSet(N, B)
    return N % (B + B) >= B
  end

  -- Remove duplicates from table
  local function remove_duplicates_from_table(input_table)
    if not input_table then return {} end
    local seen = {}
    local result = {}
    for _, value in ipairs(input_table) do
      if not seen[value] then
        table.insert(result, value)
        seen[value] = true
      end
    end
    return result
  end

  -- Deep copy function for quest data
  local function deepCopy(original)
    local copy = {}
    for k, v in pairs(original) do
      if type(v) == "table" then
        copy[k] = deepCopy(v)
      else
        copy[k] = v
      end
    end
    return copy
  end

  local start_time_quests = os.clock()
  do -- quests
    print("- loading quests...")

    pfDB["quests"] = pfDB["quests"] or {}
    pfDB["quests"][data] = {}

    pfDB["quests-itemreq"] = pfDB["quests-itemreq"] or {}
    pfDB["quests-itemreq"][data] = {}

    -- AzerothCore-specific ItemReq extraction (execute ONCE before quest processing)
    local function extract_itemreq_azerothcore()
      if core ~= "acore" then
        return 0 -- Skip if not AzerothCore
      end

      print("  Extracting ItemReq for AzerothCore...")
      local extracted_count = 0

      -- Mechanism 1: NPC-targets via conditions (covers most cases)
      local npc_query = [[
        SELECT i.entry, i.spellid_1, c.ConditionValue2
        FROM item_template i
        JOIN conditions c ON c.SourceEntry = i.spellid_1
        WHERE i.class = 12 AND i.spellid_1 > 0
          AND c.SourceTypeOrReferenceId = 17
          AND c.ConditionTypeOrReference = 31
          AND c.ConditionValue1 = 3
      ]]

      local npc_result = mysql:execute(npc_query)
      if npc_result then
        local npc_row = {}
        while npc_result:fetch(npc_row) do
          local itemID = tonumber(npc_row[1])
          local spellID = tonumber(npc_row[2])
          local npcID = tonumber(npc_row[3])

          if itemID and spellID and npcID then
            pfDB["quests-itemreq"][data][itemID] = pfDB["quests-itemreq"][data][itemID] or {}
            pfDB["quests-itemreq"][data][itemID][npcID] = spellID
            extracted_count = extracted_count + 1
          end
        end
      end

      -- Mechanism 2: GameObject-targets via smart_scripts
      local go_query = [[
        SELECT i.entry, i.spellid_1, s.entryorguid
        FROM item_template i
        JOIN smart_scripts s ON s.event_param1 = i.spellid_1
        WHERE i.class = 12 AND i.spellid_1 > 0
          AND s.source_type = 1 AND s.event_type = 8
      ]]

      local go_result = mysql:execute(go_query)
      if go_result then
        local go_row = {}
        while go_result:fetch(go_row) do
          local itemID = tonumber(go_row[1])
          local spellID = tonumber(go_row[2])
          local goID = tonumber(go_row[3])

          if itemID and spellID and goID then
            pfDB["quests-itemreq"][data][itemID] = pfDB["quests-itemreq"][data][itemID] or {}
            pfDB["quests-itemreq"][data][itemID][-goID] = spellID  -- Negative for GameObjects
            extracted_count = extracted_count + 1
          end
        end
      end

      if extracted_count > 0 then
        print("    AzerothCore ItemReq: Found " .. extracted_count .. " item-target relationships")
      end

      return extracted_count
    end

    -- Execute AzerothCore ItemReq extraction once
    local azerothcore_itemreq_count = extract_itemreq_azerothcore()

    -- iterate over all quests (LIMITED FOR TESTING)
    local quest_template = {}
    local quest_pk_column = (core == "acore" and "ID" or "entry") -- Added for AzerothCore

    -- QUEST 784 DEBUG MODE - фильтруем только нужный квест
    local where_clause = ""
    local limit_clause = ""
    if QUEST_784_TEST then
      where_clause = " WHERE qt." .. quest_pk_column .. " IN (" .. table.concat(QUEST_784_IDS, ", ") .. ") "
      print("🎯 QUEST 784 DEBUG: Processing quests " .. table.concat(QUEST_784_IDS, ", "))
    else
      limit_clause = (DEBUG_EXTRACTION and not FULL_EXTRACTION) and (' LIMIT ' .. QUEST_LIMIT) or ''
    end

    local query_string = 'SELECT qt.*, qta.AllowableClasses, qta.PrevQuestID as AddonPrevQuestID, qta.NextQuestID as AddonNextQuestID, qta.ExclusiveGroup as AddonExclusiveGroup, qta.RequiredSkillID as AddonRequiredSkillID, qta.RequiredSkillPoints as AddonRequiredSkillPoints, qxp.Difficulty_3 as BaseQuestXP FROM quest_template qt LEFT JOIN quest_template_addon qta ON qt.' .. quest_pk_column .. ' = qta.ID LEFT JOIN questxp_dbc qxp ON qt.RewardXPDifficulty = qxp.ID' .. where_clause .. ' ORDER BY qt.' .. quest_pk_column .. limit_clause

    -- Count total quests first for progress
    local count_query = mysql:execute('SELECT COUNT(*) as total FROM quest_template qt LEFT JOIN quest_template_addon qta ON qt.' .. quest_pk_column .. ' = qta.ID LEFT JOIN questxp_dbc qxp ON qt.RewardXPDifficulty = qxp.ID' .. where_clause .. limit_clause)
    local count_result = {}
    count_query:fetch(count_result, "a")
    local total_quests = tonumber(count_result.total) or 0
    print("  Processing " .. total_quests .. " quests...")

    -- PASS 1: Collect all quest data and build chain relationship maps
    print("  Pass 1: Building quest chain maps...")
    local all_fetched_quests = {}
    local reward_next_leads_to_prev = {}
    local addon_next_leads_to_prev = {}
    local quest_has_addon_prev = {}

    local query = mysql:execute(query_string)
    if query then
      while query:fetch(quest_template, "a") do
        local current_id = tonumber(quest_template[quest_pk_column])
        local reward_next = tonumber(quest_template.RewardNextQuest)
        local addon_next = tonumber(quest_template.AddonNextQuestID)
        local addon_prev = tonumber(quest_template.AddonPrevQuestID)

        -- Store quest data for pass 2
        table.insert(all_fetched_quests, deepCopy(quest_template))

        -- Build chain relationship maps
        if reward_next and reward_next > 0 then
          reward_next_leads_to_prev[reward_next] = reward_next_leads_to_prev[reward_next] or {}
          table.insert(reward_next_leads_to_prev[reward_next], current_id)
        end
        if addon_next and addon_next > 0 then
          addon_next_leads_to_prev[addon_next] = addon_next_leads_to_prev[addon_next] or {}
          table.insert(addon_next_leads_to_prev[addon_next], current_id)
        end
        if addon_prev and addon_prev > 0 then
          quest_has_addon_prev[current_id] = addon_prev
        end
      end
    end

    -- PASS 2: Batch load quest relationships for optimization
    print("  Pass 2a: Batch loading quest relationships...")
    local quest_starters_creature = {}
    local quest_starters_object = {}
    local quest_starters_item = {}
    local quest_enders_creature = {}
    local quest_enders_object = {}

    -- Get all quest IDs for batch loading
    local all_quest_ids = {}
    for _, quest_data in ipairs(all_fetched_quests) do
      local quest_id = tonumber(quest_data[quest_pk_column])
      table.insert(all_quest_ids, quest_id)
    end

    if #all_quest_ids > 0 then
      local quest_ids_string = table.concat(all_quest_ids, ",")

      -- Debug: Check if quest 833 is in the batch
      local found_833 = false
      for _, id in ipairs(all_quest_ids) do
        if id == 833 then found_833 = true; break end
      end
--       print("DEBUG: Quest 833 found in all_quest_ids: " .. (found_833 and "YES" or "NO"))
--       print("DEBUG: Total quest IDs for batch: " .. #all_quest_ids)

      -- Batch load creature quest starters
      local starter_table = (core == "acore" and "creature_queststarter" or "creature_questrelation")
      local sql = "SELECT * FROM " .. starter_table .. " WHERE " .. starter_table .. ".quest IN (" .. quest_ids_string .. ")"
--       print("DEBUG: Batch SQL for starters: " .. string.sub(sql, 1, 100) .. "...")
      local query = mysql:execute(sql)
      if query then
        local row = {}
        while query:fetch(row, "a") do
          local quest_id = tonumber(row.quest)
          if quest_id == 833 then
--             print("DEBUG: Found quest 833 starter in batch: creature " .. row.id)
          end
          quest_starters_creature[quest_id] = quest_starters_creature[quest_id] or {}
          table.insert(quest_starters_creature[quest_id], tonumber(row.id))
        end
      end

      -- Batch load gameobject quest starters
      local go_starter_table = (core == "acore" and "gameobject_queststarter" or "gameobject_questrelation")
      sql = "SELECT * FROM " .. go_starter_table .. " WHERE " .. go_starter_table .. ".quest IN (" .. quest_ids_string .. ")"
      query = mysql:execute(sql)
      if query then
        local row = {}
        while query:fetch(row, "a") do
          local quest_id = tonumber(row.quest)
          quest_starters_object[quest_id] = quest_starters_object[quest_id] or {}
          table.insert(quest_starters_object[quest_id], tonumber(row.id))
        end
      end

      -- Batch load item quest starters
      sql = "SELECT entry as id, " .. C.startquest .. " as quest FROM item_template WHERE " .. C.startquest .. " IN (" .. quest_ids_string .. ")"
      query = mysql:execute(sql)
      if query then
        local row = {}
        while query:fetch(row, "a") do
          local quest_id = tonumber(row.quest)
          quest_starters_item[quest_id] = quest_starters_item[quest_id] or {}
          table.insert(quest_starters_item[quest_id], tonumber(row.id))
        end
      end

      -- Batch load creature quest enders
      local ender_table = (core == "acore" and "creature_questender" or "creature_involvedrelation")
      sql = "SELECT * FROM " .. ender_table .. " WHERE " .. ender_table .. ".quest IN (" .. quest_ids_string .. ")"
      query = mysql:execute(sql)
      if query then
        local row = {}
        while query:fetch(row, "a") do
          local quest_id = tonumber(row.quest)
          quest_enders_creature[quest_id] = quest_enders_creature[quest_id] or {}
          table.insert(quest_enders_creature[quest_id], tonumber(row.id))
        end
      end

      -- Batch load gameobject quest enders
      local go_ender_table = (core == "acore" and "gameobject_questender" or "gameobject_involvedrelation")
      sql = "SELECT * FROM " .. go_ender_table .. " WHERE " .. go_ender_table .. ".quest IN (" .. quest_ids_string .. ")"
      query = mysql:execute(sql)
      if query then
        local row = {}
        while query:fetch(row, "a") do
          local quest_id = tonumber(row.quest)
          quest_enders_object[quest_id] = quest_enders_object[quest_id] or {}
          table.insert(quest_enders_object[quest_id], tonumber(row.id))
        end
      end
    end

    -- Debug: Show batch loading results
    local creature_starter_count = 0
    local object_starter_count = 0
    local item_starter_count = 0
    local creature_ender_count = 0
    local object_ender_count = 0

    for quest_id, starters in pairs(quest_starters_creature) do
      creature_starter_count = creature_starter_count + table.getn(starters)
    end
    for quest_id, starters in pairs(quest_starters_object) do
      object_starter_count = object_starter_count + table.getn(starters)
    end
    for quest_id, starters in pairs(quest_starters_item) do
      item_starter_count = item_starter_count + table.getn(starters)
    end
    for quest_id, enders in pairs(quest_enders_creature) do
      creature_ender_count = creature_ender_count + table.getn(enders)
    end
    for quest_id, enders in pairs(quest_enders_object) do
      object_ender_count = object_ender_count + table.getn(enders)
    end

    -- Debug quest 833 specifically
    if quest_starters_creature[833] then
--         print("DEBUG: Quest 833 creature starters: " .. table.getn(quest_starters_creature[833]))
        for _, starter in ipairs(quest_starters_creature[833]) do
--             print("  Starter: " .. starter)
        end
    else
--         print("DEBUG: Quest 833 has NO creature starters in batch data!")
    end

    if quest_enders_creature[833] then
--         print("DEBUG: Quest 833 creature enders: " .. table.getn(quest_enders_creature[833]))
        for _, ender in ipairs(quest_enders_creature[833]) do
--             print("  Ender: " .. ender)
        end
    else
--         print("DEBUG: Quest 833 has NO creature enders in batch data!")
    end

--     print("  Batch loaded: " .. creature_starter_count .. " creature starters, " ..
--           object_starter_count .. " object starters, " .. item_starter_count .. " item starters")
--     print("  Batch loaded: " .. creature_ender_count .. " creature enders, " ..
--           object_ender_count .. " object enders")

    -- BATCH LOAD EVENT DATA (eliminates 9k+ individual event queries!)
    print("  Pass 2a.2: Batch loading quest event data...")
    local quest_events_seasonal = {}
    local quest_events_creature = {}
    local quest_events_gameobject = {}

    if #all_quest_ids > 0 then
      local quest_ids_string = table.concat(all_quest_ids, ",")

      -- Batch load seasonal quest events
      if core == "acore" then
        local query = mysql:execute("SELECT questId as quest, eventEntry as event FROM game_event_seasonal_questrelation WHERE questId IN (" .. quest_ids_string .. ")")
        if query then
          local row = {}
          while query:fetch(row, "a") do
            quest_events_seasonal[tonumber(row.quest)] = tonumber(row.event)
          end
        end
      else
        local query = mysql:execute("SELECT quest, event FROM game_event_quest WHERE quest IN (" .. quest_ids_string .. ")")
        if query then
          local row = {}
          while query:fetch(row, "a") do
            quest_events_seasonal[tonumber(row.quest)] = tonumber(row.event)
          end
        end
      end

      -- Batch load creature quest events
      if core == "acore" then
        local query = mysql:execute("SELECT quest, eventEntry as event FROM game_event_creature_quest WHERE quest IN (" .. quest_ids_string .. ")")
        if query then
          local row = {}
          while query:fetch(row, "a") do
            quest_events_creature[tonumber(row.quest)] = tonumber(row.event)
          end
        end
      end

      -- Batch load gameobject quest events
      if core == "acore" then
        local query = mysql:execute("SELECT quest, eventEntry as event FROM game_event_gameobject_quest WHERE quest IN (" .. quest_ids_string .. ")")
        if query then
          local row = {}
          while query:fetch(row, "a") do
            quest_events_gameobject[tonumber(row.quest)] = tonumber(row.event)
          end
        end
      end
    end

    -- BATCH LOAD PRE-QUEST DATA (eliminates 9k+ individual pre-quest queries!)
    print("  Pass 2a.3: Batch loading pre-quest relationships...")
    local quest_pre_relationships = {}
    local quest_pre_chain_relationships = {}

    if #all_quest_ids > 0 then
      local quest_ids_string = table.concat(all_quest_ids, ",")
      local next_quest_id_column = core == "acore" and "PrevQuestId" or "NextQuestId"
      local exclusive_group_column = core == "acore" and "ExclusiveGroup" or "ExclusiveGroup"

      -- Batch load pre-quest relationships
      local query = mysql:execute('SELECT ' .. quest_pk_column .. ' AS entry, ' .. next_quest_id_column .. ' AS next_quest FROM quest_template WHERE ' .. next_quest_id_column .. ' IN (' .. quest_ids_string .. ') AND ' .. exclusive_group_column .. ' < 0')
      if query then
        local row = {}
        while query:fetch(row, "a") do
          local entry = tonumber(row.entry)
          local next_quest = tonumber(row.next_quest)
          quest_pre_relationships[next_quest] = quest_pre_relationships[next_quest] or {}
          table.insert(quest_pre_relationships[next_quest], entry)
        end
      end

      -- Batch load pre-chain relationships (only if NextQuestInChain column exists)
      if core ~= "acore" then -- AzerothCore doesn't have NextQuestInChain
        local query = mysql:execute('SELECT ' .. quest_pk_column .. ' AS entry, NextQuestInChain FROM quest_template WHERE NextQuestInChain IN (' .. quest_ids_string .. ')')
        if query then
          local row = {}
          while query:fetch(row, "a") do
            local entry = tonumber(row.entry)
            local next_quest = tonumber(row.NextQuestInChain)
            quest_pre_chain_relationships[next_quest] = quest_pre_chain_relationships[next_quest] or {}
            table.insert(quest_pre_chain_relationships[next_quest], entry)
          end
        end
      end
    end

    -- BATCH LOAD KILL CREDIT DATA (eliminates 30k+ individual kill credit queries!)
    print("  Pass 2a.4: Batch loading kill credit relationships...")
    local kill_credit_relationships = {}

    if core ~= "vmangos" then
      -- Batch load ALL kill credit relationships at once
      local query = mysql:execute("SELECT Entry, KillCredit1, KillCredit2 FROM creature_template WHERE KillCredit1 > 0 OR KillCredit2 > 0")
      if query then
        local row = {}
        while query:fetch(row, "a") do
          local entry = tonumber(row.Entry)
          local credit1 = tonumber(row.KillCredit1)
          local credit2 = tonumber(row.KillCredit2)

          if credit1 and credit1 > 0 then
            kill_credit_relationships[credit1] = kill_credit_relationships[credit1] or {}
            table.insert(kill_credit_relationships[credit1], entry)
          end
          if credit2 and credit2 > 0 then
            kill_credit_relationships[credit2] = kill_credit_relationships[credit2] or {}
            table.insert(kill_credit_relationships[credit2], entry)
          end
        end
      end
    end

    print("  Pass 2b: Processing quests with pre-loaded relationship data...")
    for i, current_quest_data in ipairs(all_fetched_quests) do
      if debug("quests") then break end

      -- Show progress every 1000 quests
      if i % 1000 == 0 then
        print("  Processed " .. i .. "/" .. total_quests .. " quests (" .. math.floor(i/total_quests*100) .. "%)")
      end

      local entry = tonumber(current_quest_data[quest_pk_column])
      local quest_id = current_quest_data[quest_pk_column] or current_quest_data.entry

      -- Debug quest 833 processing
      if entry == 833 then
--         print("DEBUG: Processing quest 833, entry=" .. entry .. ", quest_id=" .. quest_id)
        local found_in_batch = false
        for _, id in ipairs(all_quest_ids) do
          if id == 833 then found_in_batch = true; break end
        end
--         print("DEBUG: Quest 833 in all_quest_ids: " .. (found_in_batch and "YES" or "NO"))
      end
        local minlevel = tonumber(current_quest_data.MinLevel)
      local questlevel = tonumber(current_quest_data.QuestLevel)
      local class_column = C.RequiredClasses or "AllowableClasses" -- AzerothCore uses AllowableClasses
      local race_column = C.RequiredRaces or "AllowableRaces" -- Default to AC if not in C
      local skill_column = C.RequiredSkill or "RequiredSkillId" -- Default to AC if not in C
      local srcitem_column = C.SrcItemId or "StartItem" -- Default to AC if not in C
      local prevquest_column = C.PrevQuestId or "PrevQuestId" -- Default if not in C

        local class = current_quest_data[class_column] and tonumber(current_quest_data[class_column]) or 0
        local race = current_quest_data[race_column] and tonumber(current_quest_data[race_column]) or 0
        -- For AzerothCore, skill data comes from quest_template_addon
        local skill = 0
        if current_quest_data.AddonRequiredSkillID then
          skill = tonumber(current_quest_data.AddonRequiredSkillID) or 0
        elseif current_quest_data[skill_column] then
          skill = tonumber(current_quest_data[skill_column]) or 0
        end
        local chain = current_quest_data.NextQuestInChain and tonumber(current_quest_data.NextQuestInChain) or 0 -- This will be problematic for AC
        local srcitem = current_quest_data[srcitem_column] and tonumber(current_quest_data[srcitem_column]) or 0
        local repeatable = current_quest_data.SpecialFlags and (tonumber(current_quest_data.SpecialFlags) % 2) or 0
      local event = nil

        -- USE BATCH EVENT DATA - MAJOR OPTIMIZATION! (eliminates 9k+ individual event queries!)
        event = quest_events_seasonal[entry] or quest_events_creature[entry] or quest_events_gameobject[entry]

      pfDB["quests"][data][entry] = {}
      pfDB["quests"][data][entry]["min"] = minlevel ~= 0 and minlevel


      if skill ~= 0 then
        pfDB["quests"][data][entry]["skill"] = skill
      end
      pfDB["quests"][data][entry]["lvl"] = questlevel ~= 0 and questlevel

      -- Extract quest XP difficulty index (RewardXPDifficulty)
      local reward_xp_diff = tonumber(current_quest_data.RewardXPDifficulty) or 0
      if reward_xp_diff > 0 then
        pfDB["quests"][data][entry]["xp_diff"] = reward_xp_diff
      end

      -- Store AllowableClasses as number (pfQuest expects bit.band operations)
      local allowable_classes_mask = current_quest_data[class_column] and tonumber(current_quest_data[class_column]) or 0
      local allowable_races_mask = tonumber(current_quest_data[race_column]) or 0

      if allowable_classes_mask ~= 0 then
        pfDB["quests"][data][entry]["class"] = allowable_classes_mask
      end

      -- Универсальное определение фракции для квестов с AllowableRaces = 0
      local final_race = allowable_races_mask ~= 0 and allowable_races_mask or race
      if final_race == 0 then
        local check_npc_id = nil

        -- Сначала пытаемся взять стартового NPC
        if quest_starters_creature[tonumber(quest_id)] then
          check_npc_id = quest_starters_creature[tonumber(quest_id)][1]
          -- Если квест с предмета, берем финального NPC (кому сдавать)
        elseif quest_enders_creature[tonumber(quest_id)] then
          check_npc_id = quest_enders_creature[tonumber(quest_id)][1]
        end

        if check_npc_id and pfDB["units"][data][check_npc_id] then
          local npc_data = pfDB["units"][data][check_npc_id]

          -- 1. Сначала проверяем фракцию самого NPC (самый точный и универсальный метод для ЛЮБОЙ зоны)
          if npc_data.fac == "A" then
            final_race = 1101 -- Alliance
          elseif npc_data.fac == "H" then
            final_race = 690  -- Horde

            -- 2. Если фракция NPC не прописана явно, оставляем старый fallback по стартовым зонам на всякий случай
          elseif npc_data.coords and npc_data.coords[1] then
            local zone = npc_data.coords[1][3]
            if zone == 215 or zone == 17 or zone == 14 then -- Mulgore, Northern Barrens, Durotar
              final_race = 690 -- Horde
            elseif zone == 12 or zone == 40 or zone == 130 then -- Elwynn Forest, Westfall, Teldrassil
              final_race = 1101 -- Alliance
            end
          end
        end
      end

      if entry == 833 then
--         print("DEBUG: Quest 833 race assignment:")
--         print("  allowable_races_mask = " .. allowable_races_mask)
--         print("  race = " .. race)
--         print("  final_race = " .. final_race)
      end
      if final_race ~= 0 then
        pfDB["quests"][data][entry]["race"] = final_race
      end
      if event and event ~= 0 then
        pfDB["quests"][data][entry]["event"] = event
      end

      -- Build pre-quest relationships
      local pre_quests_list = {}
      if quest_has_addon_prev[entry] then
        table.insert(pre_quests_list, quest_has_addon_prev[entry])
      end
      if reward_next_leads_to_prev[entry] then
        for _, prev_id in ipairs(reward_next_leads_to_prev[entry]) do
          table.insert(pre_quests_list, prev_id)
        end
      end
      if addon_next_leads_to_prev[entry] then
        for _, prev_id in ipairs(addon_next_leads_to_prev[entry]) do
          table.insert(pre_quests_list, prev_id)
        end
      end

      -- Build chain (next quest) relationships
      local chain_quests_list = {}
      local reward_next_val = tonumber(current_quest_data.RewardNextQuest)
      local addon_next_val = tonumber(current_quest_data.AddonNextQuestID)
      if reward_next_val and reward_next_val > 0 then
        table.insert(chain_quests_list, reward_next_val)
      end
      if addon_next_val and addon_next_val > 0 then
        table.insert(chain_quests_list, addon_next_val)
      end

      if #pre_quests_list > 0 then
        pfDB["quests"][data][entry]["pre"] = remove_duplicates_from_table(pre_quests_list)
      end
      if #chain_quests_list > 0 then
        pfDB["quests"][data][entry]["chain"] = remove_duplicates_from_table(chain_quests_list)
      end

      -- quest objectives
      local units, objects, items, itemreq, areatrigger, zones, pre = {}, {}, {}, {}, {}, {}, {}

        -- add single pre-quests
        local prevquest_value = quest_template[prevquest_column]
        if prevquest_value and tonumber(prevquest_value) and tonumber(prevquest_value) ~= 0 then
          pre[math.abs(tonumber(prevquest_value))] = true
        end

      -- USE BATCH PRE-QUEST DATA - MAJOR OPTIMIZATION! (eliminates 9k+ individual pre-quest queries!)
      if quest_pre_relationships[entry] then
        for _, pre_quest in ipairs(quest_pre_relationships[entry]) do
          pre[pre_quest] = true
        end
      end
      if quest_pre_chain_relationships[entry] then
        for _, pre_quest in ipairs(quest_pre_chain_relationships[entry]) do
          pre[pre_quest] = true
        end
      end

      -- temporary add provided quest item
      items[srcitem] = true


      -- Mapping for ReqCreatureOrGOId, ReqItemId, ReqSourceId based on C config or defaults
      local req_npc_go_id_base = C.ReqCreatureOrGOId or "RequiredNpcOrGo" -- Defaulting to AC naming
      local req_item_id_base = C.ReqItemId or "RequiredItemId" -- Defaulting to AC naming
      local req_source_id_base = C.ReqSourceId or "RequiredItemSourceId" -- Placeholder, AC might not have direct ReqSourceId, often covered by loot or quest item spells

      for i=1,4 do
        local req_npc_go_col = req_npc_go_id_base .. i
        local req_item_col = req_item_id_base .. i
        local req_source_col = req_source_id_base .. i -- Might be unused if AC has no direct map


        if current_quest_data[req_npc_go_col] and tonumber(current_quest_data[req_npc_go_col]) > 0 then
          units[tonumber(current_quest_data[req_npc_go_col])] = true
        elseif current_quest_data[req_npc_go_col] and tonumber(current_quest_data[req_npc_go_col]) < 0 then
          objects[math.abs(tonumber(current_quest_data[req_npc_go_col]))] = true
        end
        if current_quest_data[req_item_col] and tonumber(current_quest_data[req_item_col]) > 0 then
          if entry == 833 then
--             print("DEBUG: Quest 833 adding required item: " .. current_quest_data[req_item_col] .. " from " .. req_item_col)
          end
          items[tonumber(current_quest_data[req_item_col])] = true
        end
        -- Handling ReqSourceId needs to be verified for AC. It might involve looking at item loot that starts quests or specific quest flags.
        -- For now, we attempt to use it if the column exists in the query result.
        if current_quest_data[req_source_col] and tonumber(current_quest_data[req_source_col]) > 0 then
          if entry == 833 then
--             print("DEBUG: Quest 833 adding source item: " .. current_quest_data[req_source_col] .. " from " .. req_source_col)
          end
          items[tonumber(current_quest_data[req_source_col])] = true
        end

        if current_quest_data["ReqSpellCast" .. i] and tonumber(current_quest_data["ReqSpellCast" .. i]) > 0 then
          local spell_template = {}
          local query = mysql:execute('SELECT ID, RequiresSpellFocus FROM spell_dbc_full WHERE ID = ' .. current_quest_data["ReqSpellCast" .. i])
          while query:fetch(spell_template, "a") do
            if debug("quests_questspellobject") then break end
            if spell_template["RequiresSpellFocus"] ~= "0" then
              local gameobject_template = {}
              local query = mysql:execute('SELECT * FROM gameobject_template WHERE gameobject_template.type = 8 and gameobject_template.data0 = ' .. spell_template["RequiresSpellFocus"])
              while query:fetch(gameobject_template, "a") do
                objects[tonumber(gameobject_template["entry"])] = true
              end
            end
          end
        end
      end


      -- USE BATCH KILL CREDIT DATA - ITERATIVE APPROACH (100% accurate, eliminates 30k+ individual queries!)
      if core ~= "vmangos" then
        -- Build queue of units to process (mimics original growing loop behavior)
        local units_to_process = {}
        for id in pairs(units) do
          table.insert(units_to_process, id)
        end

        local processed_units = {}
        while #units_to_process > 0 do
          local current_id = table.remove(units_to_process)
          if not processed_units[current_id] then
            processed_units[current_id] = true

            if kill_credit_relationships[current_id] then
              for _, credit_entry in ipairs(kill_credit_relationships[current_id]) do
                if debug("quests_credit") then break end
                if not units[credit_entry] then
                  units[credit_entry] = true
                  -- CRITICAL: Add newly found units to processing queue (reproduces original behavior)
                  table.insert(units_to_process, credit_entry)

                end
              end
            end
          end
        end
      end



      -- scan all involved questitems for spells that require or are required by gameobjects, units or zones
      -- ITEMREQ SECTION FIXES FOR AZEROTHCORE:
      -- 1. Uses spell_scripts instead of spell_script_target
      -- 2. Handles missing spells in spell_dbc gracefully
      -- 3. Skips item_required_target table (doesn't exist in AC)
      -- 4. Added compatibility layer for non-AC cores
      -- Process itemreq (debug info will be shown only if relationships found)
        for id in pairs(items) do
          if id > 0 then
            local item_template = {}
            for _, spellcolumn in pairs({ "spellid_1", "spellid_2", "spellid_3", "spellid_4", "spellid_5" }) do
              local query = mysql:execute('SELECT * FROM item_template WHERE ' .. spellcolumn .. ' > 0 and entry = ' .. id)
              if query then
                while query:fetch(item_template, "a") do
                  if debug("quests_item") then break end
                  local spellid = item_template[spellcolumn]

                  -- scan through all spells that are associated with the item
                  if spellid and tonumber(spellid) > 0 then
                    local spell_template = {}
                    local spell_query = mysql:execute('SELECT ID, RequiresSpellFocus FROM spell_dbc_full WHERE ID = ' .. spellid)
                    if spell_query then
                      local spell_found = false
                      while spell_query:fetch(spell_template, "a") do
                        spell_found = true
                        if debug("quests_itemspell") then break end
                local area = nil  -- AreaId not needed for RequiresSpellFocus logic
                local focus = spell_template["RequiresSpellFocus"]
                local match = nil

                -- spell requires focusing a creature (using spell_scripts for AC)
                local spell_script_target = {}
                for itemid in pairs(items) do
                  if spellid and tonumber(spellid) > 0 then
                    -- Use spell_scripts table for AzerothCore compatibility
                    local script_table = C["spell_script_target"] or "spell_scripts"
                    if script_table == "spell_scripts" then
                      -- AzerothCore: Use spell_scripts table (correct structure)
                      local query = mysql:execute([[
                        SELECT command, datalong, datalong2, dataint, x, y, z
                        FROM spell_scripts
                        WHERE id = ]] .. spellid .. [[
                      ]])
                      if query then
                        while query:fetch(spell_script_target, "a") do
                          if debug("quests_itemspellcreature") then break end

                          local cmd = tonumber(spell_script_target.command)
                          local datalong = tonumber(spell_script_target.datalong)
                          local datalong2 = tonumber(spell_script_target.datalong2)
                          local dataint = tonumber(spell_script_target.dataint)

                          -- Check for commands that indicate targeting specific creatures/objects
                          -- Command 15 = SCRIPT_COMMAND_CAST_SPELL
                          if cmd == 15 and datalong2 then
                            -- datalong2 determines cast type:
                            -- 0 = Source->Target, 4 = Source->Closest entry of dataint
                            if datalong2 == 4 and dataint and dataint > 0 then
                              -- Target closest creature with entry = dataint
                              pfDB["quests-itemreq"][data][id] = pfDB["quests-itemreq"][data][id] or {}
                              pfDB["quests-itemreq"][data][id][dataint] = spellid
                              itemreq[id] = true
                              match = true
                            elseif datalong2 == 0 and datalong and datalong > 0 then
                              -- Cast spell (datalong) on target - need to check if target is specific
                              -- This might need additional logic based on spell effects
                            end
                          end
                          -- Command 14 = SCRIPT_COMMAND_MODIFY_FLAGS might also be relevant
                          -- Add other commands as needed
                        end
                      end
                    else
                      -- Legacy: Use spell_script_target table (for non-AC cores)
                      local query = mysql:execute([[
                        SELECT targetEntry AS creature
                        FROM ]] .. script_table .. [[
                        WHERE entry = ]] .. spellid .. [[ AND type = 1
                      ]])
                      if query then
                        while query:fetch(spell_script_target, "a") do
                          if debug("quests_itemspellcreature") then break end
                          pfDB["quests-itemreq"][data][id] = pfDB["quests-itemreq"][data][id] or {}
                          pfDB["quests-itemreq"][data][id][tonumber(spell_script_target.creature)] = spellid
                          itemreq[id] = true
                          match = true
                        end
                      end
                    end
                  end
                end

                -- spell requries focusing an object
                if focus and tonumber(focus) > 0  then
                  local gameobject_template = {}
                  local query = mysql:execute('SELECT * FROM gameobject_template WHERE gameobject_template.type = 8 and gameobject_template.data0 = ' .. focus)
                  while query:fetch(gameobject_template, "a") do
                    if debug("quests_itemspellobject") then break end
                    pfDB["quests-itemreq"][data][id] = pfDB["quests-itemreq"][data][id] or {}
                    pfDB["quests-itemreq"][data][id][-tonumber(gameobject_template["entry"])] = spellid
                    itemreq[id] = true
                    match = true
                  end
                end

                -- NOTE: EffectTriggerSpell logic removed (requires full spell_template fields)
                -- This focused implementation only handles RequiresSpellFocus for better itemreq coverage

                -- only spell limitation is a zone
                if not match and area and tonumber(area) > 0 then
                  zones[tonumber(area)] = true
                end
                      end -- spell_query:fetch

                      if not spell_found and debug("quests_itemspell") then
                        print("  DEBUG: Spell " .. spellid .. " not found in " .. C.spell_template .. " - skipping itemreq analysis")
                      end
                    end -- if spell_query
                  end -- if spellid and tonumber(spellid) > 0
                end -- query:fetch
              end -- if query
              end -- for spellcolumn
          end -- if id > 0
        end -- for id in pairs(items)

        -- item is used to open a creature (skip for AzerothCore - table doesn't exist)
        -- Note: item_required_target table doesn't exist in AzerothCore
        -- This functionality might be handled differently or through smart_scripts
        local has_item_required_target = false

        -- Check if item_required_target table exists (for non-AC cores)
        local check_table_query = mysql:execute("SHOW TABLES LIKE 'item_required_target'")
        if check_table_query and check_table_query:fetch() then
          has_item_required_target = true
        end

        if has_item_required_target then
          for id in pairs(items) do
            if id > 0 then
              local creature_items = {}
              local target_entry_field = C.targetEntry or "targetEntry" -- Default fallback
              local query = mysql:execute([[
                SELECT ]] .. target_entry_field .. [[ AS creature FROM item_required_target
                WHERE entry = ]] .. id .. [[
              ]])
              if query then
                while query:fetch(creature_items, "a") do
                  if debug("quests_itemcreature") then break end
                  pfDB["quests-itemreq"][data][id] = pfDB["quests-itemreq"][data][id] or {}
                  pfDB["quests-itemreq"][data][id][tonumber(creature_items.creature)] = 0
                  itemreq[id] = true
                end
              end
            end
          end
        else
          if debug("quests_itemcreature") then
            print("  DEBUG: item_required_target table not found - skipping (normal for AzerothCore)")
          end
        end

        -- Count and report itemreq results (only once per quest block)
        local itemreq_count = 0
        for itemid, targets in pairs(pfDB["quests-itemreq"][data] or {}) do
          for targetid, spellid in pairs(targets) do
            itemreq_count = itemreq_count + 1
          end
        end
        if itemreq_count > 0 then
--           print("  DEBUG: Found " .. itemreq_count .. " item-target relationships for this quest batch.")
        end

        -- NOTE: Lock-based object logic removed (redundant with RequiresSpellFocus logic)

        -- scan for related areatriggers
        local areatrigger_involvedrelation = {}
        local query = mysql:execute('SELECT * FROM areatrigger_involvedrelation WHERE quest = ' .. entry)
        if query then
          while query:fetch(areatrigger_involvedrelation, "a") do
            if debug("quests_areatrigger") then break end
            areatrigger[tonumber(areatrigger_involvedrelation["id"])] = true
          end
        end

      -- remove provided quest item from objectives
      items[srcitem] = nil

      -- write pre-quests
      for id in opairs(pre) do
        pfDB["quests"][data][entry]["pre"] = pfDB["quests"][data][entry]["pre"] or {}
        table.insert(pfDB["quests"][data][entry]["pre"], tonumber(id))
      end

          do -- write objectives

              if tblsize(units) > 0 or tblsize(objects) > 0 or tblsize(items) > 0 or tblsize(itemreq) > 0 or tblsize(areatrigger) > 0 or tblsize(zones) > 0 then
                  pfDB["quests"][data][entry]["obj"] = pfDB["quests"][data][entry]["obj"] or {}


                  for id in opairs(units) do
                      pfDB["quests"][data][entry]["obj"]["U"] = pfDB["quests"][data][entry]["obj"]["U"] or {}
                      table.insert(pfDB["quests"][data][entry]["obj"]["U"], tonumber(id))
                  end


                  for id in opairs(objects) do
                      pfDB["quests"][data][entry]["obj"]["O"] = pfDB["quests"][data][entry]["obj"]["O"] or {}
                      table.insert(pfDB["quests"][data][entry]["obj"]["O"], tonumber(id))
                  end

                  for id in opairs(items) do
                      if entry == 833 then
--                         print("DEBUG: Quest 833 adding item objective: " .. id)
                      end
                      pfDB["quests"][data][entry]["obj"]["I"] = pfDB["quests"][data][entry]["obj"]["I"] or {}
                      table.insert(pfDB["quests"][data][entry]["obj"]["I"], tonumber(id))
                  end

                  for id in opairs(itemreq) do
                      pfDB["quests"][data][entry]["obj"]["IR"] = pfDB["quests"][data][entry]["obj"]["IR"] or {}
                      table.insert(pfDB["quests"][data][entry]["obj"]["IR"], tonumber(id))
                  end

                  for id in opairs(areatrigger) do
                      pfDB["quests"][data][entry]["obj"]["A"] = pfDB["quests"][data][entry]["obj"]["A"] or {}
                      table.insert(pfDB["quests"][data][entry]["obj"]["A"], tonumber(id))
                  end

                  for id in opairs(zones) do
                      pfDB["quests"][data][entry]["obj"]["Z"] = pfDB["quests"][data][entry]["obj"]["Z"] or {}
                      table.insert(pfDB["quests"][data][entry]["obj"]["Z"], tonumber(id))
                  end
              end

              -- quest starter (using pre-loaded data)
              if entry == 833 then
--                 print("DEBUG: Quest 833 processing starters, quest_id=" .. quest_id)
--                 print("DEBUG: quest_starters_creature[833] exists: " .. (quest_starters_creature[833] and "YES" or "NO"))
--                 print("DEBUG: quest_starters_creature[tonumber(quest_id)] exists: " .. (quest_starters_creature[tonumber(quest_id)] and "YES" or "NO"))
              end

              if quest_starters_creature[tonumber(quest_id)] then
                  if not debug("quests_starterunit") then
                  pfDB["quests"][data][entry]["start"] = pfDB["quests"][data][entry]["start"] or {}
                  pfDB["quests"][data][entry]["start"]["U"] = pfDB["quests"][data][entry]["start"]["U"] or {}
                  for _, creature_id in ipairs(quest_starters_creature[tonumber(quest_id)]) do
                      table.insert(pfDB["quests"][data][entry]["start"]["U"], creature_id)
                  end
                  end
              end

              if quest_starters_object[tonumber(quest_id)] then
                  if not debug("quests_starterobject") then
                  pfDB["quests"][data][entry]["start"] = pfDB["quests"][data][entry]["start"] or {}
                  pfDB["quests"][data][entry]["start"]["O"] = pfDB["quests"][data][entry]["start"]["O"] or {}
                  for _, object_id in ipairs(quest_starters_object[tonumber(quest_id)]) do
                      table.insert(pfDB["quests"][data][entry]["start"]["O"], object_id)
                  end
                  end
              end

              if quest_starters_item[tonumber(quest_id)] then
                  if not debug("quests_starteritem") then

                  for _, item_id in ipairs(quest_starters_item[tonumber(quest_id)]) do
                      -- remove quest start items from objectives
                      if pfDB["quests"][data][entry]["obj"] and pfDB["quests"][data][entry]["obj"]["I"] then
                          for id, objective in pairs(pfDB["quests"][data][entry]["obj"]["I"]) do
                              if objective == item_id then
                                  pfDB["quests"][data][entry]["obj"]["I"][id] = nil
                              end
                          end
                      end

                      -- add item to quest starters
                      pfDB["quests"][data][entry]["start"] = pfDB["quests"][data][entry]["start"] or {}
                      pfDB["quests"][data][entry]["start"]["I"] = pfDB["quests"][data][entry]["start"]["I"] or {}
                      table.insert(pfDB["quests"][data][entry]["start"]["I"], item_id)
                  end
                  end
              end

              -- quest ender (using pre-loaded data)
              if quest_enders_creature[tonumber(quest_id)] then
                  if not debug("quests_enderunit") then
                  pfDB["quests"][data][entry]["end"] = pfDB["quests"][data][entry]["end"] or {}
                  pfDB["quests"][data][entry]["end"]["U"] = pfDB["quests"][data][entry]["end"]["U"] or {}
                  for _, creature_id in ipairs(quest_enders_creature[tonumber(quest_id)]) do
                      table.insert(pfDB["quests"][data][entry]["end"]["U"], creature_id)
                  end
                  end
              end

              if quest_enders_object[tonumber(quest_id)] then
                  if not debug("quests_enderobject") then
                  pfDB["quests"][data][entry]["end"] = pfDB["quests"][data][entry]["end"] or {}
                  pfDB["quests"][data][entry]["end"]["O"] = pfDB["quests"][data][entry]["end"]["O"] or {}
                  for _, object_id in ipairs(quest_enders_object[tonumber(quest_id)]) do
                      table.insert(pfDB["quests"][data][entry]["end"]["O"], object_id)
                  end
                  end
              end

          end
      end
    end
    local end_time_quests = os.clock()
    if pfDB and pfDB["quests"] then
      table.insert(execution_times, {name = "quests", time = end_time_quests - start_time_quests})
    end

    -- Final itemreq summary
    local total_itemreq_count = 0
    for itemid, targets in pairs(pfDB["quests-itemreq"][data] or {}) do
      for targetid, spellid in pairs(targets) do
        total_itemreq_count = total_itemreq_count + 1
      end
    end
    if total_itemreq_count > 0 then
      print("  ItemReq Summary: Found " .. total_itemreq_count .. " total item-target relationships.")
    else
      print("  ItemReq Summary: No item-target relationships found (may be normal for AzerothCore).")
    end
    -- ДОБАВЬТЕ:
    collectgarbage("collect")
    print("  Memory cleanup after quests: " .. math.floor(collectgarbage("count")) .. " KB")
  end

  -- Extract QuestXP data from questxp_dbc table
  local start_time_questxp = os.clock()
  do -- questxp
    print("- loading questxp...")

    pfDB["questxp"] = pfDB["questxp"] or {}
    pfDB["questxp"][data] = {}

    if core == "acore" then
      local questxp_query = mysql:execute("SELECT * FROM questxp_dbc ORDER BY ID")
      if questxp_query then
        local questxp_row = {}
        while questxp_query:fetch(questxp_row, "a") do
          local level = tonumber(questxp_row.ID)
          if level and level >= 1 and level <= 80 then
            pfDB["questxp"][data][level] = {
              tonumber(questxp_row.Difficulty_1) or 0,
              tonumber(questxp_row.Difficulty_2) or 0,
              tonumber(questxp_row.Difficulty_3) or 0,
              tonumber(questxp_row.Difficulty_4) or 0,
              tonumber(questxp_row.Difficulty_5) or 0,
              tonumber(questxp_row.Difficulty_6) or 0,
              tonumber(questxp_row.Difficulty_7) or 0,
              tonumber(questxp_row.Difficulty_8) or 0,
              tonumber(questxp_row.Difficulty_9) or 0,
              tonumber(questxp_row.Difficulty_10) or 0
            }
          end
        end
        print("  Extracted QuestXP data for " .. table.getn(pfDB["questxp"][data]) .. " quest levels")
      else
        print("  WARNING: questxp_dbc table not found - skipping questxp extraction")
      end
    end

    local end_time_questxp = os.clock()
    table.insert(execution_times, {name = "questxp", time = end_time_questxp - start_time_questxp})
  end



  local start_time_minimap = os.clock()
  do -- minimap
    print("- loading minimap...")

    pfDB["minimap"..exp] = pfDB["minimap"..exp] or {}

    if core == "acore" then
      -- For AzerothCore, use loaded DBC tables
      local minimap_size = {}
      local query = mysql:execute('SELECT * FROM WorldMapArea_wotlk ORDER BY areatableID ASC')
      if query then
        while query:fetch(minimap_size, "a") do
          if debug("minimap") then break end
          local mapID = minimap_size.mapID
          local areaID = minimap_size.areatableID
          local name = minimap_size.name
          local x_min = minimap_size.x_min
          local y_min = minimap_size.y_min
          local x_max = minimap_size.x_max
          local y_max = minimap_size.y_max

            local world_y_bottom = tonumber(minimap_size.x_min)
            local world_x_left = tonumber(minimap_size.y_min)
            local world_y_top = tonumber(minimap_size.x_max)
            local world_x_right = tonumber(minimap_size.y_max)

            local calculated_width, calculated_height

            -- Check for zero boundaries and use DungeonMap fallback if needed
            if world_x_left == 0 and world_x_right == 0 and world_y_top == 0 and world_y_bottom == 0 then
                local dungeon_bounds = GetDungeonMapBoundariesFallback(tonumber(minimap_size.areatableID), tonumber(minimap_size.mapID))
                if dungeon_bounds then
                    world_x_left = dungeon_bounds.x_left
                    world_x_right = dungeon_bounds.x_right
                    world_y_top = dungeon_bounds.y_top
                    world_y_bottom = dungeon_bounds.y_bottom
                    print(string.format("🗺️  [MINIMAP DUNGEONMAP FALLBACK] Used DungeonMap for minimap AreaID: %d (MapID: %d)", tonumber(minimap_size.areatableID), tonumber(minimap_size.mapID)))
                end
            end

            -- Используем math.abs для гарантии положительных размеров для всех зон
            calculated_width = math.abs(world_x_right - world_x_left)
            calculated_height = math.abs(world_y_top - world_y_bottom)

            -- Проверка на нулевые размеры, чтобы избежать деления на ноль где-либо дальше
            if calculated_width == 0 then calculated_width = 1 end -- Минимальная ширина
            if calculated_height == 0 then calculated_height = 1 end -- Минимальная высота

            pfDB["minimap"..exp][tonumber(areaID)] = { calculated_height, calculated_width }
        end
      else
        print("  Warning: Failed to query minimap from DBC tables - run load_dbc.lua first")
      end
    else
      -- Test if pfquest database is available
      local minimap_size = {}
      local query = mysql:execute('SELECT * FROM pfquest.WorldMapArea_'..expansion..' ORDER BY areatableID ASC LIMIT 5')
      if query then
        while query:fetch(minimap_size, "a") do
          if debug("minimap") then break end
          local mapID = minimap_size.mapID
          local areaID = minimap_size.areatableID
          local name = minimap_size.name
          local x_min = minimap_size.x_min
          local y_min = minimap_size.y_min
          local x_max = minimap_size.x_max
          local y_max = minimap_size.y_max

          local x = -1 * x_min + x_max
          local y = -1 * y_min + y_max

          pfDB["minimap"..exp][tonumber(areaID)] = { tonumber(y+.0), tonumber(x+.0) }
          print("    Processed zone: " .. (name or "Unknown") .. " (ID: " .. areaID .. ")")
        end
      else
        print("  DISABLED: pfquest database not available")
      end
    end
    local end_time_minimap = os.clock()
    if pfDB and pfDB["minimap"..exp] then
      table.insert(execution_times, {name = "minimap", time = end_time_minimap - start_time_minimap})
    end
    -- ДОБАВЬТЕ:
    collectgarbage("collect")
    print("  Memory cleanup after minimap: " .. math.floor(collectgarbage("count")) .. " KB")
  end

  local start_time_meta = os.clock()
  do -- meta
    print("- loading meta...")

    pfDB["meta"..exp] = pfDB["meta"..exp] or {
      ["mines"] = {},
      ["herbs"] = {},
      ["chests"] = {},
      ["rares"] = {},
      ["flight"] = {},
    }

    do -- flightmasters
      local mask = core == "vmangos" and 8 or 8192
      local creature_template = {}

      if core == "acore" then
        -- For AzerothCore, get flightmasters without faction detection
        local npcflag_field = C.NpcFlags or "npcflag"
        local entry_field = C.Entry or "entry"
        local query = mysql:execute([[
          SELECT ]] .. entry_field .. [[ FROM `creature_template`
          WHERE ( ]] .. npcflag_field .. [[ & ]]..mask..[[) > 0
        ]])

        if query then
          while query:fetch(creature_template, "a") do
            if debug("meta_taxi") then break end
            local entry = tonumber(creature_template[entry_field])
            if entry then
              pfDB["meta"..exp]["flight"][entry] = "AH" -- Default to both factions for AC
            end
          end
        else
          print("  Warning: Failed to execute flightmasters query")
        end
      else
        -- Original logic for other cores
        local query = mysql:execute([[
          SELECT Entry, A, H FROM `creature_template`, `pfquest`.FactionTemplate_]]..expansion..[[
          WHERE pfquest.FactionTemplate_]]..expansion..[[.factiontemplateID = creature_template.]] .. C.Faction .. [[
          AND ( ]] .. C.NpcFlags .. [[ & ]]..mask..[[) > 1
        ]])

        if query then
          while query:fetch(creature_template, "a") do
            if debug("meta_taxi") then break end
            local fac = ""
            local entry = tonumber(creature_template.Entry)
            local A = tonumber(creature_template.A)
            local H = tonumber(creature_template.H)
            if A >= 0 then fac = fac .. "A" end
            if H >= 0 then fac = fac .. "H" end
            pfDB["meta"..exp]["flight"][entry] = fac
          end
        end
      end
    end

    do -- raremobs
      local creature_template = {}
      local rank_field = C.Rank or "rank"
      local entry_field = C.Entry or "entry"
      local minlevel_field = C.MinLevel or "minlevel"
      local limit_clause = UNITS_LIMIT and (' LIMIT ' .. UNITS_LIMIT) or ''

--       print(string.format("  DEBUG: Using fields - entry:%s, minlevel:%s, rank:%s", entry_field, minlevel_field, rank_field))
      local query_sql_rares = string.format([[
        SELECT `%s`, `%s` FROM `creature_template` WHERE `%s` = 4 OR `%s` = 2 ORDER BY `%s`%s
      ]], entry_field, minlevel_field, rank_field, rank_field, entry_field, limit_clause)
--       print(string.format("  DEBUG: SQL for rares = %s", query_sql_rares))

      local query, err_rares = mysql:execute(query_sql_rares)
      if not query then
        print(string.format("  ERROR executing raremobs query: %s", err_rares or "Unknown MySQL error"))
      else
        local processed_rares_count = 0
        while query:fetch(creature_template, "a") do
          if debug("meta_rares") then break end
          local entry = tonumber(creature_template[entry_field])
          local level = tonumber(creature_template[minlevel_field])
          if entry and level then
            pfDB["meta"..exp]["rares"][entry] = level
            processed_rares_count = processed_rares_count + 1
          end
        end
        query:close()
        print(string.format("  Processed %d creatures for rares FROM LUA.", processed_rares_count))
      end
    end

    do -- gameobject relations
      if core == "acore" then
        -- For AzerothCore, use loaded DBC Lock table
        local gameobject_meta_info = {}
        local limit_clause = OBJECTS_LIMIT and not FULL_EXTRACTION and (' LIMIT ' .. OBJECTS_LIMIT) or ''
        local meta_farm_query_sql = string.format([[
            SELECT gt.entry, l.data AS lock_data_type, l.skill AS required_skill
            FROM gameobject_template gt
            JOIN Lock_wotlk l ON gt.data0 = l.id
            WHERE gt.type = 3 AND l.locktype = 2
            ORDER BY gt.entry ASC
            %s
        ]], limit_clause)

        local farm_query, err_farm = mysql:execute(meta_farm_query_sql)
        if not farm_query then
          print(string.format("  ERROR executing farm query for meta: %s", err_farm or "Unknown MySQL error"))
        else
          local processed_farm_count = 0
          local chests_count, herbs_count, mines_count = 0, 0, 0
          while farm_query:fetch(gameobject_meta_info, "a") do
            if debug("meta_farm") then break end

            local entry = tonumber(gameobject_meta_info.entry)
            local lock_type = tonumber(gameobject_meta_info.lock_data_type)
            local required_skill = tonumber(gameobject_meta_info.required_skill)

            if entry and lock_type and required_skill then
              local negative_entry = -entry
              if lock_type == 1 then
                pfDB["meta"..exp]["chests"][negative_entry] = required_skill
                chests_count = chests_count + 1
              elseif lock_type == 2 then
                pfDB["meta"..exp]["herbs"][negative_entry] = required_skill
                herbs_count = herbs_count + 1
              elseif lock_type == 3 then
                pfDB["meta"..exp]["mines"][negative_entry] = required_skill
                mines_count = mines_count + 1
              end
              processed_farm_count = processed_farm_count + 1
            end
          end
          farm_query:close()
          print(string.format("  Processed %d gameobjects: %d chests, %d herbs, %d mines", processed_farm_count, chests_count, herbs_count, mines_count))
        end
      else
        -- Original logic for other cores
        local gameobject_template = {}
        local query = mysql:execute([[
          SELECT * FROM `gameobject_template`, pfquest.Lock_]]..expansion..[[
          WHERE `type` = 3 AND `locktype` = 2 AND `flags` = 0 AND `data1` > 0 and id = data0 GROUP BY `gameobject_template`.entry ORDER BY `gameobject_template`.entry ASC
        ]])

        if query then
          while query:fetch(gameobject_template, "a") do
            if debug("meta_farm") then break end
            local entry   = tonumber(gameobject_template.entry) * -1
            local data = tonumber(gameobject_template.data)
            local skill = tonumber(gameobject_template.skill)
            if data == 1 then
              pfDB["meta"..exp]["chests"][entry] = skill
            elseif data == 2 then
              pfDB["meta"..exp]["herbs"][entry] = skill
            elseif data == 3 then
              pfDB["meta"..exp]["mines"][entry] = skill
            end
          end
        end
      end
    end
    local end_time_meta = os.clock()
    if pfDB and pfDB["meta"..exp] then
      table.insert(execution_times, {name = "meta", time = end_time_meta - start_time_meta})
    end
    -- ДОБАВЬТЕ:
    collectgarbage("collect")
    print("  Memory cleanup after meta: " .. math.floor(collectgarbage("count")) .. " KB")
  end

  local start_time_locales = os.clock()
  print("- loading locales...")
  do -- unit locales
    if core == "acore" then
      -- AzerothCore uses separate locale records
      for loc in pairs(locales) do
        local locales_creature = {}
        local locale_code = GetLocaleCode(loc)
        local where_clause = ""

        -- QUEST 784 DEBUG MODE - фильтруем только нужных NPC
        if QUEST_784_TEST then
          local npc_list = table.concat(QUEST_784_NPCS, ",")
          where_clause = " WHERE creature_template.entry IN (" .. npc_list .. ") "
        end

          local query = mysql:execute('SELECT creature_template.entry, creature_template.name, creature_template_locale.Name AS locale_name FROM creature_template LEFT JOIN creature_template_locale ON creature_template_locale.entry = creature_template.entry AND creature_template_locale.locale = \'' .. locale_code .. '\'' .. where_clause .. ' ORDER BY creature_template.entry ASC')

        if query then
          while query:fetch(locales_creature, "a") do
            if debug("locales_unit") then break end

            local entry = tonumber(locales_creature.entry)
            local name = locales_creature.name
            local locale_name = locales_creature.locale_name

            if entry then
              local final_name = locale_name or name or ""
              if final_name ~= "" then
                local locale = loc .. ( expansion ~= "vanilla" and "-" .. expansion or "" )
                pfDB["units"][locale] = pfDB["units"][locale] or { [420] = "Shagu" }
                pfDB["units"][locale][entry] = sanitize(final_name)
              end
            end
          end
        else
          print("  Warning: Failed to execute unit locales query for " .. loc)
        end
      end
    else
      -- Original MaNGOS logic
      local locales_creature = {}
      local creature_loc_pk_col = "entry"
      local creature_template_pk_col = "entry"

      local where_clause = ""
      -- QUEST 784 DEBUG MODE - фильтруем только нужных NPC
      if QUEST_784_TEST then
        local npc_list = table.concat(QUEST_784_NPCS, ",")
        where_clause = " WHERE creature_template." .. creature_template_pk_col .. " IN (" .. npc_list .. ") "
      end

      local query = mysql:execute('SELECT *, creature_template.'..creature_template_pk_col..' AS _entry FROM creature_template LEFT JOIN ' .. (C.locales_creature or "creature_template_locale") .. ' ON ' .. (C.locales_creature or "creature_template_locale") .. '.' .. creature_loc_pk_col .. ' = creature_template.' .. creature_template_pk_col .. where_clause .. ' GROUP BY creature_template.' .. creature_template_pk_col .. ' ORDER BY creature_template.' .. creature_template_pk_col .. ' ASC')

      if query then
        while query:fetch(locales_creature, "a") do
          if debug("locales_unit") then break end

          local entry = tonumber(locales_creature["_entry"])
          local name = locales_creature["name"]

          if entry then
            for loc in pairs(locales) do
              local name_loc_col = "name_loc" .. GetLocaleNumber(loc)
              local name_loc = locales_creature[name_loc_col]
              if not name_loc or name_loc == "" then name_loc = name or "" end
              if name_loc and name_loc ~= "" then
                local locale = loc .. ( expansion ~= "vanilla"  and "-" .. expansion or "" )
                pfDB["units"][locale] = pfDB["units"][locale] or { [420] = "Shagu" }
                pfDB["units"][locale][entry] = sanitize(name_loc)
              end
            end
          end
        end
      else
        print("  Warning: Failed to execute unit locales query")
      end
    end
  end

  do -- objects locales
    if core == "acore" then
      -- AzerothCore uses separate locale records
      for loc in pairs(locales) do
        local locales_gameobject = {}
        local locale_code = GetLocaleCode(loc)
        local limit_clause = OBJECTS_LIMIT and (' LIMIT ' .. OBJECTS_LIMIT) or ''  -- Use OBJECTS_LIMIT
        local where_clause = ""

        -- QUEST 784 DEBUG MODE - фильтруем только нужные объекты
        if QUEST_784_TEST then
          local object_list = table.concat(QUEST_784_OBJECTS, ",")
          where_clause = " WHERE entry IN (" .. object_list .. ") "
        end

          local query = mysql:execute('SELECT gameobject_template.entry, gameobject_template.name, gameobject_template_locale.name AS locale_name FROM gameobject_template LEFT JOIN gameobject_template_locale ON gameobject_template_locale.entry = gameobject_template.entry AND gameobject_template_locale.locale = \'' .. locale_code .. '\'' .. where_clause .. ' ORDER BY gameobject_template.entry ASC' .. limit_clause)

          if query then
              while query:fetch(locales_gameobject, "a") do
                  if debug("locales_object") then break end

                  local entry = tonumber(locales_gameobject.entry)
                  local name = locales_gameobject.name

                  -- WE MUST ADD THIS LINE TO READ THE RUSSIAN NAME:
                  local locale_name = locales_gameobject.locale_name

                  if entry then
                      -- WE MUST CHANGE THIS LINE SO IT PRIORITIZES THE RUSSIAN NAME:
                      local final_name = locale_name or name or ""

                      if final_name ~= "" then
                          local locale = loc .. ( expansion ~= "vanilla" and "-" .. expansion or "" )
                          pfDB["objects"][locale] = pfDB["objects"][locale] or {}
                          pfDB["objects"][locale][entry] = sanitize(final_name)
                      end
                  end
              end
        else
          print("  Warning: Failed to execute objects locales query for " .. loc)
        end
      end
    else
      -- Original MaNGOS logic
      local locales_gameobject = {}
      local go_loc_pk_col = "entry"
      local go_template_pk_col = "entry"

      local where_clause = ""
      -- QUEST 784 DEBUG MODE - фильтруем только нужные объекты
      if QUEST_784_TEST then
        local object_list = table.concat(QUEST_784_OBJECTS, ",")
        where_clause = " WHERE gameobject_template." .. go_template_pk_col .. " IN (" .. object_list .. ") "
      end

      local query = mysql:execute('SELECT *, gameobject_template.'..go_template_pk_col..' AS _entry FROM gameobject_template LEFT JOIN ' .. (C.locales_gameobject or "gameobject_template_locale") .. ' ON ' .. (C.locales_gameobject or "gameobject_template_locale") .. '.' .. go_loc_pk_col .. ' = gameobject_template.' .. go_template_pk_col .. where_clause .. ' GROUP BY gameobject_template.' .. go_template_pk_col .. ' ORDER BY gameobject_template.' .. go_template_pk_col .. ' ASC')

      if query then
        while query:fetch(locales_gameobject, "a") do
          if debug("locales_object") then break end

          local entry = tonumber(locales_gameobject["_entry"])
          local name = locales_gameobject["name"]

          if entry then
            for loc in pairs(locales) do
              local name_loc_col = "name_loc" .. GetLocaleNumber(loc)
              local name_loc = locales_gameobject[name_loc_col]
              if not name_loc or name_loc == "" then name_loc = name or "" end
              if name_loc and name_loc ~= "" then
                local locale = loc .. ( expansion ~= "vanilla"  and "-" .. expansion or "" )
                pfDB["objects"][locale] = pfDB["objects"][locale] or {}
                pfDB["objects"][locale][entry] = sanitize(name_loc)
              end
            end
          end
        end
      else
        print("  Warning: Failed to execute objects locales query")
      end
    end
  end

  do -- items locales
    if core == "acore" then
      -- AzerothCore uses separate locale records
      for loc in pairs(locales) do
        local locales_item = {}
        local locale_code = GetLocaleCode(loc)
        local limit_clause = ITEMS_LIMIT and (' LIMIT ' .. ITEMS_LIMIT) or ''  -- Use ITEMS_LIMIT
        local where_clause = ""

        -- QUEST 784 DEBUG MODE - фильтруем только нужные предметы
        if QUEST_784_TEST then
          local item_list = table.concat(QUEST_784_ITEMS, ",")
          where_clause = " WHERE item_template.entry IN (" .. item_list .. ") "
        end

        local query_sql = 'SELECT item_template.entry, item_template.name, item_template_locale.Name AS locale_name FROM item_template LEFT JOIN item_template_locale ON item_template_locale.ID = item_template.entry AND item_template_locale.locale = \'' .. locale_code .. '\'' .. where_clause .. ' ORDER BY item_template.entry ASC' .. limit_clause
        local query = mysql:execute(query_sql)

        if query then
          while query:fetch(locales_item, "a") do
            if debug("locales_item") then break end

            local entry = tonumber(locales_item.entry)
            local name = locales_item.name
            local locale_name = locales_item.locale_name

            if entry then
              local final_name = locale_name or name or ""
              if final_name ~= "" then
                local locale = loc .. ( expansion ~= "vanilla" and "-" .. expansion or "" )
                pfDB["items"][locale] = pfDB["items"][locale] or {}
                pfDB["items"][locale][entry] = sanitize(final_name)
              end
            end
          end
        else
          print("  Warning: Failed to execute items locales query for " .. loc)
        end
      end
    else
      -- Original MaNGOS logic
      local locales_item = {}
      local item_loc_pk_col = "entry"
      local item_template_pk_col = "entry"

      local query = mysql:execute('SELECT *, item_template.'..item_template_pk_col..' AS _entry FROM item_template LEFT JOIN ' .. (C.locales_item or "item_template_locale") .. ' ON ' .. (C.locales_item or "item_template_locale") .. '.' .. item_loc_pk_col .. ' = item_template.' .. item_template_pk_col .. ' GROUP BY item_template.' .. item_template_pk_col .. ' ORDER BY item_template.' .. item_template_pk_col .. ' ASC')

      if query then
        while query:fetch(locales_item, "a") do
          if debug("locales_item") then break end

          local entry = tonumber(locales_item["_entry"])
          local name = locales_item["name"]

          if entry then
            for loc in pairs(locales) do
              local name_loc_col = "name_loc" .. GetLocaleNumber(loc)
              local name_loc = locales_item[name_loc_col]
              if not name_loc or name_loc == "" then name_loc = name or "" end
              if name_loc and name_loc ~= "" then
                local locale = loc .. ( expansion ~= "vanilla"  and "-" .. expansion or "" )
                pfDB["items"][locale] = pfDB["items"][locale] or {}
                pfDB["items"][locale][entry] = sanitize(name_loc)
              end
            end
          end
        end
      else
        print("  Warning: Failed to execute items locales query")
      end
    end
  end

  do -- quests locales
    if core == "acore" then
      -- AzerothCore uses separate locale records
      for loc in pairs(locales) do
        local locales_quest = {}
        local locale_code = GetLocaleCode(loc)
        local limit_clause = ""
        local where_clause = ""

        -- QUEST 784 DEBUG MODE - фильтруем только нужный квест
        if QUEST_784_TEST then
          where_clause = " WHERE quest_template.ID IN (" .. table.concat(QUEST_784_IDS, ", ") .. ") "
        else
          limit_clause = QUEST_LIMIT and (' LIMIT ' .. QUEST_LIMIT) or ''
        end

        local query = mysql:execute('SELECT quest_template.ID, quest_template.LogTitle, quest_template.QuestDescription, quest_template.LogDescription, quest_template_locale.Title AS locale_title, quest_template_locale.Details AS locale_details, quest_template_locale.Objectives AS locale_objectives FROM quest_template LEFT JOIN quest_template_locale ON quest_template_locale.ID = quest_template.ID AND quest_template_locale.locale = \'' .. locale_code .. '\' ' .. where_clause .. ' ORDER BY quest_template.ID ASC' .. limit_clause)

        if query then
          while query:fetch(locales_quest, "a") do
            if debug("locales_quest") then break end

            local entry = tonumber(locales_quest.ID)

            if entry then
              local locale = loc .. ( expansion ~= "vanilla" and "-" .. expansion or "" )
              pfDB["quests"][locale] = pfDB["quests"][locale] or {}

              local title = locales_quest.locale_title or locales_quest.LogTitle or ""
              local details = locales_quest.locale_details or locales_quest.QuestDescription or ""
              local objectives = locales_quest.locale_objectives or locales_quest.LogDescription or ""

              pfDB["quests"][locale][entry] = {
                ["T"] = sanitize(title),
                ["O"] = sanitize(objectives),
                ["D"] = sanitize(details)
              }
            end
          end
        else
          print("  Warning: Failed to execute quests locales query for " .. loc)
        end
      end
    else
      -- Original MaNGOS logic
      local locales_quest = {}
      local quest_loc_pk_col = "entry"
      local quest_template_pk_col = "entry"

      local query = mysql:execute('SELECT *, quest_template.'..quest_template_pk_col..' AS _entry FROM quest_template LEFT JOIN ' .. (C.locales_quest or "quest_template_locale") .. ' ON ' .. (C.locales_quest or "quest_template_locale") ..'.' .. quest_loc_pk_col .. ' = quest_template.' .. quest_template_pk_col .. ' GROUP BY quest_template.' .. quest_template_pk_col .. ' ORDER BY quest_template.' .. quest_template_pk_col .. ' ASC')

      if query then
        while query:fetch(locales_quest, "a") do
          if debug("locales_quest") then break end

          for loc in pairs(locales) do
            local entry = tonumber(locales_quest["_entry"])

            if entry then
              local locale = loc .. ( expansion ~= "vanilla"  and "-" .. expansion or "" )
              pfDB["quests"][locale] = pfDB["quests"][locale] or {}

              local title_loc = locales_quest["Title_loc" .. locales[loc]]
              local details_loc = locales_quest["Details_loc" .. locales[loc]]
              local objectives_loc = locales_quest["Objectives_loc" .. locales[loc]]

              if not title_loc or title_loc == "" then title_loc = locales_quest.Title or "" end
              if not details_loc or details_loc == "" then details_loc = locales_quest.Details or "" end
              if not objectives_loc or objectives_loc == "" then objectives_loc = locales_quest.Objectives or "" end

              pfDB["quests"][locale][entry] = {
                ["T"] = sanitize(title_loc),
                ["O"] = sanitize(objectives_loc),
                ["D"] = sanitize(details_loc)
              }
            end
          end
        end
      else
        print("  Warning: Failed to execute quests locales query")
      end
    end
    local end_time_locales = os.clock()
    table.insert(execution_times, {name = "locales", time = end_time_locales - start_time_locales})
    -- ДОБАВЬТЕ:
    collectgarbage("collect")
    print("  Memory cleanup after quest-locales: " .. math.floor(collectgarbage("count")) .. " KB")
  end

  do -- professions locales
    pfDB["professions"] = {}

    if core == "acore" then
      -- For AzerothCore, use loaded DBC skillline table (lowercase name)
      local locales_professions = {}
      local dbc_exp = config.dbc_expansion or "wotlk"
      local query = mysql:execute('SELECT * FROM skillline_'..dbc_exp..' ORDER BY id ASC')
      if query then
        local profession_count = 0
        while query:fetch(locales_professions, "a") do
          if debug("locales_profession") then break end

          local entry = tonumber(locales_professions.id)
          profession_count = profession_count + 1

          if entry then
            for loc in pairs(locales) do
              -- Use appropriate locale column or fallback to enUS
              local locale_col = "name_loc" .. (locales[loc] or "0")
              local name = locales_professions[locale_col] or locales_professions["name_loc0"]
              if name and name ~= "" then
                local locale = loc .. ( expansion ~= "vanilla"  and "-" .. expansion or "" )
                pfDB["professions"][locale] = pfDB["professions"][locale] or {}
                pfDB["professions"][locale][entry] = sanitize(name)

              end
            end
          end
        end
        query:close()
      else
        print("  Warning: Failed to query professions locales from skillline_" .. dbc_exp .. " table")
      end
    else
      -- Original logic for other cores
      local locales_professions = {}
      local query = mysql:execute('SELECT * FROM pfquest.SkillLine_'..expansion..' ORDER BY id ASC')
      if query then
        while query:fetch(locales_professions, "a") do
          if debug("locales_profession") then break end

          local entry = tonumber(locales_professions.id)

          if entry then
            for loc in pairs(locales) do
              local name = locales_professions["name_loc" .. locales[loc]]
              if name and name ~= "" then
                local locale = loc .. ( expansion ~= "vanilla"  and "-" .. expansion or "" )
                pfDB["professions"][locale] = pfDB["professions"][locale] or {}
                pfDB["professions"][locale][entry] = sanitize(name)
              end
            end
          end
        end
      end
    end
  end

  if expansion ~= "vanilla" then
    print("- compress DB")
    pfDB["areatrigger"][data] = tablesubstract(pfDB["areatrigger"][data], pfDB["areatrigger"]["data"])
    pfDB["units"][data] = tablesubstract(pfDB["units"][data], pfDB["units"]["data"])
    pfDB["objects"][data] = tablesubstract(pfDB["objects"][data], pfDB["objects"]["data"])
    pfDB["items"][data] = tablesubstract(pfDB["items"][data], pfDB["items"]["data"])
    pfDB["refloot"][data] = tablesubstract(pfDB["refloot"][data], pfDB["refloot"]["data"])
    pfDB["quests"][data] = tablesubstract(pfDB["quests"][data], pfDB["quests"]["data"])
    pfDB["quests-itemreq"][data] = tablesubstract(pfDB["quests-itemreq"][data], pfDB["quests-itemreq"]["data"])
    pfDB["zones"][data] = tablesubstract(pfDB["zones"][data], pfDB["zones"]["data"])
    pfDB["minimap"..exp] = tablesubstract(pfDB["minimap"..exp], pfDB["minimap"])
    pfDB["meta"..exp] = tablesubstract(pfDB["meta"..exp], pfDB["meta"])

    for loc in pairs(locales) do
      local locale = loc .. exp
      local prev_locale = loc

      pfDB["units"][locale] = pfDB["units"][locale] and tablesubstract(pfDB["units"][locale], pfDB["units"][prev_locale]) or {}
      pfDB["objects"][locale] = pfDB["objects"][locale] and tablesubstract(pfDB["objects"][locale], pfDB["objects"][prev_locale]) or {}
      pfDB["items"][locale] = pfDB["items"][locale] and tablesubstract(pfDB["items"][locale], pfDB["items"][prev_locale]) or {}
      pfDB["quests"][locale] = pfDB["quests"][locale] and tablesubstract(pfDB["quests"][locale], pfDB["quests"][prev_locale]) or {}
      pfDB["zones"][locale] = pfDB["zones"][locale] and tablesubstract(pfDB["zones"][locale], pfDB["zones"][prev_locale]) or {}
      pfDB["professions"][locale] = pfDB["professions"][locale] and tablesubstract(pfDB["professions"][locale], pfDB["professions"][prev_locale]) or {}
    end
  end

      -- ДОБАВЬТЕ:
      collectgarbage("collect")
      print("  Memory cleanup after compression: " .. math.floor(collectgarbage("count")) .. " KB")

  -- ================================================================
  -- ZONES LOCALES EXTRACTION
  -- ================================================================
  print("- loading zones locales...")

  local dbc_area_table_name = "AreaTable_wotlk" -- Имя таблицы DBC с зонами

  -- Убедитесь, что эти переменные определены и доступны:
  -- all_locales: Таблица {["enUS"]=0, ["deDE"]=3, ...} - маппинг ключа локали на номер колонки _locX.
  -- locales: Таблица активных локалей для текущей экспансии (из config).
  -- exp: Строковый суффикс экспансии ("" или "-wotlk" и т.п.).
  -- sanitize: Функция для очистки строк.

  if not all_locales or not locales or exp == nil or not sanitize then
      print("  ERROR: Prerequisite variables (all_locales, locales, exp, sanitize) not available for zones locales. Skipping.")
  else
      for loc_key, _ in pairs(locales) do
          local loc_number = all_locales[loc_key]

          if loc_number == nil then
              print(string.format("  WARNING: Locale number for '%s' not in all_locales. Skipping zones locale.", loc_key))
          else
              local current_pfdb_key = loc_key .. exp
              pfDB["zones"] = pfDB["zones"] or {}
              pfDB["zones"][current_pfdb_key] = pfDB["zones"][current_pfdb_key] or {}

              local locale_field = "name_loc" .. loc_number
              local sql = string.format(
                  "SELECT ID, %s AS LocalizedName FROM %s WHERE ID != 0 AND %s IS NOT NULL AND %s != '' ORDER BY ID ASC",
                  locale_field, dbc_area_table_name, locale_field, locale_field
              )

              local query = mysql:execute(sql)
              if query then
                  local row, count = {}, 0
                  while query:fetch(row, "a") do
                      local zone_id = tonumber(row.ID)
                      if zone_id and row.LocalizedName then
                          pfDB["zones"][current_pfdb_key][zone_id] = sanitize(row.LocalizedName)
                          count = count + 1
                      end
                  end
                  query:close()
                  print(string.format("  Loaded %d zone names for locale '%s' (pfDB key: '%s').", count, loc_key, current_pfdb_key))
              else
                  print(string.format("  ERROR: SQL query failed for zones locale '%s'.", loc_key))
              end
          end
      end
  end
      -- ДОБАВЬТЕ:
      collectgarbage("collect")
      print("  Memory cleanup after zone-locales: " .. math.floor(collectgarbage("count")) .. " KB")

  -- write down tables
  print("- writing database...")
  output = settings.custom and "output/custom/" or "output/"

  mkdir(output)

  -- Memory-optimized serialization with aggressive cleanup
  print("  Writing areatrigger...")
  serialize(output .. string.format("areatrigger%s.lua", exp), "pfDB[\"areatrigger\"][\""..data.."\"]", pfDB["areatrigger"][data])
  pfDB["areatrigger"][data] = nil  -- Free memory immediately
  collectgarbage("collect")
  collectgarbage("collect")  -- Double collect for better cleanup
  -- print("    Memory after areatrigger: " .. math.floor(collectgarbage("count")) .. " KB")

  print("  Writing units...")
  serialize(output .. string.format("units%s.lua", exp), "pfDB[\"units\"][\""..data.."\"]", pfDB["units"][data])
  pfDB["units"][data] = nil
  collectgarbage("collect")
  collectgarbage("collect")
  -- print("    Memory after units: " .. math.floor(collectgarbage("count")) .. " KB")

  print("  Writing objects...")
  serialize(output .. string.format("objects%s.lua", exp), "pfDB[\"objects\"][\""..data.."\"]", pfDB["objects"][data])
  pfDB["objects"][data] = nil
  collectgarbage("collect")
  collectgarbage("collect")
  -- print("    Memory after objects: " .. math.floor(collectgarbage("count")) .. " KB")

  print("  Writing items...")
  serialize(output .. string.format("items%s.lua", exp), "pfDB[\"items\"][\""..data.."\"]", pfDB["items"][data])
  pfDB["items"][data] = nil
  collectgarbage("collect")
  collectgarbage("collect")
  -- print("    Memory after items: " .. math.floor(collectgarbage("count")) .. " KB")

  print("  Writing refloot...")
  serialize(output .. string.format("refloot%s.lua", exp), "pfDB[\"refloot\"][\""..data.."\"]", pfDB["refloot"][data])
  pfDB["refloot"][data] = nil
  collectgarbage("collect")
  collectgarbage("collect")
  -- print("    Memory after refloot: " .. math.floor(collectgarbage("count")) .. " KB")

  print("  Writing quests...")
  serialize(output .. string.format("quests%s.lua", exp), "pfDB[\"quests\"][\""..data.."\"]", pfDB["quests"][data])
  pfDB["quests"][data] = nil
  collectgarbage("collect")
  collectgarbage("collect")
  -- print("    Memory after quests: " .. math.floor(collectgarbage("count")) .. " KB")

  print("  Writing questxp...")
  serialize(output .. string.format("questxp%s.lua", exp), "pfDB[\"questxp\"][\""..data.."\"]", pfDB["questxp"][data])
  pfDB["questxp"][data] = nil
  collectgarbage("collect")
  collectgarbage("collect")

  print("  Writing quests-itemreq...")
  serialize(output .. string.format("quests-itemreq%s.lua", exp), "pfDB[\"quests-itemreq\"][\""..data.."\"]", pfDB["quests-itemreq"][data])
  pfDB["quests-itemreq"][data] = nil
  collectgarbage("collect")
  collectgarbage("collect")
  -- print("    Memory after quests-itemreq: " .. math.floor(collectgarbage("count")) .. " KB")

  print("  Writing zones...")
  serialize(output .. string.format("zones%s.lua", exp), "pfDB[\"zones\"][\""..data.."\"]", pfDB["zones"][data])
  pfDB["zones"][data] = nil
  collectgarbage("collect")
  collectgarbage("collect")
  -- print("    Memory after zones: " .. math.floor(collectgarbage("count")) .. " KB")

  print("  Writing minimap...")
  serialize(output .. string.format("minimap%s.lua", exp), "pfDB[\"minimap"..exp.."\"]", pfDB["minimap"..exp])
  pfDB["minimap"..exp] = nil
  collectgarbage("collect")
  collectgarbage("collect")
  -- print("    Memory after minimap: " .. math.floor(collectgarbage("count")) .. " KB")

  print("  Writing meta...")
  serialize(output .. string.format("meta%s.lua", exp), "pfDB[\"meta"..exp.."\"]", pfDB["meta"..exp])
  pfDB["meta"..exp] = nil
  collectgarbage("collect")
  collectgarbage("collect")
  -- print("    Memory after meta: " .. math.floor(collectgarbage("count")) .. " KB")

  print("  Writing locale data...")
  for loc in pairs(locales) do
    local locale = loc .. ( expansion ~= "vanilla"  and "-" .. expansion or "" )
    print("    Processing locale: " .. loc)

    mkdir(output .. loc)

    if pfDB["units"][locale] then
      serialize(output .. string.format("%s/units%s.lua", loc, exp), "pfDB[\"units\"][\""..locale.."\"]", pfDB["units"][locale])
      pfDB["units"][locale] = nil
    end
    collectgarbage("collect")
    collectgarbage("collect")

    if pfDB["objects"][locale] then
      serialize(output .. string.format("%s/objects%s.lua", loc, exp), "pfDB[\"objects\"][\""..locale.."\"]", pfDB["objects"][locale])
      pfDB["objects"][locale] = nil
    end
    collectgarbage("collect")
    collectgarbage("collect")

    if pfDB["items"][locale] then
      serialize(output .. string.format("%s/items%s.lua", loc, exp), "pfDB[\"items\"][\""..locale.."\"]", pfDB["items"][locale])
      pfDB["items"][locale] = nil
    end
    collectgarbage("collect")
    collectgarbage("collect")

    if pfDB["quests"][locale] then
      serialize(output .. string.format("%s/quests%s.lua", loc, exp), "pfDB[\"quests\"][\""..locale.."\"]", pfDB["quests"][locale])
      pfDB["quests"][locale] = nil
    end
    collectgarbage("collect")
    collectgarbage("collect")

    if pfDB["professions"][locale] then
      serialize(output .. string.format("%s/professions%s.lua", loc, exp), "pfDB[\"professions\"][\""..locale.."\"]", pfDB["professions"][locale])
      pfDB["professions"][locale] = nil
    end
    collectgarbage("collect")
    collectgarbage("collect")

    if pfDB["zones"][locale] then
      serialize(output .. string.format("%s/zones%s.lua", loc, exp), "pfDB[\"zones\"][\""..locale.."\"]", pfDB["zones"][locale])
      pfDB["zones"][locale] = nil
    end
    collectgarbage("collect")
    collectgarbage("collect")

    -- print("      Memory after locale " .. loc .. ": " .. math.floor(collectgarbage("count")) .. " KB")
  end

  -- Final aggressive memory cleanup after all main data written
  print("  Performing final memory cleanup...")

  -- Clear any remaining data structures
  for key in pairs(pfDB) do
    if type(pfDB[key]) == "table" then
      for subkey in pairs(pfDB[key]) do
        pfDB[key][subkey] = nil
      end
    end
  end

  -- Multiple garbage collection passes for maximum cleanup
  collectgarbage("collect")
  collectgarbage("collect")
  collectgarbage("collect")
  -- print("    Final memory before init.lua: " .. math.floor(collectgarbage("count")) .. " KB")

  -- Create minimal empty init.lua to avoid 'block too big' error
  if not settings.custom then
    local init_file = io.open(output .. "init.lua", "w")
    if init_file then
      init_file:write([[pfDB = {
  ["areatrigger"] = {},
  ["items"] = {},
  ["meta"] = {},
  ["minimap"] = {},
  ["objects"] = {},
  ["professions"] = {},
  ["quests"] = {},
  ["quests-itemreq"] = {},
  ["questxp"] = {},
  ["refloot"] = {},
  ["units"] = {},
  ["zones"] = {},
}
]])
      init_file:close()
--       print("Created empty init.lua")
    end
  end

  debug_statistics()
else
  print("Error: Expansion '" .. expansion_to_process .. "' not found in config.expansions")
end

-- === DEBUG/ПАТЧ: Явная генерация локализованного zones.lua ===
for loc in pairs(locales) do
  local locale = loc .. ( expansion ~= "vanilla" and "-" .. expansion or "" )
  local outdir = output .. loc
  mkdir(outdir)
  local outpath = outdir .. "/zones" .. (exp or "") .. ".lua"
  print("DEBUG: Writing zones for locale", locale, "to", outpath)
  if pfDB["zones"][locale] then
    print("DEBUG: pfDB[\"zones\"][\"" .. locale .. "\"] has " .. TableCount(pfDB["zones"][locale]) .. " entries")
    if pfDB["zones"][locale][14] then
      print("DEBUG: Durotar in zones:", pfDB["zones"][locale][14])
    else
      print("WARNING: Durotar (14) not found in pfDB[\"zones\"][\"" .. locale .. "\"]!")
    end
    serialize(outpath, "pfDB[\"zones\"][\"" .. locale .. "\"]", pfDB["zones"][locale])
    os.execute('mkdir "db/' .. loc .. '" 2>nul')
    os.execute('copy "' .. outpath .. '" "db/' .. loc .. '/zones.lua"')
    print("DEBUG: zones.lua copied to db/" .. loc .. "/zones.lua")
  else
    print("ERROR: pfDB[\"zones\"][\"" .. locale .. "\"] is nil! Zones localization not generated!")
  end
end

-- ================================================================
-- АВТОМАТИЧЕСКОЕ КОПИРОВАНИЕ ФАЙЛОВ ПОСЛЕ ЭКСТРАКЦИИ
-- ================================================================

-- Zone fallback statistics
zone_fallback_count = zone_fallback_count or 0
total_units_processed = total_units_processed or 0

if total_units_processed > 0 then
  print("================================================================")
  print("Zone Detection Statistics:")
  print("  Total units processed: " .. total_units_processed)
  print("  Zone fallbacks used: " .. zone_fallback_count)
  if total_units_processed > 0 then
    print("  Success rate: " .. math.floor(((total_units_processed - zone_fallback_count) / total_units_processed) * 100) .. "%")
  end
  print("================================================================")
end

  debug_statistics()

print("================================================================")
print("BLOCK EXECUTION TIMES:")
if execution_times and #execution_times > 0 then
    local total_time = 0
    for _, data in ipairs(execution_times) do
        print(string.format("  BLOCK '%s' execution time: %.4f seconds", data.name, data.time))
        total_time = total_time + data.time
    end
    print("  --------------------------------------------------------")
    print(string.format("  TOTAL execution time: %.4f seconds", total_time))
    print("Extraction completed!")
else
    print("  No execution times recorded.")
end
print("================================================================")



-- Автоматически запускаем скрипт копирования файлов
local transfer_result = os.execute("copy_files.bat auto")

if transfer_result == 0 then
  if QUEST_784_TEST then
--     print("🎯 QUEST 784 DEBUG: Ready for testing! Commands: /run print(\"Quest 784:\", pfDB[\"quests\"][\"data\"][784] and \"FOUND\" or \"NOT FOUND\"); print(\"NPC 3139:\", pfDB[\"units\"][\"data\"][3139] and \"FOUND\" or \"NOT FOUND\")")
  else
--     print("✅ Extraction completed! Test: /run local count = 0; for _ in pairs(pfDB[\"quests\"][\"data\"]) do count = count + 1 end; print(\"Total quests:\", count)")
  end
else
  print("⚠️  File transfer failed - run copy_files.bat manually")
end

-- Close main processing

-- ================================================================
-- Helper functions for proper zone selection on world map
-- ================================================================

-- Cache for continent-level WorldMapArea lookups
local continent_zone_cache = {}

-- REMOVED: Duplicate functions IsZoneOnContinentMap and NormalizeDisplayZone
-- Using the original versions above instead

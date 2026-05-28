# pfQuest AzerothCore Debug Guide

## 🎯 ЦЕЛЬ
Настроить pfQuest для работы с AzerothCore WotLK без множественных экстракций

## 📊 ТЕКУЩИЙ СТАТУС
- ✅ pfQuest загружается (1000 квестов)
- ✅ Базовая структура работает
- ❌ Координаты существ не извлекаются
- ❌ Квесты не отображаются на карте

## 🔧 ГЛАВНАЯ ПРОБЛЕМА
**Неправильное поле для связи creature_template ↔ creature**

### В extractor.lua строка ~625:
```lua
WHERE creature.id = ]] .. id .. [[
```

### Нужно найти правильное поле в AzerothCore:
```sql
-- В HeidiSQL проверь структуру:
DESCRIBE creature;
DESCRIBE creature_template;

-- Найди связь между таблицами:
SELECT * FROM creature LIMIT 1;
SELECT * FROM creature_template LIMIT 1;
```

Возможные варианты:
- `creature.id1` (была раньше)
- `creature.entry`
- `creature.guid`
- `creature.creature_id`

## 🛠️ DEBUGGING БЕЗ ЭКСТРАКЦИИ

### 1. SQL Диагностика (HeidiSQL)

#### Проверь структуру таблиц:
```sql
-- Основные поля creature
SHOW COLUMNS FROM creature;

-- Первые записи
SELECT id, entry, position_x, position_y, map, zoneId, areaId
FROM creature
LIMIT 5;

-- Количество записей по ID
SELECT COUNT(*) as total_creatures FROM creature;
SELECT COUNT(DISTINCT id) as unique_ids FROM creature;
SELECT COUNT(DISTINCT entry) as unique_entries FROM creature;
```

#### Тест связи creature_template ↔ creature:
```sql
-- Проверь есть ли существо ID 1 в creature_template
SELECT entry, name FROM creature_template WHERE entry = 1;

-- Проверь есть ли спавны существа ID 1
SELECT COUNT(*) FROM creature WHERE id = 1;      -- тест текущего
SELECT COUNT(*) FROM creature WHERE entry = 1;   -- тест альтернативы
SELECT COUNT(*) FROM creature WHERE id1 = 1;     -- тест старого
```

#### Найди правильное поле:
```sql
-- Если creature_template.entry = 1 существует, найди соответствующие спавны
SELECT c.*, ct.name
FROM creature c
JOIN creature_template ct ON c.[ПОЛЕ] = ct.entry
WHERE ct.entry = 1
LIMIT 5;

-- Попробуй разные поля:
-- c.id = ct.entry
-- c.entry = ct.entry
-- c.id1 = ct.entry
```

### 2. Быстрая проверка extractor.lua

#### Перед экстракцией добавь дебаг:
```lua
-- В функции GetCreatureCoords добавь перед запросом:
print("DEBUG: Looking for creature ID " .. id)
local test_query = mysql:execute("SELECT COUNT(*) as count FROM creature WHERE creature.id = " .. id)
if test_query then
    local result = {}
    test_query:fetch(result, "a")
    print("DEBUG: Found " .. (result.count or 0) .. " spawns for creature " .. id)
end
```

#### Тест одного существа:
```lua
-- Измени FAST_MODE лимит на 1 существо для быстрого теста:
local limit_clause = config.debug and ' LIMIT 1' or ''
```

### 3. In-Game диагностика

#### Команды pfQuest debug (уже есть):
```
/pftest     - полная диагностика
/pfstats    - быстрая статистика
/pfdebug    - базовый отчет
```

#### Проверка конкретных данных:
```lua
-- Проверь есть ли координаты у популярных существ
/run for i=1,10 do local u=pfDB["units"]["data"][i]; if u and u.coords and #u.coords>0 then print("Unit "..i.." has "..#u.coords.." coords") end end

-- Проверь связь квест → существо
/run local q=pfDB["quests"]["data"][7]; if q and q.obj and q.obj.U then for id,count in pairs(q.obj.U) do print("Quest 7 needs Unit "..id) end end

-- Проверь зоны
/run local count=0; for id,zone in pairs(pfDB["zones"]["data"]) do count=count+1; if count<=5 then print("Zone "..id..": "..zone[1]) end end
```

## 🎯 ПЛАН ОТЛАДКИ

### Этап 1: SQL анализ (5 минут)
1. Открой HeidiSQL
2. Выполни запросы из раздела "SQL Диагностика"
3. Найди правильное поле для связи таблиц

### Этап 2: Исправление extractor.lua (2 минуты)
1. Замени `creature.id` на найденное поле
2. Добавь дебаг-вывод
3. Установи лимит 1 для быстрого теста

### Этап 3: Быстрый тест (3 минуты)
1. Запусти экстракцию с лимитом 1
2. Проверь появились ли координаты в output/units.lua
3. Если да - убери лимит и делай полную экстракцию

### Этап 4: Проверка в игре (2 минуты)
1. Скопируй файлы: `transfer_files.bat`
2. Перезапусти WoW
3. Выполни `/pftest`
4. Попробуй `/db quest Kobold Camp Cleanup`

## 🚨 ИЗВЕСТНЫЕ ПРОБЛЕМЫ

### Coordinates в zone 0
Если координаты извлекаются, но все в zone 0:

```lua
-- В GetCreatureCoords исправь:
local final_zone = area_id and area_id > 0 and area_id or zone_id and zone_id > 0 and zone_id or 14
-- Где 14 = Durotar zone ID
```

### Пустые таблицы координат
- Неправильное поле связи creature ↔ creature_template
- Неверный SQL запрос
- Проблемы с базой данных

### pfQuest не показывает квесты
1. ✅ Данные есть (`/pftest`)
2. ❌ Координаты пустые → исправь extractor
3. ❌ Координаты в zone 0 → исправь зоны
4. ❌ Конфиг pfQuest → проверь `/db config`

## 📝 КОНТРОЛЬНЫЕ ТОЧКИ

### ✅ Экстракция успешна если:
- `units.lua` содержит координаты (не пустые `coords = {}`)
- Координаты не все в zone 0
- Размер файла > 1000 строк

### ✅ pfQuest работает если:
- `/pftest` показывает юниты с координатами
- При клике на квест в браузере появляются точки на карте
- `/db quest Kobold Camp Cleanup` показывает маркеры

## 🔧 БЫСТРЫЕ ИСПРАВЛЕНИЯ

### Если нашел правильное поле:
```lua
-- extractor.lua строка ~625:
WHERE creature.[ПРАВИЛЬНОЕ_ПОЛЕ] = ]] .. id .. [[
```

### Если нужно исправить зоны:
```lua
-- Замени zone 0 на реальный ID зоны
local final_zone = area_id and area_id > 0 and area_id or zone_id and zone_id > 0 and zone_id or 14
```

### Если extractor не находит существ:
```sql
-- Проверь есть ли данные:
SELECT COUNT(*) FROM creature;
SELECT COUNT(*) FROM creature_template;
SELECT COUNT(*) FROM creature WHERE entry IN (SELECT entry FROM creature_template LIMIT 10);
```

## 🎯 ЦЕЛЬ ИТЕРАЦИИ
1. **Один SQL запрос** → найти правильное поле
2. **Одно исправление** в extractor.lua
3. **Одна экстракция** → проверить результат
4. **Один тест** в игре → подтвердить работу

## 📞 ПОМОЩЬ ИИ
При обращении предоставь:
1. Результат `DESCRIBE creature;`
2. Вывод `/pftest` из игры
3. Первые 10 строк `output/units.lua`
4. Скриншот проблемы в игре

Это минимизирует количество итераций и ускорит решение проблемы.

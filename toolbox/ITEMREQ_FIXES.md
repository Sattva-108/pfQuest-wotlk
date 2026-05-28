# ItemReq Fixes for AzerothCore Compatibility

## Summary of Changes Made to extractor.lua

### 1. **spell_script_target → spell_scripts Migration**

**Problem**: AzerothCore doesn't have `spell_script_target` table, uses `spell_scripts` instead.

**Fix**: Added compatibility layer that:
- Detects which table to use based on configuration
- For AzerothCore: Uses `spell_scripts` with proper command/target_type mapping
- For Legacy cores: Falls back to original `spell_script_target` logic

**Key Changes**:
```lua
local script_table = C["spell_script_target"] or "spell_scripts"
if script_table == "spell_scripts" then
  -- AzerothCore logic using command/target_type
else
  -- Legacy logic using type/targetEntry  
end
```

### 2. **Missing Spell Protection**

**Problem**: Items referencing non-existent spells in spell_dbc cause errors.

**Fix**: Added spell existence check:
```lua
if spellid and tonumber(spellid) > 0 then
  local spell_found = false
  while spell_query:fetch(spell_template, "a") do
    spell_found = true
    -- process spell
  end
  if not spell_found then
    -- log and skip
  end
end
```

### 3. **item_required_target Table Handling**

**Problem**: `item_required_target` table doesn't exist in AzerothCore.

**Fix**: Added dynamic table existence check:
```lua
local check_table_query = mysql:execute("SHOW TABLES LIKE 'item_required_target'")
if check_table_query and check_table_query:fetch() then
  -- process table
else
  -- skip gracefully
end
```

### 4. **AzerothCore spell_scripts Command Mapping**

**Commands Handled**:
- Command 15 (`SCRIPT_COMMAND_CAST_SPELL`) with different target types:
  - `target_type = 1`: Unit (positive ID)
  - `target_type = 2`: GameObject (negative ID)

## Testing Recommendations

1. **Run `/pfa`** to validate itemreq data after extraction
2. **Check for empty itemreq**: Should now have entries if items exist
3. **Test with debug enabled**: `debug("quests_itemspell")` to see processing
4. **Verify spell_scripts data**: Make sure your AC database has spell_scripts entries

## Configuration

Ensure your extractor configuration has:
```lua
["spell_script_target"] = "spell_scripts"
```

This tells the extractor to use AzerothCore's table structure.

## Backward Compatibility

These changes maintain compatibility with non-AzerothCore servers that still use the original table structure.
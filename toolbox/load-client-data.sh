#!/bin/bash
root="DBC"
rootsql="client-data.sql"
versions="vanilla turtle tbc wotlk"
locales="enUS koKR frFR deDE zhCN zhTW esES esMX ruRU jaJP ptBR"

# delete old extraction
if [ -f "$rootsql" ]; then
  rm $rootsql
fi

function Run() {
  echo "- $1" &&  $1
}

function WorldMapOverlay() {
  cat >> $rootsql << EOF
DROP TABLE IF EXISTS \`WorldMapOverlay_${v}\`;
CREATE TABLE \`WorldMapOverlay_${v}\` (
\`areaID\` smallint(3) unsigned NOT NULL,
\`zoneID\` smallint(3) unsigned NOT NULL,
\`texture\` varchar(255),
\`textureWidth\` smallint(3) unsigned NOT NULL,
\`textureHeight\` smallint(3) unsigned NOT NULL,
\`offsetX\` smallint(3) unsigned NOT NULL,
\`offsetY\` smallint(3) unsigned NOT NULL,
\`hitRectTop\` smallint(3) unsigned NOT NULL,
\`hitRectLeft\` smallint(3) unsigned NOT NULL,
\`hitRectBottom\` smallint(3) unsigned NOT NULL,
\`hitRectRight\` smallint(3) unsigned NOT NULL
) ENGINE=MyISAM DEFAULT CHARSET=utf8 ROW_FORMAT=FIXED COMMENT='WorldMapOverlay';

EOF

  if [ -d $root/$v ] && [ -f $root/$v/WorldMapOverlay.dbc.csv ]; then
    cat $root/$v/WorldMapOverlay.dbc.csv | tail -n +2 | sort -nt ',' -k3,3 | while IFS= read -r line; do
      # Remove quotes and split properly
      line_clean=$(echo "$line" | sed 's/"//g')
      IFS=',' read -ra FIELDS <<< "$line_clean"

      areaID="${FIELDS[2]}"       # AreaID_1
      zoneID="${FIELDS[1]}"       # MapAreaID
      texture="\"${FIELDS[8]}\""  # TextureName (re-add quotes)
      textureWidth="${FIELDS[9]}"
      textureHeight="${FIELDS[10]}"
      offsetX="${FIELDS[11]}"
      offsetY="${FIELDS[12]}"
      top="${FIELDS[13]}"
      left="${FIELDS[14]}"
      bottom="${FIELDS[15]}"
      right="${FIELDS[16]}"

      echo "INSERT INTO \`WorldMapOverlay_${v}\` VALUES ($areaID, $zoneID, $texture, $textureWidth, $textureHeight, $offsetX, $offsetY, $top, $left, $bottom, $right);" >> $rootsql
    done
  fi
}


function AreaTrigger() {
  cat >> $rootsql << EOF
DROP TABLE IF EXISTS \`AreaTrigger_${v}\`;
CREATE TABLE \`AreaTrigger_${v}\` (
\`ID\` smallint(3) unsigned NOT NULL,
\`MapID\` smallint(3) unsigned NOT NULL,
\`X\` float NOT NULL DEFAULT 0.0,
\`Y\` float NOT NULL DEFAULT 0.0,
\`Z\` float NOT NULL DEFAULT 0.0,
\`Size\` float NOT NULL DEFAULT 0.0
) ENGINE=MyISAM DEFAULT CHARSET=utf8 ROW_FORMAT=FIXED COMMENT='AreaTrigger';

EOF

  if [ -d $root/$v ] && [ -f $root/$v/AreaTrigger.dbc.csv ]; then
    cat $root/$v/AreaTrigger.dbc.csv | tail -n +2 | sort -nt "," -k1,1 | while IFS= read -r line; do
      # Remove quotes and split by comma, handling quoted values properly
      line_clean=$(echo "$line" | sed 's/"//g')

      # Use array to split fields properly
      IFS=',' read -ra FIELDS <<< "$line_clean"

      id="${FIELDS[0]}"
      map="${FIELDS[1]}"
      x="${FIELDS[2]}"
      y="${FIELDS[3]}"
      z="${FIELDS[4]}"
      size="${FIELDS[5]}"

      # Convert comma decimals to dot decimals for MySQL
      x=$(echo "$x" | sed 's/,/./g')
      y=$(echo "$y" | sed 's/,/./g')
      z=$(echo "$z" | sed 's/,/./g')
      size=$(echo "$size" | sed 's/,/./g')

      echo "INSERT INTO \`AreaTrigger_${v}\` VALUES ($id, $map, $x, $y, $z, $size);" >> $rootsql
    done
  fi
}

function WorldMapArea() {
  cat >> $rootsql << EOF
DROP TABLE IF EXISTS \`WorldMapArea_${v}\`;
CREATE TABLE \`WorldMapArea_${v}\` (
\`zoneID\` smallint(3) unsigned NOT NULL,
\`mapID\` smallint(3) unsigned NOT NULL,
\`areatableID\` smallint(3) unsigned NOT NULL,
\`name\` varchar(255) NOT NULL,
\`x_min\` float NOT NULL DEFAULT 0.0,
\`y_min\` float NOT NULL DEFAULT 0.0,
\`x_max\` float NOT NULL DEFAULT 0.0,
\`y_max\` float NOT NULL DEFAULT 0.0
) ENGINE=MyISAM DEFAULT CHARSET=utf8 ROW_FORMAT=FIXED COMMENT='WorldMapArea';

EOF

if [ -d $root/$v ] && [ -f $root/$v/WorldMapArea.dbc.csv ]; then
    cat $root/$v/WorldMapArea.dbc.csv | tail -n +2 | sort -nt ',' -k3,3 | while IFS= read -r line; do
      # Парсим CSV с учетом кавычек
      zone=$(echo "$line" | cut -d'"' -f2)
      map=$(echo "$line" | cut -d'"' -f4)
      area=$(echo "$line" | cut -d'"' -f6)
      name=$(echo "$line" | cut -d'"' -f8)
      loc_left=$(echo "$line" | cut -d'"' -f10)
      loc_right=$(echo "$line" | cut -d'"' -f12)
      loc_top=$(echo "$line" | cut -d'"' -f14)
      loc_bottom=$(echo "$line" | cut -d'"' -f16)

      # Convert comma decimals to dot decimals for MySQL
      loc_left=$(echo "$loc_left" | sed 's/,/./g')
      loc_right=$(echo "$loc_right" | sed 's/,/./g')
      loc_top=$(echo "$loc_top" | sed 's/,/./g')
      loc_bottom=$(echo "$loc_bottom" | sed 's/,/./g')

      # Calculate proper min/max coordinates using robust numeric comparison
      # Use printf and sort for proper floating point comparison
      x_min=$(printf "%s\n%s" "$loc_left" "$loc_right" | sort -n | head -n1)
      x_max=$(printf "%s\n%s" "$loc_left" "$loc_right" | sort -n | tail -n1)
      y_min=$(printf "%s\n%s" "$loc_top" "$loc_bottom" | sort -n | head -n1)
      y_max=$(printf "%s\n%s" "$loc_top" "$loc_bottom" | sort -n | tail -n1)

      echo "INSERT INTO \`WorldMapArea_${v}\` VALUES ($zone, $map, $area, \"$name\", $x_min, $y_min, $x_max, $y_max);" >> $rootsql
    done
  fi
}

function FactionTemplate() {
  cat >> $rootsql << EOF
DROP TABLE IF EXISTS \`FactionTemplate_${v}\`;
CREATE TABLE \`FactionTemplate_${v}\` (
\`factiontemplateID\` smallint(3) unsigned NOT NULL,
\`factionID\` smallint(3) unsigned NOT NULL,
\`A\` smallint(1) NOT NULL,
\`H\` smallint(1) NOT NULL
) ENGINE=MyISAM DEFAULT CHARSET=utf8 ROW_FORMAT=FIXED COMMENT='WorldMapArea';

EOF

  local csv_file_path="$root/$v/FactionTemplate.dbc.csv"
  echo "DEBUG FactionTemplate: Checking for file: [$csv_file_path] for version [$v]"

  if [ -f "$csv_file_path" ]; then
    echo "DEBUG FactionTemplate: File FOUND: [$csv_file_path]"
    echo "DEBUG FactionTemplate: Starting to process file..."

    local line_count=0
    local processed_count=0

    # Попытка прочитать первую строку данных для проверки cut
    local first_data_line=$(tail -n +2 "$csv_file_path" | head -n 1)
    if [ -n "$first_data_line" ]; then
        echo "DEBUG FactionTemplate: First data line of CSV: [$first_data_line]"
        local test_factiontemplate_id=$(echo "$first_data_line" | cut -d "," -f 1)
        local test_faction_id=$(echo "$first_data_line" | cut -d "," -f 2)
        local test_friendly_group=$(echo "$first_data_line" | cut -d "," -f 5)
        local test_enemy_group=$(echo "$first_data_line" | cut -d "," -f 6)
        echo "DEBUG FactionTemplate: Test cut - factiontemplate_id: [$test_factiontemplate_id], faction_id: [$test_faction_id], friendly_group: [$test_friendly_group], enemy_group: [$test_enemy_group]"
    else
        echo "DEBUG FactionTemplate: WARNING - Could not read first data line from CSV or CSV is empty (after header)."
    fi

    # Основной цикл обработки
    tail -n +2 "$csv_file_path" | sort -nt ',' -k1,1 | while IFS= read -r line; do # Изменено на sort -k1,1, если -k3 было опечаткой
      line_count=$((line_count + 1))
      echo "----------------------------------------------------"
      echo "DEBUG FactionTemplate: Processing line #$line_count: [$line]"

      factiontemplate=$(echo "$line" | cut -d "," -f 1)
      faction=$(echo "$line" | cut -d "," -f 2)
      # Убрал кавычки из friendly и hostile, чтобы cut работал с чистыми значениями, если они в кавычках в CSV
      friendly_raw=$(echo "$line" | cut -d "," -f 5)
      hostile_raw=$(echo "$line" | cut -d "," -f 6)

      # Удаляем возможные кавычки из извлеченных значений
      friendly=${friendly_raw//\"/}
      hostile=${hostile_raw//\"/}

      echo "DEBUG FactionTemplate VARS: factiontemplate=[$factiontemplate], faction=[$faction], friendly_raw=[$friendly_raw], hostile_raw=[$hostile_raw], friendly_clean=[$friendly], hostile_clean=[$hostile]"

      # Проверка, являются ли friendly и hostile числами
      if ! [[ "$friendly" =~ ^[0-9]+$ ]] || ! [[ "$hostile" =~ ^[0-9]+$ ]]; then
        echo "DEBUG FactionTemplate: WARNING - Non-numeric value for friendly or hostile. friendly=[$friendly], hostile=[$hostile]. Skipping line."
        continue # Пропустить эту строку, если значения нечисловые
      fi

      local alliance=0
      local horde=0

      # Логика определения Альянса/Орды (та же, что и раньше, но с отладкой)
      echo "DEBUG FactionTemplate: Checking Horde hostility: hostile_val=[$hostile]"
      if [ $(( 4 & $hostile )) != 0 ] || [ "$hostile" = "1" ]; then
        horde=-1
        echo "DEBUG FactionTemplate: Horde set to -1 (hostile)"
      elif [ $(( 4 & $friendly )) != 0 ] || [ "$friendly" = "1" ]; then
        horde=1
        echo "DEBUG FactionTemplate: Horde set to 1 (friendly)"
      else
        horde=0
        echo "DEBUG FactionTemplate: Horde set to 0 (neutral)"
      fi

      echo "DEBUG FactionTemplate: Checking Alliance hostility: hostile_val=[$hostile]"
      if [ $(( 2 & $hostile )) != 0 ] || [ "$hostile" = "1" ]; then
        alliance=-1
        echo "DEBUG FactionTemplate: Alliance set to -1 (hostile)"
      elif [ $(( 2 & $friendly )) != 0 ] || [ "$friendly" = "1" ]; then
        alliance=1
        echo "DEBUG FactionTemplate: Alliance set to 1 (friendly)"
      else
        alliance=0
        echo "DEBUG FactionTemplate: Alliance set to 0 (neutral)"
      fi

      echo "DEBUG FactionTemplate: Final values for SQL: factiontemplate=[$factiontemplate], faction=[$faction], alliance=[$alliance], horde=[$horde]"
      echo "INSERT INTO \`FactionTemplate_${v}\` VALUES ($factiontemplate, $faction, $alliance, $horde);" >> $rootsql
      processed_count=$((processed_count + 1))
    done
    echo "----------------------------------------------------"
    echo "DEBUG FactionTemplate: Finished processing. Total lines read from CSV (after header): $line_count. Lines inserted into SQL: $processed_count."
  else
    echo "DEBUG FactionTemplate: File NOT FOUND: [$csv_file_path]"
  fi
}

function Lock() {
  cat >> $rootsql << EOF
DROP TABLE IF EXISTS \`Lock_${v}\`;
CREATE TABLE \`Lock_${v}\` (
\`id\` smallint(3) unsigned NOT NULL,
\`locktype\` smallint(3) NOT NULL,
\`data\` smallint(3) unsigned NOT NULL,
\`skill\` smallint(3) unsigned NOT NULL
) ENGINE=MyISAM DEFAULT CHARSET=utf8 ROW_FORMAT=FIXED COMMENT='Lock';

EOF

  if [ -d $root/$v ] && [ -f $root/$v/Lock.dbc.csv ]; then
    cat $root/$v/Lock.dbc.csv | tail -n +2 | while read line; do
      id=$(echo $line | cut -d "," -f 1)
      locktype=$(echo $line | cut -d "," -f 2)
      locktype=$(echo $locktype | cut -d "x" -f 2)
      data=$(echo $line | cut -d "," -f 10)
      skill=$(echo $line | cut -d "," -f 18)

      # hackfix to display chests
      if [ "$id" = "57" ]; then
        echo "INSERT INTO \`Lock_${v}\` VALUES (57, 2, 1, 0);" >> $rootsql
      else
        echo "INSERT INTO \`Lock_${v}\` VALUES ($id, $locktype, $data, $skill);" >> $rootsql
      fi

    done
  fi
}

function SkillLine() {
  cat >> $rootsql << EOF
DROP TABLE IF EXISTS \`SkillLine_${v}\`;
CREATE TABLE \`SkillLine_${v}\` (
\`id\` smallint(3) unsigned NOT NULL,
\`name_loc0\` varchar(255) NOT NULL,
\`name_loc1\` varchar(255) NOT NULL,
\`name_loc2\` varchar(255) NOT NULL,
\`name_loc3\` varchar(255) NOT NULL,
\`name_loc4\` varchar(255) NOT NULL,
\`name_loc5\` varchar(255) NOT NULL,
\`name_loc6\` varchar(255) NOT NULL,
\`name_loc7\` varchar(255) NOT NULL,
\`name_loc8\` varchar(255) NOT NULL,
\`name_loc10\` varchar(255) NOT NULL
) ENGINE=MyISAM DEFAULT CHARSET=utf8 ROW_FORMAT=FIXED COMMENT='SkillLine';

EOF

  index=0
  for loc in $locales; do
    # locale fixes
    if [ "$loc" = "ruRU" ] && [ "$v" == "vanilla" ]; then
      dbcslot=0 # there's no index for ruRU in 1.12, using enUS index
    elif [ "$loc" = "ptBR" ] && [ "$v" == "vanilla" ]; then
      dbcslot=0 # there's no index for ptBR in 1.12, using enUS index
    elif [ "$loc" = "deDE" ] && [ "$v" == "turtle" ]; then
      dbcslot=0 # no turtle client for that language, falling back to enUS
    elif [ "$loc" = "esMX" ] && [ "$v" == "turtle" ]; then
      dbcslot=0 # no turtle client for that language, falling back to enUS
    elif [ "$loc" = "frFR" ] && [ "$v" == "turtle" ]; then
      dbcslot=0 # no turtle client for that language, falling back to enUS
    elif [ "$loc" = "jaJP" ] && [ "$v" == "turtle" ]; then
      dbcslot=0 # no turtle client for that language, falling back to enUS
    elif [ "$loc" = "koKR" ] && [ "$v" == "turtle" ]; then
      dbcslot=0 # no turtle client for that language, falling back to enUS
    elif [ "$loc" = "ruRU" ] && [ "$v" == "turtle" ]; then
      dbcslot=0 # no turtle client for that language, falling back to enUS
    elif [ "$loc" = "zhTW" ] && [ "$v" == "turtle" ]; then
      dbcslot=0 # no turtle client for that language, falling back to enUS
    elif [ "$loc" = "ptBR" ] && [ "$v" == "turtle" ]; then
      dbcslot=7 # turtle uses xxYY (loc7) for ptBR
    else
      dbcslot=$index
    fi

    if [ -d $root/$v ] && [ -f $root/$v/$loc/SkillLine.dbc.csv ]; then
      tail -n +2 $root/$v/$loc/SkillLine.dbc.csv | while read line; do
        id=$(echo $line | cut -d , -f 1)
        entry=$(echo $line | cut -d , -f $(expr 4 + $dbcslot))

        if [ "$loc" = "enUS" ]; then
          echo "INSERT INTO \`SkillLine_${v}\` VALUES ($id, $entry, '', '', '', '', '', '', '', '', '');" >> $rootsql
        elif [ "$loc" = "ptBR" ] && [ "$v" == "turtle" ]; then
          echo "UPDATE \`SkillLine_${v}\` SET name_loc7 = $entry WHERE id = $id;" >> $rootsql
        else
          echo "UPDATE \`SkillLine_${v}\` SET name_loc$index = $entry WHERE id = $id;" >> $rootsql
        fi
      done
    fi
    index=$(expr $index + 1)
  done
}

function AreaTable() {
  cat >> $rootsql << EOF
DROP TABLE IF EXISTS \`AreaTable_${v}\`;
CREATE TABLE \`AreaTable_${v}\` (
\`id\` int(3) unsigned NOT NULL,
\`zoneID\` smallint(3) unsigned NOT NULL,
\`name_loc0\` varchar(255) NOT NULL,
\`name_loc1\` varchar(255) NOT NULL,
\`name_loc2\` varchar(255) NOT NULL,
\`name_loc3\` varchar(255) NOT NULL,
\`name_loc4\` varchar(255) NOT NULL,
\`name_loc5\` varchar(255) NOT NULL,
\`name_loc6\` varchar(255) NOT NULL,
\`name_loc7\` varchar(255) NOT NULL,
\`name_loc8\` varchar(255) NOT NULL,
\`name_loc10\` varchar(255) NOT NULL
) ENGINE=MyISAM DEFAULT CHARSET=utf8 ROW_FORMAT=FIXED COMMENT='AreaTable';

EOF


  index=0
  for loc in $locales; do
    # locale fixes
    if [ "$loc" = "ruRU" ] && [ "$v" == "vanilla" ]; then
      dbcslot=0 # there's no index for ruRU in 1.12, using enUS index
    elif [ "$loc" = "ptBR" ] && [ "$v" == "vanilla" ]; then
      dbcslot=0 # there's no index for ptBR in 1.12, using enUS index
    elif [ "$loc" = "deDE" ] && [ "$v" == "turtle" ]; then
      dbcslot=0 # no turtle client for that language, falling back to enUS
    elif [ "$loc" = "esMX" ] && [ "$v" == "turtle" ]; then
      dbcslot=0 # no turtle client for that language, falling back to enUS
    elif [ "$loc" = "frFR" ] && [ "$v" == "turtle" ]; then
      dbcslot=0 # no turtle client for that language, falling back to enUS
    elif [ "$loc" = "jaJP" ] && [ "$v" == "turtle" ]; then
      dbcslot=0 # no turtle client for that language, falling back to enUS
    elif [ "$loc" = "koKR" ] && [ "$v" == "turtle" ]; then
      dbcslot=0 # no turtle client for that language, falling back to enUS
    elif [ "$loc" = "ruRU" ] && [ "$v" == "turtle" ]; then
      dbcslot=0 # no turtle client for that language, falling back to enUS
    elif [ "$loc" = "zhTW" ] && [ "$v" == "turtle" ]; then
      dbcslot=0 # no turtle client for that language, falling back to enUS
    elif [ "$loc" = "ptBR" ] && [ "$v" == "turtle" ]; then
      dbcslot=7 # turtle uses xxYY (loc7) for ptBR
    else
      dbcslot=$index
    fi

    if [ -d $root/$v ] && [ -f $root/$v/$loc/AreaTable.dbc.csv ]; then
      tail -n +2 $root/$v/$loc/AreaTable.dbc.csv | while read line; do
        id=$(echo $line | cut -d , -f 1)
        zoneID=$(echo $line | cut -d , -f 3)
        entry=$(echo $line | cut -d , -f $(expr 12 + $dbcslot))
        if ! [ -z "$entry" ] && [ "$entry" != "\"\"" ]; then
          entry=$(echo $entry | sed 's/""/\\"/g')
        fi

        # some zones must be flagged with UNUSED for some locales
        unused_zones="55 276 394 407 470 474 476 696 697 698 699 1196"
        if [ "$loc" = "zhCN" ]; then
          for unused in $unused_zones; do
            if [ "$unused" == "$id" ]; then
              entry="\"$(echo ${entry} | sed 's/"//g')UNUSED\""
            fi
          done
        fi

        if [ "$loc" = "enUS" ]; then
          echo "INSERT INTO \`AreaTable_${v}\` VALUES ($id, $zoneID, $entry, '', '', '', '', '', '', '', '', '');" >> $rootsql
        elif [ "$loc" = "ptBR" ] && [ "$v" == "turtle" ]; then
          echo "UPDATE \`AreaTable_${v}\` SET name_loc7 = $entry WHERE id = $id;" >> $rootsql
        else
          echo "UPDATE \`AreaTable_${v}\` SET name_loc$index = $entry WHERE id = $id;" >> $rootsql
        fi
      done
    fi
    index=$(expr $index + 1)
  done
}

# build sql tables
for v in $versions; do
  echo "Expansion: $v"

  Run WorldMapOverlay
  Run AreaTrigger
  Run WorldMapArea
  Run FactionTemplate
  Run Lock
  Run SkillLine
  Run AreaTable
done

# Добавляем команду read в самом конце, чтобы окно не закрывалось
echo "Script finished. Press Enter to close."
read

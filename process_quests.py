import re
import csv
import os

# Get the directory where the script is located
script_dir = os.path.dirname(os.path.abspath(__file__))

# Define file paths relative to the script's location
quests_lua_path = os.path.join(script_dir, 'quests.lua')
quests_csv_path = os.path.join(script_dir, 'quests.csv')

# Regex to find lines that start with '[questID] = {'
quest_id_pattern = re.compile(r'^\s*\[(\d+)\]\s*=\s*\{')

print(f"Reading from: {quests_lua_path}")
print(f"Writing to: {quests_csv_path}")

try:
    with open(quests_lua_path, 'r', encoding='utf-8') as f_in, \
         open(quests_csv_path, 'w', newline='', encoding='utf-8') as f_out:

        writer = csv.writer(f_out)
        # Write the header row
        writer.writerow(['ID', 'Wowhead Link', 'Completion Time'])

        processed_count = 0
        # Process the lua file line by line
        for line in f_in:
            match = quest_id_pattern.match(line)
            if match:
                # ensure quest line contains both start and end definitions
                if ('["start"]' not in line) or ('["end"]' not in line):
                    continue  # skip quests without explicit start or end

                # skip pure delivery/turn-in quests that lack objectives block
                if '["obj"]' not in line:
                    continue

                quest_id = match.group(1)
                # Determine expansion for correct Wowhead subdomain
                qid = int(quest_id)
                if qid < 9000:
                    expansion_prefix = 'classic'
                elif qid < 11559:
                    expansion_prefix = 'tbc'
                else:
                    expansion_prefix = 'wotlk'

                wowhead_link = f'https://www.wowhead.com/{expansion_prefix}/quest={quest_id}'
                writer.writerow([quest_id, wowhead_link, ''])
                processed_count += 1
    
    print(f"Successfully processed {processed_count} quests.")
    print(f"CSV file created at: {quests_csv_path}")

except FileNotFoundError:
    print(f"Error: Could not find the file {quests_lua_path}")
except Exception as e:
    print(f"An error occurred: {e}")

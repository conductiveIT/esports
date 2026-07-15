#!/usr/bin/env python3
import os
import sys
import sqlite3
import re
import json
import argparse

class LuaParser:
    def __init__(self, text):
        text = text.strip()
        self.locals = {}
        
        # Match pattern: _[1]="string"
        local_matches = re.findall(r'_\[(\d+)\]\s*=\s*"(.*?)"', text)
        for idx, val in local_matches:
            self.locals[int(idx)] = val
            
        # Find where return starts
        return_match = re.search(r'return\s+(.*)', text, re.DOTALL)
        if return_match:
            text = return_match.group(1).strip()
        
        # Apply substitutions
        for idx in sorted(self.locals.keys(), reverse=True):
            val = self.locals[idx]
            text = re.sub(rf'\[\s*_\s*\[\s*{idx}\s*\]\s*\]', f'["{val}"]', text)
            text = re.sub(rf'_\s*\[\s*{idx}\s*\](?!\d)', f'"{val}"', text)
            
        self.text = text
        self.pos = 0
        self.length = len(text)

    def skip_whitespace(self):
        while self.pos < self.length and self.text[self.pos].isspace():
            self.pos += 1

    def parse(self):
        self.skip_whitespace()
        if self.pos >= self.length:
            return None
        
        char = self.text[self.pos]
        if char == '{':
            return self.parse_table()
        elif char == '"' or char == "'":
            return self.parse_string()
        elif char.isdigit() or char == '-' or char == '.':
            return self.parse_number()
        elif self.text[self.pos:self.pos+4] == "true":
            self.pos += 4
            return True
        elif self.text[self.pos:self.pos+5] == "false":
            self.pos += 5
            return False
        elif self.text[self.pos:self.pos+3] == "nil":
            self.pos += 3
            return None
        else:
            return self.parse_identifier()

    def parse_string(self):
        quote = self.text[self.pos]
        self.pos += 1
        start = self.pos
        while self.pos < self.length and self.text[self.pos] != quote:
            if self.text[self.pos] == '\\':
                self.pos += 2
            else:
                self.pos += 1
        val = self.text[start:self.pos]
        self.pos += 1
        try:
            return val.encode().decode('unicode-escape')
        except Exception:
            return val

    def parse_number(self):
        start = self.pos
        while self.pos < self.length and (self.text[self.pos].isdigit() or self.text[self.pos] in '-.eE+'):
            self.pos += 1
        num_str = self.text[start:self.pos]
        if '.' in num_str or 'e' in num_str or 'E' in num_str:
            return float(num_str)
        else:
            return int(num_str)

    def parse_identifier(self):
        start = self.pos
        while self.pos < self.length and (self.text[self.pos].isalnum() or self.text[self.pos] in '_'):
            self.pos += 1
        val = self.text[start:self.pos]
        return val

    def parse_table(self):
        self.pos += 1
        self.skip_whitespace()
        
        is_array = True
        items = []
        dict_items = {}
        
        while self.pos < self.length and self.text[self.pos] != '}':
            self.skip_whitespace()
            if self.pos >= self.length or self.text[self.pos] == '}':
                break
            
            # Check for keys
            key = None
            if self.text[self.pos] == '[':
                self.pos += 1
                self.skip_whitespace()
                key = self.parse()
                self.skip_whitespace()
                if self.pos < self.length and self.text[self.pos] == ']':
                    self.pos += 1
                self.skip_whitespace()
                if self.pos < self.length and self.text[self.pos] == '=':
                    self.pos += 1
                    is_array = False
            elif self.text[self.pos] == '"' or self.text[self.pos] == "'":
                # Check ahead for '=' to see if it's a key
                orig_pos = self.pos
                temp_key = self.parse_string()
                self.skip_whitespace()
                if self.pos < self.length and self.text[self.pos] == '=':
                    self.pos += 1
                    key = temp_key
                    is_array = False
                else:
                    self.pos = orig_pos
            else:
                # Check for identifier key like: name = "value"
                orig_pos = self.pos
                ident = self.parse_identifier()
                self.skip_whitespace()
                if self.pos < self.length and self.text[self.pos] == '=':
                    self.pos += 1
                    key = ident
                    is_array = False
                else:
                    self.pos = orig_pos

            self.skip_whitespace()
            val = self.parse()
            
            if is_array:
                items.append(val)
            else:
                if key is not None:
                    dict_items[key] = val
            
            self.skip_whitespace()
            if self.pos < self.length and self.text[self.pos] == ',':
                self.pos += 1
            elif self.pos < self.length and self.text[self.pos] == ';':
                self.pos += 1
                
        if self.pos < self.length:
            self.pos += 1 # skip '}'
            
        if is_array:
            return items
        else:
            return dict_items

def load_teams(db_path):
    if not os.path.exists(db_path):
        print(f"Error: Database not found at '{db_path}'")
        sys.exit(1)
        
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # Get esports_league teams
    cursor.execute("SELECT value FROM entries WHERE modname = 'esports_league' AND key = 'teams';")
    teams_row = cursor.fetchone()
    
    teams = {}
    if teams_row:
        teams_val = teams_row[0]
        v = teams_val.decode('utf-8', errors='ignore') if isinstance(teams_val, bytes) else teams_val
        try:
            parser = LuaParser(v)
            parsed_teams = parser.parse()
            if isinstance(parsed_teams, dict):
                teams = parsed_teams
        except Exception as e:
            print(f"Error parsing teams: {e}")
            
    # Load nicknames from esports_core
    cursor.execute("SELECT value FROM entries WHERE modname = 'esports_core' AND key = ?;", (b'nicknames',))
    nicknames_row = cursor.fetchone()
    nicknames = {}
    if nicknames_row:
        nicknames_val = nicknames_row[0]
        v = nicknames_val.decode('utf-8', errors='ignore') if isinstance(nicknames_val, bytes) else nicknames_val
        try:
            parser = LuaParser(v)
            parsed_nicks = parser.parse()
            if isinstance(parsed_nicks, dict):
                for nk, nv in parsed_nicks.items():
                    nicknames[str(nk)] = nv
        except Exception as e:
            print(f"Warning: Failed to parse nicknames: {e}")
            
    conn.close()
    
    # Build clean output
    output_teams = []
    for name, data in teams.items():
        members = data.get("members", [])
        if isinstance(members, dict):
            # Convert dict keys/values if needed
            members = list(members.values())
            
        formatted_members = []
        for mname in members:
            formatted_members.append({
                "username": mname,
                "nickname": nicknames.get(mname, mname)
            })
            
        output_teams.append({
            "name": name,
            "logo_id": data.get("logo_id", "eagle"),
            "leader": data.get("leader", ""),
            "members": formatted_members
        })
        
    return output_teams

def main():
    parser = argparse.ArgumentParser(description="Export Luanti Esports teams database to JSON.")
    parser.add_argument("world_dir", help="Path to the Luanti/Minetest World directory containing mod_storage.sqlite")
    args = parser.parse_args()
    
    db_path = os.path.join(args.world_dir, "mod_storage.sqlite")
    print(f"Reading league database from: {db_path}...")
    
    teams_data = load_teams(db_path)
    
    # Save to teams.json in the same folder as the HTML file
    script_dir = os.path.dirname(os.path.abspath(__file__))
    output_path = os.path.join(script_dir, "teams.json")
    
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(teams_data, f, indent=4)
        
    print(f"Success! Exported {len(teams_data)} teams to: {output_path}")

if __name__ == "__main__":
    main()

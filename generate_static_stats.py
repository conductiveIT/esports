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
            
        # Find where return starts (using re.DOTALL so that '.' matches newlines in multi-line tables)
        return_match = re.search(r'return\s+(.*)', text, re.DOTALL)
        if return_match:
            text = return_match.group(1).strip()
        
        # Apply substitutions for the compression tables in descending order of index
        for idx in sorted(self.locals.keys(), reverse=True):
            val = self.locals[idx]
            # Replace [_[1]] with ["captures"]
            text = re.sub(rf'\[\s*_\s*\[\s*{idx}\s*\]\s*\]', f'["{val}"]', text)
            # Replace _[1] with "captures" (ensuring it's not followed by a digit)
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
        array_index = 1
        
        while self.pos < self.length:
            self.skip_whitespace()
            if self.pos >= self.length:
                break
            if self.text[self.pos] == '}':
                self.pos += 1
                break
            
            has_key = False
            key = None
            
            if self.text[self.pos] == '[':
                self.pos += 1
                key = self.parse()
                self.skip_whitespace()
                if self.pos < self.length and self.text[self.pos] == ']':
                    self.pos += 1
                self.skip_whitespace()
                if self.pos < self.length and self.text[self.pos] == '=':
                    self.pos += 1
                    has_key = True
            elif self.pos < self.length:
                start_pos = self.pos
                ident = self.parse_identifier()
                self.skip_whitespace()
                if self.pos < self.length and self.text[self.pos] == '=':
                    self.pos += 1
                    key = ident
                    has_key = True
                else:
                    self.pos = start_pos
            
            val = self.parse()
            if has_key:
                is_array = False
                dict_items[key] = val
            else:
                items.append(val)
                dict_items[array_index] = val
                array_index += 1
                
            self.skip_whitespace()
            if self.pos < self.length and self.text[self.pos] == ',':
                self.pos += 1
            elif self.pos < self.length and self.text[self.pos] == ';':
                self.pos += 1
                
        if is_array:
            return items
        else:
            return dict_items

def load_league_data(db_path):
    if not os.path.exists(db_path):
        print(f"Error: Database not found at '{db_path}'")
        sys.exit(1)
        
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # Check table existence
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='entries';")
    if not cursor.fetchone():
        print("Error: The 'entries' table was not found in mod_storage.sqlite.")
        sys.exit(1)
        
    cursor.execute("SELECT key, value FROM entries WHERE modname = 'esports_league';")
    rows = cursor.fetchall()
    
    raw_data = {}
    for key, value in rows:
        k = key.decode('utf-8', errors='ignore') if isinstance(key, bytes) else key
        v = value.decode('utf-8', errors='ignore') if isinstance(value, bytes) else value
        raw_data[k] = v
        
    # Load nicknames from esports_core (querying key as binary to match SQLite BLOB format)
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
                    if isinstance(nk, (str, int)) and isinstance(nv, str):
                        nicknames[str(nk)] = nv
        except Exception as e:
            print(f"Warning: Failed to parse nicknames: {e}")
            
    conn.close()
    
    # Parse keys
    parsed_data = {}
    expected_dicts = {"teams", "players", "stats", "requests", "invites"}
    expected_lists = {"fixtures", "history", "season_archive"}
    
    for key, val_str in raw_data.items():
        try:
            parser = LuaParser(val_str)
            parsed = parser.parse()
            # Enforce types for empty tables {}
            if key in expected_dicts and isinstance(parsed, list):
                parsed = {}
            if key in expected_lists and isinstance(parsed, dict):
                parsed = []
            parsed_data[key] = parsed
        except Exception as e:
            print(f"Warning: Failed to parse key '{key}': {e}")
            parsed_data[key] = {} if key in expected_dicts else []
            
    parsed_data["nicknames"] = nicknames
    
    # Default values for missing keys
    for key in expected_dicts:
        if key not in parsed_data:
            parsed_data[key] = {}
    for key in expected_lists:
        if key not in parsed_data:
            parsed_data[key] = []
    if "season_state" not in parsed_data:
        parsed_data["season_state"] = "offseason"
    if "playoffs" not in parsed_data:
        parsed_data["playoffs"] = {}
        
    return parsed_data

# HTML/CSS/JS Template
HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Luanti Deathmatch Esports League</title>
    <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;600;800&display=swap" rel="stylesheet">
    <style>
        :root {
            --bg-color: #0b0f19;
            --card-bg: rgba(22, 27, 34, 0.85);
            --card-border: rgba(48, 54, 61, 0.7);
            --text-color: #f0f6fc;
            --text-muted: #8b949e;
            --accent-color: #00f2fe;
            --accent-purple: #4facfe;
            --success-color: #10b981;
            --red-team: #ff4d4d;
            --blue-team: #3399ff;
            --shadow: 0 8px 32px 0 rgba(0, 0, 0, 0.37);
        }

        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }

        body {
            font-family: 'Outfit', sans-serif;
            background-color: var(--bg-color);
            background-image: radial-gradient(circle at 50% 10%, #151e33 0%, var(--bg-color) 70%);
            color: var(--text-color);
            min-height: 100vh;
            display: flex;
            flex-direction: column;
            align-items: center;
            overflow-x: hidden;
        }

        header {
            width: 100%;
            max-width: 1200px;
            padding: 2.5rem 1rem 1rem;
            display: flex;
            flex-direction: column;
            align-items: center;
            text-align: center;
        }

        .logo-container {
            display: flex;
            align-items: center;
            gap: 12px;
            margin-bottom: 0.5rem;
        }

        .logo-text {
            font-size: 2.5rem;
            font-weight: 800;
            text-transform: uppercase;
            letter-spacing: 2px;
            background: linear-gradient(135deg, var(--accent-color) 0%, var(--accent-purple) 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            text-shadow: 0 4px 10px rgba(0, 242, 254, 0.2);
        }

        .subtitle {
            color: var(--text-muted);
            font-size: 1.1rem;
            font-weight: 300;
            letter-spacing: 1px;
            text-transform: uppercase;
            margin-bottom: 2rem;
        }

        .tab-menu {
            display: flex;
            flex-wrap: wrap;
            gap: 10px;
            justify-content: center;
            max-width: 1200px;
            width: 95%;
            margin-bottom: 2rem;
            background: rgba(13, 17, 23, 0.6);
            padding: 8px;
            border-radius: 12px;
            border: 1px solid var(--card-border);
            backdrop-filter: blur(10px);
        }

        .tab-btn {
            background: transparent;
            border: none;
            color: var(--text-muted);
            padding: 10px 20px;
            font-size: 1rem;
            font-weight: 600;
            cursor: pointer;
            border-radius: 8px;
            transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
            display: flex;
            align-items: center;
            gap: 8px;
        }

        .tab-btn:hover {
            color: var(--text-color);
            background: rgba(255, 255, 255, 0.05);
        }

        .tab-btn.active {
            color: var(--bg-color);
            background: linear-gradient(135deg, var(--accent-color) 0%, var(--accent-purple) 100%);
            box-shadow: 0 4px 15px rgba(0, 242, 254, 0.3);
        }

        main {
            width: 100%;
            max-width: 1200px;
            padding: 0 1rem 4rem;
            display: flex;
            flex-direction: column;
            align-items: center;
        }

        .tab-content {
            display: none;
            width: 100%;
            animation: fadeIn 0.4s ease-out forwards;
        }

        .tab-content.active {
            display: block;
        }

        @keyframes fadeIn {
            from { opacity: 0; transform: translateY(10px); }
            to { opacity: 1; transform: translateY(0); }
        }

        /* Dashboard/Cards Styling */
        .highlight-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
            gap: 20px;
            width: 100%;
            margin-bottom: 2rem;
        }

        .glass-card {
            background: var(--card-bg);
            border: 1px solid var(--card-border);
            border-radius: 16px;
            padding: 1.5rem;
            box-shadow: var(--shadow);
            backdrop-filter: blur(10px);
            transition: transform 0.3s ease, border-color 0.3s ease;
            position: relative;
            overflow: hidden;
        }

        .glass-card:hover {
            transform: translateY(-4px);
            border-color: rgba(0, 242, 254, 0.4);
        }

        .glass-card::before {
            content: '';
            position: absolute;
            top: 0;
            left: 0;
            width: 4px;
            height: 100%;
            background: linear-gradient(to bottom, var(--accent-color), var(--accent-purple));
        }

        .card-title {
            color: var(--text-muted);
            font-size: 0.9rem;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 1px;
            margin-bottom: 0.5rem;
        }

        .card-value {
            font-size: 1.8rem;
            font-weight: 800;
            margin-bottom: 0.2rem;
        }

        .card-desc {
            font-size: 0.85rem;
            color: var(--text-muted);
        }

        /* Status Badge */
        .status-badge {
            display: inline-block;
            padding: 4px 10px;
            border-radius: 20px;
            font-size: 0.8rem;
            font-weight: 800;
            text-transform: uppercase;
        }
        .status-offseason { background: rgba(139, 148, 158, 0.2); color: var(--text-muted); border: 1px solid var(--text-muted); }
        .status-regular_season { background: rgba(16, 185, 129, 0.2); color: var(--success-color); border: 1px solid var(--success-color); }
        .status-playoffs { background: rgba(255, 77, 77, 0.2); color: var(--red-team); border: 1px solid var(--red-team); }

        /* Tables */
        .table-container {
            width: 100%;
            overflow-x: auto;
            background: var(--card-bg);
            border: 1px solid var(--card-border);
            border-radius: 16px;
            box-shadow: var(--shadow);
            margin-bottom: 2rem;
        }

        table {
            width: 100%;
            border-collapse: collapse;
            text-align: left;
        }

        th {
            background: rgba(13, 17, 23, 0.8);
            color: var(--text-muted);
            padding: 16px;
            font-size: 0.9rem;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            border-bottom: 1px solid var(--card-border);
        }

        td {
            padding: 16px;
            border-bottom: 1px solid rgba(48, 54, 61, 0.4);
            font-size: 1rem;
            font-weight: 400;
        }

        tr:hover td {
            background: rgba(255, 255, 255, 0.02);
        }

        .rank-badge {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            width: 28px;
            height: 28px;
            border-radius: 50%;
            font-weight: 800;
            font-size: 0.9rem;
            background: rgba(255, 255, 255, 0.1);
        }
        tr:nth-child(1) .rank-badge:not(.ur-badge) { background: linear-gradient(135deg, #ffd700, #ffa500); color: #000; }
        tr:nth-child(2) .rank-badge:not(.ur-badge) { background: linear-gradient(135deg, #c0c0c0, #808080); color: #000; }
        tr:nth-child(3) .rank-badge:not(.ur-badge) { background: linear-gradient(135deg, #cd7f32, #8b4513); color: #000; }
        .ur-badge {
            background: rgba(255, 255, 255, 0.05) !important;
            color: var(--text-muted) !important;
            box-shadow: none !important;
        }

        /* Teams Cards Grid */
        .teams-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
            gap: 20px;
            width: 100%;
        }

        .team-card {
            border-left: 5px solid var(--accent-purple);
        }
        .team-card.red-border { border-left-color: var(--red-team); }
        .team-card.blue-border { border-left-color: var(--blue-team); }

        .team-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 1rem;
            padding-bottom: 0.5rem;
            border-bottom: 1px solid rgba(48, 54, 61, 0.4);
        }

        .team-name {
            font-size: 1.4rem;
            font-weight: 800;
        }

        .team-leader {
            font-size: 0.85rem;
            color: var(--text-muted);
            margin-bottom: 0.8rem;
        }
        .team-leader span {
            color: var(--accent-color);
            font-weight: 600;
        }

        .roster-list {
            list-style: none;
            display: flex;
            flex-direction: column;
            gap: 8px;
        }

        .roster-item {
            font-size: 0.95rem;
            display: flex;
            justify-content: space-between;
            align-items: center;
            background: rgba(255, 255, 255, 0.02);
            padding: 8px 12px;
            border-radius: 8px;
            border: 1px solid rgba(48, 54, 61, 0.2);
        }

        /* Search & Filters */
        .controls-bar {
            display: flex;
            flex-wrap: wrap;
            gap: 15px;
            width: 100%;
            margin-bottom: 1.5rem;
        }

        .search-input, .select-input {
            background: var(--card-bg);
            border: 1px solid var(--card-border);
            color: var(--text-color);
            padding: 12px 16px;
            border-radius: 10px;
            font-family: inherit;
            font-size: 0.95rem;
            outline: none;
            transition: border-color 0.3s;
        }
        .search-input { flex-grow: 1; min-width: 250px; }
        .select-input { min-width: 180px; }
        .search-input:focus, .select-input:focus {
            border-color: var(--accent-color);
        }

        /* Fixtures Rounds */
        .round-container {
            width: 100%;
            margin-bottom: 2.5rem;
        }

        .round-title {
            font-size: 1.5rem;
            font-weight: 800;
            margin-bottom: 1rem;
            color: var(--accent-color);
            display: flex;
            align-items: center;
            gap: 10px;
        }
        .round-title::after {
            content: '';
            flex-grow: 1;
            height: 1px;
            background: var(--card-border);
        }

        .match-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
            gap: 20px;
        }

        .match-card {
            display: flex;
            flex-direction: column;
            padding: 1.2rem;
            align-items: center;
            text-align: center;
        }

        .match-status-label {
            font-size: 0.75rem;
            font-weight: 800;
            text-transform: uppercase;
            padding: 3px 8px;
            border-radius: 12px;
            margin-bottom: 0.8rem;
        }
        .status-completed { background: rgba(16, 185, 129, 0.15); color: var(--success-color); }
        .status-pending { background: rgba(245, 158, 11, 0.15); color: #f59e0b; }

        .match-teams {
            display: flex;
            justify-content: space-between;
            align-items: center;
            width: 100%;
            gap: 10px;
            margin-bottom: 0.5rem;
        }

        .match-team {
            font-weight: 600;
            font-size: 1.05rem;
            width: 42%;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }
        .match-team.home { text-align: right; }
        .match-team.away { text-align: left; }

        .match-score {
            font-size: 1.5rem;
            font-weight: 800;
            color: var(--text-color);
            background: rgba(0, 0, 0, 0.3);
            padding: 4px 12px;
            border-radius: 8px;
            font-variant-numeric: tabular-nums;
            min-width: 60px;
        }

        /* Bracket Styling */
        .bracket-container {
            display: flex;
            justify-content: center;
            align-items: center;
            gap: 40px;
            width: 100%;
            overflow-x: auto;
            padding: 2rem 0;
        }

        .bracket-column {
            display: flex;
            flex-direction: column;
            gap: 40px;
            min-width: 250px;
        }

        .bracket-round-title {
            text-align: center;
            font-weight: 800;
            font-size: 1.1rem;
            color: var(--accent-color);
            margin-bottom: 1rem;
            text-transform: uppercase;
        }

        .bracket-match {
            background: var(--card-bg);
            border: 1px solid var(--card-border);
            border-radius: 12px;
            overflow: hidden;
            box-shadow: var(--shadow);
            position: relative;
        }

        .bracket-match-row {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 12px 16px;
            border-bottom: 1px solid rgba(48, 54, 61, 0.3);
        }
        .bracket-match-row:last-child { border-bottom: none; }

        .bracket-team-name {
            font-weight: 600;
            font-size: 0.95rem;
        }
        .bracket-team-name.winner {
            color: var(--accent-color);
        }

        .bracket-score {
            font-weight: 800;
            background: rgba(0, 0, 0, 0.2);
            padding: 2px 8px;
            border-radius: 4px;
            font-size: 0.9rem;
        }

        /* Responsive Design */
        @media (max-width: 768px) {
            .logo-text { font-size: 1.8rem; }
            .subtitle { font-size: 0.9rem; }
            .tab-btn { padding: 8px 12px; font-size: 0.9rem; }
            .bracket-container { flex-direction: column; gap: 30px; }
            .bracket-column { width: 100%; }
        }
    </style>
</head>
<body>
    <header>
        <div class="logo-container">
            <span class="logo-text">Luanti Deathmatch</span>
        </div>
        <div class="subtitle">League Tournament Portal</div>
        
        <div class="tab-menu">
            <button class="tab-btn active" onclick="switchTab('dashboard')">📊 Dashboard</button>
            <button class="tab-btn" onclick="switchTab('standings')">🏆 Standings</button>
            <button class="tab-btn" onclick="switchTab('teams')">👥 Teams & Rosters</button>
            <button class="tab-btn" onclick="switchTab('leaderboard')">🎯 Player Stats</button>
            <button class="tab-btn" onclick="switchTab('fixtures')">📅 Fixtures & Schedule</button>
            <button class="tab-btn" onclick="switchTab('history')">📜 History & Archives</button>
        </div>
    </header>

    <main>
        <!-- DASHBOARD TAB -->
        <div id="dashboard" class="tab-content active">
            <div class="highlight-grid">
                <div class="glass-card">
                    <div class="card-title">Season Status</div>
                    <div class="card-value" id="dash-season-state">-</div>
                    <div class="card-desc">Current state of the tournament</div>
                </div>
                <div class="glass-card">
                    <div class="card-title">MVP</div>
                    <div class="card-value" id="dash-top-player">-</div>
                    <div class="card-desc" id="dash-top-player-details">-</div>
                </div>
                <div class="glass-card">
                    <div class="card-title">Champion</div>
                    <div class="card-value" id="dash-champion">-</div>
                    <div class="card-desc">Reigning league title holder</div>
                </div>
            </div>

            <div id="playoffs-bracket-section" style="display: none; width: 100%;">
                <h2 style="font-size: 1.8rem; font-weight: 800; margin: 2rem 0 1rem; text-align: center;">🏆 PLAYOFFS BRACKET</h2>
                <div class="bracket-container" id="playoff-bracket">
                    <!-- Dynamic Bracket Placement -->
                </div>
            </div>
        </div>

        <!-- STANDINGS TAB -->
        <div id="standings" class="tab-content">
            <div class="table-container">
                <table>
                    <thead>
                        <tr>
                            <th style="width: 70px;">Rank</th>
                            <th>Team</th>
                            <th>Leader</th>
                            <th style="text-align: center;">Wins</th>
                            <th style="text-align: center;">Losses</th>
                            <th style="text-align: center;">Win Rate</th>
                            <th style="text-align: center;">Kills Scored</th>
                            <th style="text-align: center;">Deaths Conceded</th>
                            <th style="text-align: center;">Kill Diff</th>
                        </tr>
                    </thead>
                    <tbody id="standings-table-body">
                        <!-- Dynamic Standings Rows -->
                    </tbody>
                </table>
            </div>
        </div>

        <!-- TEAMS TAB -->
        <div id="teams" class="tab-content">
            <div class="teams-grid" id="teams-cards-container">
                <!-- Dynamic Team Cards -->
            </div>
        </div>

        <!-- LEADERBOARD TAB -->
        <div id="leaderboard" class="tab-content">
            <div class="controls-bar">
                <input type="text" id="leaderboard-search" class="search-input" placeholder="Search players by name..." oninput="updateLeaderboard()">
                <select id="leaderboard-team-filter" class="select-input" onchange="updateLeaderboard()">
                    <option value="">All Teams</option>
                    <!-- Dynamic team options -->
                </select>
            </div>
            <div class="table-container">
                <table>
                    <thead>
                        <tr>
                            <th style="width: 70px;">Rank</th>
                            <th>Player</th>
                            <th>Team</th>
                            <th style="text-align: center;">Kills</th>
                            <th style="text-align: center;">Deaths</th>
                            <th style="text-align: center;">Captures</th>
                            <th style="text-align: center;">Dom Points</th>
                            <th style="text-align: center;">K/D Ratio</th>
                        </tr>
                    </thead>
                    <tbody id="leaderboard-table-body">
                        <!-- Dynamic Leaderboard Rows -->
                    </tbody>
                </table>
            </div>
        </div>

        <!-- FIXTURES TAB -->
        <div id="fixtures" class="tab-content">
            <div id="fixtures-container">
                <!-- Dynamic Fixture Rounds -->
            </div>
        </div>

        <!-- HISTORY TAB -->
        <div id="history" class="tab-content">
            <h2 style="font-size: 1.6rem; margin-bottom: 1.5rem;">Match History</h2>
            <div class="table-container" style="margin-bottom: 3rem;">
                <table>
                    <thead>
                        <tr>
                            <th>Time</th>
                            <th>Type</th>
                            <th>Home Team</th>
                            <th style="text-align: center;">Score</th>
                            <th>Away Team</th>
                            <th>MVP</th>
                        </tr>
                    </thead>
                    <tbody id="history-table-body">
                        <!-- Dynamic History Rows -->
                    </tbody>
                </table>
            </div>

            <h2 style="font-size: 1.6rem; margin-bottom: 1.5rem;">Archived Seasons</h2>
            <div id="archives-container">
                <!-- Dynamic Archives -->
            </div>
        </div>
    </main>

    <script>
        // EMBEDDED LEAGUE DATA (Populated by generator script)
        const data = __LEAGUE_DATA__;

        function switchTab(tabId) {
            document.querySelectorAll('.tab-btn').forEach(btn => btn.classList.remove('active'));
            document.querySelectorAll('.tab-content').forEach(content => content.classList.remove('active'));
            
            // Find active tab button by onclick attribute
            const activeBtn = Array.from(document.querySelectorAll('.tab-btn')).find(btn => btn.getAttribute('onclick').includes(tabId));
            if (activeBtn) activeBtn.classList.add('active');
            
            const activeContent = document.getElementById(tabId);
            if (activeContent) activeContent.classList.add('active');
        }

        // Initialize Site Data
        window.addEventListener('DOMContentLoaded', () => {
            initDashboard();
            initStandings();
            initTeams();
            initFilters();
            updateLeaderboard();
            initFixtures();
            initHistory();
        });

        // 1. Dashboard Handler
        defGet = (obj, key, def) => (obj && obj[key] !== undefined) ? obj[key] : def;
        
        function getDisplayName(username) {
            if (!username || username === 'None' || username === '-') return username;
            const nicks = defGet(data, 'nicknames', {});
            const nick = nicks[username];
            if (nick && nick !== username) {
                return `${nick} (${username})`;
            }
            return username;
        }
        
        function initDashboard() {
            // Season State
            const stateEl = document.getElementById('dash-season-state');
            const state = defGet(data, 'season_state', 'offseason');
            stateEl.textContent = state.replace('_', ' ');
            stateEl.className = 'card-value status-badge status-' + state;

            // Top Player
            const playerEl = document.getElementById('dash-top-player');
            const detailsEl = document.getElementById('dash-top-player-details');
            
            let topPlayer = null;
            let maxKills = -1;
            let topDetails = '';

            for (const [pname, pstats] of Object.entries(defGet(data, 'stats', {}))) {
                const kills = defGet(pstats, 'kills', 0);
                if (kills > maxKills) {
                    maxKills = kills;
                    topPlayer = pname;
                    topDetails = `${kills} Kills / ${defGet(pstats, 'deaths', 0)} Deaths`;
                }
            }

            if (topPlayer) {
                playerEl.textContent = getDisplayName(topPlayer);
                detailsEl.textContent = topDetails;
            } else {
                playerEl.textContent = 'None';
                detailsEl.textContent = 'No stats recorded yet';
            }

            // Champion Detection
            const champEl = document.getElementById('dash-champion');
            let champion = 'TBD';

            const playoffs = defGet(data, 'playoffs', {});
            if (playoffs.finals && playoffs.finals.winner) {
                champion = playoffs.finals.winner;
            } else if (data.season_archive && data.season_archive.length > 0) {
                champion = data.season_archive[data.season_archive.length - 1].champion;
            } else {
                // Find top team in regular standings
                let topTeam = null;
                let maxWins = -1;
                let maxDiff = -9999;
                for (const [tname, tdata] of Object.entries(defGet(data, 'teams', {}))) {
                    const wins = defGet(tdata, 'wins', 0);
                    const diff = defGet(tdata, 'kills_scored', 0) - defGet(tdata, 'deaths_conceded', 0);
                    if (wins > maxWins || (wins === maxWins && diff > maxDiff)) {
                        maxWins = wins;
                        maxDiff = diff;
                        topTeam = tname;
                    }
                }
                if (topTeam && maxWins > 0) {
                    champion = topTeam + " (Leader)";
                }
            }
            champEl.textContent = champion;

            // Playoffs Bracket
            if (state === 'playoffs' && playoffs.semifinals) {
                document.getElementById('playoffs-bracket-section').style.display = 'block';
                const bracketContainer = document.getElementById('playoff-bracket');
                
                const semi = playoffs.semifinals;
                const finals = playoffs.finals || {team1: '', team2: '', winner: '', score1: 0, score2: 0};
                
                let bracketHtml = `
                    <!-- Semifinals -->
                    <div class="bracket-column">
                        <div class="bracket-round-title">Semifinals</div>
                        
                        <!-- Match 1 -->
                        <div class="bracket-match">
                            <div class="bracket-match-row">
                                <span class="bracket-team-name ${semi[0].winner === semi[0].team1 ? 'winner' : ''}">${semi[0].team1 || 'TBD'}</span>
                                <span class="bracket-score">${semi[0].score1}</span>
                            </div>
                            <div class="bracket-match-row">
                                <span class="bracket-team-name ${semi[0].winner === semi[0].team2 ? 'winner' : ''}">${semi[0].team2 || 'TBD'}</span>
                                <span class="bracket-score">${semi[0].score2}</span>
                            </div>
                        </div>

                        <!-- Match 2 -->
                        <div class="bracket-match">
                            <div class="bracket-match-row">
                                <span class="bracket-team-name ${semi[1].winner === semi[1].team1 ? 'winner' : ''}">${semi[1].team1 || 'TBD'}</span>
                                <span class="bracket-score">${semi[1].score1}</span>
                            </div>
                            <div class="bracket-match-row">
                                <span class="bracket-team-name ${semi[1].winner === semi[1].team2 ? 'winner' : ''}">${semi[1].team2 || 'TBD'}</span>
                                <span class="bracket-score">${semi[1].score2}</span>
                            </div>
                        </div>
                    </div>

                    <!-- Connective Divider -->
                    <div style="font-size: 2rem; color: var(--card-border);">➔</div>

                    <!-- Finals -->
                    <div class="bracket-column">
                        <div class="bracket-round-title">Grand Finals</div>
                        <div class="bracket-match" style="border-color: var(--accent-color); box-shadow: 0 0 15px rgba(0,242,254,0.15);">
                            <div class="bracket-match-row">
                                <span class="bracket-team-name ${finals.winner === finals.team1 ? 'winner' : ''}">${finals.team1 || 'TBD'}</span>
                                <span class="bracket-score">${finals.score1}</span>
                            </div>
                            <div class="bracket-match-row">
                                <span class="bracket-team-name ${finals.winner === finals.team2 ? 'winner' : ''}">${finals.team2 || 'TBD'}</span>
                                <span class="bracket-score">${finals.score2}</span>
                            </div>
                        </div>
                    </div>
                `;
                bracketContainer.innerHTML = bracketHtml;
            }
        }

        // 2. Standings Handler
        function initStandings() {
            const tbody = document.getElementById('standings-table-body');
            const teamsList = [];

            for (const [tname, tdata] of Object.entries(defGet(data, 'teams', {}))) {
                const wins = defGet(tdata, 'wins', 0);
                const losses = defGet(tdata, 'losses', 0);
                const kills = defGet(tdata, 'kills_scored', 0);
                const deaths = defGet(tdata, 'deaths_conceded', 0);
                const diff = kills - deaths;
                const total = wins + losses;
                const winrate = total > 0 ? ((wins / total) * 100).toFixed(0) + '%' : '0%';

                teamsList.push({
                    name: tname,
                    leader: defGet(tdata, 'leader', '-'),
                    wins, losses, winrate, kills, deaths, diff
                });
            }

            // Sort by Wins desc, then Diff desc
            teamsList.sort((a, b) => {
                if (a.wins !== b.wins) return b.wins - a.wins;
                return b.diff - a.diff;
            });

            if (teamsList.length === 0) {
                tbody.innerHTML = '<tr><td colspan="9" style="text-align: center; color: var(--text-muted);">No teams registered in the league yet.</td></tr>';
                return;
            }

            tbody.innerHTML = teamsList.map((team, idx) => `
                <tr>
                    <td style="text-align: center;"><span class="rank-badge">${idx + 1}</span></td>
                    <td style="font-weight: 800; color: var(--accent-color);">${team.name}</td>
                    <td>${getDisplayName(team.leader)}</td>
                    <td style="text-align: center; font-weight: 600;">${team.wins}</td>
                    <td style="text-align: center;">${team.losses}</td>
                    <td style="text-align: center;">${team.winrate}</td>
                    <td style="text-align: center;">${team.kills}</td>
                    <td style="text-align: center;">${team.deaths}</td>
                    <td style="text-align: center; font-weight: 600; color: ${team.diff >= 0 ? 'var(--success-color)' : 'var(--red-team)'};">
                        ${team.diff > 0 ? '+' + team.diff : team.diff}
                    </td>
                </tr>
            `).join('');
        }

        // 3. Teams Handler
        function initTeams() {
            const container = document.getElementById('teams-cards-container');
            const entries = Object.entries(defGet(data, 'teams', {}));
            
            if (entries.length === 0) {
                container.innerHTML = '<div style="grid-column: 1/-1; text-align: center; color: var(--text-muted);">No teams to display.</div>';
                return;
            }

            let cardsHtml = '';
            entries.forEach(([tname, tdata], idx) => {
                const members = defGet(tdata, 'members', []);
                const colorClass = (idx % 2 === 0) ? 'red-border' : 'blue-border';
                
                cardsHtml += `
                    <div class="glass-card team-card ${colorClass}">
                        <div class="team-header">
                            <span class="team-name">${tname}</span>
                            <span class="status-badge" style="background: rgba(0, 242, 254, 0.1); color: var(--accent-color); border: 1px solid var(--accent-color);">
                                ${members.length} Members
                            </span>
                        </div>
                        <div class="team-leader">Leader: <span>${getDisplayName(tdata.leader || 'None')}</span></div>
                        <ul class="roster-list">
                            ${members.map(member => `
                                <li class="roster-item">
                                    <span>${getDisplayName(member)}</span>
                                    ${member === tdata.leader ? '<span style="font-size:0.75rem; background:rgba(245,158,11,0.2); color:#f59e0b; padding:2px 6px; border-radius:4px; font-weight:800;">LEADER</span>' : ''}
                                </li>
                            `).join('')}
                        </ul>
                    </div>
                `;
            });
            container.innerHTML = cardsHtml;
        }

        // 4. Player Stats / Leaderboard Handler
        function initFilters() {
            const filter = document.getElementById('leaderboard-team-filter');
            const teams = Object.keys(defGet(data, 'teams', {}));
            teams.forEach(team => {
                const opt = document.createElement('option');
                opt.value = team;
                opt.textContent = team;
                filter.appendChild(opt);
            });
        }

        function updateLeaderboard() {
            const searchVal = document.getElementById('leaderboard-search').value.toLowerCase();
            const teamVal = document.getElementById('leaderboard-team-filter').value;
            const tbody = document.getElementById('leaderboard-table-body');
            
            const playersList = [];
            const playersMap = defGet(data, 'players', {});

            for (const [pname, pstats] of Object.entries(defGet(data, 'stats', {}))) {
                const team = playersMap[pname] || 'No Team';
                const displayName = getDisplayName(pname);
                
                // Filters
                if (searchVal && !displayName.toLowerCase().includes(searchVal)) continue;
                if (teamVal && team !== teamVal) continue;

                const kills = defGet(pstats, 'kills', 0);
                const deaths = defGet(pstats, 'deaths', 0);
                const captures = defGet(pstats, 'captures', 0);
                const domPoints = defGet(pstats, 'dom_points', 0);
                const kd = deaths > 0 ? (kills / deaths).toFixed(2) : kills.toFixed(2);

                playersList.push({
                    name: pname,
                    displayName: displayName,
                    team, kills, deaths, captures, domPoints, kd: parseFloat(kd)
                });
            }

            // Sort by K/D ratio desc, but only those with >= 5 kills are ranked.
            // Unranked players (kills < 5) are placed below ranked players.
            playersList.sort((a, b) => {
                const aQual = a.kills >= 5;
                const bQual = b.kills >= 5;
                if (aQual && !bQual) return -1;
                if (!aQual && bQual) return 1;
                
                // Both qualified or both unqualified: sort by K/D ratio descending
                if (b.kd !== a.kd) {
                    return b.kd - a.kd;
                }
                // Tiebreaker: sort by kills descending
                return b.kills - a.kills;
            });

            if (playersList.length === 0) {
                tbody.innerHTML = '<tr><td colspan="7" style="text-align: center; color: var(--text-muted);">No player stats found matching filters.</td></tr>';
                return;
            }

            let rankCounter = 1;
            tbody.innerHTML = playersList.map((player) => {
                const isRanked = player.kills >= 5;
                const rankHtml = isRanked 
                    ? `<span class="rank-badge">${rankCounter++}</span>`
                    : `<span class="rank-badge ur-badge">UR</span>`;
                return `
                    <tr>
                        <td style="text-align: center;">${rankHtml}</td>
                        <td style="font-weight: 800;">${player.displayName}</td>
                        <td style="color: var(--text-muted); font-size:0.9rem;">${player.team}</td>
                        <td style="text-align: center; font-weight: 600;">${player.kills}</td>
                        <td style="text-align: center;">${player.deaths}</td>
                        <td style="text-align: center;">${player.captures}</td>
                        <td style="text-align: center;">${player.domPoints}</td>
                        <td style="text-align: center; font-weight: 600; color: ${player.kd >= 1.0 ? 'var(--success-color)' : 'var(--text-muted)'};">${player.kd.toFixed(2)}</td>
                    </tr>
                `;
            }).join('');
        }

        // 5. Fixtures / Schedule Handler
        function initFixtures() {
            const container = document.getElementById('fixtures-container');
            const fixtures = defGet(data, 'fixtures', []);

            if (fixtures.length === 0) {
                container.innerHTML = '<div style="text-align: center; color: var(--text-muted); padding: 2rem 0;">No active season schedule generated.</div>';
                return;
            }

            let roundsHtml = '';
            fixtures.forEach((round, rIdx) => {
                if (!round || round.length === 0) return;
                
                roundsHtml += `
                    <div class="round-container">
                        <div class="round-title">Round ${rIdx + 1}</div>
                        <div class="match-grid">
                            ${round.map(match => {
                                const statusClass = match.status === 'completed' ? 'status-completed' : 'status-pending';
                                return `
                                    <div class="glass-card match-card">
                                        <span class="match-status-label ${statusClass}">${match.status}</span>
                                        <div class="match-teams">
                                            <span class="match-team home">${match.home}</span>
                                            <span class="match-score">${match.score ? match.score.home : 0} - ${match.score ? match.score.away : 0}</span>
                                            <span class="match-team away">${match.away}</span>
                                        </div>
                                    </div>
                                `;
                            }).join('')}
                        </div>
                    </div>
                `;
            });
            container.innerHTML = roundsHtml;
        }

        // 6. History / Archives Handler
        function initHistory() {
            const tbody = document.getElementById('history-table-body');
            const history = defGet(data, 'history', []);

            if (history.length === 0) {
                tbody.innerHTML = '<tr><td colspan="6" style="text-align: center; color: var(--text-muted);">No match history available.</td></tr>';
            } else {
                // Sort by time desc
                const sortedHistory = [...history].sort((a, b) => b.time - a.time);
                tbody.innerHTML = sortedHistory.map(match => {
                    const date = new Date(match.time * 1000).toLocaleString();
                    return `
                        <tr>
                            <td style="color: var(--text-muted); font-size: 0.85rem;">${date}</td>
                            <td style="color: var(--accent-color); font-weight: 600;">${match.match_type || 'Team Deathmatch'}</td>
                            <td style="font-weight: 600; text-align: right; width: 30%;">${match.home}</td>
                            <td style="text-align: center; font-weight: 800; font-size:1.1rem; background: rgba(0,0,0,0.1); width: 10%;">${match.home_score} - ${match.away_score}</td>
                            <td style="font-weight: 600; text-align: left; width: 30%;">${match.away}</td>
                            <td style="color: var(--accent-color); font-weight: 600;">${getDisplayName(match.mvp || '-')}</td>
                        </tr>
                    `;
                }).join('');
            }

            // Season Archives
            const archivesContainer = document.getElementById('archives-container');
            const archives = defGet(data, 'season_archive', []);

            if (archives.length === 0) {
                archivesContainer.innerHTML = '<div style="text-align: center; color: var(--text-muted); padding: 1rem 0;">No archived season data.</div>';
                return;
            }

            let archHtml = '';
            archives.forEach(arch => {
                const date = new Date(arch.timestamp * 1000).toLocaleDateString();
                archHtml += `
                    <div class="glass-card" style="margin-bottom: 1.5rem;">
                        <div class="team-header">
                            <span style="font-size: 1.2rem; font-weight: 800;">Season ${arch.season_num}</span>
                            <span style="color: var(--text-muted); font-size: 0.9rem;">Archived on ${date}</span>
                        </div>
                        <div style="font-size: 1.1rem; margin-bottom: 1rem;">Champion: <span style="color: gold; font-weight: 800;">🏆 ${arch.champion}</span></div>
                        <div class="table-container" style="border-radius: 8px; margin-bottom: 0;">
                            <table style="font-size: 0.9rem;">
                                <thead>
                                    <tr>
                                        <th>Rank</th>
                                        <th>Team</th>
                                        <th style="text-align: center;">Wins</th>
                                        <th style="text-align: center;">Losses</th>
                                        <th style="text-align: center;">Kills</th>
                                        <th style="text-align: center;">Deaths</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    ${arch.standings.map((team, idx) => `
                                        <tr>
                                            <td>${idx + 1}</td>
                                            <td style="font-weight: 600;">${team.name}</td>
                                            <td style="text-align: center;">${team.wins}</td>
                                            <td style="text-align: center;">${team.losses}</td>
                                            <td style="text-align: center;">${team.kills}</td>
                                            <td style="text-align: center;">${team.deaths}</td>
                                        </tr>
                                    `).join('')}
                                </tbody>
                            </table>
                        </div>
                    </div>
                `;
            });
            archivesContainer.innerHTML = archHtml;
        }
    </script>
</body>
</html>
"""

def main():
    parser = argparse.ArgumentParser(description="Generate a beautiful static site from Luanti Esports League data.")
    parser.add_argument("world_dir", nargs="?", default=r"N:\Minetest Worlds\World 3",
                        help="Path to the Luanti/Minetest World directory containing mod_storage.sqlite")
    parser.add_argument("-o", "--output", default="league_stats.html",
                        help="Output HTML file path (default: league_stats.html)")
                        
    args = parser.parse_args()
    
    db_path = os.path.join(args.world_dir, "mod_storage.sqlite")
    print(f"Reading league database from: {db_path}...")
    
    league_data = load_league_data(db_path)
    
    # Serialize data to JSON
    json_data = json.dumps(league_data)
    
    # Insert JSON data into HTML template
    html_content = HTML_TEMPLATE.replace("__LEAGUE_DATA__", json_data)
    
    # Write output
    output_path = args.output
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(html_content)
        
    print(f"Success! Static website generated successfully at: {os.path.abspath(output_path)}")
    print("Double-click this file to view the Esports League Standings & Stats.")

if __name__ == "__main__":
    main()

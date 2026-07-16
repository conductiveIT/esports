esports_core.lobby = {}
esports_core.lobby.blackouts = {}

function esports_core.lobby.blackout_show(player)
	local name = player:get_player_name()
	if esports_core.lobby.blackouts[name] then
		return
	end

	local hud_id = player:hud_add({
		type = "image",
		position = {x = 0.5, y = 0.5},
		name = "lobby_blackout",
		scale = {x = -100, y = -100},  -- 100% screen size
		text = "esports_hud_bar.png^[colorize:#000000:255",  -- Solid black
		alignment = {x = 0, y = 0},
		offset = {x = 0, y = 0},
	})
	esports_core.lobby.blackouts[name] = hud_id
end

function esports_core.lobby.blackout_hide(player)
	local name = player:get_player_name()
	local hud_id = esports_core.lobby.blackouts[name]
	if hud_id then
		player:hud_remove(hud_id)
		esports_core.lobby.blackouts[name] = nil
	end
end

-- Store player current tab and settings
local player_tabs = {}  -- name -> tab_id
local player_settings = {}  -- name -> {bot_count=x, bot_diff=y, ...}

local function get_team_online_count(tname)
	if not tname or tname == "" or tname == "No teams registered" then return 0 end
	local count = 0
	for _, p in ipairs(core.get_connected_players()) do
		local pname = p:get_player_name()
		if not esports_core.is_spectator(pname) and esports_league.get_team(pname) == tname then
			count = count + 1
		end
	end
	return count
end

local function get_available_teams()
	local list = {}
	for tname, _ in pairs(esports_league.teams) do
		local count = get_team_online_count(tname)
		table.insert(list, tname .. " (" .. count .. ")")
	end
	table.sort(list, function(a, b)
		return a:lower() < b:lower()
	end)
	return list
end

local function is_team_online(tname_with_count)
	if not tname_with_count or tname_with_count == "" or tname_with_count == "No teams registered" then return false end
	-- Strip " (N)" suffix for checking actual team existence/count
	local tname = tname_with_count:gsub("%s%(%d+%)$", "")
	return get_team_online_count(tname) > 0
end

local function handle_match_start_close(player)
	local name = player:get_player_name()
	local side = esports_core.match.get_player_match_side(name)
	if not side then
		esports_core.lobby.show(player)
	else
		core.close_formspec(name, "esports_core:lobby")
	end
end

function esports_core.lobby.get_live_scoreboard_formspec(name)
	local red_team = esports_core.match.active_teams.red or "Red Team"
	local blue_team = esports_core.match.active_teams.blue or "Blue Team"
	local red_score = esports_core.teams.scores.red or 0
	local blue_score = esports_core.teams.scores.blue or 0
	local time_left = esports_core.match.timer or 0
	local state = esports_core.match.state or "active"

	local mode_name = "Team Deathmatch"
	if esports_core.match.is_ctf then
		mode_name = "Capture The Flag"
	elseif esports_core.match.is_koth then
		mode_name = "King of the Hill"
	elseif esports_core.match.is_payload then
		mode_name = "Payload"
	elseif esports_core.match.is_domination then
		mode_name = "Domination"
	elseif esports_core.match.is_spleef then
		mode_name = "Spleef"
	elseif esports_core.match.is_tagctf then
		mode_name = "Tag CTF"
	elseif esports_core.match.is_ffa then
		mode_name = "Free For All"
	end

	local mins = math.floor(time_left / 60)
	local secs = time_left % 60
	local time_str = string.format("%02d:%02d", mins, secs)
	if state == "countdown" then
		time_str = "COUNTDOWN: " .. time_left
	end

	local list_items = {}
	local players_stats = {}
	for pname, stats in pairs(esports_core.match.player_stats or {}) do
		local p_side = esports_core.match.get_player_match_side(pname) or "spec"
		local rating = (stats.kills or 0) - (stats.deaths or 0) + ((stats.captures or 0) * 10) + math.floor((stats.hill_time or 0) / 10) + ((stats.dom_points or 0) * 2)
		table.insert(players_stats, {
			name = pname,
			nick = esports_core.get_nick(pname),
			side = p_side,
			kills = stats.kills or 0,
			deaths = stats.deaths or 0,
			captures = stats.captures or 0,
			hill_time = stats.hill_time or 0,
			escort_time = stats.escort_time or 0,
			dom_points = stats.dom_points or 0,
			rating = rating
		})
	end

	table.sort(players_stats, function(a, b)
		if a.rating ~= b.rating then return a.rating > b.rating end
		return a.kills > b.kills
	end)

	for _, p in ipairs(players_stats) do
		local special_str = ""
		if esports_core.match.is_ctf then
			special_str = ", Captures: " .. p.captures
		elseif esports_core.match.is_koth then
			special_str = ", Hill Time: " .. p.hill_time .. "s"
		elseif esports_core.match.is_payload then
			special_str = ", Escort: " .. p.escort_time .. "s"
		elseif esports_core.match.is_domination then
			special_str = ", Points: " .. p.dom_points
		end
		table.insert(list_items, core.formspec_escape(string.format("%s (%s) - K: %d, D: %d%s [Rating: %d]", p.nick, p.side:upper(), p.kills, p.deaths, special_str, p.rating)))
	end

	if #list_items == 0 then
		table.insert(list_items, "No active players in match")
	end

	local fs = {
		"formspec_version[6]",
		"size[17.5,13.75]",
		"background9[0,0;17.5,13.75;esports_hud_bar.png;false;10]",
		"style_type[button;bgcolor=#333333;textcolor=white;font=bold]",
		"style_type[label;textcolor=white;font=bold]",
		
		"label[0.5,0.8;LUANTI ESPORTS - LIVE SCOREBOARD v" .. esports_core.version .. " (build " .. esports_core.build .. ")]",
		"label[0.5,1.3;Mode: " .. mode_name .. " | Remaining: " .. time_str .. "]",
		"style[exit_server;bgcolor=#770000;textcolor=white]",
		"button[14.0,0.8;3.0,0.8;exit_server;DISCONNECT]"
	}

	if esports_core.match.is_ffa then
		table.insert(fs, "box[0.5,2.0;16.5,1.5;#333333aa]")
		table.insert(fs, "label[1.0,2.75;FREE FOR ALL MATCH IN PROGRESS]")
	else
		table.insert(fs, "box[0.5,2.0;8.0;1.8;#551111aa]")
		table.insert(fs, "label[1.0,2.6;RED: " .. red_team:upper() .. "]")
		table.insert(fs, "label[1.0,3.2;Score: " .. red_score .. "]")

		table.insert(fs, "box[9.0,2.0;8.0;1.8;#111155aa]")
		table.insert(fs, "label[9.5,2.6;BLUE: " .. blue_team:upper() .. "]")
		table.insert(fs, "label[9.5,3.2;Score: " .. blue_score .. "]")
	end

	table.insert(fs, "label[0.5,4.4;PLAYER STATISTICS (LIVE)]")
	table.insert(fs, "textlist[0.5,5.0;16.5,7.0;live_stats_list;" .. table.concat(list_items, ",") .. ";;false]")

	table.insert(fs, "style[stop_match;bgcolor=#770000;textcolor=white]")
	table.insert(fs, "button[0.5,12.5;5.2,0.9;stop_match;STOP MATCH]")

	table.insert(fs, "style[go_spectate;bgcolor=#335533;textcolor=white]")
	table.insert(fs, "button[6.1,12.5;5.2,0.9;go_spectate;SPECTATE 3D]")

	table.insert(fs, "style[show_lobby;bgcolor=#0055aa;textcolor=white]")
	table.insert(fs, "button[11.7,12.5;5.3,0.9;show_lobby;LOBBY MENU]")

	return table.concat(fs)
end

local function get_recommended_max_players(size, mode, layout)
	if mode == "SPLEEF" then
		return "4 - 8 players"
	end

	local is_lane = (layout == "Choke Point" or layout == "Three Lanes" or layout == "Split Center")

	if size == "Small" then
		if mode == "FFA" then
			return is_lane and "4 - 6 players (Solo)" or "6 - 8 players (Solo)"
		else
			return is_lane and "2v2 to 3v3 (4 - 6 players)" or "2v2 to 4v4 (4 - 8 players)"
		end
	elseif size == "Medium" then
		if mode == "FFA" then
			return is_lane and "8 - 10 players (Solo)" or "10 - 14 players (Solo)"
		else
			return is_lane and "4v4 to 6v6 (8 - 12 players)" or "5v5 to 8v8 (10 - 16 players)"
		end
	else -- Large
		if mode == "FFA" then
			return is_lane and "12 - 16 players (Solo)" or "16 - 24 players (Solo)"
		else
			return is_lane and "6v6 to 8v8 (12 - 16 players)" or "8v8 to 12v12 (16 - 24 players)"
		end
	end
end

local function build_matchmaking_tab(fs, settings)
	local match_active = (esports_core.match.state == "active")
	local teams_list = get_available_teams()
	local teams_str = table.concat(teams_list, ",")
	if teams_str == "" then teams_str = "No teams registered" end
	local red_ready = is_team_online(settings.red)
	local blue_ready = is_team_online(settings.blue)
	local pve_ready = is_team_online(settings.pve)

	local start_comp_name = (not match_active and red_ready and blue_ready) and "start_comp" or "btn_disabled"
	local start_pve_name = pve_ready and "start_pve" or "btn_disabled"

	local red_idx = 0
	local blue_idx = 0
	local pve_idx = 0
	for i, v in ipairs(teams_list) do
		if v == settings.red then red_idx = i end
		if v == settings.blue then blue_idx = i end
		if v == settings.pve then pve_idx = i end
	end

	local match_mode = settings.match_mode or "TDM"

	if match_mode == "FFA" then
		table.insert(fs, "label[0.8,3.8;FREE FOR ALL (SOLO DEATHMATCH)]")
		table.insert(fs, "label[0.8,4.4;No teams. Every player for themselves!]")
		table.insert(fs, "label[0.8,5.2;Rules:]")
		table.insert(fs, "label[0.8,5.8;- Friendly fire is always enabled.]")
		table.insert(fs, "label[0.8,6.4;- Spawn points are randomized across the island.]")
		table.insert(fs, "label[0.8,7.0;- Match standings and leaderboards are NOT affected.]")
	else
		table.insert(fs, "label[0.8,3.8;COMPETITIVE MATCH]")
		table.insert(fs, "label[0.8,4.4;Choose the competing teams:]")

		table.insert(fs, "label[0.8,5.3;Red Team:]")
		table.insert(fs, "dropdown[0.8,5.8;7.5,0.6;sel_red;" .. teams_str .. ";" .. red_idx .. "]")

		table.insert(fs, "label[0.8,7.1;Blue Team:]")
		table.insert(fs, "dropdown[0.8,7.6;7.5,0.6;sel_blue;" .. teams_str .. ";" .. blue_idx .. "]")

		table.insert(fs, "box[8.7,3.8;0.1,5.0;#ffffff]") -- Divider (Shortened to avoid Arena overlap)

		table.insert(fs, "label[9.2,3.8;BOT PRACTICE (PVE)]")
		table.insert(fs, "label[9.2,4.4;Current Setup: " .. settings.count .. " Bots, " .. settings.diff .. " difficulty]")

		table.insert(fs, "label[9.2,5.3;Player Team:]")
		table.insert(fs, "dropdown[9.2,5.8;7.5,0.6;sel_pve;" .. teams_str .. ";" .. pve_idx .. "]")
	end

	local dur_list = {"1m","5m","10m","15m","20m","30m"}
	local dur_idx = 2
	for i, v in ipairs(dur_list) do if v == settings.match_dur then dur_idx = i break end end

	local tod_list = {"Day","Night"}
	local tod_idx = 1
	for i, v in ipairs(tod_list) do if v == settings.match_tod then tod_idx = i break end end

	local size_list = {"Small","Medium","Large"}
	local size_idx = 1
	for i, v in ipairs(size_list) do if v == settings.map_size then size_idx = i break end end

	local layout_list = {"Random","Classic","Choke Point","Three Lanes","Split Center"}
	local layout_idx = 1
	for i, v in ipairs(layout_list) do if v == settings.map_layout then layout_idx = i break end end

	local spleef_levels_list = {"1 Level", "2 Levels", "3 Levels"}
	local spleef_levels_idx = 1
	for i, v in ipairs(spleef_levels_list) do if v == settings.spleef_levels then spleef_levels_idx = i break end end

	local mode_idx = 1
	if settings.match_mode == "CTF" then mode_idx = 2
	elseif settings.match_mode == "FFA" then mode_idx = 3
	elseif settings.match_mode == "KOTH" then mode_idx = 4
	elseif settings.match_mode == "PAYLOAD" then mode_idx = 5
	elseif settings.match_mode == "TAGCTF" then mode_idx = 6
	elseif settings.match_mode == "SPLEEF" then mode_idx = 7
	elseif settings.match_mode == "DOMINATION" then mode_idx = 8 end

	table.insert(fs, "box[0.8,9.0;15.9,2.2;#333333]")
	table.insert(fs, "label[1.0,9.3;ARENA CONFIGURATION]")
	table.insert(fs, "label[1.0,10.1;Dur:]")
	table.insert(fs, "dropdown[2.0,9.8;2.0,0.6;sel_dur;1m,5m,10m,15m,20m,30m;" .. dur_idx .. "]")
	table.insert(fs, "label[4.5,10.1;Mode:]")
	table.insert(fs, "dropdown[5.5,9.8;2.5,0.6;sel_mode;TDM,CTF,FFA,KOTH,PAYLOAD,TAGCTF,SPLEEF,DOMINATION;" .. mode_idx .. "]")
	table.insert(fs, "label[8.5,10.1;Time:]")
	table.insert(fs, "dropdown[9.5,9.8;2.5,0.6;sel_tod;Day,Night;" .. tod_idx .. "]")
	table.insert(fs, "label[12.5,10.1;Size:]")
	table.insert(fs, "dropdown[13.5,9.8;2.2,0.6;sel_map_size;Small,Medium,Large;" .. size_idx .. "]")

	if match_mode == "FFA" then
		table.insert(fs, "style[chk_friendly_fire_dummy;enabled=false]")
		table.insert(fs, "checkbox[1.0,10.6;chk_friendly_fire_dummy;Friendly Fire (Forced ON);true]")
	else
		table.insert(fs, "checkbox[1.0,10.6;chk_friendly_fire;Friendly Fire (FF);" .. (settings.friendly_fire and "true" or "false") .. "]")
	end
	table.insert(fs, "checkbox[6.5,10.6;chk_melee_damage;Melee Damage;" .. (settings.melee_damage and "true" or "false") .. "]")
	if match_mode == "SPLEEF" then
		table.insert(fs, "label[11.5,10.9;Levels:]")
		table.insert(fs, "dropdown[12.5,10.6;3.2,0.6;sel_spleef_levels;1 Level,2 Levels,3 Levels;" .. spleef_levels_idx .. "]")
	else
		table.insert(fs, "label[11.5,10.9;Layout:]")
		table.insert(fs, "dropdown[12.5,10.6;3.2,0.6;sel_map_layout;Random,Classic,Choke Point,Three Lanes,Split Center;" .. layout_idx .. "]")
	end

	local rec_players = get_recommended_max_players(settings.map_size or "Small", settings.match_mode or "TDM", settings.map_layout or "Random")
	table.insert(fs, "label[1.0,11.25;" .. core.colorize("#ffa500", "Recommended Capacity: " .. rec_players) .. "]")

	if match_mode == "FFA" then
		table.insert(fs, "button[0.8,11.5;15.9,0.8;start_ffa;START FREE FOR ALL]")
	else
		table.insert(fs, "button[0.8,11.5;7.5,0.8;" .. start_comp_name .. ";START TEAM BATTLE]")
		table.insert(fs, "button[9.2,11.5;7.5,0.8;" .. start_pve_name .. ";START PVE MATCH]")
	end

	if match_active then
		table.insert(fs, "style[stop_match;bgcolor=#770000;textcolor=white]")
		if esports_core.match.paused then
			table.insert(fs, "style[resume_match;bgcolor=#007700;textcolor=white]")
			table.insert(fs, "label[6.0,12.5;" .. core.colorize("#ffa500", "MATCH CURRENTLY PAUSED") .. "]")
			table.insert(fs, "button[0.8,12.9;7.5,0.5;resume_match;RESUME MATCH]")
		else
			table.insert(fs, "style[pause_match;bgcolor=#dd7700;textcolor=white]")
			table.insert(fs, "label[6.0,12.5;MATCH CURRENTLY IN PROGRESS]")
			table.insert(fs, "button[0.8,12.9;7.5,0.5;pause_match;PAUSE MATCH]")
		end
		table.insert(fs, "button[9.2,12.9;7.5,0.5;stop_match;STOP MATCH]")
	end
end

local function build_league_tab(fs, settings, is_admin)
	local match_active = (esports_core.match.state == "active" or esports_core.match.state == "countdown")
	local league_subtab = settings.league_subtab or "standings"

	-- Style active sub-tab button
	local active_sub_btn = ""
	if league_subtab == "standings" then active_sub_btn = "league_tab_standings"
	elseif league_subtab == "schedule" then active_sub_btn = "league_tab_schedule"
	elseif league_subtab == "history" then active_sub_btn = "league_tab_history"
	elseif league_subtab == "playoffs" then active_sub_btn = "league_tab_playoffs" end

	if active_sub_btn ~= "" then
		table.insert(fs, "style[" .. active_sub_btn .. ";bgcolor=#0077dd;textcolor=white]")
	end

	table.insert(fs, "button[0.5,3.4;3.9,0.6;league_tab_standings;STANDINGS]")
	table.insert(fs, "button[4.8,3.4;3.9,0.6;league_tab_schedule;SCHEDULE]")
	table.insert(fs, "button[9.1,3.4;3.9,0.6;league_tab_history;HISTORY]")
	table.insert(fs, "button[13.4,3.4;3.9,0.6;league_tab_playoffs;PLAYOFFS]")

	if league_subtab == "standings" then
		local sorted = {}
		for tname, _ in pairs(esports_league.teams) do
			table.insert(sorted, tname)
		end
		table.sort(sorted, function(a, b)
			local da = esports_league.teams[a]
			local db = esports_league.teams[b]
			local wa = da.wins or 0
			local wb = db.wins or 0
			if wa ~= wb then return wa > wb end

			local diffa = (da.kills_scored or 0) - (da.deaths_conceded or 0)
			local diffb = (db.kills_scored or 0) - (db.deaths_conceded or 0)
			if diffa ~= diffb then return diffa > diffb end

			return (da.kills_scored or 0) > (db.kills_scored or 0)
		end)

		local list_items = {}
		for _, tname in ipairs(sorted) do
			local d = esports_league.teams[tname]
			local diff = (d.kills_scored or 0) - (d.deaths_conceded or 0)
			local formatted = string.format("%s (W:%d L:%d D:%+d)", tname, d.wins or 0, d.losses or 0, diff)
			table.insert(list_items, core.formspec_escape(formatted))
		end

		local selected = settings.selected_team
		local selected_idx = 0
		local list_name = "teams_list"
		if selected then
			for idx, tname in ipairs(sorted) do
				if tname == selected then
					selected_idx = idx
					break
				end
			end
		else
			list_name = "teams_list_clear"
		end

		table.insert(fs, "label[0.5,4.3;LEAGUE STANDINGS]")
		table.insert(fs, "textlist[0.5,4.8;7.5,6.8;" .. list_name .. ";" .. table.concat(list_items, ",") .. ";" .. selected_idx .. ";false]")

		-- Team Inspector Panel
		if selected and esports_league.teams[selected] then
			local data = esports_league.teams[selected]

			local roster_items = {}
			for _, mname in ipairs(data.members) do
				local stats = esports_league.player_stats[mname] or {kills=0, deaths=0, captures=0, hill_time=0, dom_points=0}
				local k = stats.kills or 0
				local d = stats.deaths or 0
				local c = stats.captures or 0
				local h = stats.hill_time or 0
				local dom = stats.dom_points or 0
				local rating = k - d + (c * 10) + math.floor(h / 10) + (dom * 2)
				local kd
				if d > 0 then
					local val = math.floor((k / d) * 10)
					kd = tostring(math.floor(val / 10)) .. "." .. tostring(val % 10)
				else
					kd = tostring(k) .. ".0"
				end
				table.insert(roster_items, core.formspec_escape(string.format("%s (R:%d KD:%s H:%ds P:%d)", esports_core.get_nick(mname), rating, kd, h, dom)))
			end

			local leader_display = esports_core.get_nick(data.leader or "")
			if leader_display == "" then
				leader_display = "None"
			end

			if is_admin then
				-- Admin Team Inspector Panel: Roster + Join Requests + Set Owner + Approve/Deny
				local requests = esports_league.requests[selected] or {}
				local req_items = {}
				for _, req_name in ipairs(requests) do
					table.insert(req_items, core.formspec_escape(esports_core.get_nick(req_name)))
				end
				table.insert(fs, "box[8.5,4.6;8.5,7.0;#222222aa]")
				table.insert(fs, "label[8.7,4.9;TEAM: " .. core.formspec_escape(selected:upper() .. " [" .. (data.tag or "???") .. "]") .. "]")
				table.insert(fs, "label[8.7,5.3;Leader: " .. core.formspec_escape(leader_display) .. "]")
				table.insert(fs, "label[8.7,5.7;ROSTER:]")
				table.insert(fs, "textlist[8.7,6.0;8.1,1.5;sel_roster_admin;" .. table.concat(roster_items, ",") .. ";;false]")
				table.insert(fs, "label[8.7,7.9;JOIN REQUESTS:]")

				if #requests > 0 then
					table.insert(fs, "textlist[8.7,8.2;4.5,1.2;sel_request;" .. table.concat(req_items, ",") .. ";;false]")
					table.insert(fs, "button[13.5,8.2;3.0,0.5;accept_request;APPROVE]")
					table.insert(fs, "button[13.5,8.8;3.0,0.5;deny_request;DENY]")
				else
					table.insert(fs, "label[8.7,8.3;No pending requests.]")
				end

				table.insert(fs, "field[8.7,9.7;5.0,0.5;rename_val;New Team Name;]")
				table.insert(fs, "button[13.9,9.7;2.8,0.5;rename_team;RENAME]")

				table.insert(fs, "field[8.7,10.8;5.0,0.5;tag_val;New Tag (3 letters);]")
				table.insert(fs, "button[13.9,10.8;2.8,0.5;change_tag;SET TAG]")

				table.insert(fs, "button[8.5,12.0;2.6,0.8;unselect_team;BACK]")
				table.insert(fs, "button[11.3,12.0;2.6,0.8;unset_owner;UNSET LEADER]")
				table.insert(fs, "button[14.1,12.0;2.6,0.8;set_owner;SET LEADER]")
			else
				-- Normal Team Inspector Panel
				table.insert(fs, "box[8.5,4.6;8.5,6.8;#222222aa]")
				table.insert(fs, "label[8.7,5;TEAM: " .. core.formspec_escape(selected:upper() .. " [" .. (data.tag or "???") .. "]") .. "]")
				table.insert(fs, "label[8.7,5.5;Leader: " .. core.formspec_escape(leader_display) .. "]")
				table.insert(fs, "label[8.7,6.2;ROSTER:]")
				table.insert(fs, "textlist[8.7,6.6;8.1,3.5;sel_roster_admin;" .. table.concat(roster_items, ",") .. ";;false]")
				table.insert(fs, "button[8.7,10.4;8.1,0.6;unselect_team;Show Global Leaderboard]")
			end
		else
			-- Sort players for Global Leaderboard
			local sorted_players = {}
			for pname, stats in pairs(esports_league.player_stats) do
				local k = stats.kills or 0
				local d = stats.deaths or 0
				local c = stats.captures or 0
				local h = stats.hill_time or 0
				local dom = stats.dom_points or 0
				local rating = k - d + (c * 10) + math.floor(h / 10) + (dom * 2)
				table.insert(sorted_players, {
					name = pname,
					kills = k,
					deaths = d,
					captures = c,
					hill_time = h,
					dom_points = dom,
					rating = rating
				})
			end

			table.sort(sorted_players, function(a, b)
				if a.rating ~= b.rating then return a.rating > b.rating end
				if a.kills ~= b.kills then return a.kills > b.kills end
				return a.deaths < b.deaths
			end)

			local board_items = {}
			for i, p in ipairs(sorted_players) do
				if i > 50 then break end -- Show top 50
				local nick = esports_core.get_nick(p.name)
				local formatted = string.format("%d. %s (R:%d K:%d D:%d C:%d H:%ds P:%d)", i, nick, p.rating, p.kills, p.deaths, p.captures, p.hill_time, p.dom_points)
				table.insert(board_items, core.formspec_escape(formatted))
			end
			if #board_items == 0 then
				table.insert(board_items, "No player stats recorded yet")
			end

			table.insert(fs, "box[8.5,4.6;8.5,6.8;#222222aa]")
			table.insert(fs, "label[8.7,5.0;GLOBAL LEADERBOARD]")
			table.insert(fs, "textlist[8.7,5.4;8.1,5.5;global_leaderboard;" .. table.concat(board_items, ",") .. ";;false]")
		end

		if is_admin then
			if not selected then
				table.insert(fs, "field[0.5,11.8;3.8,0.8;new_team;New Team Name;]")
				table.insert(fs, "field[4.6,11.8;2.4,0.8;new_team_tag;Tag (3 chars);]")
				table.insert(fs, "button[7.3,11.8;4.2,0.8;create_team;CREATE TEAM]")
			end
		else
			table.insert(fs, "label[0.5,11.8;Registration handled by administrators.]")
		end

	elseif league_subtab == "schedule" then
		if not esports_league.fixtures or #esports_league.fixtures == 0 then
			table.insert(fs, "label[0.5,4.6;No regular season schedule has been generated yet.]")
			if is_admin then
				table.insert(fs, "button[0.5,5.5;5.0,0.8;btn_generate_schedule;GENERATE SCHEDULE]")
			end
		else
			local round_count = #esports_league.fixtures
			local round_options = {}
			for r = 1, round_count do
				table.insert(round_options, "Round " .. r)
			end

			local sel_round = settings.sel_round or 1
			if sel_round > round_count then sel_round = round_count end

			table.insert(fs, "label[0.5,4.3;SELECT ROUND:]")
			table.insert(fs, "dropdown[3.2,4.0;2.0,0.6;sel_round_dropdown;" .. table.concat(round_options, ",") .. ";" .. sel_round .. "]")

			local round_matches = esports_league.fixtures[sel_round] or {}
			local match_items = {}
			for idx, m in ipairs(round_matches) do
				local status_str = m.status == "completed" and ("(W: " .. m.score.home .. "-" .. m.score.away .. ")") or "(Pending)"
				local formatted = string.format("%d. %s vs %s %s", idx, m.home, m.away, status_str)
				table.insert(match_items, core.formspec_escape(formatted))
			end

			local sel_match_idx = settings.sel_match_idx or 1
			if sel_match_idx > #match_items then sel_match_idx = #match_items end
			if #match_items == 0 then
				table.insert(match_items, "No matches this round")
			end

			table.insert(fs, "label[0.5,4.8;MATCHUPS IN SELECTED ROUND:]")
			table.insert(fs, "textlist[0.5,5.3;7.5,6.5;sel_match_list;" .. table.concat(match_items, ",") .. ";" .. sel_match_idx .. ";false]")

			local selected_match = round_matches[sel_match_idx]
			if selected_match then
				table.insert(fs, "box[8.5,5.3;8.5,6.5;#222222aa]")
				table.insert(fs, "label[8.7,5.7;MATCH DETAILS]")
				table.insert(fs, "label[8.7,6.4;Home: " .. selected_match.home .. "]")
				table.insert(fs, "label[8.7,7.1;Away: " .. selected_match.away .. "]")
				table.insert(fs, "label[8.7,7.8;Status: " .. selected_match.status:upper() .. "]")

				if selected_match.status == "completed" then
					table.insert(fs, "label[8.7,8.5;Score: " .. selected_match.score.home .. " - " .. selected_match.score.away .. "]")
				elseif is_admin and not match_active then
					table.insert(fs, "button[8.7,10.6;8.1,0.8;start_scheduled_match;START MATCH]")
				end
			end
		end

	elseif league_subtab == "history" then
		local history_items = {}
		for idx = #esports_league.history, 1, -1 do
			local entry = esports_league.history[idx]
			local date_str = os.date("%Y-%m-%d %H:%M", entry.time or 0)
			local m_type = entry.match_type or "Team Deathmatch"
			local mvp_nick = "None"
			if entry.mvp and entry.mvp ~= "None" then
				mvp_nick = esports_core.get_nick(entry.mvp)
			end
			local item_str = string.format("[%s] (%s) %s %d - %d %s (MVP: %s)", date_str, m_type, entry.home, entry.home_score, entry.away_score, entry.away, mvp_nick)
			table.insert(history_items, core.formspec_escape(item_str))
		end

		if #history_items == 0 then
			table.insert(fs, "label[0.5,4.6;No match history recorded yet.]")
		else
			table.insert(fs, "label[0.5,4.2;RECENT MATCH HISTORY:]")
			table.insert(fs, "textlist[0.5,4.7;16.5,7.5;history_list;" .. table.concat(history_items, ",") .. ";;false]")
		end

	elseif league_subtab == "playoffs" then
		if esports_league.season_state ~= "playoffs" then
			table.insert(fs, "label[0.5,4.6;Playoffs have not started yet.]")

			local all_done = true
			local has_fixtures = (esports_league.fixtures and #esports_league.fixtures > 0)
			if has_fixtures then
				for _, round in ipairs(esports_league.fixtures) do
					for _, m in ipairs(round) do
						if m.status == "pending" then
							all_done = false
							break
						end
					end
				end
			else
				all_done = false
			end

			if has_fixtures and all_done then
				table.insert(fs, "label[0.5,5.1;All regular season matches are completed!]")
				if is_admin then
					table.insert(fs, "button[0.5,5.7;5.0,0.8;btn_start_playoffs;START PLAYOFFS]")
				end
			end
		else
			local p = esports_league.playoffs
			local sf1 = p.semifinals[1]
			local sf2 = p.semifinals[2]
			local fn = p.finals

			table.insert(fs, "box[0.5,4.5;16.5,7.0;#222222aa]")
			table.insert(fs, "label[0.7,4.9;SEMIFINALS]")
			table.insert(fs, "label[9.5,4.9;GRAND FINALS]")

			local sf1_winner_text = sf1.winner ~= "" and (" (Winner: " .. sf1.winner .. ")") or ""
			local sf1_score_text = sf1.status == "completed" and (" [" .. sf1.score1 .. "-" .. sf1.score2 .. "]") or ""
			table.insert(fs, "label[0.7,5.8;SF 1: " .. sf1.team1 .. " vs " .. sf1.team2 .. sf1_score_text .. sf1_winner_text .. "]")

			local sf2_winner_text = sf2.winner ~= "" and (" (Winner: " .. sf2.winner .. ")") or ""
			local sf2_score_text = sf2.status == "completed" and (" [" .. sf2.score1 .. "-" .. sf2.score2 .. "]") or ""
			table.insert(fs, "label[0.7,7.0;SF 2: " .. sf2.team1 .. " vs " .. sf2.team2 .. sf2_score_text .. sf2_winner_text .. "]")

			local fn_team1 = fn.team1 ~= "" and fn.team1 or "(TBD)"
			local fn_team2 = fn.team2 ~= "" and fn.team2 or "(TBD)"
			local fn_winner_text = fn.winner ~= "" and (" (CHAMPION: " .. fn.winner .. ")") or ""
			local fn_score_text = fn.status == "completed" and (" [" .. fn.score1 .. "-" .. fn.score2 .. "]") or ""
			table.insert(fs, "label[9.5,6.4;FINAL: " .. fn_team1 .. " vs " .. fn_team2 .. fn_score_text .. fn_winner_text .. "]")

			if is_admin and not match_active then
				table.insert(fs, "label[0.7,8.5;ADMIN CONTROL PANEL:]")
				if sf1.status == "pending" then
					table.insert(fs, "button[0.7,9.2;6.0,0.8;start_sf1;START SEMIFINAL 1]")
				elseif sf2.status == "pending" then
					table.insert(fs, "button[0.7,9.2;6.0,0.8;start_sf2;START SEMIFINAL 2]")
				elseif fn.status == "pending" and fn.team1 ~= "" and fn.team2 ~= "" then
					table.insert(fs, "button[0.7,9.2;6.0,0.8;start_final;START GRAND FINAL]")
				elseif fn.status == "completed" then
					table.insert(fs, "button[0.7,9.2;6.0,0.8;archive_season;ARCHIVE & END SEASON]")
				end
			end
		end
	end

	-- Error display at the bottom of the league tab
	if settings.err_msg then
		table.insert(fs, "style[err_lbl;textcolor=#ff3333;font=bold]")
		table.insert(fs, "label[0.5,12.8;ERROR: " .. settings.err_msg .. "]")
	end
end

local function build_team_tab(fs, name)
	local p_team_name = esports_league.get_team(name)

	if not p_team_name then
		-- FREE AGENT VIEW
		local all_teams = {}
		for tname, _ in pairs(esports_league.teams) do table.insert(all_teams, tname) end
		table.sort(all_teams)

		local escaped_teams = {}
		for _, tname in ipairs(all_teams) do
			table.insert(escaped_teams, core.formspec_escape(tname))
		end

		table.insert(fs, "label[0.5,3.8;FIND A TEAM]")
		table.insert(fs, "textlist[0.5,4.3;7.5,6.8;find_teams;" .. table.concat(escaped_teams, ",") .. ";;false]")
		table.insert(fs, "button[0.5,11.5;7.5,0.8;request_join;REQUEST TO JOIN]")

		table.insert(fs, "box[8.5,4.3;8.5,6.8;#222222aa]")
		table.insert(fs, "label[8.7,4.8;PENDING INVITATIONS]")

		local invites = {}
		for tname, target in pairs(esports_league.invites) do
			if tname == name then table.insert(invites, target) end
		end

		if #invites > 0 then
			local escaped_invites = {}
			for _, target in ipairs(invites) do
				table.insert(escaped_invites, core.formspec_escape(target))
			end
			table.insert(fs, "textlist[8.7,5.3;8.1,4.5;sel_invite;" .. table.concat(escaped_invites, ",") .. ";;false]")
			table.insert(fs, "button[8.7,10.2;3.8,0.6;accept_invite;ACCEPT]")
			table.insert(fs, "button[13.0,10.2;3.8,0.6;decline_invite;DECLINE]")
		else
			table.insert(fs, "label[8.7,6.5;No pending invites.]")
		end
	else
		-- SQUAD VIEW (Member or Owner)
		local is_owner = esports_league.is_owner(name, p_team_name)
		local team_data = esports_league.teams[p_team_name]

		table.insert(fs, "label[0.5,3.8;TEAM ROSTER: " .. core.formspec_escape(p_team_name:upper()) .. "]")
		table.insert(fs, "label[0.5,4.3;Leader: " .. core.formspec_escape(team_data.leader ~= "" and esports_core.get_nick(team_data.leader) or "None") .. "]")

		local roster_items = {}
		for _, mname in ipairs(team_data.members) do
			local stats = esports_league.player_stats[mname] or {kills=0, deaths=0, captures=0, hill_time=0, dom_points=0}
			local k = stats.kills or 0
			local d = stats.deaths or 0
			local c = stats.captures or 0
			local h = stats.hill_time or 0
			local dom = stats.dom_points or 0
			local rating = k - d + (c * 10) + math.floor(h / 10) + (dom * 2)
			table.insert(roster_items, core.formspec_escape(string.format("%s (R:%d K:%d D:%d C:%d H:%ds P:%d)", esports_core.get_nick(mname), rating, k, d, c, h, dom)))
		end

		table.insert(fs, "textlist[0.5,4.8;7.5,6.3;roster_list;" .. table.concat(roster_items, ",") .. ";;false]")

		if is_owner then
			table.insert(fs, "button[0.5,11.5;7.5,0.8;kick_player;KICK MEMBER]")
			table.insert(fs, "box[8.5,4.3;8.5,6.8;#222222aa]")
			table.insert(fs, "label[8.7,4.8;JOIN REQUESTS]")

			local requests = esports_league.requests[p_team_name] or {}
			local req_items = {}
			for _, req_name in ipairs(requests) do
				table.insert(req_items, core.formspec_escape(esports_core.get_nick(req_name)))
			end
			if #requests > 0 then
				table.insert(fs, "textlist[8.7,5.3;8.1,4.5;sel_request;" .. table.concat(req_items, ",") .. ";;false]")
				table.insert(fs, "button[8.7,10.2;3.8,0.6;accept_request;APPROVE]")
				table.insert(fs, "button[13.0,10.2;3.8,0.6;deny_request;DENY]")
			else
				table.insert(fs, "label[8.7,6.5;No pending requests.]")
			end

			table.insert(fs, "field[8.5,11.5;5.5,0.8;invite_name;Invite Player;]")
			table.insert(fs, "button[14.5,11.5;2.5,0.8;send_invite;INVITE]")
		else
			table.insert(fs, "button[0.5,11.5;7.5,0.8;leave_team;LEAVE TEAM]")
		end
	end
end

local function build_admin_tab(fs, settings)
	local count_list = {"1","2","3","4","5","10","15","20"}
	local diff_list = {"easy","medium","hard"}

	local count_idx = 5
	for i, v in ipairs(count_list) do if v == settings.count then count_idx = i break end end

	local diff_idx = 2
	for i, v in ipairs(diff_list) do if v == settings.diff then diff_idx = i break end end

	table.insert(fs, "label[0.5,4.0;PVE CONFIGURATION]")
	table.insert(fs, "label[0.5,4.7;Bot Count:]")
	table.insert(fs, "dropdown[0.5,5.1;4.5,0.8;bot_count;" .. table.concat(count_list, ",") .. ";" .. count_idx .. "]")

	table.insert(fs, "label[0.5,6.2;AI Difficulty:]")
	table.insert(fs, "dropdown[0.5,6.6;4.5,0.8;bot_diff;" .. table.concat(diff_list, ",") .. ";" .. diff_idx .. "]")

	table.insert(fs, "checkbox[0.5,7.9;chk_allow_team_create;Allow Team Creation;" .. (esports_league.allow_team_creation and "true" or "false") .. "]")
	table.insert(fs, "checkbox[0.5,8.5;chk_allow_nicks;Allow Nickname Changes;" .. (esports_core.allow_nicks and "true" or "false") .. "]")

	table.insert(fs, "label[0.5,9.4;TIPS]")
	table.insert(fs, "label[0.5,9.9;- Bots spawn with 0 ammo.]")
	table.insert(fs, "label[0.5,10.4;- They hunt crates to reload.]")
	table.insert(fs, "label[0.5,10.9;- Hard bots move faster/hit harder.]")

	-- Nicknames mappings display for admins
	local mapping_items = {}
	local keys = {}
	for username, _ in pairs(esports_core.nicknames) do
		table.insert(keys, username)
	end
	table.sort(keys)

	for _, u in ipairs(keys) do
		table.insert(mapping_items, core.formspec_escape(u .. " -> " .. esports_core.nicknames[u]))
	end

	local sel_nick_idx = settings.sel_nick_idx or 1
	if sel_nick_idx > #mapping_items then sel_nick_idx = #mapping_items end
	if #mapping_items == 0 then
		table.insert(mapping_items, "No nicknames registered")
	end

	table.insert(fs, "label[5.8,4.0;NICKNAME MAPPINGS]")
	table.insert(fs, "textlist[5.8,4.5;5.2,6.5;admin_nicks_list;" .. table.concat(mapping_items, ",") .. ";" .. sel_nick_idx .. ";false]")

	if #keys > 0 then
		table.insert(fs, "button[5.8,11.4;5.2,0.8;btn_reset_nick;RESET NICKNAME]")
	end

	-- Spectator Management display for admins
	local online_players = core.get_connected_players()
	local spec_items = {}
	local spec_keys = {}
	for _, p in ipairs(online_players) do
		table.insert(spec_keys, p:get_player_name())
	end
	table.sort(spec_keys)

	for _, pname in ipairs(spec_keys) do
		local status = esports_core.is_spectator(pname) and "Spectator" or "Player"
		local nick = esports_core.get_nick(pname)
		local display = nick
		if nick ~= pname then
			display = nick .. " (" .. pname .. ")"
		end
		table.insert(spec_items, core.formspec_escape(display .. " [" .. status .. "]"))
	end

	local sel_spec_idx = settings.sel_spec_idx or 1
	if sel_spec_idx > #spec_items then sel_spec_idx = #spec_items end
	if #spec_items == 0 then
		table.insert(spec_items, "No players online")
	end

	local selected_spec_player = spec_keys[sel_spec_idx]
	local spec_btn_text = "TOGGLE SPECTATOR"
	if selected_spec_player then
		if esports_core.is_spectator(selected_spec_player) then
			spec_btn_text = "REMOVE SPECTATOR"
		else
			spec_btn_text = "GIVE SPECTATOR"
		end
	end

	table.insert(fs, "label[11.8,4.0;SPECTATOR MANAGEMENT]")
	table.insert(fs, "textlist[11.8,4.5;5.2,6.5;admin_spec_list;" .. table.concat(spec_items, ",") .. ";" .. sel_spec_idx .. ";false]")
	table.insert(fs, "button[11.8,11.4;5.2,0.8;btn_toggle_spec;" .. spec_btn_text .. "]")
end

local function build_locker_tab(fs, name, is_admin)
	local meta = core.get_player_by_name(name):get_meta()
	local current = meta:get_string("esports_selected_skin")
	if current == "" then current = "character.png" end

	local match_side = esports_core.match.get_player_match_side(name)
	local is_spectator = esports_core.is_spectator(name)

	table.insert(fs, "label[1,4;CHARACTER LOCKER]")

	if match_side or is_spectator then
		table.insert(fs, "style_type[label;textcolor=#FF4444]")
		table.insert(fs, "label[1,5.5;OUTFIT MODIFICATION DISABLED DURING ACTIVE SESSION]")
		table.insert(fs, "style_type[label;textcolor=white]")
		table.insert(fs, "label[1,6.0;Finish your match or stop spectating to customize your character.]")
	else
		table.insert(fs, "label[1,3.5;Select your base field outfit:]")

		local skins = {
			{id = "sam", name = "Tactical Sam", file = "character.png", portrait = "esports_portrait_sam.png", x = 1.1},
			{id = "elite", name = "Elite Soldier", file = "skin_1.png", portrait = "esports_portrait_elite.png", x = 5.2},
			{id = "recon", name = "Ghost Recon", file = "skin_2.png", portrait = "esports_portrait_recon.png", x = 9.3},
			{id = "infil", name = "Infiltrator", file = "skin_3.png", portrait = "esports_portrait_infil.png", x = 13.4},
		}

		for _, s in ipairs(skins) do
			table.insert(fs, "image[" .. s.x .. ",4.6;3.0,5.5;" .. s.portrait .. "]")

			if current == s.file then
				table.insert(fs, "style[set_skin_" .. s.id .. ";bgcolor=#00FF00;textcolor=black]")
				table.insert(fs, "button[" .. s.x .. ",10.3;3.0,0.6;set_skin_" .. s.id .. ";ACTIVE]")
			else
				table.insert(fs, "button[" .. s.x .. ",10.3;3.0,0.6;set_skin_" .. s.id .. ";SELECT]")
			end
			table.insert(fs, "label[" .. s.x .. ",4.2;" .. s.name .. "]")
		end

		table.insert(fs, "label[1.1,11.1;Team colors will overlay these choices during a match.]")
	end

	-- Nickname Editor at the very bottom
	if esports_core.allow_nicks or is_admin then
		local raw_nick = esports_core.nicknames[name] or name
		table.insert(fs, "field[1.5,12.2;7.0,0.8;txt_nickname;Lobby Nickname;" .. core.formspec_escape(raw_nick) .. "]")
		table.insert(fs, "button[8.8,12.2;4.0,0.8;btn_set_nickname;UPDATE NICKNAME]")
		table.insert(fs, "button[13.1,12.2;3.0,0.8;btn_clear_nickname;RESET]")
	else
		table.insert(fs, "label[1.5,12.2;Nickname changes are currently disabled by an administrator. (Current: " .. core.formspec_escape(esports_core.get_nick(name)) .. ")]")
	end
end

local function get_formspec(name)
	local is_admin = core.check_player_privs(name, {server = true})
	local side = esports_core.match.get_player_match_side(name)
	local match_active = (esports_core.match.state == "active" or esports_core.match.state == "countdown")

	-- Ensure settings exist early
	if not player_settings[name] then
		player_settings[name] = {
			count = "5", diff = "medium", red = "", blue = "", pve = "",
			match_dur = "5m", match_tod = "Day", match_mode = "TDM",
			map_size = "Small", map_layout = "Random", friendly_fire = false, melee_damage = true,
			spleef_levels = "1 Level",
			league_subtab = "standings", sel_round = 1, sel_match_idx = 1, sel_spec_idx = 1
		}
	end

	if match_active and is_admin and not side then
		local settings = player_settings[name]
		if not settings.show_lobby_during_match then
			return esports_core.lobby.get_live_scoreboard_formspec(name)
		end
	end

	local tab = player_tabs[name] or (is_admin and "matchmaking" or "league")
	local p_team = esports_league.get_team(name) or "NONE"
	local settings = player_settings[name]
	if not settings.spleef_levels then
		settings.spleef_levels = "1 Level"
	end

	local fs = {
		"formspec_version[6]",
		"size[17.5,13.75]",
		"background9[0,0;17.5,13.75;esports_hud_bar.png;false;10]",
		"style_type[button;bgcolor=#333333;textcolor=white;font=bold]",
		"style_type[label;textcolor=white;font=bold]",
		"style[btn_disabled;bgcolor=#111111;textcolor=#888888]",

		-- Header (Dynamic Team Logo)
		"image[0.5,0.2;2,2;" .. esports_core.get_team_logo(p_team, "esports_logo_red.png") .. "]",
		"label[2.5,1;LUANTI ESPORTS - MAIN LOBBY v" .. esports_core.version .. " (build " .. esports_core.build .. ")]",
		"label[2.5,1.5;Current Team: " .. p_team .. "]",
		"style[exit_server;bgcolor=#770000;textcolor=white]",
		"button[14.0,1.3;3.0,0.9;exit_server;DISCONNECT]"
	}

	if is_admin then
		table.insert(fs, "style[exit_lobby;bgcolor=#555555;textcolor=white]")
		table.insert(fs, "button[11.5,1.3;2.2,0.9;exit_lobby;EXIT]")
		if match_active then
			table.insert(fs, "style[show_scoreboard;bgcolor=#007700;textcolor=white]")
			table.insert(fs, "button[9.0,1.3;2.2,0.9;show_scoreboard;SCOREBOARD]")
		end
	end

	-- Dynamic Tab Highlighting Style
	local active_btn = ""
	if tab == "matchmaking" then active_btn = "tab_match"
	elseif tab == "league" then active_btn = "tab_league"
	elseif tab == "team" then active_btn = "tab_team"
	elseif tab == "locker" then active_btn = "tab_locker"
	elseif tab == "settings" then active_btn = "tab_settings" end

	if active_btn ~= "" then
		table.insert(fs, "style[" .. active_btn .. ";bgcolor=#0055aa;textcolor=white]")
	end

	if is_admin then
		table.insert(fs, "button[0.5,2.5;2.5,0.8;tab_match;MATCH]")
		table.insert(fs, "button[3.3,2.5;2.5,0.8;tab_league;LEAGUE]")
		table.insert(fs, "button[6.1,2.5;2.5,0.8;tab_team;TEAM]")
		table.insert(fs, "button[8.9,2.5;2.5,0.8;tab_locker;LOCKER]")
		table.insert(fs, "button[11.7,2.5;2.5,0.8;tab_settings;ADMIN]")
		table.insert(fs, "style[btn_practice;bgcolor=#005533;textcolor=white]")
		table.insert(fs, "button[14.5,2.5;2.5,0.8;btn_practice;PRACTICE]")
	else
		table.insert(fs, "button[0.5,2.5;3.8,0.8;tab_league;LEAGUE]")
		table.insert(fs, "button[4.7,2.5;3.8,0.8;tab_team;TEAM]")
		table.insert(fs, "button[8.9,2.5;3.8,0.8;tab_locker;LOCKER]")
		table.insert(fs, "style[btn_practice;bgcolor=#005533;textcolor=white]")
		table.insert(fs, "button[13.1,2.5;3.9,0.8;btn_practice;PRACTICE]")
	end

	-- Assemble active tab UI
	if tab == "matchmaking" then
		build_matchmaking_tab(fs, settings)
	elseif tab == "league" then
		build_league_tab(fs, settings, is_admin)
	elseif tab == "team" then
		build_team_tab(fs, name)
	elseif tab == "settings" then
		build_admin_tab(fs, settings)
	elseif tab == "locker" then
		build_locker_tab(fs, name, is_admin)
	end

	return table.concat(fs)
end

function esports_core.lobby.show(player)
	local name = player:get_player_name()
	esports_core.lobby.blackout_show(player)
	core.show_formspec(name, "esports_core:lobby", get_formspec(name))
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "esports_core:lobby" then return end
	local name = player:get_player_name()
	local is_admin = core.check_player_privs(name, {server = true})

	-- Practice Range transition
	if fields.btn_practice then
		esports_core.lobby.blackout_hide(player)
		core.close_formspec(name, "esports_core:lobby")
		esports_core.practice.enter(name)
		return
	end

	-- Lobby Lock for non-participants (Mandatory Main Menu)
	if fields.quit then
		local side = esports_core.match.get_player_match_side(name)
		local in_practice = esports_core.practice and esports_core.practice.players and esports_core.practice.players[name]
		local huds = esports_core.hud and esports_core.hud.player_huds and esports_core.hud.player_huds[name]
		local is_viewing_outro = huds and huds.outro_bg ~= nil

		if not side and not esports_core.is_spectator(name) and (not is_admin or not fields.exit_lobby) and not in_practice and not is_viewing_outro then
			core.after(0, function()
				if core.get_player_by_name(name) then
					esports_core.lobby.show(player)
				end
			end)
			if not is_admin then
				core.chat_send_player(name, "LOBBY: You must remain in the menu until a match starts.")
			end
			return
		else
			esports_core.lobby.blackout_hide(player)
		end
	end

	-- Ensure settings exist
	if not player_settings[name] then
		player_settings[name] = {count = "5", diff = "medium"}
	end
	if not fields.quit then
		player_settings[name].err_msg = nil
	end

	-- Disconnect Logic
	if fields.exit_server then
		core.kick_player(name, "Logged out via Main Lobby")
		return
	end

	-- Scoreboard / Lobby toggles for admin during active match
	if fields.show_lobby and is_admin then
		player_settings[name].show_lobby_during_match = true
		esports_core.lobby.show(player)
		return
	end
	if fields.show_scoreboard and is_admin then
		player_settings[name].show_lobby_during_match = nil
		esports_core.lobby.show(player)
		return
	end

	-- Tab Switching
	if fields.tab_match and is_admin then player_tabs[name] = "matchmaking" end
	if fields.tab_league then player_tabs[name] = "league" end
	if fields.tab_team then player_tabs[name] = "team" end
	if fields.tab_locker then player_tabs[name] = "locker" end
	if fields.tab_settings and is_admin then player_tabs[name] = "settings" end

	-- League Sub-Tab Switching
	if fields.league_tab_standings then
		player_settings[name].league_subtab = "standings"
		esports_core.lobby.show(player)
		return
	end
	if fields.league_tab_schedule then
		player_settings[name].league_subtab = "schedule"
		esports_core.lobby.show(player)
		return
	end
	if fields.league_tab_history then
		player_settings[name].league_subtab = "history"
		esports_core.lobby.show(player)
		return
	end
	if fields.league_tab_playoffs then
		player_settings[name].league_subtab = "playoffs"
		esports_core.lobby.show(player)
		return
	end



	if fields.btn_generate_schedule and is_admin then
		local ok, msg = esports_league.generate_fixtures()
		core.chat_send_player(name, "LOBBY: " .. msg)
		esports_core.lobby.show(player)
		return
	end

	if fields.start_scheduled_match and is_admin then
		local sel_round = player_settings[name].sel_round or 1
		local sel_match_idx = player_settings[name].sel_match_idx or 1
		local round_matches = esports_league.fixtures[sel_round] or {}
		local m_info = round_matches[sel_match_idx]

		core.log("action", "[TDM League] Match start clicked by " .. name ..
			" | round: " .. tostring(sel_round) .. " | match: " .. tostring(sel_match_idx) ..
			" | info: " .. (m_info and (m_info.home .. " vs " .. m_info.away .. " status: " .. m_info.status) or "nil"))

		if m_info and m_info.status == "pending" then
			local red = m_info.home
			local blue = m_info.away
			local dur = 300
			local tod = "day"
			local mode = "tdm"
			local map_size = "Small"

			local my_team = esports_league.get_team(name)
			if my_team ~= red and my_team ~= blue then
				local cmd = core.registered_chatcommands["spectate"]
				if cmd and not esports_core.is_spectator(name) then cmd.func(name, "") end
			end

			esports_core.match.scheduled_context = {
				type = "regular_season",
				round = sel_round,
				index = sel_match_idx
			}

			local ok, err = esports_core.match.start(red, blue, dur, false, tod, 0, nil, mode, map_size)
			if not ok then
				player_settings[name].err_msg = err or "Could not start match."
				core.chat_send_player(name, "ERROR: " .. (err or "Could not start match."))
				esports_core.lobby.show(player)
			else
				handle_match_start_close(player)
			end
			return
		else
			player_settings[name].err_msg = "Selected match not found or not pending."
			core.chat_send_player(name, "ERROR: Selected match not found or not pending.")
			esports_core.lobby.show(player)
			return
		end
	end

	if fields.btn_start_playoffs and is_admin then
		local ok, msg = esports_league.start_playoffs()
		core.chat_send_player(name, "LOBBY: " .. msg)
		esports_core.lobby.show(player)
		return
	end

	if fields.start_sf1 and is_admin then
		local p = esports_league.playoffs
		local sf1 = p.semifinals[1]
		if sf1 and sf1.status == "pending" then
			esports_core.match.scheduled_context = {
				type = "playoff_semifinal",
				index = 1
			}
			local ok, err = esports_core.match.start(sf1.team1, sf1.team2, 300, false, "day", 0, nil, "tdm", "Large")
			if not ok then
				player_settings[name].err_msg = err or "Could not start match."
				core.chat_send_player(name, "ERROR: " .. (err or "Could not start match."))
				esports_core.lobby.show(player)
			else
				handle_match_start_close(player)
			end
			return
		else
			player_settings[name].err_msg = "Semifinal 1 not found or not pending."
			core.chat_send_player(name, "ERROR: Semifinal 1 not found or not pending.")
			esports_core.lobby.show(player)
			return
		end
	end

	if fields.start_sf2 and is_admin then
		local p = esports_league.playoffs
		local sf2 = p.semifinals[2]
		if sf2 and sf2.status == "pending" then
			esports_core.match.scheduled_context = {
				type = "playoff_semifinal",
				index = 2
			}
			local ok, err = esports_core.match.start(sf2.team1, sf2.team2, 300, false, "day", 0, nil, "tdm", "Large")
			if not ok then
				player_settings[name].err_msg = err or "Could not start match."
				core.chat_send_player(name, "ERROR: " .. (err or "Could not start match."))
				esports_core.lobby.show(player)
			else
				handle_match_start_close(player)
			end
			return
		else
			player_settings[name].err_msg = "Semifinal 2 not found or not pending."
			core.chat_send_player(name, "ERROR: Seminal 2 not found or not pending.")
			esports_core.lobby.show(player)
			return
		end
	end

	if fields.start_final and is_admin then
		local p = esports_league.playoffs
		local fn = p.finals
		if fn and fn.status == "pending" and fn.team1 ~= "" and fn.team2 ~= "" then
			esports_core.match.scheduled_context = {
				type = "playoff_final"
			}
			local ok, err = esports_core.match.start(fn.team1, fn.team2, 300, false, "day", 0, nil, "tdm", "Large")
			if not ok then
				player_settings[name].err_msg = err or "Could not start match."
				core.chat_send_player(name, "ERROR: " .. (err or "Could not start match."))
				esports_core.lobby.show(player)
			else
				handle_match_start_close(player)
			end
			return
		else
			player_settings[name].err_msg = "Grand Final not found or not pending."
			core.chat_send_player(name, "ERROR: Grand Final not found or not pending.")
			esports_core.lobby.show(player)
			return
		end
	end

	if fields.archive_season and is_admin then
		local ok, msg = esports_league.archive_season()
		core.chat_send_player(name, "LOBBY: " .. msg)
		esports_core.lobby.show(player)
		return
	end

	-- Skin Selection
	local meta = player:get_meta()
	local is_skin_field = fields.set_skin_sam or fields.set_skin_elite or fields.set_skin_recon or fields.set_skin_infil

	if is_skin_field then
		-- SERVER-SIDE SECURITY: Prevent mid-match skin hacks
		local match_side = esports_core.match.get_player_match_side(name)
		if match_side or esports_core.is_spectator(name) then
			core.chat_send_player(name, "LOBBY: Cannot change skins during active combat or spectating.")
			esports_core.lobby.show(player)
			return
		end

		if fields.set_skin_sam then meta:set_string("esports_selected_skin", "character.png") end
		if fields.set_skin_elite then meta:set_string("esports_selected_skin", "skin_1.png") end
		if fields.set_skin_recon then meta:set_string("esports_selected_skin", "skin_2.png") end
		if fields.set_skin_infil then meta:set_string("esports_selected_skin", "skin_3.png") end

		esports_core.skins.apply(player, nil)
		esports_core.lobby.show(player)
		return
	end

	-- Textlist Selection Tracking
	if fields.find_teams then
		local event = core.explode_textlist_event(fields.find_teams)
		player_settings[name].sel_team_idx = event.index
	end
	if fields.sel_invite then
		local event = core.explode_textlist_event(fields.sel_invite)
		player_settings[name].sel_invite_idx = event.index
	end
	if fields.roster_list then
		local event = core.explode_textlist_event(fields.roster_list)
		player_settings[name].sel_roster_idx = event.index
	end
	if fields.sel_request then
		local event = core.explode_textlist_event(fields.sel_request)
		player_settings[name].sel_request_idx = event.index
	end
	if fields.sel_roster_admin then
		local event = core.explode_textlist_event(fields.sel_roster_admin)
		player_settings[name].sel_admin_roster_idx = event.index
	end

	-- TEAM MANAGEMENT ACTIONS
	local p_team_nav = esports_league.get_team(name)

	-- Join Request
	if fields.request_join then
		local idx = player_settings[name].sel_team_idx
		if idx then
			local all_teams = {}
			for tname, _ in pairs(esports_league.teams) do table.insert(all_teams, tname) end
			table.sort(all_teams)
			local target = all_teams[idx]
			if target then
				local ok, msg = esports_league.add_request(name, target)
				core.chat_send_player(name, "LOBBY: " .. msg)
				esports_core.lobby.show(player)
			end
		end
	end

	-- Accept/Decline Invite
	if fields.accept_invite or fields.decline_invite then
		local idx = player_settings[name].sel_invite_idx
		local invites = {}
		for target, team in pairs(esports_league.invites) do if target == name then table.insert(invites, team) end end
		local target_team = invites[idx or 1]

		if target_team then
			if fields.accept_invite then
				local cmd = core.registered_chatcommands["team"]
				local ok, msg = cmd.func(name, "join")
				core.chat_send_player(name, "LOBBY: " .. msg)
			else
				esports_league.invites[name] = nil
				esports_league.save()
				core.chat_send_player(name, "LOBBY: Invite declined.")
			end
			esports_core.lobby.show(player)
		end
	end

	-- Kick Player (Owner)
	if fields.kick_player then
		local idx = player_settings[name].sel_roster_idx
		if p_team_nav and idx then
			local team_data = esports_league.teams[p_team_nav]
			local target = team_data.members[idx]
			if target then
				local ok, msg = esports_league.kick_member(name, target)
				core.chat_send_player(name, "LOBBY: " .. msg)
				esports_core.lobby.show(player)
			end
		end
	end

	-- Leave Team
	if fields.leave_team then
		local cmd = core.registered_chatcommands["team"]
		local ok, msg = cmd.func(name, "leave")
		core.chat_send_player(name, "LOBBY: " .. msg)
		esports_core.lobby.show(player)
	end

	-- Send Invite (Owner)
	if fields.send_invite and fields.invite_name ~= "" then
		local cmd = core.registered_chatcommands["team"]
		local ok, msg = cmd.func(name, "invite " .. fields.invite_name)
		core.chat_send_player(name, "LOBBY: " .. msg)
		esports_core.lobby.show(player)
	end

	-- Process Join Request (Owner or Admin)
	if fields.accept_request or fields.deny_request then
		local target_team = p_team_nav
		if is_admin then
			target_team = player_settings[name].selected_team
		end

		local idx = player_settings[name].sel_request_idx
		if target_team and idx then
			local requests = esports_league.requests[target_team] or {}
			local target = requests[idx]

			if target then
				if fields.accept_request then
					table.insert(esports_league.teams[target_team].members, target)
					esports_league.player_to_team[target] = target_team
					esports_league.update_player_nametag(target)
					core.chat_send_player(target, "LOBBY: Your request to join '" .. target_team .. "' was approved!")
					core.chat_send_player(name, "LOBBY: Accepted " .. target .. " into the team.")
				else
					core.chat_send_player(target, "LOBBY: Your request to join '" .. target_team .. "' was denied.")
					core.chat_send_player(name, "LOBBY: Denied " .. target .. "'s request.")
				end
				esports_league.remove_request(target, target_team)
				esports_league.save()
				esports_core.lobby.show(player)
			end
		end
	end

	-- Set Owner (Admin)
	if fields.set_owner and is_admin then
		local selected_team = player_settings[name].selected_team
		local idx = player_settings[name].sel_admin_roster_idx
		if selected_team and idx then
			local team_data = esports_league.teams[selected_team]
			local target = team_data.members[idx]
			if target then
				local ok, msg = esports_league.set_owner(name, selected_team, target)
				core.chat_send_player(name, "LOBBY: " .. msg)
				esports_core.lobby.show(player)
			end
		end
	end

	-- Unset Leader (Admin)
	if fields.unset_owner and is_admin then
		local selected_team = player_settings[name].selected_team
		if selected_team then
			local ok, msg = esports_league.unset_owner(name, selected_team)
			core.chat_send_player(name, "LOBBY: " .. msg)
			esports_core.lobby.show(player)
		end
	end

	-- Rename Team (Admin)
	if fields.rename_team and is_admin then
		local selected_team = player_settings[name].selected_team
		local new_name = fields.rename_val
		if selected_team and new_name and new_name ~= "" then
			local ok, msg = esports_league.rename_team(name, selected_team, new_name)
			core.chat_send_player(name, "LOBBY: " .. msg)
			if ok then
				player_settings[name].selected_team = new_name
			end
			esports_core.lobby.show(player)
		else
			core.chat_send_player(name, "LOBBY: Please enter a valid team name.")
		end
	end

	-- Change Team Tag (Admin)
	if fields.change_tag and is_admin then
		local selected_team = player_settings[name].selected_team
		local new_tag = fields.tag_val
		if selected_team and new_tag and new_tag ~= "" then
			local cmd_def = core.registered_chatcommands["leaguesettag"]
			if cmd_def then
				local ok, msg = cmd_def.func(name, selected_team .. " " .. new_tag)
				core.chat_send_player(name, "LOBBY: " .. msg)
			end
			esports_core.lobby.show(player)
		else
			core.chat_send_player(name, "LOBBY: Please enter a valid team tag.")
		end
	end

	-- Dropdown Updates
	if fields.bot_count then player_settings[name].count = fields.bot_count end
	if fields.bot_diff then player_settings[name].diff = fields.bot_diff end
	if fields.sel_red then player_settings[name].red = fields.sel_red end
	if fields.sel_blue then player_settings[name].blue = fields.sel_blue end
	if fields.sel_pve then player_settings[name].pve = fields.sel_pve end
	if fields.sel_dur then player_settings[name].match_dur = fields.sel_dur end
	if fields.sel_tod then player_settings[name].match_tod = fields.sel_tod end
	if fields.sel_mode then player_settings[name].match_mode = fields.sel_mode end
	if fields.sel_map_size then player_settings[name].map_size = fields.sel_map_size end
	if fields.sel_map_layout then player_settings[name].map_layout = fields.sel_map_layout end
	if fields.sel_spleef_levels then player_settings[name].spleef_levels = fields.sel_spleef_levels end
	if fields.chk_friendly_fire then player_settings[name].friendly_fire = (fields.chk_friendly_fire == "true") end
	if fields.chk_melee_damage then player_settings[name].melee_damage = (fields.chk_melee_damage == "true") end

	-- League Inspector Selection
	local teams_list_field = fields.teams_list or fields.teams_list_clear
	if teams_list_field then
		local event = core.explode_textlist_event(teams_list_field)
		if event.type == "CHG" or event.type == "DCL" then
			local sorted = {}
			for tname, _ in pairs(esports_league.teams) do
				table.insert(sorted, tname)
			end
			table.sort(sorted, function(a, b)
				local da = esports_league.teams[a]
				local db = esports_league.teams[b]
				local wa = da.wins or 0
				local wb = db.wins or 0
				if wa ~= wb then return wa > wb end

				local diffa = (da.kills_scored or 0) - (da.deaths_conceded or 0)
				local diffb = (db.kills_scored or 0) - (db.deaths_conceded or 0)
				if diffa ~= diffb then return diffa > diffb end

				return (da.kills_scored or 0) > (db.kills_scored or 0)
			end)

			local selected = sorted[event.index]
			if selected then
				if player_settings[name].selected_team == selected then
					player_settings[name].selected_team = nil
				else
					player_settings[name].selected_team = selected
				end
				esports_core.lobby.show(core.get_player_by_name(name))
			end
		end
	end

	if fields.unselect_team then
		player_settings[name].selected_team = nil
		esports_core.lobby.show(player)
	end

	-- Actions (Admin Only)
	if fields.spectate and is_admin then
		local cmd = core.registered_chatcommands["spectate"]
		if cmd then cmd.func(name, "") end
		core.close_formspec(name, "esports_core:lobby")
		return
	end

	if fields.create_team and fields.new_team ~= "" and is_admin then
		local tag = (fields.new_team_tag or ""):trim()
		local cmd = core.registered_chatcommands["team"]
		if cmd then
			local ok, msg = cmd.func(name, "create " .. fields.new_team .. " " .. tag)
			if msg then core.chat_send_player(name, msg) end
			if not ok then
				player_settings[name].err_msg = msg
			else
				player_settings[name].err_msg = nil
			end
		end
	end

	local function sanitize(tname)
		if not tname then return "" end
		return tname:gsub("%s%(%d+%)$", "")
	end

	if fields.start_pve and is_admin then
		local p_team_raw = player_settings[name].pve
		local p_team = sanitize(p_team_raw)

		if p_team and p_team ~= "" and p_team ~= "No teams registered" then
			local count = tonumber(player_settings[name].count) or 5
			local diff = player_settings[name].diff or "medium"
			local dur_str = player_settings[name].match_dur or "5m"
			local dur = tonumber(dur_str:match("%d+")) * 60
			local tod = (player_settings[name].match_tod or "Day"):lower()
			local mode = (player_settings[name].match_mode or "TDM"):lower()

			-- Auto-spectate if admin is not in the team
			if esports_league.get_team(name) ~= p_team then
				local cmd = core.registered_chatcommands["spectate"]
				if cmd and not esports_core.is_spectator(name) then cmd.func(name, "") end
			end

			local map_size = player_settings[name].map_size or "Small"
			local map_layout = player_settings[name].map_layout or "Random"

			local spleef_levels_str = player_settings[name].spleef_levels or "1 Level"
			local spleef_levels = tonumber(spleef_levels_str:match("%d+")) or 1

			esports_core.match.scheduled_context = nil
			local ok, err = esports_core.match.start(p_team, "BOTS", dur, true, tod, count, diff, mode, map_size, player_settings[name].friendly_fire, player_settings[name].melee_damage, map_layout, spleef_levels)
			if not ok then
				player_settings[name].err_msg = err or "Could not start match."
				esports_core.lobby.show(player)
			else
				handle_match_start_close(player)
			end
			return
		else
			core.chat_send_player(name, "Please select a valid team for PVE practice!")
		end
	end

	if fields.start_ffa and is_admin then
		local dur_str = player_settings[name].match_dur or "5m"
		local dur = tonumber(dur_str:match("%d+")) * 60
		local tod = (player_settings[name].match_tod or "Day"):lower()
		local map_size = player_settings[name].map_size or "Small"
		local map_layout = player_settings[name].map_layout or "Random"

		esports_core.match.scheduled_context = nil
		esports_core.match.friendly_fire = true

		local ok, err = esports_core.match.start(nil, nil, dur, false, tod, nil, nil, "ffa", map_size, true, player_settings[name].melee_damage, map_layout)
		if not ok then
			player_settings[name].err_msg = err or "Could not start Free For All."
			esports_core.lobby.show(player)
		else
			handle_match_start_close(player)
		end
		return
	end

	if fields.start_comp and is_admin then
		local red_raw = player_settings[name].red
		local blue_raw = player_settings[name].blue
		local red = sanitize(red_raw)
		local blue = sanitize(blue_raw)

		if red and blue and red ~= "" and blue ~= "" and red ~= "No teams registered" and blue ~= "No teams registered" then
			if red == blue then
				core.chat_send_player(name, "A team cannot fight itself! Choose two different teams.")
			else
				local dur_str = player_settings[name].match_dur or "5m"
				local dur = tonumber(dur_str:match("%d+")) * 60
				local tod = (player_settings[name].match_tod or "Day"):lower()
				local mode = (player_settings[name].match_mode or "TDM"):lower()

				-- Auto-spectate if admin is not in either team
				local my_team = esports_league.get_team(name)
				if my_team ~= red and my_team ~= blue then
					local cmd = core.registered_chatcommands["spectate"]
					if cmd and not esports_core.is_spectator(name) then cmd.func(name, "") end
				end

				local map_size = player_settings[name].map_size or "Small"
				local map_layout = player_settings[name].map_layout or "Random"
				local spleef_levels_str = player_settings[name].spleef_levels or "1 Level"
				local spleef_levels = tonumber(spleef_levels_str:match("%d+")) or 1

				esports_core.match.scheduled_context = nil
				local ok, err = esports_core.match.start(red, blue, dur, false, tod, 0, nil, mode, map_size, player_settings[name].friendly_fire, player_settings[name].melee_damage, map_layout, spleef_levels)
				if not ok then
					player_settings[name].err_msg = err or "Could not start match."
					esports_core.lobby.show(player)
				else
					handle_match_start_close(player)
				end
				return
			end
		else
			core.chat_send_player(name, "Please select two valid teams for a competitive match!")
		end
	end

	if fields.pause_match and is_admin then
		esports_core.match.pause()
		esports_core.lobby.show(player)
		return
	end

	if fields.resume_match and is_admin then
		esports_core.match.resume()
		esports_core.lobby.show(player)
		return
	end

	if fields.stop_match and is_admin then
		esports_core.match.state = "over"
		esports_core.match.timer = 1
		esports_core.match.paused = false
		-- Clear state immediately to prevent stale data on instant restarts
		esports_core.match.player_sides = {}
		esports_core.teams.players = {}
		esports_core.match.player_stats = {}

		if esports_core.bots then esports_core.bots.clear_all() end
		if esports_mapgen and esports_mapgen.reset_island then
			esports_mapgen.reset_island("lobby")
		end

		-- Teleport all players back to the lobby center spawn to prevent falling into the void
		for _, p in ipairs(core.get_connected_players()) do
			p:set_pos({x=0, y=1.5, z=0})
			p:set_physics_override({speed = 0, jump = 0, gravity = 1})
		end
		core.chat_send_all("ADMIN: Match has been stopped by " .. name)
		esports_core.lobby.show(player)
		return
	end

	if fields.go_spectate and is_admin then
		player_settings[name].spectator_view = true
		local cmd = core.registered_chatcommands["spectate"]
		if cmd and not esports_core.is_spectator(name) then
			cmd.func(name, "")
		end
		esports_core.lobby.blackout_hide(player)
		core.close_formspec(name, "esports_core:lobby")
		return
	end

	if fields.btn_reset_nick and is_admin then
		local sel_idx = player_settings[name].sel_nick_idx or 1
		local keys = {}
		for username in pairs(esports_core.nicknames) do
			table.insert(keys, username)
		end
		table.sort(keys)
		local target = keys[sel_idx]
		if target then
			esports_core.nicknames[target] = nil
			esports_core.save_nicknames()
			local tp = core.get_player_by_name(target)
			if tp then tp:set_properties({nametag = target}) end
			core.chat_send_player(name, "LOBBY: Reset " .. target .. "'s nickname to default.")
		end
		esports_core.lobby.show(player)
		return
	end

	if fields.chk_allow_nicks then
		esports_core.allow_nicks = (fields.chk_allow_nicks == "true")
		local storage = core.get_mod_storage()
		storage:set_string("allow_nicks", esports_core.allow_nicks and "true" or "false")
		esports_core.lobby.show(player)
		return
	end

	if fields.chk_allow_team_create then
		esports_league.allow_team_creation = (fields.chk_allow_team_create == "true")
		esports_league.save()
		esports_core.lobby.show(player)
		return
	end

	if fields.btn_set_nickname and fields.txt_nickname then
		if not esports_core.allow_nicks and not is_admin then
			player_settings[name].err_msg = "Nickname changes are currently disabled by an administrator."
			esports_core.lobby.show(player)
			return
		end

		local new_nick = fields.txt_nickname:gsub("[^%w%s%-%_]", ""):sub(1, 15)
		if new_nick == "" then
			player_settings[name].err_msg = "Invalid nickname (alpha-numeric only, max 15 chars)."
			esports_core.lobby.show(player)
			return
		end

		esports_core.nicknames[name] = new_nick
		esports_core.save_nicknames()
		player:set_properties({nametag = new_nick})
		player_settings[name].err_msg = nil
		esports_core.lobby.show(player)
		return
	end

	if fields.btn_clear_nickname then
		esports_core.nicknames[name] = nil
		esports_core.save_nicknames()
		player:set_properties({nametag = name})
		player_settings[name].err_msg = nil
		esports_core.lobby.show(player)
		return
	end

	if fields.sel_round_dropdown then
		local r_num = tonumber(fields.sel_round_dropdown:match("Round (%d+)"))
		if r_num then
			player_settings[name].sel_round = r_num
			esports_core.lobby.show(player)
			return
		end
	end

	if fields.sel_match_list then
		local event = core.explode_textlist_event(fields.sel_match_list)
		player_settings[name].sel_match_idx = event.index
		esports_core.lobby.show(player)
		return
	end

	if fields.admin_nicks_list then
		local event = core.explode_textlist_event(fields.admin_nicks_list)
		player_settings[name].sel_nick_idx = event.index
		esports_core.lobby.show(player)
		return
	end

	if fields.admin_spec_list then
		local event = core.explode_textlist_event(fields.admin_spec_list)
		player_settings[name].sel_spec_idx = event.index
		esports_core.lobby.show(player)
		return
	end

	if fields.btn_toggle_spec and is_admin then
		local online_players = core.get_connected_players()
		local spec_keys = {}
		for _, p in ipairs(online_players) do
			table.insert(spec_keys, p:get_player_name())
		end
		table.sort(spec_keys)

		local sel_idx = player_settings[name].sel_spec_idx or 1
		local target_name = spec_keys[sel_idx]
		if target_name then
			local target_player = core.get_player_by_name(target_name)
			if target_player then
				local is_spec = esports_core.is_spectator(target_name)
				if is_spec then
					esports_core.set_spectator(target_player, false)
					core.chat_send_player(target_name, "Spectator mode disabled by administrator " .. name .. ".")
					core.chat_send_player(name, "LOBBY: Removed spectator rights for " .. target_name .. ".")
					esports_core.lobby.show(target_player)
				else
					esports_core.set_spectator(target_player, true)
					core.chat_send_player(target_name, "Spectator mode enabled by administrator " .. name .. ".")
					core.chat_send_player(name, "LOBBY: Granted spectator rights to " .. target_name .. ".")
					esports_core.lobby.blackout_hide(target_player)
					core.close_formspec(target_name, "esports_core:lobby")
				end
				esports_core.lobby.refresh_admins()
			else
				core.chat_send_player(name, "LOBBY: Player is no longer online.")
			end
		end
		esports_core.lobby.show(player)
		return
	end

	-- Refresh if not closing
	if not fields.quit then
		esports_core.lobby.show(player)
	end
end)

-- LOBBY WATCHDOG: Ensures non-participants stay in the lobby at all times
local watchdog_timer = 0
core.register_globalstep(function(dtime)
	watchdog_timer = watchdog_timer + dtime
	if watchdog_timer < 1 then return end
	watchdog_timer = 0

	for _, player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()
		local is_admin = core.check_player_privs(name, {server = true})
		local side = esports_core.match.get_player_match_side(name)

		-- Dynamic mid-match join detection: if a player in the lobby gets assigned a team side during an active match
		local match_active = (esports_core.match.state == "active" or esports_core.match.state == "countdown")
		if match_active and side and esports_core.teams.players[name] ~= side then
			esports_core.match.join_player_to_ongoing(player)
		end

		-- If NOT in a match side, NOT an admin, and NOT already a spectator
		if not side and not is_admin and not esports_core.is_spectator(name) then
			local huds = esports_core.hud and esports_core.hud.player_huds and esports_core.hud.player_huds[name]
			local is_viewing_outro = huds and huds.outro_bg ~= nil
			if not is_viewing_outro then
				-- Force physics freeze with gravity
				player:set_physics_override({speed = 0, jump = 0, gravity = 1})
				-- Force lobby re-open
				esports_core.lobby.show(player)
			end
		else
			-- Restore normal settings
			player:override_day_night_ratio(nil)
			local settings = player_settings[name]
			local is_spectator_view = settings and settings.spectator_view
			if match_active and is_admin and not side and not is_spectator_view then
				-- Force live scoreboard refresh/stay open for spectating admins who are not in 3D spectate view
				esports_core.lobby.show(player)
			elseif (side or esports_core.is_spectator(name)) and not is_admin then
				-- Close lobby formspec and hide blackout for participants/spectators (except admins!)
				esports_core.lobby.blackout_hide(player)
				core.close_formspec(name, "esports_core:lobby")
			end
		end

		-- DYNAMIC PRIVILEGE REFRESH: Ensure all active players can interact, and lobby players cannot
		if not esports_core.is_spectator(name) then
			local privs = core.get_player_privs(name)
			local in_lobby = esports_core.is_in_lobby(name)

			if in_lobby then
				-- Revoke interact privilege in lobby mode
				if privs.interact then
					privs.interact = nil
					core.set_player_privs(name, privs)
				end
				-- Wipe inventory weapons/ammo/health pack if they have them in lobby
				local inv = player:get_inventory()
				if inv then
					local main = inv:get_list("main")
					local ammo = inv:get_list("ammo")
					local cleared = false
					if main then
						for slot, stack in ipairs(main) do
							local item_name = stack:get_name()
							if item_name:find("esports_weapons:") or item_name:find("health_pack") then
								main[slot] = ItemStack("")
								cleared = true
							end
						end
						if cleared then inv:set_list("main", main) end
					end
					if ammo and #ammo > 0 then
						inv:set_list("ammo", {})
					end
				end

				-- Ensure interact_distance is 0 and they are immortal in lobby mode
				local props = player:get_properties()
				if props.interact_distance ~= 0 then
					player:set_properties({
						interact_distance = 0,
					})
				end
				local armor = player:get_armor_groups()
				if not armor.immortal or armor.immortal ~= 1 then
					player:set_armor_groups({immortal = 1})
				end
			else
				-- Grant interact privilege to active match players or practice range players
				if not privs.interact or not privs.shout then
					privs.interact = true
					privs.shout = true
					core.set_player_privs(name, privs)
					core.chat_send_player(name, "SYSTEM: Privileges synchronized.")
				end

				-- Ensure interact_distance is restored for active combatants (and not spectators)
				local props = player:get_properties()
				if props.interact_distance ~= 10 then
					player:set_properties({
						interact_distance = 10,
					})
				end
			end
		end
	end
end)

core.register_chatcommand("lobby", {
	description = "Open the League Lobby Menu",
	func = function(name)
		local player = core.get_player_by_name(name)
		if player then
			if player_settings[name] then
				player_settings[name].spectator_view = nil
			else
				player_settings[name] = { spectator_view = nil }
			end

			-- Reset player from practice range if they are inside
			if esports_core.practice and esports_core.practice.players[name] then
				esports_core.practice.players[name] = nil
				player:set_pos({x=0, y=1.5, z=0})
				esports_core.reset_to_lobby(player)
			end

			esports_core.lobby.show(player)
		end
	end
})

core.register_chatcommand("l", {
	description = "Shortcut to open the League Lobby Menu",
	func = function(name)
		local cmd = core.registered_chatcommands["lobby"]
		if cmd then
			return cmd.func(name)
		end
	end
})

local refresh_timer = nil

function esports_core.lobby.refresh_admins()
	if refresh_timer then
		return
	end

	refresh_timer = core.after(0.2, function()
		refresh_timer = nil
		for _, player in ipairs(core.get_connected_players()) do
			local pname = player:get_player_name()
			if core.check_player_privs(pname, {server = true}) then
				-- Only refresh if the admin is NOT actively playing the match (not on a side)
				local side = esports_core.match.get_player_match_side(pname)
				if not side then
					esports_core.lobby.show(player)
				end
			end
		end
	end)
end

core.register_on_joinplayer(function(player)
	-- Delay slightly to ensure team data/state is finalized
	core.after(1, esports_core.lobby.refresh_admins)
end)

core.register_on_leaveplayer(function(player)
	esports_core.lobby.blackouts[player:get_player_name()] = nil
	-- Delay to ensure core.get_connected_players() reflects the departure
	core.after(0.5, esports_core.lobby.refresh_admins)
end)


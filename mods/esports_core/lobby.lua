esports_core.lobby = {}
esports_core.lobby.blackouts = {}

function esports_core.lobby.blackout_show(player)
    local name = player:get_player_name()
    if esports_core.lobby.blackouts[name] then
        return
    end
    
    local hud_id = player:hud_add({
        hud_elem_type = "image",
        position = {x = 0.5, y = 0.5},
        name = "lobby_blackout",
        scale = {x = -100, y = -100}, -- 100% screen size
        text = "esports_hud_bar.png^[colorize:#000000:255", -- Solid black
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
local player_tabs = {} -- name -> tab_id
local player_settings = {} -- name -> {bot_count=x, bot_diff=y, ...}

local player_settings = {} -- name -> {bot_count=x, bot_diff=y, ...}

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

local function get_formspec(name)
    local is_admin = core.check_player_privs(name, {server = true})
    local tab = player_tabs[name] or (is_admin and "matchmaking" or "league")
    local p_team = esports_league.get_team(name) or "NONE"
    
    -- Ensure settings exist
    if not player_settings[name] then
        player_settings[name] = { 
            count = "5", diff = "medium", red = "", blue = "", pve = "", 
            match_dur = "5m", match_tod = "Day", match_mode = "TDM",
            map_size = "Large",
            league_subtab = "standings", sel_round = 1, sel_match_idx = 1
        }
    end
    local settings = player_settings[name]
    
    local teams_list = get_available_teams()
    local teams_str = table.concat(teams_list, ",")
    if teams_str == "" then teams_str = "No teams registered" end
    
    local fs = "formspec_version[6]" ..
        "size[14,11]" ..
        "background9[0,0;14,11;esports_hud_bar.png;false;10]" ..
        "style_type[button;bgcolor=#333333;textcolor=white;font=bold]" ..
        "style_type[label;textcolor=white;font=bold]" ..
        "style[btn_disabled;bgcolor=#111111;textcolor=#888888]" ..
        
        -- Header (Dynamic Team Logo)
        "image[0.5,0.2;2,2;" .. esports_core.get_team_logo(p_team, "esports_logo_red.png") .. "]" ..
        "label[2.5,1;LUANTI ESPORTS - MAIN LOBBY]" ..
        "label[2.5,1.5;Current Team: " .. p_team .. "]" ..
        "style[exit_server;bgcolor=#770000;textcolor=white]" ..
        "button[10.5,1.3;3.0,0.9;exit_server;DISCONNECT]"
        
    if is_admin then
        fs = fs ..
            "style[exit_lobby;bgcolor=#555555;textcolor=white]" ..
            "button[8.0,1.3;2.2,0.9;exit_lobby;EXIT]"
    end
        
    -- Dynamic Tab Highlighting Style
    local active_btn = ""
    if tab == "matchmaking" then active_btn = "tab_match"
    elseif tab == "league" then active_btn = "tab_league"
    elseif tab == "team" then active_btn = "tab_team"
    elseif tab == "locker" then active_btn = "tab_locker"
    elseif tab == "settings" then active_btn = "tab_settings" end
    
    if active_btn ~= "" then
        fs = fs .. "style[" .. active_btn .. ";bgcolor=#0055aa;textcolor=white]"
    end
        
    if is_admin then
        fs = fs .. 
            "button[0.5,2.5;2.4,0.8;tab_match;MATCH]" ..
            "button[3.15,2.5;2.4,0.8;tab_league;LEAGUE]" ..
            "button[5.8,2.5;2.4,0.8;tab_team;TEAM]" ..
            "button[8.45,2.5;2.4,0.8;tab_locker;LOCKER]" ..
            "button[11.1,2.5;2.4,0.8;tab_settings;ADMIN]"
    else
        fs = fs ..
            "button[0.5,2.5;4.0,0.8;tab_league;LEAGUE]" ..
            "button[5.0,2.5;4.0,0.8;tab_team;TEAM]" ..
            "button[9.5,2.5;4.0,0.8;tab_locker;LOCKER]"
    end
        
    local match_active = (esports_core.match.state == "active")
    
    if tab == "matchmaking" then
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

        fs = fs .. 
            "label[0.8,3.8;COMPETITIVE MATCH]" ..
            "label[0.8,4.3;Choose the competing teams:]" ..
            
            "label[0.8,5.2;Red Team:]" ..
            "dropdown[0.8,5.6;5.4,0.6;sel_red;" .. teams_str .. ";" .. red_idx .. "]" ..
            
            "label[0.8,6.8;Blue Team:]" ..
            "dropdown[0.8,7.2;5.4,0.6;sel_blue;" .. teams_str .. ";" .. blue_idx .. "]"
            
        fs = fs .. "box[6.95,3.8;0.1,4.0;#ffffff]" .. -- Divider (Shortened to avoid Arena overlap)
            
            "label[7.4,3.8;BOT PRACTICE (PVE)]" ..
            "label[7.4,4.3;Current Setup: " .. settings.count .. " Bots, " .. settings.diff .. " difficulty]" ..
            
            "label[7.4,5.2;Player Team:]" ..
            "dropdown[7.4,5.6;5.8,0.6;sel_pve;" .. teams_str .. ";" .. pve_idx .. "]"
            
            local size_list = {"Small","Medium","Large"}
            local size_idx = 3
            for i, v in ipairs(size_list) do if v == settings.map_size then size_idx = i break end end
 
            fs = fs .. "box[0.8,8.0;12.4,1.2;#333333]" ..
            "label[1.0,8.2;ARENA CONFIGURATION]" ..
            "label[1.0,8.8;Dur:]" ..
            "dropdown[2.0,8.5;1.5,0.6;sel_dur;1m,5m,10m,15m,20m,30m;2]" ..
            "label[3.9,8.8;Mode:]" ..
            "dropdown[4.9,8.5;1.8,0.6;sel_mode;TDM,CTF;" .. (settings.match_mode == "CTF" and 2 or 1) .. "]" ..
            "label[7.2,8.8;Time:]" ..
            "dropdown[8.2,8.5;1.8,0.6;sel_tod;Day,Night;1]" ..
            "label[10.5,8.8;Size:]" ..
            "dropdown[11.5,8.5;1.5,0.6;sel_map_size;Small,Medium,Large;" .. size_idx .. "]" ..
 
            "button[0.8,9.4;5.4,0.8;" .. start_comp_name .. ";START TEAM BATTLE]" ..
            "button[7.8,9.4;5.4,0.8;" .. start_pve_name .. ";START PVE MATCH]"
            
        if match_active then
            fs = fs .. 
                "style[stop_match;bgcolor=#770000;textcolor=white]" ..
                "label[4.2,10.0;MATCH CURRENTLY IN PROGRESS]" ..
                "button[0.8,10.4;12.4,0.5;stop_match;STOP MATCH]"
        end
    elseif tab == "league" then
        local league_subtab = settings.league_subtab or "standings"
        
        -- Style active sub-tab button
        local active_sub_btn = ""
        if league_subtab == "standings" then active_sub_btn = "league_tab_standings"
        elseif league_subtab == "schedule" then active_sub_btn = "league_tab_schedule"
        elseif league_subtab == "history" then active_sub_btn = "league_tab_history"
        elseif league_subtab == "playoffs" then active_sub_btn = "league_tab_playoffs" end
        
        if active_sub_btn ~= "" then
            fs = fs .. "style[" .. active_sub_btn .. ";bgcolor=#0077dd;textcolor=white]"
        end
        
        fs = fs ..
            "button[0.5,3.4;3.0,0.6;league_tab_standings;STANDINGS]" ..
            "button[3.8,3.4;3.0,0.6;league_tab_schedule;SCHEDULE]" ..
            "button[7.1,3.4;3.0,0.6;league_tab_history;HISTORY]" ..
            "button[10.4,3.4;3.0,0.6;league_tab_playoffs;PLAYOFFS]"

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
                table.insert(list_items, string.format("%s (W:%d L:%d D:%+d)", tname, d.wins or 0, d.losses or 0, diff))
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
            
            fs = fs ..
                "label[0.5,4.1;LEAGUE STANDINGS]" ..
                "textlist[0.5,4.6;6.0,4.4;" .. list_name .. ";" .. table.concat(list_items, ",") .. ";" .. selected_idx .. ";false]"
                
            -- Team Inspector Panel
            if selected and esports_league.teams[selected] then
                 local data = esports_league.teams[selected]
                 
                 local roster_items = {}
                 for _, mname in ipairs(data.members) do
                     local stats = esports_league.player_stats[mname] or {kills=0, deaths=0, captures=0}
                     local k = stats.kills or 0
                     local d = stats.deaths or 0
                     local c = stats.captures or 0
                     local rating = k - d + (c * 10)
                     local kd = "0.0"
                     if d > 0 then
                         local val = math.floor((k / d) * 10)
                         kd = tostring(math.floor(val / 10)) .. "." .. tostring(val % 10)
                     else
                         kd = tostring(k) .. ".0"
                     end
                     table.insert(roster_items, string.format("%s (R:%d KD:%s)", esports_core.get_nick(mname), rating, kd))
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
                         table.insert(req_items, esports_core.get_nick(req_name))
                     end
                     fs = fs ..
                         "box[7.0,4.6;6.5,4.4;#222222aa]" ..
                         "label[7.2,4.9;TEAM: " .. selected:upper() .. "]" ..
                         "label[7.2,5.3;Leader: " .. leader_display .. "]" ..
                         "label[7.2,5.8;ROSTER:]" ..
                         "textlist[7.2,6.1;6.1,1.2;sel_roster_admin;" .. table.concat(roster_items, ",") .. ";;false]" ..
                         "label[7.2,7.4;JOIN REQUESTS:]"
                     
                     if #requests > 0 then
                         fs = fs ..
                             "textlist[7.2,7.7;3.5,1.1;sel_request;" .. table.concat(req_items, ",") .. ";;false]" ..
                             "button[10.9,7.7;2.2,0.5;accept_request;APPROVE]" ..
                             "button[10.9,8.3;2.2,0.5;deny_request;DENY]"
                     else
                         fs = fs .. "label[7.2,7.9;No pending requests.]"
                     end
                    
                    fs = fs ..
                        "button[7.0,9.2;3.0,0.8;unselect_team;BACK]" ..
                        "button[10.2,9.2;3.3,0.8;set_owner;SET OWNER]"
                else
                    -- Normal Team Inspector Panel
                    fs = fs ..
                        "box[7.0,4.6;6.5,4.4;#222222aa]" ..
                        "label[7.2,5;TEAM: " .. selected:upper() .. "]" ..
                        "label[7.2,5.5;Leader: " .. leader_display .. "]" ..
                        "label[7.2,6.2;ROSTER:]" ..
                        "textlist[7.2,6.6;6.1,1.5;sel_roster_admin;" .. table.concat(roster_items, ",") .. ";;false]" ..
                        "button[7.2,8.2;6.1,0.6;unselect_team;Show Global Leaderboard]"
                end
            else
                -- Sort players for Global Leaderboard
                local sorted_players = {}
                for pname, stats in pairs(esports_league.player_stats) do
                    local k = stats.kills or 0
                    local d = stats.deaths or 0
                    local c = stats.captures or 0
                    local rating = k - d + (c * 10)
                    table.insert(sorted_players, {
                        name = pname,
                        kills = k,
                        deaths = d,
                        captures = c,
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
                    table.insert(board_items, string.format("%d. %s (R:%d K:%d D:%d C:%d)", i, p.name, p.rating, p.kills, p.deaths, p.captures))
                end
                if #board_items == 0 then
                    table.insert(board_items, "No player stats recorded yet")
                end
                
                fs = fs ..
                    "box[7.0,4.6;6.5,4.4;#222222aa]" ..
                    "label[7.2,5.0;GLOBAL LEADERBOARD]" ..
                    "textlist[7.2,5.4;6.1,3.3;global_leaderboard;" .. table.concat(board_items, ",") .. ";;false]"
            end
            
            if is_admin then
                if not selected then
                    fs = fs .. "field[0.5,9.2;4.5,0.8;new_team;New Team Name;]" ..
                    "button[5.2,9.2;3.5,0.8;create_team;CREATE TEAM]"
                end
            else
                fs = fs .. "label[0.5,9.2;Registration handled by administrators.]"
            end

        elseif league_subtab == "schedule" then
            if not esports_league.fixtures or #esports_league.fixtures == 0 then
                fs = fs .. "label[0.5,4.6;No regular season schedule has been generated yet.]"
                if is_admin then
                    fs = fs .. "button[0.5,5.3;5.0,0.8;btn_generate_schedule;GENERATE SCHEDULE]"
                end
            else
                local round_count = #esports_league.fixtures
                local round_options = {}
                for r = 1, round_count do
                    table.insert(round_options, "Round " .. r)
                end
                
                local sel_round = settings.sel_round or 1
                if sel_round > round_count then sel_round = round_count end
                
                fs = fs ..
                    "label[0.5,4.3;SELECT ROUND:]" ..
                    "dropdown[3.2,4.0;2.0,0.6;sel_round_dropdown;" .. table.concat(round_options, ",") .. ";" .. sel_round .. "]"
                
                local round_matches = esports_league.fixtures[sel_round] or {}
                local match_items = {}
                for idx, m in ipairs(round_matches) do
                    local status_str = m.status == "completed" and ("(W: " .. m.score.home .. "-" .. m.score.away .. ")") or "(Pending)"
                    table.insert(match_items, string.format("%d. %s vs %s %s", idx, m.home, m.away, status_str))
                end
                
                local sel_match_idx = settings.sel_match_idx or 1
                if sel_match_idx > #match_items then sel_match_idx = #match_items end
                if #match_items == 0 then
                    table.insert(match_items, "No matches this round")
                end
                
                fs = fs ..
                    "label[0.5,4.8;MATCHUPS IN SELECTED ROUND:]" ..
                    "textlist[0.5,5.3;6.0,3.8;sel_match_list;" .. table.concat(match_items, ",") .. ";" .. sel_match_idx .. ";false]"
                
                local selected_match = round_matches[sel_match_idx]
                if selected_match then
                    fs = fs ..
                        "box[7.0,5.3;6.5,3.8;#222222aa]" ..
                        "label[7.2,5.7;MATCH DETAILS]" ..
                        "label[7.2,6.3;Home: " .. selected_match.home .. "]" ..
                        "label[7.2,6.8;Away: " .. selected_match.away .. "]" ..
                        "label[7.2,7.3;Status: " .. selected_match.status:upper() .. "]"
                    
                    if selected_match.status == "completed" then
                        fs = fs .. "label[7.2,7.8;Score: " .. selected_match.score.home .. " - " .. selected_match.score.away .. "]"
                    elseif is_admin and not match_active then
                        fs = fs .. "button[7.2,7.8;6.1,0.8;start_scheduled_match;START MATCH]"
                    end
                end
            end

        elseif league_subtab == "history" then
            local history_items = {}
            for idx = #esports_league.history, 1, -1 do
                local entry = esports_league.history[idx]
                local date_str = os.date("%Y-%m-%d %H:%M", entry.time or 0)
                table.insert(history_items, string.format("[%s] %s %d - %d %s (MVP: %s)", date_str, entry.home, entry.home_score, entry.away_score, entry.away, entry.mvp or "None"))
            end
            
            if #history_items == 0 then
                fs = fs .. "label[0.5,4.6;No match history recorded yet.]"
            else
                fs = fs ..
                    "label[0.5,4.2;RECENT MATCH HISTORY:]" ..
                    "textlist[0.5,4.7;13.0,5.2;history_list;" .. table.concat(history_items, ",") .. ";;false]"
            end

        elseif league_subtab == "playoffs" then
            if esports_league.season_state ~= "playoffs" then
                fs = fs .. "label[0.5,4.6;Playoffs have not started yet.]"
                
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
                    fs = fs .. "label[0.5,5.1;All regular season matches are completed!]"
                    if is_admin then
                        fs = fs .. "button[0.5,5.7;5.0,0.8;btn_start_playoffs;START PLAYOFFS]"
                    end
                end
            else
                local p = esports_league.playoffs
                local sf1 = p.semifinals[1]
                local sf2 = p.semifinals[2]
                local fn = p.finals
                
                fs = fs ..
                    "box[0.5,4.5;13.0,4.8;#222222aa]" ..
                    "label[0.7,4.8;SEMIFINALS]" ..
                    "label[8.0,4.8;GRAND FINALS]"
                
                local sf1_winner_text = sf1.winner ~= "" and (" (Winner: " .. sf1.winner .. ")") or ""
                local sf1_score_text = sf1.status == "completed" and (" [" .. sf1.score1 .. "-" .. sf1.score2 .. "]") or ""
                fs = fs ..
                    "label[0.7,5.5;SF 1: " .. sf1.team1 .. " vs " .. sf1.team2 .. sf1_score_text .. sf1_winner_text .. "]"
                
                local sf2_winner_text = sf2.winner ~= "" and (" (Winner: " .. sf2.winner .. ")") or ""
                local sf2_score_text = sf2.status == "completed" and (" [" .. sf2.score1 .. "-" .. sf2.score2 .. "]") or ""
                fs = fs ..
                    "label[0.7,6.3;SF 2: " .. sf2.team1 .. " vs " .. sf2.team2 .. sf2_score_text .. sf2_winner_text .. "]"
                
                local fn_team1 = fn.team1 ~= "" and fn.team1 or "(TBD)"
                local fn_team2 = fn.team2 ~= "" and fn.team2 or "(TBD)"
                local fn_winner_text = fn.winner ~= "" and (" (CHAMPION: " .. fn.winner .. ")") or ""
                local fn_score_text = fn.status == "completed" and (" [" .. fn.score1 .. "-" .. fn.score2 .. "]") or ""
                fs = fs ..
                    "label[8.0,5.9;FINAL: " .. fn_team1 .. " vs " .. fn_team2 .. fn_score_text .. fn_winner_text .. "]"
                
                if is_admin and not match_active then
                    fs = fs .. "label[0.7,7.3;ADMIN CONTROL PANEL:]"
                    if sf1.status == "pending" then
                        fs = fs .. "button[0.7,7.8;4.0,0.8;start_sf1;START SEMIFINAL 1]"
                    elseif sf2.status == "pending" then
                        fs = fs .. "button[0.7,7.8;4.0,0.8;start_sf2;START SEMIFINAL 2]"
                    elseif fn.status == "pending" and fn.team1 ~= "" and fn.team2 ~= "" then
                        fs = fs .. "button[0.7,7.8;4.0,0.8;start_final;START GRAND FINAL]"
                    elseif fn.status == "completed" then
                        fs = fs .. "button[0.7,7.8;4.0,0.8;archive_season;ARCHIVE & END SEASON]"
                    end
                end
            end
        end
        
        -- Error display at the bottom of the league tab
        if settings.err_msg then
            fs = fs .. "style[err_lbl;textcolor=#ff3333;font=bold]" ..
                       "label[0.5,10.2;ERROR: " .. settings.err_msg .. "]"
        end
    elseif tab == "team" then
        local p_team_name = esports_league.get_team(name)
        
        if not p_team_name then
            -- FREE AGENT VIEW
            local all_teams = {}
            for tname, _ in pairs(esports_league.teams) do table.insert(all_teams, tname) end
            table.sort(all_teams)

            fs = fs ..
                "label[0.5,3.8;FIND A TEAM]" ..
                "textlist[0.5,4.3;6.0,4.5;find_teams;" .. table.concat(all_teams, ",") .. ";;false]" ..
                "button[0.5,9.0;6.0,0.8;request_join;REQUEST TO JOIN]" ..
                
                "box[7.0,4.3;6.5,4.5;#222222aa]" ..
                "label[7.2,4.8;PENDING INVITATIONS]"
                
            local invites = {}
            for tname, target in pairs(esports_league.invites) do
                if tname == name then table.insert(invites, target) end
            end
            
            if #invites > 0 then
                fs = fs .. "textlist[7.2,5.3;6.1,2.5;sel_invite;" .. table.concat(invites, ",") .. ";;false]" ..
                    "button[7.2,8.0;3.0,0.6;accept_invite;ACCEPT]" ..
                    "button[10.3,8.0;3.0,0.6;decline_invite;DECLINE]"
            else
                fs = fs .. "label[7.2,6;No pending invites.]"
            end
        else
            -- SQUAD VIEW (Member or Owner)
            local is_owner = esports_league.is_owner(name, p_team_name)
            local team_data = esports_league.teams[p_team_name]
            
            fs = fs ..
                "label[0.5,3.8;TEAM ROSTER: " .. p_team_name:upper() .. "]" ..
                "label[0.5,4.3;Leader: " .. (team_data.leader ~= "" and esports_core.get_nick(team_data.leader) or "None") .. "]"
                
            local roster_items = {}
            for _, mname in ipairs(team_data.members) do
                local stats = esports_league.player_stats[mname] or {kills=0, deaths=0, captures=0}
                local k = stats.kills or 0
                local d = stats.deaths or 0
                local c = stats.captures or 0
                local rating = k - d + (c * 10)
                table.insert(roster_items, string.format("%s (R:%d K:%d D:%d C:%d)", esports_core.get_nick(mname), rating, k, d, c))
            end
            
            fs = fs .. "textlist[0.5,4.8;6.0,4.0;roster_list;" .. table.concat(roster_items, ",") .. ";;false]"
            
            if is_owner then
                fs = fs .. "button[0.5,9.0;6.0,0.8;kick_player;KICK MEMBER]" ..
                    "box[7.0,4.3;6.5,4.5;#222222aa]" ..
                    "label[7.2,4.8;JOIN REQUESTS]"
                    
                local requests = esports_league.requests[p_team_name] or {}
                local req_items = {}
                for _, req_name in ipairs(requests) do
                    table.insert(req_items, esports_core.get_nick(req_name))
                end
                if #requests > 0 then
                    fs = fs .. "textlist[7.2,5.3;6.1,2.5;sel_request;" .. table.concat(req_items, ",") .. ";;false]" ..
                        "button[7.2,8.0;3.0,0.6;accept_request;APPROVE]" ..
                        "button[10.3,8.0;3.0,0.6;deny_request;DENY]"
                else
                    fs = fs .. "label[7.2,6;No pending requests.]"
                end
                
                fs = fs .. "field[7.0,9.2;4.5,0.8;invite_name;Invite Player;]" ..
                    "button[11.6,9.2;1.9,0.8;send_invite;INVITE]"
            else
                fs = fs .. "button[0.5,9.0;6.0,0.8;leave_team;LEAVE TEAM]"
            end
        end
    elseif tab == "settings" then
        local count_list = {"1","2","3","4","5","10","15","20"}
        local diff_list = {"easy","medium","hard"}
        
        local count_idx = 5
        for i, v in ipairs(count_list) do if v == settings.count then count_idx = i break end end
        
        local diff_idx = 2
        for i, v in ipairs(diff_list) do if v == settings.diff then diff_idx = i break end end

        fs = fs ..
            "label[0.5,4.0;PVE CONFIGURATION]" ..
            "label[0.5,4.7;Bot Count:]" ..
            "dropdown[0.5,5.1;3,0.8;bot_count;" .. table.concat(count_list, ",") .. ";" .. count_idx .. "]" ..
            
            "label[0.5,6.2;AI Difficulty:]" ..
            "dropdown[0.5,6.6;3,0.8;bot_diff;" .. table.concat(diff_list, ",") .. ";" .. diff_idx .. "]" ..
            
            "checkbox[0.5,7.4;chk_allow_nicks;Allow player nickname changes;" .. (esports_core.allow_nicks and "true" or "false") .. "]" ..
            
            "label[0.5,8.1;TIPS]" ..
            "label[0.5,8.6;- Bots spawn with 0 ammo.]" ..
            "label[0.5,9.0;- They hunt crates to reload.]" ..
            "label[0.5,9.4;- Hard bots move faster/hit harder.]"

        -- Nicknames mappings display for admins
        local mapping_items = {}
        local keys = {}
        for username, nickname in pairs(esports_core.nicknames) do
            table.insert(keys, username)
        end
        table.sort(keys)
        
        for _, u in ipairs(keys) do
            table.insert(mapping_items, u .. " -> " .. esports_core.nicknames[u])
        end
        
        local sel_nick_idx = settings.sel_nick_idx or 1
        if sel_nick_idx > #mapping_items then sel_nick_idx = #mapping_items end
        if #mapping_items == 0 then
            table.insert(mapping_items, "No nicknames registered")
        end
        
        fs = fs ..
            "label[5.5,4.0;NICKNAME MAPPINGS]" ..
            "textlist[5.5,4.5;8.0,4.5;admin_nicks_list;" .. table.concat(mapping_items, ",") .. ";" .. sel_nick_idx .. ";false]"
            
        if #keys > 0 then
            fs = fs .. "button[5.5,9.2;8.0,0.8;btn_reset_nick;RESET SELECTED NICKNAME]"
        end
    elseif tab == "locker" then
        local meta = core.get_player_by_name(name):get_meta()
        local current = meta:get_string("esports_selected_skin")
        if current == "" then current = "character.png" end
        
        local match_side = esports_core.match.get_player_match_side(name)
        local is_spectator = esports_core.is_spectator(name)

        fs = fs .. "label[1,4;CHARACTER LOCKER]"
        
        if match_side or is_spectator then
            fs = fs .. 
                "style_type[label;textcolor=#FF4444]" ..
                "label[1,5.5;OUTFIT MODIFICATION DISABLED DURING ACTIVE SESSION]" ..
                "style_type[label;textcolor=white]" ..
                "label[1,6.0;Finish your match or stop spectating to customize your character.]"
        else
            fs = fs .. "label[1,3.5;Select your base field outfit:]"
            
            local skins = {
                {id = "sam", name = "Tactical Sam", file = "character.png", portrait = "esports_portrait_sam.png", x = 1.0},
                {id = "elite", name = "Elite Soldier", file = "skin_1.png", portrait = "esports_portrait_elite.png", x = 4.2},
                {id = "recon", name = "Ghost Recon", file = "skin_2.png", portrait = "esports_portrait_recon.png", x = 7.4},
                {id = "infil", name = "Infiltrator", file = "skin_3.png", portrait = "esports_portrait_infil.png", x = 10.6},
            }
 
            for _, s in ipairs(skins) do
                -- High-Fidelity Operative Portrait
                fs = fs .. "image[" .. s.x .. ",4.5;2.4,4.2;" .. s.portrait .. "]"
                
                if current == s.file then
                    fs = fs .. "style[set_skin_" .. s.id .. ";bgcolor=#00FF00;textcolor=black]"
                    fs = fs .. "button[" .. s.x .. ",8.8;2.4,0.6;set_skin_" .. s.id .. ";ACTIVE]"
                else
                    fs = fs .. "button[" .. s.x .. ",8.8;2.4,0.6;set_skin_" .. s.id .. ";SELECT]"
                end
                fs = fs .. "label[" .. s.x .. ",4.2;" .. s.name .. "]"
            end
 
            fs = fs .. 
                "label[1,9.4;Team colors will overlay these choices during a match.]"
        end

        -- Nickname Editor at the very bottom
        local is_admin = core.check_player_privs(name, {server = true})
        if esports_core.allow_nicks or is_admin then
            fs = fs ..
                "field[1.0,10.0;5.0,0.8;txt_nickname;Lobby Nickname;" .. esports_core.get_nick(name) .. "]" ..
                "button[6.2,10.0;3.0,0.8;btn_set_nickname;UPDATE NICKNAME]" ..
                "button[9.4,10.0;2.0,0.8;btn_clear_nickname;RESET]"
        else
            fs = fs .. "label[1.0,10.0;Nickname changes are currently disabled by an administrator. (Current: " .. esports_core.get_nick(name) .. ")]"
        end
    end
    
    return fs
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
    
    -- Lobby Lock for non-participants (Mandatory Main Menu)
    if fields.quit then
        local side = esports_core.match.get_player_match_side(name)
        
        if not side and not esports_core.is_spectator(name) and (not is_admin or not fields.exit_lobby) then
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
        player_settings[name] = { count = "5", diff = "medium" }
    end
    if not fields.quit then
        player_settings[name].err_msg = nil
    end

    -- Disconnect Logic
    if fields.exit_server then
        core.kick_player(name, "Logged out via Main Lobby")
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
            local map_size = "Large"
            
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
                core.close_formspec(name, "esports_core:lobby")
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
                core.close_formspec(name, "esports_core:lobby")
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
                core.close_formspec(name, "esports_core:lobby")
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
                core.close_formspec(name, "esports_core:lobby")
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
                local wa = esports_league.teams[a].wins or 0
                local wb = esports_league.teams[b].wins or 0
                return wa > wb
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
        local cmd = core.registered_chatcommands["team"]
        if cmd then
            local ok, msg = cmd.func(name, "create " .. fields.new_team)
            if msg then core.chat_send_player(name, msg) end
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

            local map_size = player_settings[name].map_size or "Large"

            esports_core.match.scheduled_context = nil
            local ok, err = esports_core.match.start(p_team, "BOTS", dur, true, tod, count, diff, mode, map_size)
            if not ok then
                player_settings[name].err_msg = err or "Could not start match."
                esports_core.lobby.show(player)
            else
                core.close_formspec(name, "esports_core:lobby")
            end
            return
        else
            core.chat_send_player(name, "Please select a valid team for PVE practice!")
        end
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

                local map_size = player_settings[name].map_size or "Large"
                esports_core.match.scheduled_context = nil
                local ok, err = esports_core.match.start(red, blue, dur, false, tod, 0, nil, mode, map_size)
                if not ok then
                    player_settings[name].err_msg = err or "Could not start match."
                    esports_core.lobby.show(player)
                else
                    core.close_formspec(name, "esports_core:lobby")
                end
                return
            end
        else
            core.chat_send_player(name, "Please select two valid teams for a competitive match!")
        end
    end
    
    if fields.stop_match and is_admin then
        esports_core.match.state = "over"
        esports_core.match.timer = 1
        -- Clear state immediately to prevent stale data on instant restarts
        esports_core.match.player_sides = {}
        esports_core.teams.players = {}
        esports_core.match.player_stats = {}
        
        if esports_core.bots then esports_core.bots.clear_all() end
        core.chat_send_all("ADMIN: Match has been stopped by " .. name)
        esports_core.lobby.show(player)
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
            if tp then tp:set_properties({ nametag = target }) end
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
        player:set_properties({ nametag = new_nick })
        player_settings[name].err_msg = nil
        esports_core.lobby.show(player)
        return
    end

    if fields.btn_clear_nickname then
        esports_core.nicknames[name] = nil
        esports_core.save_nicknames()
        player:set_properties({ nametag = name })
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
        
        -- If NOT in a match side, NOT an admin, and NOT already a spectator
        if not side and not is_admin and not esports_core.is_spectator(name) then
            -- Force physics freeze with gravity
            player:set_physics_override({speed = 0, jump = 0, gravity = 1})
            -- Force lobby re-open
            esports_core.lobby.show(player)
        else
            -- Restore normal settings
            player:override_day_night_ratio(nil)
            
            -- Close lobby formspec and hide blackout for participants/spectators (except admins!)
            if (side or esports_core.is_spectator(name)) and not is_admin then
                esports_core.lobby.blackout_hide(player)
                core.close_formspec(name, "esports_core:lobby")
            end
        end
        
        -- DYNAMIC PRIVILEGE REFRESH: Ensure all active players can interact
        if not esports_core.is_spectator(name) then
            local privs = core.get_player_privs(name)
            if not privs.interact or not privs.shout then
                privs.interact = true
                privs.shout = true
                core.set_player_privs(name, privs)
                core.chat_send_player(name, "SYSTEM: Privileges synchronized.")
            end
        end
    end
end)

-- Command to open lobby
core.register_chatcommand("lobby", {
    description = "Open the League Lobby Menu",
    func = function(name)
        local player = core.get_player_by_name(name)
        if player then
            esports_core.lobby.show(player)
        end
    end
})

-- LIVE DYNAMIC REFRESH: Automatically update admin lobby when player counts change
function esports_core.lobby.refresh_admins()
    for _, player in ipairs(core.get_connected_players()) do
        if core.check_player_privs(player:get_player_name(), {server = true}) then
            esports_core.lobby.show(player)
        end
    end
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


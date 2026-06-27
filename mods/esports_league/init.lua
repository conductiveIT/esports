esports_league = {}
local storage = core.get_mod_storage()

-- Load persistent data
local teams_data = storage:get_string("teams")
esports_league.teams = teams_data ~= "" and core.deserialize(teams_data) or {}

local players_data = storage:get_string("players")
esports_league.player_to_team = players_data ~= "" and core.deserialize(players_data) or {}

local stats_data = storage:get_string("stats")
esports_league.player_stats = stats_data ~= "" and core.deserialize(stats_data) or {}

-- Persistent invites and requests
local invites_data = storage:get_string("invites")
esports_league.invites = invites_data ~= "" and core.deserialize(invites_data) or {}

local requests_data = storage:get_string("requests")
esports_league.requests = requests_data ~= "" and core.deserialize(requests_data) or {} -- team -> list of players

-- Persistent League Management Data
local fixtures_data = storage:get_string("fixtures")
esports_league.fixtures = fixtures_data ~= "" and core.deserialize(fixtures_data) or {}

local history_data = storage:get_string("history")
esports_league.history = history_data ~= "" and core.deserialize(history_data) or {}

local playoffs_data = storage:get_string("playoffs")
esports_league.playoffs = playoffs_data ~= "" and core.deserialize(playoffs_data) or {}

local state_data = storage:get_string("season_state")
esports_league.season_state = state_data ~= "" and state_data or "offseason"

local archive_data = storage:get_string("season_archive")
esports_league.season_archive = archive_data ~= "" and core.deserialize(archive_data) or {}

function esports_league.save()
    storage:set_string("teams", core.serialize(esports_league.teams))
    storage:set_string("players", core.serialize(esports_league.player_to_team))
    storage:set_string("stats", core.serialize(esports_league.player_stats))
    storage:set_string("invites", core.serialize(esports_league.invites))
    storage:set_string("requests", core.serialize(esports_league.requests))
    storage:set_string("fixtures", core.serialize(esports_league.fixtures))
    storage:set_string("history", core.serialize(esports_league.history))
    storage:set_string("playoffs", core.serialize(esports_league.playoffs))
    storage:set_string("season_state", esports_league.season_state)
    storage:set_string("season_archive", core.serialize(esports_league.season_archive))
end

-- PUBLIC API
function esports_league.get_team(player_name)
    return esports_league.player_to_team[player_name]
end

function esports_league.is_owner(player_name, team_name)
    local team = esports_league.teams[team_name]
    return team and team.leader == player_name
end

-- LEAGUE MANAGEMENT CORE API
function esports_league.generate_fixtures()
    local team_names = {}
    for tname in pairs(esports_league.teams) do
        table.insert(team_names, tname)
    end
    
    table.sort(team_names)
    local num_teams = #team_names
    if num_teams < 2 then return false, "Need at least 2 teams to generate fixtures." end
    
    if num_teams % 2 ~= 0 then
        table.insert(team_names, "BYE")
        num_teams = num_teams + 1
    end
    
    local rounds = num_teams - 1
    local matches_per_round = num_teams / 2
    
    esports_league.fixtures = {}
    
    for r = 1, rounds do
        esports_league.fixtures[r] = {}
        for m = 1, matches_per_round do
            local home = team_names[m]
            local away = team_names[num_teams - m + 1]
            if home ~= "BYE" and away ~= "BYE" then
                table.insert(esports_league.fixtures[r], {
                    home = home,
                    away = away,
                    status = "pending",
                    score = {home = 0, away = 0}
                })
            end
        end
        -- Rotate teams (Circle Method, keeping element 1 fixed)
        local last = team_names[num_teams]
        for i = num_teams, 3, -1 do
            team_names[i] = team_names[i - 1]
        end
        team_names[2] = last
    end
    
    esports_league.season_state = "regular_season"
    esports_league.playoffs = {}
    esports_league.save()
    return true, "Season fixtures generated."
end

function esports_league.start_playoffs()
    if esports_league.season_state ~= "regular_season" then
        return false, "Playoffs can only start from regular season."
    end
    
    -- Get sorted standings
    local sorted = {}
    for tname, data in pairs(esports_league.teams) do
        local wins = data.wins or 0
        local losses = data.losses or 0
        local kills = data.kills_scored or 0
        local deaths = data.deaths_conceded or 0
        local diff = kills - deaths
        table.insert(sorted, {name = tname, wins = wins, diff = diff, kills = kills})
    end
    
    table.sort(sorted, function(a, b)
        if a.wins ~= b.wins then return a.wins > b.wins end
        if a.diff ~= b.diff then return a.diff > b.diff end
        return a.kills > b.kills
    end)
    
    if #sorted < 4 then
        return false, "Need at least 4 registered teams to start playoffs."
    end
    
    local t1 = sorted[1].name
    local t2 = sorted[2].name
    local t3 = sorted[3].name
    local t4 = sorted[4].name
    
    esports_league.playoffs = {
        semifinals = {
            { team1 = t1, team2 = t4, status = "pending", winner = "", score1 = 0, score2 = 0 },
            { team1 = t2, team2 = t3, status = "pending", winner = "", score1 = 0, score2 = 0 }
        },
        finals = { team1 = "", team2 = "", status = "pending", winner = "", score1 = 0, score2 = 0 }
    }
    
    esports_league.season_state = "playoffs"
    esports_league.save()
    return true, "Playoffs started. Semifinals: " .. t1 .. " vs " .. t4 .. ", and " .. t2 .. " vs " .. t3 .. "."
end

function esports_league.archive_season()
    local sorted = {}
    for tname, data in pairs(esports_league.teams) do
        table.insert(sorted, {
            name = tname,
            wins = data.wins or 0,
            losses = data.losses or 0,
            kills = data.kills_scored or 0,
            deaths = data.deaths_conceded or 0
        })
    end
    
    table.sort(sorted, function(a, b)
        if a.wins ~= b.wins then return a.wins > b.wins end
        return (a.kills - a.deaths) > (b.kills - b.deaths)
    end)
    
    local champion = "None"
    if esports_league.season_state == "playoffs" and esports_league.playoffs.finals and esports_league.playoffs.finals.winner ~= "" then
        champion = esports_league.playoffs.finals.winner
    elseif #sorted > 0 then
        champion = sorted[1].name
    end
    
    local archive_entry = {
        season_num = #esports_league.season_archive + 1,
        timestamp = os.time(),
        champion = champion,
        standings = sorted
    }
    table.insert(esports_league.season_archive, archive_entry)
    
    -- Reset team stats
    for tname, data in pairs(esports_league.teams) do
        data.wins = 0
        data.losses = 0
        data.kills_scored = 0
        data.deaths_conceded = 0
    end
    
    esports_league.fixtures = {}
    esports_league.playoffs = {}
    esports_league.season_state = "offseason"
    esports_league.save()
    
    return true, "Season archived. Champion: " .. champion
end

-- MANAGEMENT API
function esports_league.add_request(player_name, team_name)
    local team = esports_league.teams[team_name]
    if not team then return false, "Team does not exist." end
    if esports_league.player_to_team[player_name] then return false, "You are already in a team." end
    
    -- AUTO-PROMOTION: If the team is empty, the player becomes leader immediately
    if #team.members == 0 then
        table.insert(team.members, player_name)
        team.leader = player_name
        esports_league.player_to_team[player_name] = team_name
        esports_league.save()
        core.chat_send_all("LOBBY: " .. player_name .. " has revived team '" .. team_name .. "' and is now the leader!")
        return true, "Team '" .. team_name .. "' was empty! You have been auto-approved and promoted to LEADER."
    end

    esports_league.requests[team_name] = esports_league.requests[team_name] or {}
    for _, name in ipairs(esports_league.requests[team_name]) do
        if name == player_name then return false, "Request already pending." end
    end
    
    table.insert(esports_league.requests[team_name], player_name)
    esports_league.save()
    return true, "Request sent to " .. team_name
end

function esports_league.remove_request(player_name, team_name)
    local list = esports_league.requests[team_name]
    if not list then return end
    for i, name in ipairs(list) do
        if name == player_name then
            table.remove(list, i)
            esports_league.save()
            return true
        end
    end
end

function esports_league.kick_member(owner_name, target_name)
    local team_name = esports_league.player_to_team[owner_name]
    if not team_name or not esports_league.is_owner(owner_name, team_name) then
        return false, "Only the team owner can kick members."
    end
    if owner_name == target_name then return false, "You cannot kick yourself! Use 'Leave Team'." end
    
    local team = esports_league.teams[team_name]
    for i, mname in ipairs(team.members) do
        if mname == target_name then
            table.remove(team.members, i)
            esports_league.player_to_team[target_name] = nil
            esports_league.save()
            core.chat_send_player(target_name, "LOBBY: You have been removed from team '" .. team_name .. "'.")
            return true, "Player " .. target_name .. " kicked."
        end
    end
    return false, "Player not found in your team."
end

function esports_league.set_owner(admin_name, team_name, new_owner_name)
    if not core.check_player_privs(admin_name, {server = true}) then return false, "Admin only." end
    if not esports_league.teams[team_name] then return false, "Team does not exist." end
    
    -- Ensure new owner is in the team
    local is_member = false
    for _, mname in ipairs(esports_league.teams[team_name].members) do
        if mname == new_owner_name then is_member = true break end
    end
    if not is_member then return false, "The new owner must be a member of the team." end
    
    esports_league.teams[team_name].leader = new_owner_name
    esports_league.save()
    core.chat_send_all("LOBBY: " .. new_owner_name .. " is now the leader of team '" .. team_name .. "'.")
    return true, "Ownership transferred to " .. new_owner_name
end

function esports_league.get_team_members(team_name)
    if not esports_league.teams[team_name] then return {} end
    return esports_league.teams[team_name].members
end

-- COMMANDS
core.register_chatcommand("team", {
    params = "create <name> | invite <player> | join | leave | list",
    description = "Manage your TDM League team",
    func = function(name, param)
        local cmd, arg = param:match("^(%w+)%s*(.*)$")
        if not cmd then return false, "Usage: /team create|invite|join|leave|list" end
        
        if cmd == "create" then
            local is_admin = core.check_player_privs(name, {server = true})
            if esports_league.player_to_team[name] and not is_admin then
                return false, "You are already in a team!"
            end
            if arg == "" then return false, "Please specify a team name." end
            if esports_league.teams[arg] then return false, "Team name already taken." end
            
            if is_admin then
                -- Admin creates a team: empty leader, empty members, admin does not join
                esports_league.teams[arg] = {
                    leader = "",
                    members = {},
                    wins = 0,
                    losses = 0
                }
                esports_league.save()
                return true, "Team '" .. arg .. "' created by Administrator."
            else
                esports_league.teams[arg] = {
                    leader = name,
                    members = {name},
                    wins = 0,
                    losses = 0
                }
                esports_league.player_to_team[name] = arg
                esports_league.save()
                return true, "Team '" .. arg .. "' created! You are the leader."
            end
            
        elseif cmd == "invite" then
            local team_name = esports_league.player_to_team[name]
            if not team_name or esports_league.teams[team_name].leader ~= name then
                return false, "Only the team leader can invite players."
            end
            if arg == "" then return false, "Specify player to invite." end
            if not core.get_player_by_name(arg) then return false, "Player not online." end
            
            esports_league.invites[arg] = team_name
            core.chat_send_player(arg, "You have been invited to join team '" .. team_name .. "'. Type '/team join' to accept.")
            return true, "Invitation sent to " .. arg
            
        elseif cmd == "join" then
            local team_name = esports_league.invites[name]
            if not team_name then return false, "You have no pending invitations." end
            if esports_league.player_to_team[name] then return false, "Leave your current team first." end
            
            table.insert(esports_league.teams[team_name].members, name)
            esports_league.player_to_team[name] = team_name
            esports_league.invites[name] = nil
            esports_league.save()
            return true, "You have joined '" .. team_name .. "'!"
            
        elseif cmd == "leave" then
            local team_name = esports_league.player_to_team[name]
            if not team_name then return false, "You are not in a team." end
            local team = esports_league.teams[team_name]
            
            -- Remove from member list
            for i, member in ipairs(team.members) do
                if member == name then
                    table.remove(team.members, i)
                    break
                end
            end
            esports_league.player_to_team[name] = nil
            
            if team.leader == name then
                if #team.members > 0 then
                    -- Successon: Automatically promote the next member
                    local new_leader = team.members[1]
                    team.leader = new_leader
                    core.chat_send_all("LOBBY: " .. new_leader .. " has been promoted to leader of '" .. team_name .. "' following a departure.")
                else
                    -- Persistence: Last player leaves, but team survives
                    team.leader = ""
                    core.chat_send_all("LOBBY: Team '" .. team_name .. "' is now inactive (0 members).")
                end
            end
            
            esports_league.save()
            return true, "You have left the team."
            
        elseif cmd == "logo" then
            local team_name = esports_league.player_to_team[name]
            if not team_name or esports_league.teams[team_name].leader ~= name then
                return false, "Only the team leader can set the logo."
            end
            
            local valid_logos = {eagle=true, lion=true, dragon=true, skull=true}
            if not valid_logos[arg] then
                return false, "Invalid logo ID. Use: eagle, lion, dragon, or skull."
            end
            
            esports_league.teams[team_name].logo_id = arg
            esports_league.save()
            return true, "Team logo updated to: " .. arg
            
        elseif cmd == "list" then
            local list = "Active Teams:\n"
            for tname, data in pairs(esports_league.teams) do
                list = list .. "- " .. tname .. " (Leader: " .. data.leader .. ", Points: " .. data.wins .. ")\n"
            end
            return true, list
        end
    end
})

core.register_chatcommand("leaguedelete", {
    params = "<team_name>",
    description = "Completely remove a team from the league (Admin only)",
    privs = {server = true},
    func = function(name, param)
        if param == "" then return false, "Usage: /leaguedelete <team_name>" end
        local team = esports_league.teams[param]
        if not team then return false, "Team '" .. param .. "' not found." end
        
        -- Clear all members
        for _, member in ipairs(team.members) do
            esports_league.player_to_team[member] = nil
        end
        
        -- Delete team
        esports_league.teams[param] = nil
        esports_league.save()
        
        core.log("action", "[TDM League] Admin " .. name .. " deleted team: " .. param)
        return true, "Team '" .. param .. "' has been removed from the league."
    end
})

core.register_chatcommand("leaguesetleader", {
    params = "<team_name> <player_name>",
    description = "Assign a player as the leader/owner of a team (Admin only)",
    privs = {server = true},
    func = function(name, param)
        local team_name, player_name = param:match("^(%S+)%s+(%S+)$")
        if not team_name or not player_name then
            return false, "Usage: /leaguesetleader <team_name> <player_name>"
        end
        
        local team = esports_league.teams[team_name]
        if not team then return false, "Team '" .. team_name .. "' not found." end
        
        -- Remove player from old team if any
        local old_team_name = esports_league.player_to_team[player_name]
        if old_team_name then
            local old_team = esports_league.teams[old_team_name]
            if old_team then
                for i, member in ipairs(old_team.members) do
                    if member == player_name then
                        table.remove(old_team.members, i)
                        break
                    end
                end
            end
        end
        
        -- Set as new leader
        team.leader = player_name
        esports_league.player_to_team[player_name] = team_name
        
        -- Add to members if not there
        local found = false
        for _, m in ipairs(team.members) do
            if m == player_name then found = true break end
        end
        if not found then table.insert(team.members, player_name) end
        
        esports_league.save()
        core.chat_send_player(player_name, "Admin " .. name .. " has assigned you as the LEADER of team '" .. team_name .. "'.")
        return true, "Leadership of '" .. team_name .. "' transferred to " .. player_name
    end
})


core.register_chatcommand("league", {
    params = "[generate_schedule | start_playoffs | archive_season | reset_all]",
    description = "League Management and Standings System",
    func = function(name, param)
        local is_admin = core.check_player_privs(name, {server = true})
        local cmd = param:match("^(%S+)")
        
        if cmd and cmd ~= "" then
            if not is_admin then return false, "Admin privileges required." end
            
            if cmd == "generate_schedule" then
                local ok, msg = esports_league.generate_fixtures()
                return ok, msg
            elseif cmd == "start_playoffs" then
                local ok, msg = esports_league.start_playoffs()
                return ok, msg
            elseif cmd == "archive_season" then
                local ok, msg = esports_league.archive_season()
                return ok, msg
            elseif cmd == "reset_all" then
                esports_league.fixtures = {}
                esports_league.history = {}
                esports_league.playoffs = {}
                esports_league.season_state = "offseason"
                esports_league.season_archive = {}
                for tname, data in pairs(esports_league.teams) do
                    data.wins = 0
                    data.losses = 0
                    data.kills_scored = 0
                    data.deaths_conceded = 0
                end
                esports_league.save()
                return true, "League state reset to offseason. All stats cleared."
            else
                return false, "Unknown league sub-command. Try /league generate_schedule | start_playoffs | archive_season | reset_all"
            end
        end
        
        -- Default view (standings)
        local sorted = {}
        for tname, data in pairs(esports_league.teams) do
            local wins = data.wins or 0
            local losses = data.losses or 0
            local kills = data.kills_scored or 0
            local deaths = data.deaths_conceded or 0
            local diff = kills - deaths
            table.insert(sorted, {name = tname, wins = wins, losses = losses, diff = diff})
        end
        table.sort(sorted, function(a, b)
            if a.wins ~= b.wins then return a.wins > b.wins end
            return a.diff > b.diff
        end)
        
        local out = "=== LEAGUE STANDINGS ===\n"
        out = out .. string.format("%-15s | %-3s | %-3s | %-5s\n", "Team", "W", "L", "Diff")
        out = out .. "-----------------------------------\n"
        for _, t in ipairs(sorted) do
            out = out .. string.format("%-15s | %-3d | %-3d | %-+5d\n", t.name, t.wins, t.losses, t.diff)
        end
        return true, out
    end
})

core.register_chatcommand("leaderboard", {
    description = "Show the Global Player Leaderboard (Rating = Kills - Deaths + Captures * 10)",
    func = function(name, param)
        local sorted = {}
        for pname, stats in pairs(esports_league.player_stats) do
            local kills = stats.kills or 0
            local deaths = stats.deaths or 0
            local captures = stats.captures or 0
            local rating = kills - deaths + (captures * 10)
            table.insert(sorted, {
                name = pname,
                kills = kills,
                deaths = deaths,
                captures = captures,
                rating = rating
            })
        end
        
        table.sort(sorted, function(a, b)
            if a.rating ~= b.rating then return a.rating > b.rating end
            if a.kills ~= b.kills then return a.kills > b.kills end
            return a.deaths < b.deaths
        end)
        
        local out = "=== GLOBAL PLAYER LEADERBOARD ===\n"
        out = out .. string.format("%-15s | %-6s | %-5s | %-5s | %-5s\n", "Player", "Rating", "Kills", "Deaths", "Caps")
        out = out .. "----------------------------------------------\n"
        for i, p in ipairs(sorted) do
            if i > 10 then break end -- Top 10
            out = out .. string.format("%-15s | %-6d | %-5d | %-5d | %-5d\n", p.name:sub(1,15), p.rating, p.kills, p.deaths, p.captures)
        end
        return true, out
    end
})

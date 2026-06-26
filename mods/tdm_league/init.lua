tdm_league = {}
local storage = core.get_mod_storage()

-- Load persistent data
local teams_data = storage:get_string("teams")
tdm_league.teams = teams_data ~= "" and core.deserialize(teams_data) or {}

local players_data = storage:get_string("players")
tdm_league.player_to_team = players_data ~= "" and core.deserialize(players_data) or {}

local stats_data = storage:get_string("stats")
tdm_league.player_stats = stats_data ~= "" and core.deserialize(stats_data) or {}

-- Persistent invites and requests
local invites_data = storage:get_string("invites")
tdm_league.invites = invites_data ~= "" and core.deserialize(invites_data) or {}

local requests_data = storage:get_string("requests")
tdm_league.requests = requests_data ~= "" and core.deserialize(requests_data) or {} -- team -> list of players

function tdm_league.save()
    storage:set_string("teams", core.serialize(tdm_league.teams))
    storage:set_string("players", core.serialize(tdm_league.player_to_team))
    storage:set_string("stats", core.serialize(tdm_league.player_stats))
    storage:set_string("invites", core.serialize(tdm_league.invites))
    storage:set_string("requests", core.serialize(tdm_league.requests))
end

-- PUBLIC API
function tdm_league.get_team(player_name)
    return tdm_league.player_to_team[player_name]
end

function tdm_league.is_owner(player_name, team_name)
    local team = tdm_league.teams[team_name]
    return team and team.leader == player_name
end

-- MANAGEMENT API
function tdm_league.add_request(player_name, team_name)
    local team = tdm_league.teams[team_name]
    if not team then return false, "Team does not exist." end
    if tdm_league.player_to_team[player_name] then return false, "You are already in a team." end
    
    -- AUTO-PROMOTION: If the team is empty, the player becomes leader immediately
    if #team.members == 0 then
        table.insert(team.members, player_name)
        team.leader = player_name
        tdm_league.player_to_team[player_name] = team_name
        tdm_league.save()
        core.chat_send_all("LOBBY: " .. player_name .. " has revived team '" .. team_name .. "' and is now the leader!")
        return true, "Team '" .. team_name .. "' was empty! You have been auto-approved and promoted to LEADER."
    end

    tdm_league.requests[team_name] = tdm_league.requests[team_name] or {}
    for _, name in ipairs(tdm_league.requests[team_name]) do
        if name == player_name then return false, "Request already pending." end
    end
    
    table.insert(tdm_league.requests[team_name], player_name)
    tdm_league.save()
    return true, "Request sent to " .. team_name
end

function tdm_league.remove_request(player_name, team_name)
    local list = tdm_league.requests[team_name]
    if not list then return end
    for i, name in ipairs(list) do
        if name == player_name then
            table.remove(list, i)
            tdm_league.save()
            return true
        end
    end
end

function tdm_league.kick_member(owner_name, target_name)
    local team_name = tdm_league.player_to_team[owner_name]
    if not team_name or not tdm_league.is_owner(owner_name, team_name) then
        return false, "Only the team owner can kick members."
    end
    if owner_name == target_name then return false, "You cannot kick yourself! Use 'Leave Team'." end
    
    local team = tdm_league.teams[team_name]
    for i, mname in ipairs(team.members) do
        if mname == target_name then
            table.remove(team.members, i)
            tdm_league.player_to_team[target_name] = nil
            tdm_league.save()
            core.chat_send_player(target_name, "LOBBY: You have been removed from team '" .. team_name .. "'.")
            return true, "Player " .. target_name .. " kicked."
        end
    end
    return false, "Player not found in your team."
end

function tdm_league.set_owner(admin_name, team_name, new_owner_name)
    if not core.check_player_privs(admin_name, {server = true}) then return false, "Admin only." end
    if not tdm_league.teams[team_name] then return false, "Team does not exist." end
    
    -- Ensure new owner is in the team
    local is_member = false
    for _, mname in ipairs(tdm_league.teams[team_name].members) do
        if mname == new_owner_name then is_member = true break end
    end
    if not is_member then return false, "The new owner must be a member of the team." end
    
    tdm_league.teams[team_name].leader = new_owner_name
    tdm_league.save()
    core.chat_send_all("LOBBY: " .. new_owner_name .. " is now the leader of team '" .. team_name .. "'.")
    return true, "Ownership transferred to " .. new_owner_name
end

function tdm_league.get_team_members(team_name)
    if not tdm_league.teams[team_name] then return {} end
    return tdm_league.teams[team_name].members
end

-- COMMANDS
core.register_chatcommand("team", {
    params = "create <name> | invite <player> | join | leave | list",
    description = "Manage your TDM League team",
    func = function(name, param)
        local cmd, arg = param:match("^(%w+)%s*(.*)$")
        if not cmd then return false, "Usage: /team create|invite|join|leave|list" end
        
        if cmd == "create" then
            if tdm_league.player_to_team[name] then
                return false, "You are already in a team!"
            end
            if arg == "" then return false, "Please specify a team name." end
            if tdm_league.teams[arg] then return false, "Team name already taken." end
            
            tdm_league.teams[arg] = {
                leader = name,
                members = {name},
                wins = 0,
                losses = 0
            }
            tdm_league.player_to_team[name] = arg
            tdm_league.save()
            return true, "Team '" .. arg .. "' created! You are the leader."
            
        elseif cmd == "invite" then
            local team_name = tdm_league.player_to_team[name]
            if not team_name or tdm_league.teams[team_name].leader ~= name then
                return false, "Only the team leader can invite players."
            end
            if arg == "" then return false, "Specify player to invite." end
            if not core.get_player_by_name(arg) then return false, "Player not online." end
            
            tdm_league.invites[arg] = team_name
            core.chat_send_player(arg, "You have been invited to join team '" .. team_name .. "'. Type '/team join' to accept.")
            return true, "Invitation sent to " .. arg
            
        elseif cmd == "join" then
            local team_name = tdm_league.invites[name]
            if not team_name then return false, "You have no pending invitations." end
            if tdm_league.player_to_team[name] then return false, "Leave your current team first." end
            
            table.insert(tdm_league.teams[team_name].members, name)
            tdm_league.player_to_team[name] = team_name
            tdm_league.invites[name] = nil
            tdm_league.save()
            return true, "You have joined '" .. team_name .. "'!"
            
        elseif cmd == "leave" then
            local team_name = tdm_league.player_to_team[name]
            if not team_name then return false, "You are not in a team." end
            local team = tdm_league.teams[team_name]
            
            -- Remove from member list
            for i, member in ipairs(team.members) do
                if member == name then
                    table.remove(team.members, i)
                    break
                end
            end
            tdm_league.player_to_team[name] = nil
            
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
            
            tdm_league.save()
            return true, "You have left the team."
            
        elseif cmd == "logo" then
            local team_name = tdm_league.player_to_team[name]
            if not team_name or tdm_league.teams[team_name].leader ~= name then
                return false, "Only the team leader can set the logo."
            end
            
            local valid_logos = {eagle=true, lion=true, dragon=true, skull=true}
            if not valid_logos[arg] then
                return false, "Invalid logo ID. Use: eagle, lion, dragon, or skull."
            end
            
            tdm_league.teams[team_name].logo_id = arg
            tdm_league.save()
            return true, "Team logo updated to: " .. arg
            
        elseif cmd == "list" then
            local list = "Active Teams:\n"
            for tname, data in pairs(tdm_league.teams) do
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
        local team = tdm_league.teams[param]
        if not team then return false, "Team '" .. param .. "' not found." end
        
        -- Clear all members
        for _, member in ipairs(team.members) do
            tdm_league.player_to_team[member] = nil
        end
        
        -- Delete team
        tdm_league.teams[param] = nil
        tdm_league.save()
        
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
        
        local team = tdm_league.teams[team_name]
        if not team then return false, "Team '" .. team_name .. "' not found." end
        
        -- Remove player from old team if any
        local old_team_name = tdm_league.player_to_team[player_name]
        if old_team_name then
            local old_team = tdm_league.teams[old_team_name]
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
        tdm_league.player_to_team[player_name] = team_name
        
        -- Add to members if not there
        local found = false
        for _, m in ipairs(team.members) do
            if m == player_name then found = true break end
        end
        if not found then table.insert(team.members, player_name) end
        
        tdm_league.save()
        core.chat_send_player(player_name, "Admin " .. name .. " has assigned you as the LEADER of team '" .. team_name .. "'.")
        return true, "Leadership of '" .. team_name .. "' transferred to " .. player_name
    end
})


core.register_chatcommand("league", {
    description = "Show the League Leaderboard",
    func = function(name, param)
        local sorted = {}
        for tname, data in pairs(tdm_league.teams) do
            table.insert(sorted, {name = tname, wins = data.wins, losses = data.losses})
        end
        table.sort(sorted, function(a, b) return a.wins > b.wins end)
        
        local out = "=== LEAGUE STANDINGS ===\n"
        out = out .. string.format("%-15s | %-5s | %-5s\n", "Team", "W", "L")
        out = out .. "---------------------------\n"
        for _, t in ipairs(sorted) do
            out = out .. string.format("%-15s | %-5d | %-5d\n", t.name, t.wins, t.losses)
        end
        return true, out
    end
})

core.register_chatcommand("leaderboard", {
    description = "Show the Global Player Leaderboard (Rating = Kills - Deaths + Captures * 10)",
    func = function(name, param)
        local sorted = {}
        for pname, stats in pairs(tdm_league.player_stats) do
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

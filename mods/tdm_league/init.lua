tdm_league = {}
local storage = core.get_mod_storage()

-- Load persistent data
local teams_data = storage:get_string("teams")
tdm_league.teams = teams_data ~= "" and core.deserialize(teams_data) or {}

local players_data = storage:get_string("players")
tdm_league.player_to_team = players_data ~= "" and core.deserialize(players_data) or {}

tdm_league.invites = {} -- player -> team_name (non-persistent)

function tdm_league.save()
    storage:set_string("teams", core.serialize(tdm_league.teams))
    storage:set_string("players", core.serialize(tdm_league.player_to_team))
end

-- PUBLIC API
function tdm_league.get_team(player_name)
    return tdm_league.player_to_team[player_name]
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
            if team.leader == name then
                -- Disband team if leader leaves
                for _, member in ipairs(team.members) do
                    tdm_league.player_to_team[member] = nil
                end
                tdm_league.teams[team_name] = nil
                tdm_league.save()
                return true, "Team '" .. team_name .. "' disbanded."
            else
                -- Just remove the member
                for i, member in ipairs(team.members) do
                    if member == name then
                        table.remove(team.members, i)
                        break
                    end
                end
                tdm_league.player_to_team[name] = nil
                tdm_league.save()
                return true, "You left the team."
            end
            
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

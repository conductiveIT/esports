tdm_core.teams = {}
tdm_core.teams.players = {} -- player_name -> "red" or "blue"
tdm_core.teams.scores = { red = 0, blue = 0 }
tdm_core.teams.active_team_names = { red = "Red", blue = "Blue" }


-- Disables global nametags (Visibility is handled via HUD Waypoints instead)
tdm_core.teams.update_nametag = function(player)
    player:set_nametag_attributes({
        color = {a = 0, r = 0, g = 0, b = 0}
    })
end

tdm_core.teams.assign_player = function(player_name)
    local red_count = 0
    local blue_count = 0
    
    for _, team in pairs(tdm_core.teams.players) do
        if team == "red" then red_count = red_count + 1 end
        if team == "blue" then blue_count = blue_count + 1 end
    end
    
    local assigned_team = "red"
    if tdm_core.match.is_pve then
        assigned_team = "blue"
    elseif blue_count < red_count then
        assigned_team = "blue"
    end
    
    tdm_core.teams.players[player_name] = assigned_team
    core.chat_send_player(player_name, "You have been assigned to Team " .. assigned_team)
    
    local player = core.get_player_by_name(player_name)
    if player then
        tdm_core.teams.update_nametag(player)
    end
    
    return assigned_team
end

tdm_core.teams.get_player_team = function(player_name)
    return tdm_core.teams.players[player_name]
end

-- Join logic moved to match.lua for centralized management


core.register_on_leaveplayer(function(player)
    tdm_core.teams.players[player:get_player_name()] = nil
end)

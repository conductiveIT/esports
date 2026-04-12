tdm_core.match = {}
tdm_core.match.state = "waiting" -- waiting, active, over
tdm_core.match.timer = 0
tdm_core.match.match_duration = 300
tdm_core.match.active_teams = {red = nil, blue = nil}
tdm_core.match.friendly_fire = true
tdm_core.match.is_debug = false



local dtime_accumulator = 0
local proximity_accumulator = 0

core.register_globalstep(function(dtime)
    proximity_accumulator = proximity_accumulator + dtime
    if proximity_accumulator >= 0.2 then
        proximity_accumulator = 0
        local all_players = core.get_connected_players()
        for _, p in ipairs(all_players) do
            local pname = p:get_player_name()
            
            -- Hidden completely if spectator
            if tdm_core.is_spectator(pname) then
                p:set_nametag_attributes({color = {a=0, r=0, g=0, b=0}})
            else
                local p_pos = p:get_pos()
                local show_name = false
                
                -- Loop to see if ANYONE is near this player
                for _, other in ipairs(all_players) do
                    if other:get_player_name() ~= pname then
                        if vector.distance(p_pos, other:get_pos()) < 15 then
                            show_name = true
                            break
                        end
                    end
                end
                
                -- Apply team color and alpha
                local team = tdm_core.teams.get_player_team(pname)
                local a = show_name and 255 or 0
                local r, g, b = 200, 200, 200
                if team == "red" then r, g, b = 255, 50, 50
                elseif team == "blue" then r, g, b = 50, 50, 255 end
                
                p:set_nametag_attributes({color = {a = a, r = r, g = g, b = b}})
            end
        end
    end
    
    dtime_accumulator = dtime_accumulator + dtime
    if dtime_accumulator < 1 then return end
    dtime_accumulator = dtime_accumulator - 1
    
    local players = core.get_connected_players()
    local num_players = #players
    
    -- Void death check
    for _, p in ipairs(players) do
        local pname = p:get_player_name()
        if p:get_pos().y < -10 and not tdm_core.is_spectator(pname) then
            p:set_hp(0) -- Instant elimination
        end
    end
    
    if tdm_core.match.state == "waiting" then
        tdm_core.hud.update_timer("Waiting for Admin...")
        
    elseif tdm_core.match.state == "countdown" then
        tdm_core.match.timer = tdm_core.match.timer - 1
        
        local players = core.get_connected_players()
        local r_name = tdm_core.match.active_teams.red
        local b_name = tdm_core.match.active_teams.blue
        
        for _, p in ipairs(players) do
            if not tdm_core.is_spectator(p:get_player_name()) then
                p:set_physics_override({speed = 0, jump = 0})
                tdm_core.hud.show_intro(p, tdm_core.match.timer, r_name, b_name)
            end
        end
        
        if tdm_core.match.timer > 0 then
        end
        
        if tdm_core.match.timer <= 0 then
            tdm_core.match.state = "active"
            tdm_core.match.timer = tdm_core.match.match_duration
            for _, p in ipairs(players) do
                p:set_physics_override({speed = 1, jump = 1})
                tdm_core.hud.hide_intro(p)
            end
            core.chat_send_all("MATCH STARTED!")
        end

    elseif tdm_core.match.state == "active" then
        tdm_core.match.timer = tdm_core.match.timer - 1
        
        local mins = math.floor(tdm_core.match.timer / 60)
        local secs = tdm_core.match.timer % 60
        tdm_core.hud.update_timer(string.format("Time Remaining: %02d:%02d", mins, secs))
        
        if tdm_core.match.timer <= 0 then
            tdm_core.match.state = "over"
            tdm_core.match.timer = 10
            
            local red_team = tdm_core.match.active_teams.red
            local blue_team = tdm_core.match.active_teams.blue
            local winner_name = "Tie"
            
            if tdm_core.teams.scores.red > tdm_core.teams.scores.blue then
                winner_name = red_team or "Red"
                if tdm_league and red_team and blue_team and not tdm_core.match.is_pve then
                    tdm_league.teams[red_team].wins = tdm_league.teams[red_team].wins + 1
                    tdm_league.teams[blue_team].losses = tdm_league.teams[blue_team].losses + 1
                    tdm_league.save()
                end
            elseif tdm_core.teams.scores.blue > tdm_core.teams.scores.red then
                winner_name = blue_team or "Blue"
                if tdm_league and red_team and blue_team and not tdm_core.match.is_pve then
                    tdm_league.teams[blue_team].wins = tdm_league.teams[blue_team].wins + 1
                    tdm_league.teams[red_team].losses = tdm_league.teams[red_team].losses + 1
                    tdm_league.save()
                end
            end
            
            core.chat_send_all("Match Over! Winner: " .. winner_name)
            tdm_core.hud.update_timer("Winner: " .. winner_name)
            
            -- Clear all PVE bots when match ends
            if tdm_core.match.is_pve then
                tdm_core.bots.clear_all()
            end
        end
        
    elseif tdm_core.match.state == "over" then
        tdm_core.match.timer = tdm_core.match.timer - 1
        if tdm_core.match.timer <= 0 then
            tdm_core.match.state = "waiting"
            tdm_core.match.active_teams = {red = nil, blue = nil}
            core.chat_send_all("Returning to lobby.")
        end
    end
end)

core.register_on_dieplayer(function(player, reason)
    -- This handles scoring
    if tdm_core.match.state == "active" then
        local p_team = tdm_core.teams.get_player_team(player:get_player_name())
        -- Simple scoring: if you die, the other team gets a point
        if p_team == "red" then
            tdm_core.teams.scores.blue = tdm_core.teams.scores.blue + 1
        elseif p_team == "blue" then
            tdm_core.teams.scores.red = tdm_core.teams.scores.red + 1
        end
        tdm_core.hud.update_scores()
    end

    -- Broadcast kill message
    local victim = player:get_player_name()
    if reason.type == "punch" and reason.puncher and reason.puncher:is_player() then
        local killer = reason.puncher:get_player_name()
        core.chat_send_all(">> " .. victim .. " was eliminated by " .. killer .. "!")
    else
        core.chat_send_all(">> " .. victim .. " was eliminated!")
    end
    
    -- Hide player model immediately on death
    player:set_properties({visual_size = {x=0, y=0, z=0}})
end)


-- Helper to find a safe ground position within the storm and on the island
function tdm_core.get_safe_spawn_pos(pname)
    local storm_center = tdm_storm.center
    local storm_radius = tdm_storm.current_radius
    local island_radius = 70 
    
    local my_team = pname and tdm_core.teams.get_player_team(pname) or nil
    
    local attempts = 0
    while attempts < 50 do
        local angle = math.random() * math.pi * 2
        local dist = math.random() * (storm_radius * 0.8)
        local target_x = storm_center.x + math.cos(angle) * dist
        local target_z = storm_center.z + math.sin(angle) * dist
        
        -- Clamp to island
        local dist_from_center = math.sqrt(target_x^2 + target_z^2)
        if dist_from_center > island_radius then
            local scale = island_radius / dist_from_center
            target_x = target_x * scale
            target_z = target_z * scale
        end
        
        -- Anti-Camp: Check for nearby enemies
        local enemy_nearby = false
        if my_team then
            for _, alt_p in ipairs(core.get_connected_players()) do
                local other_name = alt_p:get_player_name()
                local other_team = tdm_core.teams.get_player_team(other_name)
                if other_team and other_team ~= my_team and not tdm_core.is_spectator(other_name) then
                    local other_pos = alt_p:get_pos()
                    local d = vector.distance({x=target_x, y=0, z=target_z}, {x=other_pos.x, y=0, z=other_pos.z})
                    if d < 15 then
                        enemy_nearby = true
                        break
                    end
                end
            end
        end
        
        if not enemy_nearby then
            -- Find the ground
            for y = 30, -20, -1 do
                local node = core.get_node_or_nil({x=target_x, y=y, z=target_z})
                if node and node.name ~= "air" and node.name ~= "ignore" and node.name ~= "tdm_storm:gas" then
                    return {x=target_x, y=y + 1.5, z=target_z}
                end
            end
        end
        attempts = attempts + 1
    end
    
    return {x=0, y=2.0, z=0}
end

-- Resets a player to a clean match state
function tdm_core.reset_player(player, provide_weapons)
    local pname = player:get_player_name()
    local inv = player:get_inventory()
    
    -- Wipe Inventories
    inv:set_list("main", {})
    inv:set_list("ammo", {})
    
    -- Clear Combat State
    if tdm_weapons then
        tdm_weapons.cooldowns[pname] = 0
    end
    
    -- Reset HP and Physics
    player:set_hp(20)
    player:set_properties({visual_size = {x=1, y=1, z=1}}) -- Restore model size if it was hidden
    
    -- Give Utility Kit
    inv:add_item("main", "tdm_weapons:pickaxe")
    inv:add_item("main", "tdm_building:blueprint_wall")
    inv:add_item("main", "tdm_building:blueprint_ramp")
    
    -- Give Weapons (Debug or Staging)
    if provide_weapons then
        inv:add_item("main", "tdm_weapons:assault_rifle")
        inv:add_item("main", "tdm_weapons:shotgun")
        inv:add_item("ammo", "tdm_weapons:rifle_ammo 100")
        inv:add_item("ammo", "tdm_weapons:shotgun_ammo 50")
    end
    
    -- Update HUD
    tdm_core.hud.update_ammo(player)
    tdm_core.teams.update_nametag(player)
end

core.register_on_joinplayer(function(player)
    local pname = player:get_player_name()
    
    -- Initial Reset
    if tdm_core.is_spectator(pname) then
        -- Spectators get a pure empty inventory
        local inv = player:get_inventory()
        inv:set_list("main", {})
        inv:set_list("ammo", {})
    else
        -- Active players get the standard Utility Kit
        tdm_core.reset_player(player, false)
    end
    
    -- Initial teleport to Lobby/Safe spot
    player:set_pos(tdm_core.get_safe_spawn_pos(pname))
end)

core.register_on_respawnplayer(function(player)
    if tdm_core.match.state == "active" then
        local pname = player:get_player_name()
        player:set_pos(tdm_core.get_safe_spawn_pos(pname))
        
        -- Respawn Invulnerability (3 seconds)
        player:set_armor_groups({immortal = 1})
        core.after(3, function()
            if player:is_player() then
                player:set_armor_groups({fleshy = 100})
                core.chat_send_player(pname, "Shield deactivated! You are now vulnerable.")
            end
        end)

        -- Clean Slate Reset
        tdm_core.reset_player(player, tdm_core.match.is_debug)
    end
    return true
end)

core.register_chatcommand("match", {
    params = "<team1> <team2> [duration] [ff_on/off] [day/night]",
    description = "Start a league match (Admin only). Options: [off] for FF, [night] for Time.",
    privs = {server = true},
    func = function(name, param)
        local t1, t2, dur, ff, time_mode = param:match("^(%S+)%s+(%S+)%s*(%d*)%s*(%S*)%s*(%S*)$")
        if not t1 or not t2 then return false, "Usage: /match <Team1> <Team2> [duration] [off] [day/night]" end
        
        if not tdm_league.teams[t1] or not tdm_league.teams[t2] then
            return false, "One or both teams do not exist."
        end
        
        -- Friendly Fire Logic
        tdm_core.match.friendly_fire = true
        if ff == "off" then
            tdm_core.match.friendly_fire = false
        end

        -- Time of Day Logic
        core.settings:set("time_speed", "0") -- Freeze time
        if time_mode == "night" then
            core.set_timeofday(0) -- Midnight
        else
            core.set_timeofday(0.5) -- Noon (Default)
        end

        -- Update Team Names for HUD
        tdm_core.teams.active_team_names.red = t1
        tdm_core.teams.active_team_names.blue = t2
        
        -- Force HUD refresh for everyone
        for _, p in ipairs(core.get_connected_players()) do
            tdm_core.hud.init_hud(p)
        end
        tdm_core.hud.update_timer("MATCH ACTIVE!")

        
        -- Check for minimum players (2 per team)
        local players = core.get_connected_players()
        local t1_online = {}
        local t2_online = {}
        
        for _, p in ipairs(players) do
            local pname = p:get_player_name()
            -- Skip spectators
            if not tdm_core.is_spectator(pname) then
                local pteam = tdm_league.player_to_team[pname]
                if pteam == t1 then table.insert(t1_online, p) end
                if pteam == t2 then table.insert(t2_online, p) end
            end
        end
        
        if #t1_online < 1 or #t2_online < 1 then
            return false, "Each team needs at least 1 player online. (Found: " .. t1 .. ": " .. #t1_online .. ", " .. t2 .. ": " .. #t2_online .. ")"
        end
        
        -- Start match (with countdown)
        tdm_core.match.active_teams = {red = t1, blue = t2}
        tdm_core.match.state = "countdown"
        tdm_core.match.is_debug = false
        tdm_core.match.timer = 6 -- Adjusted for first-second trigger
        tdm_core.match.match_duration = tonumber(dur) or 300
        
        -- Clear old assignments
        tdm_core.teams.players = {}
        
        -- Assign players to Red/Blue with limited nametag distance
        for _, p in ipairs(t1_online) do
            tdm_core.teams.players[p:get_player_name()] = "red"
            tdm_core.teams.update_nametag(p)
        end
        for _, p in ipairs(t2_online) do
            tdm_core.teams.players[p:get_player_name()] = "blue"
            tdm_core.teams.update_nametag(p)
        end
        
        -- Reset Arena (Map, Gas, Items)
        if tdm_mapgen and tdm_mapgen.reset_island then
            tdm_mapgen.reset_island()
        end
        
        if tdm_storm then
            tdm_storm.current_radius = 100
            if tdm_storm.randomize_center then
                tdm_storm.randomize_center()
            end
        end
        
        tdm_core.teams.scores.red = 0
        tdm_core.teams.scores.blue = 0
        tdm_core.hud.update_scores()
        
        -- Teleport and Clean Slate for everyone
        for _, p in ipairs(players) do
            local pname = p:get_player_name()
            if not tdm_core.is_spectator(pname) then
                if tdm_league.player_to_team[pname] == t1 or tdm_league.player_to_team[pname] == t2 then
                    p:set_pos(tdm_core.get_safe_spawn_pos(pname))
                    tdm_core.reset_player(p, false) -- League matches start with loot search
                end
            end
        end
        
        core.chat_send_all("LEAGUE MATCH STARTED: " .. t1 .. " vs " .. t2 .. "!")
        return true, "Match started."
    end
})

core.register_chatcommand("matchdebug", {
    params = "<team1> <team2> [ff_on/off] [day/night]",
    description = "DEBUG: Start a match instantly. Options: [off] for FF, [night] for Time.",
    privs = {server = true},
    func = function(name, param)
        local t1, t2, ff, time_mode = param:match("^(%S+)%s+(%S+)%s*(%S*)%s*(%S*)$")
        if not t1 or not t2 then return false, "Usage: /matchdebug <Team1> <Team2> [off] [day/night]" end
        
        -- Friendly Fire Logic
        tdm_core.match.friendly_fire = true
        if ff == "off" then
            tdm_core.match.friendly_fire = false
        end

        -- Time of Day Logic
        core.settings:set("time_speed", "0")
        if time_mode == "night" then
            core.set_timeofday(0)
        else
            core.set_timeofday(0.5)
        end

        -- Update Team Names for HUD
        tdm_core.teams.active_team_names.red = t1
        tdm_core.teams.active_team_names.blue = t2
        
        -- Force HUD refresh for everyone
        for _, p in ipairs(core.get_connected_players()) do
            tdm_core.hud.init_hud(p)
        end
        tdm_core.hud.update_timer("DEBUG MATCH ACTIVE!")

        
        -- Create teams if they don't exist
        for _, tname in ipairs({t1, t2}) do
            if not tdm_league.teams[tname] then
                tdm_league.teams[tname] = {leader=name, members={name}, wins=0, losses=0}
            end
        end
        
        -- Start match (with countdown)
        tdm_core.match.active_teams = {red = t1, blue = t2}
        tdm_core.match.state = "countdown"
        tdm_core.match.is_debug = true
        tdm_core.match.timer = 6
        tdm_core.match.match_duration = 300
        
        -- Assign all online players (alternating if teamless, or staying in their team if they have one)
        local players = core.get_connected_players()
        tdm_core.teams.players = {}
        
        for i, p in ipairs(players) do
            local pname = p:get_player_name()
            local assigned = (i % 2 == 0) and "blue" or "red"
            tdm_core.teams.players[pname] = assigned
            
            -- Clean Slate with Weapons
            tdm_core.reset_player(p, true)
            p:set_pos(tdm_core.get_safe_spawn_pos(pname))
        end
        
        -- Reset Arena (Map, Gas, Items)
        if tdm_mapgen and tdm_mapgen.reset_island then
            tdm_mapgen.reset_island()
        end
        
        if tdm_storm then
            tdm_storm.current_radius = 100
            if tdm_storm.randomize_center then
                tdm_storm.randomize_center()
            end
        end
        
        tdm_core.teams.scores.red = 0
        tdm_core.teams.scores.blue = 0
        tdm_core.hud.update_scores()
        
        core.chat_send_all("DEBUG MATCH STARTED: " .. t1 .. " vs " .. t2 .. "! All systems ready.")
        return true, "Debug match started."
    end
})

-- PROTECT SPECTATORS FROM PUNCHES
core.register_on_punchplayer(function(player, hitter, time_from_last_punch, tool_capabilities, dir, damage)
    if tdm_core.is_spectator(player:get_player_name()) or (hitter and hitter:is_player() and tdm_core.is_spectator(hitter:get_player_name())) then
        return true -- Block damage
    end
end)

core.register_chatcommand("botmatch", {
    params = "<team> <bot_count> [difficulty]",
    description = "Start a PVE match against AI bots. Bots replace the blue team.",
    privs = {server = true},
    func = function(name, param)
        local team, count_str, diff = param:match("^(%S+)%s+(%d+)%s*(%S*)$")
        if not team or not count_str then return false, "Usage: /botmatch <team> <number> [easy/medium/hard]" end
        
        local bot_count = tonumber(count_str) or 5
        if not tdm_league.teams[team] then
            return false, "Team " .. team .. " does not exist."
        end
        
        -- PVE Match Settings
        tdm_core.match.friendly_fire = false
        tdm_core.match.is_debug = false
        tdm_core.match.is_pve = true
        core.set_timeofday(0.5)
        
        tdm_core.teams.active_team_names.red = team
        tdm_core.teams.active_team_names.blue = "BOTS"
        
        -- Force HUD
        for _, p in ipairs(core.get_connected_players()) do
            tdm_core.hud.init_hud(p)
        end
        tdm_core.hud.update_timer("PVE MATCH ACTIVE!")
        
        local players = core.get_connected_players()
        local t1_online = {}
        for _, p in ipairs(players) do
            local pname = p:get_player_name()
            if not tdm_core.is_spectator(pname) then
                local pteam = tdm_league.player_to_team[pname]
                if pteam == team then table.insert(t1_online, p) end
            end
        end
        
        if #t1_online < 1 then
            return false, "No players online for team " .. team
        end
        
        tdm_core.match.active_teams = {red = team, blue = "BOTS"}
        tdm_core.match.state = "countdown"
        tdm_core.match.timer = 6
        tdm_core.match.match_duration = 300
        
        tdm_core.teams.players = {}
        for _, p in ipairs(t1_online) do
            tdm_core.teams.players[p:get_player_name()] = "red"
            tdm_core.teams.update_nametag(p)
        end
        
        if tdm_mapgen and tdm_mapgen.reset_island then tdm_mapgen.reset_island() end
        if tdm_storm then tdm_storm.current_radius = 100 end
        
        tdm_core.teams.scores.red = 0
        tdm_core.teams.scores.blue = 0
        tdm_core.hud.update_scores()
        
        -- Spawn players
        for _, p in ipairs(t1_online) do
            local pname = p:get_player_name()
            p:set_pos(tdm_core.get_safe_spawn_pos(pname))
            tdm_core.reset_player(p, true) -- Give weapons for PVE
        end
        
        -- Clear old bots and spawn new ones
        tdm_core.bots.clear_all()
        core.after(5, function()
            for i = 1, bot_count do
                tdm_core.bots.spawn(tdm_core.get_safe_spawn_pos(nil), diff or "medium")
            end
        end)
        
        core.chat_send_all("PVE SENTRY PROTOCOL INITIATED. " .. bot_count .. " Hostiles Detected.")
        return true, "Bot match started."
    end
})



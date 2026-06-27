esports_core.match = {}
esports_core.match.state = "waiting" -- waiting, active, over
esports_core.match.timer = 0
esports_core.match.match_duration = 300
esports_core.match.active_teams = {red = nil, blue = nil}
esports_core.match.player_stats = {} -- [name] = {kills=0, deaths=0}
esports_core.match.last_attacker = {} -- [victim] = {name=killer, time=os.time()}
esports_core.match.friendly_fire = true
esports_core.match.is_debug = false
esports_core.match.player_sides = {} -- [name] = "red" or "blue" (Temporary overrides)



local dtime_accumulator = 0
local proximity_accumulator = 0

local proximity_accumulator = 0
core.register_globalstep(function(dtime)
    proximity_accumulator = proximity_accumulator + dtime
    if proximity_accumulator >= 0.1 then
        proximity_accumulator = 0
        local all_players = core.get_connected_players()
        for _, p in ipairs(all_players) do
            local pname = p:get_player_name()
            
            -- Hidden completely if spectator
            if esports_core.is_spectator(pname) then
                p:set_nametag_attributes({color = {a=0, r=0, g=0, b=0}})
            else
                local show_name = false
                local match_active = (esports_core.match.state == "active" or esports_core.match.state == "countdown")
                
                if not match_active then
                    -- Lobby mode: Always show names for players
                    show_name = true
                else
                    -- Active match: Show names only if another combatant is within 15 meters (Tactical Proximity)
                    local p_pos = p:get_pos()
                    for _, other in ipairs(all_players) do
                        local other_name = other:get_player_name()
                        if other_name ~= pname and not esports_core.is_spectator(other_name) then
                            if vector.distance(p_pos, other:get_pos()) < 15 then
                                show_name = true
                                break
                            end
                        end
                    end
                end
                
                -- Apply team color, alpha, and dynamic health text
                local team = esports_core.teams.get_player_team(pname)
                local hp = p:get_hp()
                local is_alive = hp > 0
                local a = (show_name and is_alive) and 255 or 0
                local r, g, b = 200, 200, 200
                if team == "red" then r, g, b = 255, 50, 50
                elseif team == "blue" then r, g, b = 50, 50, 255 end
                
                local tag_text = string.format("%s (%d HP)", pname, hp)
                
                p:set_nametag_attributes({
                    text = tag_text,
                    color = {a = a, r = r, g = g, b = b}
                })
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
        if p:get_pos().y < -10 and not esports_core.is_spectator(pname) then
            p:set_hp(0) -- Instant elimination
        end
    end
    
    if esports_core.match.state == "waiting" then
        esports_core.hud.update_timer("Waiting for Admin...")
        
    elseif esports_core.match.state == "countdown" then
        esports_core.match.timer = esports_core.match.timer - 1
        
        local players = core.get_connected_players()
        local r_name = esports_core.match.active_teams.red
        local b_name = esports_core.match.active_teams.blue
        
        for _, p in ipairs(players) do
            if not esports_core.is_spectator(p:get_player_name()) then
                p:set_physics_override({speed = 0, jump = 0})
                esports_core.hud.show_intro(p, esports_core.match.timer, r_name, b_name)
            end
        end
        
        if esports_core.match.timer > 0 then
        end
        
        if esports_core.match.timer <= 0 then
            esports_core.match.state = "active"
            esports_core.match.timer = esports_core.match.match_duration
            for _, p in ipairs(players) do
                local pname = p:get_player_name()
                local is_participant = esports_core.match.get_player_match_side(pname) ~= nil
                
                if is_participant or core.check_player_privs(pname, {server = true}) then
                     p:set_physics_override({speed = 1, jump = 1})
                end
                esports_core.hud.hide_intro(p)
            end
            core.chat_send_all("MATCH STARTED!")
        end

    elseif esports_core.match.state == "active" then
        esports_core.match.timer = esports_core.match.timer - 1
        
        local mins = math.floor(esports_core.match.timer / 60)
        local secs = esports_core.match.timer % 60
        local is_critical = esports_core.match.timer < 30
        esports_core.hud.update_timer(string.format("Time Remaining: %02d:%02d", mins, secs), is_critical)
        
        if esports_core.match.timer <= 0 then
            esports_core.match.state = "over"
            esports_core.match.timer = 0 -- Reset for safety watchdog
            
            local r_name = esports_core.match.active_teams.red
            local b_name = esports_core.match.active_teams.blue
            local winner_name = "Match Draw"
            local win_color = "white"
            local win_team_id = nil
            
            if esports_core.teams.scores.red > esports_core.teams.scores.blue then
                winner_name = (r_name or "Red Team") .. " Victory"
                win_color = "red"
                win_team_id = r_name
                if esports_league and r_name and b_name and not esports_core.match.is_pve then
                    esports_league.teams[r_name].wins = (esports_league.teams[r_name].wins or 0) + 1
                    esports_league.teams[b_name].losses = (esports_league.teams[b_name].losses or 0) + 1
                end
            elseif esports_core.teams.scores.blue > esports_core.teams.scores.red then
                winner_name = (b_name or "Blue Team") .. " Victory"
                win_color = "blue"
                win_team_id = b_name
                if esports_league and r_name and b_name and not esports_core.match.is_pve then
                    esports_league.teams[b_name].wins = (esports_league.teams[b_name].wins or 0) + 1
                    esports_league.teams[r_name].losses = (esports_league.teams[r_name].losses or 0) + 1
                end
            end

            -- Update Standings kills/deaths statistics
            if esports_league and r_name and b_name and not esports_core.match.is_pve then
                local red_score = esports_core.teams.scores.red
                local blue_score = esports_core.teams.scores.blue
                
                esports_league.teams[r_name].kills_scored = (esports_league.teams[r_name].kills_scored or 0) + red_score
                esports_league.teams[r_name].deaths_conceded = (esports_league.teams[r_name].deaths_conceded or 0) + blue_score
                esports_league.teams[b_name].kills_scored = (esports_league.teams[b_name].kills_scored or 0) + blue_score
                esports_league.teams[b_name].deaths_conceded = (esports_league.teams[b_name].deaths_conceded or 0) + red_score
                
                -- Process Scheduled Match Context
                local ctx = esports_core.match.scheduled_context
                if ctx then
                    if ctx.type == "regular_season" then
                        local round = ctx.round
                        local idx = ctx.index
                        local fixture = esports_league.fixtures[round] and esports_league.fixtures[round][idx]
                        if fixture then
                            fixture.status = "completed"
                            fixture.score.home = red_score
                            fixture.score.away = blue_score
                        end
                    elseif ctx.type == "playoff_semifinal" then
                        local idx = ctx.index
                        local sf = esports_league.playoffs.semifinals[idx]
                        if sf then
                            sf.status = "completed"
                            sf.score1 = red_score
                            sf.score2 = blue_score
                            if sf.score1 > sf.score2 then
                                sf.winner = sf.team1
                            elseif sf.score2 > sf.score1 then
                                sf.winner = sf.team2
                            else
                                sf.winner = sf.team1
                            end
                            
                            -- Advance to final if both semifinals are completed
                            local sf1 = esports_league.playoffs.semifinals[1]
                            local sf2 = esports_league.playoffs.semifinals[2]
                            if sf1.status == "completed" and sf2.status == "completed" then
                                esports_league.playoffs.finals.team1 = sf1.winner
                                esports_league.playoffs.finals.team2 = sf2.winner
                                esports_league.playoffs.finals.status = "pending"
                            end
                        end
                    elseif ctx.type == "playoff_final" then
                        local fn = esports_league.playoffs.finals
                        if fn then
                            fn.status = "completed"
                            fn.score1 = red_score
                            fn.score2 = blue_score
                            if fn.score1 > fn.score2 then
                                fn.winner = fn.team1
                            elseif fn.score2 > fn.score1 then
                                fn.winner = fn.team2
                            else
                                fn.winner = fn.team1
                            end
                            core.chat_send_all(">> CHAMPIONS: Team '" .. fn.winner .. "' has won the Grand Finals!")
                        end
                    end
                    esports_core.match.scheduled_context = nil
                end
                esports_league.save()
            end
            
            -- GATHER SCOREBOARD DATA & MVP
            local red_list = {}
            local blue_list = {}
            local mvp = {name = "No One", kills = 0}
            
            for _, p in ipairs(core.get_connected_players()) do
                local pname = p:get_player_name()
                local stats = esports_core.match.player_stats[pname] or {kills=0, deaths=0, captures=0}
                local p_team = esports_core.teams.get_player_team(pname)
                
                if p_team == "red" then 
                    table.insert(red_list, {name=pname, k=stats.kills, d=stats.deaths, c=stats.captures})
                elseif p_team == "blue" then
                    table.insert(blue_list, {name=pname, k=stats.kills, d=stats.deaths, c=stats.captures})
                end
                
                -- Determine MVP (Humans only) - prioritized by captures in CTF
                local score = stats.kills
                if esports_core.match.is_ctf then score = (stats.captures * 10) + stats.kills end
                
                if score > mvp.kills and not esports_core.is_spectator(pname) then
                    mvp = {name=pname, kills=score}
                end
                
                -- Freeze players for Outro
                p:set_physics_override({speed = 0, jump = 0})
            end
            
            -- Record completed match to History log
            if esports_league and r_name and b_name and not esports_core.match.is_pve then
                table.insert(esports_league.history, {
                    time = os.time(),
                    home = r_name,
                    away = b_name,
                    home_score = esports_core.teams.scores.red,
                    away_score = esports_core.teams.scores.blue,
                    mvp = mvp.name
                })
                esports_league.save()
            end
            
            -- SORT BY PERFORMANCE (Captures if CTF, otherwise Kills)
            local sort_fn = function(a, b) 
                if esports_core.match.is_ctf then
                    if a.c ~= b.c then return a.c > b.c end
                end
                return a.k > b.k 
            end
            table.sort(red_list, sort_fn)
            table.sort(blue_list, sort_fn)
            
            -- PERSIST OUTRO HUD
            local outro_data = {
                title = winner_name:upper(),
                color = win_color,
                mvp = mvp.name,
                mvp_kills = mvp.kills,
                is_ctf = esports_core.match.is_ctf,
                win_team = win_team_id,
                red_team = r_name,
                blue_team = b_name,
                red_roster = red_list,
                blue_roster = blue_list
            }
            
            for _, player in ipairs(core.get_connected_players()) do
                esports_core.hud.show_outro(player, outro_data)
            end
            
            core.chat_send_all(">> MATCH OVER! " .. winner_name:upper())
            
            -- Clear all PVE bots when match ends
            if esports_core.match.is_pve then
                esports_core.bots.clear_all()
            end

            -- Immediately clear participants to lock back to lobby
            esports_core.match.active_teams = {red = nil, blue = nil}
            esports_core.match.player_sides = {}
        end
        
    elseif esports_core.match.state == "over" then
        esports_core.match.timer = esports_core.match.timer - 1
        -- Safety Reset: Automatically return to lobby after 2 minutes of idle viewing
        if esports_core.match.timer <= -120 then
            esports_core.match.state = "waiting"
            esports_core.match.active_teams = {red = nil, blue = nil}
            
            for _, player in ipairs(core.get_connected_players()) do
                esports_core.hud.hide_outro(player)
                esports_core.lobby.show(player)
                -- Ensure lobby physics are reset (Frozen until match starts)
                if not core.check_player_privs(player:get_player_name(), {server=true}) then
                    player:set_physics_override({speed = 0, jump = 0, gravity = 1})
                end
            end
            
            core.chat_send_all("Idle timeout: Returning to lobby.")
        end
    end
end)

core.register_on_punchplayer(function(player, hitter, time_from_last_punch, tool_capabilities, dir, damage)
    if not player or not hitter then return end
    local victim = player:get_player_name()
    local attacker = nil
    local is_bot = false
    
    if hitter:is_player() then
        attacker = hitter:get_player_name()
    end
    
    if not attacker or attacker == "" then
        local ent = hitter:get_luaentity()
        if ent and ent.name == "esports_core:bot" then
            attacker = "Sentry"
            is_bot = true
        end
    end
    
    if not victim or not attacker or attacker == "" or victim == attacker then return end
    
    local weapon = "pickaxe"
    if hitter:is_player() then
        local item = hitter:get_wielded_item():get_name()
        if item:find("rifle") then weapon = "rifle"
        elseif item:find("shotgun") then weapon = "shotgun" end
    else
        weapon = "rifle"
    end
    
    esports_core.match.last_attacker[victim] = {
        name = attacker,
        time = os.time(),
        weapon = weapon
    }
end)

core.register_on_dieplayer(function(player, reason)
    -- This handles scoring
    if esports_core.match.state == "active" and not esports_core.match.is_ctf then
        local p_team = esports_core.teams.get_player_team(player:get_player_name())
        -- Simple scoring: if you die, the other team gets a point (TDM ONLY)
        if p_team == "red" then
            esports_core.teams.scores.blue = esports_core.teams.scores.blue + 1
        elseif p_team == "blue" then
            esports_core.teams.scores.red = esports_core.teams.scores.red + 1
        end
        esports_core.hud.update_scores()
    end

    -- Broadcast kill message
    local victim = player:get_player_name()
    esports_core.match.add_death(victim)
    
    local killer_name = nil
    local k_team = nil
    local weapon = "skull"
    
    if reason.puncher then
        if reason.puncher:is_player() then
            killer_name = reason.puncher:get_player_name()
            local item = reason.puncher:get_wielded_item():get_name()
            if item:find("rifle") then weapon = "rifle"
            elseif item:find("shotgun") then weapon = "shotgun"
            elseif item:find("pickaxe") then weapon = "pickaxe" end
        else
            local ent = reason.puncher:get_luaentity()
            if ent and ent.name == "esports_core:bot" then
                killer_name = "Sentry"
                weapon = "rifle"
            end
        end
    elseif esports_core.match.last_attacker[victim] then
        local last = esports_core.match.last_attacker[victim]
        local now = os.time()
        if now - last.time <= 10 then
            killer_name = last.name
            weapon = last.weapon or "skull"
        end
    end
    
    if killer_name and killer_name ~= "" then
        k_team = esports_core.match.get_player_match_side(killer_name)
    end
    
    local v_team = esports_core.match.get_player_match_side(victim)
    esports_core.hud.add_kill_event((killer_name and killer_name ~= "") and killer_name or "Environment", k_team, victim, v_team, weapon)

    if killer_name and killer_name ~= "" then
        esports_core.match.add_kill(killer_name)
        core.chat_send_all(">> " .. victim .. " was eliminated by " .. killer_name .. "!")
    else
        core.chat_send_all(">> " .. victim .. " was eliminated!")
    end
    
    -- Clear attacker state
    esports_core.match.last_attacker[victim] = nil
    
    -- Hide player model immediately on death and revert skin
    player:set_properties({visual_size = {x=0, y=0, z=0}})
    esports_core.skins.apply(player, nil)
end)

-- Helper stats functions
-- Helper stats functions
function esports_core.match.add_kill(name)
    if not esports_core.match.player_stats[name] then
        esports_core.match.player_stats[name] = {kills = 0, deaths = 0, captures = 0}
    end
    esports_core.match.player_stats[name].kills = esports_core.match.player_stats[name].kills + 1
    
    -- Force HUD update for active viewers
    if esports_core.hud.update_scoreboard then
        esports_core.hud.update_scoreboard()
    end
    
    -- Persist to league (PVP ONLY!)
    if not esports_core.match.is_pve then
        if esports_league and esports_league.player_stats then
            if not esports_league.player_stats[name] then
                esports_league.player_stats[name] = {kills = 0, deaths = 0, captures = 0}
            end
            esports_league.player_stats[name].kills = (esports_league.player_stats[name].kills or 0) + 1
            esports_league.save()
        end
    end
end

function esports_core.match.add_death(name)
    if not esports_core.match.player_stats[name] then
        esports_core.match.player_stats[name] = {kills = 0, deaths = 0, captures = 0}
    end
    esports_core.match.player_stats[name].deaths = esports_core.match.player_stats[name].deaths + 1
    
    -- Force HUD update for active viewers
    if esports_core.hud.update_scoreboard then
        esports_core.hud.update_scoreboard()
    end
    
    -- Persist to league (PVP ONLY!)
    if not esports_core.match.is_pve then
        if esports_league and esports_league.player_stats then
            if not esports_league.player_stats[name] then
                esports_league.player_stats[name] = {kills = 0, deaths = 0, captures = 0}
            end
            esports_league.player_stats[name].deaths = (esports_league.player_stats[name].deaths or 0) + 1
            esports_league.save()
        end
    end
end

function esports_core.match.add_capture(name)
    if not esports_core.match.player_stats[name] then
        esports_core.match.player_stats[name] = {kills = 0, deaths = 0, captures = 0}
    end
    esports_core.match.player_stats[name].captures = esports_core.match.player_stats[name].captures + 1
    
    if esports_core.hud.update_scoreboard then
        esports_core.hud.update_scoreboard()
    end
    
    -- Persist to league (PVP ONLY!)
    if not esports_core.match.is_pve then
        if esports_league and esports_league.player_stats then
            if not esports_league.player_stats[name] then
                esports_league.player_stats[name] = {kills = 0, deaths = 0, captures = 0}
            end
            esports_league.player_stats[name].captures = (esports_league.player_stats[name].captures or 0) + 1
            esports_league.save()
        end
    end
end


-- Helper to find a safe ground position within the storm and on the island
function esports_core.get_safe_spawn_pos(pname_or_side)
    local storm_center = esports_storm.center
    local storm_radius = esports_storm.current_radius
    local island_radius = 70 
    
    local side = pname_or_side
    local my_name = nil
    if side and side ~= "red" and side ~= "blue" then
        my_name = pname_or_side
        side = esports_core.match.get_player_match_side(my_name)
    end
    
    local is_base_spawn = (esports_core.match.is_ctf and side and esports_core.ctf.bases[side])
    
    local attempts = 0
    while attempts < 50 do
        local target_x, target_z
        
        if is_base_spawn then
            -- CTF: Spawn TIGHTLY near own flag stand
            local base = esports_core.ctf.bases[side]
            target_x = base.x + (math.random() * 20 - 10)
            target_z = base.z + (math.random() * 20 - 10)
        else
            -- TDM / Standard: Randomly on island
            local angle = math.random() * math.pi * 2
            local dist = math.random() * (storm_radius * 0.8)
            target_x = storm_center.x + math.cos(angle) * dist
            target_z = storm_center.z + math.sin(angle) * dist
            
            -- Clamp to island
            local dist_from_center = math.sqrt(target_x^2 + target_z^2)
            if dist_from_center > island_radius then
                local scale = island_radius / dist_from_center
                target_x = target_x * scale
                target_z = target_z * scale
            end
        end
        
        -- Anti-Camp: Check for nearby hostiles (Players and Bots)
        local enemy_nearby = false
        local safety_dist_enemy = is_base_spawn and 12 or 30 -- Reduced at bases to allow defense
        local safety_dist_team = is_base_spawn and 4 or 20 -- Reduced at bases to allow clustering
        
        -- Check Player positions
        for _, alt_p in ipairs(core.get_connected_players()) do
            local other_name = alt_p:get_player_name()
            if other_name ~= my_name and not esports_core.is_spectator(other_name) then
                local other_pos = alt_p:get_pos()
                local d = vector.distance({x=target_x, y=0, z=target_z}, {x=other_pos.x, y=0, z=other_pos.z})
                
                local other_side = esports_core.match.get_player_match_side(other_name)
                local is_enemy = (side and other_side and side ~= other_side)
                local thresh = is_enemy and safety_dist_enemy or safety_dist_team
                
                if d < thresh then
                    enemy_nearby = true
                    break
                end
            end
        end
        
        -- Check Bot positions (using object scan)
        if not enemy_nearby then
            local nearby_objects = core.get_objects_inside_radius({x=target_x, y=0, z=target_z}, safety_dist_enemy)
            for _, obj in ipairs(nearby_objects) do
                local ent = obj:get_luaentity()
                if ent and ent.name == "esports_core:bot" then
                    local other_pos = obj:get_pos()
                    local d_bot = vector.distance({x=target_x, y=0, z=target_z}, {x=other_pos.x, y=0, z=other_pos.z})
                    
                    -- If we are a player on blue, bots (red) are enemies
                    if side == "blue" and d_bot < safety_dist_enemy then
                         enemy_nearby = true
                         break
                    end
                    -- If we are a bot or a player on red, bots are teammates - check small radius
                    if (not side or side == "red") and d_bot < safety_dist_team then
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
                if node and node.name ~= "air" and node.name ~= "ignore" and node.name ~= "esports_storm:gas" and node.name ~= "esports_storm:gas_wall" and node.name ~= "esports_storm:gas_column" then
                    return {x=target_x, y=y + 0.5, z=target_z}
                end
            end
        end
        attempts = attempts + 1
    end
    
    -- LAST RESORT: Forced Deployment at Base (if CTF)
    if is_base_spawn then
        local base = esports_core.ctf.bases[side]
        return {x=base.x + (math.random() * 6 - 3), y=base.y + 1, z=base.z + (math.random() * 6 - 3)}
    end
    
    return {x=0, y=10.0, z=0}
end

-- Resets a player to a clean match state
function esports_core.reset_player(player, provide_weapons)
    local pname = player:get_player_name()
    local inv = player:get_inventory()
    
    -- Clear CTF state
    player:get_meta():set_int("has_flag", 0)
    
    -- Wipe Inventories
    inv:set_list("main", {})
    inv:set_list("ammo", {})
    
    -- Clear Combat State
    if esports_weapons then
        esports_weapons.cooldowns[pname] = 0
    end
    
    -- Reset HP and Physics (Combat Mode)
    player:set_properties({
        hp_max = 100,
        visual_size = {x=1, y=1, z=1}, -- Restore model size
        eye_height = 1.625,
        interact_distance = 10, -- Combat reach
    })
    player:set_hp(100)
    player:set_physics_override({
        speed = 1.2, -- Combat Speed
        jump = 1.1,
        gravity = 1.0
    })
    player:set_armor_groups({fleshy = 100})
    
    -- Revoke survival-breaking privileges (flight etc)
    local privs = core.get_player_privs(pname)
    if privs.fly or privs.noclip or privs.fast then
        privs.fly = nil
        privs.noclip = nil
        privs.fast = nil
        core.set_player_privs(pname, privs)
    end
    
    -- Give Utility Kit
    inv:set_stack("main", 2, ItemStack("esports_building:blueprint_wall"))
    inv:set_stack("main", 3, ItemStack("esports_building:blueprint_ramp"))
    
    -- Give Weapons (Debug or Staging)
    if provide_weapons then
        inv:add_item("main", "esports_weapons:assault_rifle")
        inv:add_item("main", "esports_weapons:shotgun")
        inv:add_item("ammo", "esports_weapons:rifle_ammo 100")
        inv:add_item("ammo", "esports_weapons:shotgun_ammo 50")
    end
    
    -- Update HUD
    esports_core.hud.update_ammo(player)
    esports_core.teams.update_nametag(player)
    
    -- Apply team skin automatically
    local side = esports_core.match.get_player_match_side(pname)
    if side == "red" then
        esports_core.skins.apply(player, "#ff0000")
    elseif side == "blue" then
        esports_core.skins.apply(player, "#0000ff")
    else
        esports_core.skins.apply(player, nil) -- Reset to default
    end
end

-- Returns "red", "blue", or nil based on whether the player is in an active match team
function esports_core.match.get_player_match_side(name)
    -- Check for temporary PVE/Join overrides first
    if esports_core.match.player_sides and esports_core.match.player_sides[name] then
        return esports_core.match.player_sides[name]
    end

    -- Strictly gate side detection to running matches
    if esports_core.match.state ~= "active" and esports_core.match.state ~= "countdown" then
        return nil
    end

    if not esports_core.match.active_teams then 
        return nil 
    end
    
    local p_team = esports_league.player_to_team[name]
    if not p_team then return nil end
    
    if p_team == esports_core.match.active_teams.red then
        return "red"
    elseif p_team == esports_core.match.active_teams.blue then
        return "blue"
    end
    
    return nil
end

core.register_on_joinplayer(function(player)
    local pname = player:get_player_name()
    
    -- Initial HUD Setup
    esports_core.hud.init_hud(player)

    -- Side Detection (Moved to top level scope)
    local side = esports_core.match.get_player_match_side(pname)
    local match_active = (esports_core.match.state == "active" or esports_core.match.state == "countdown")

    -- Detect mid-game join for participants
    if match_active then
        if side and not esports_core.is_spectator(pname) then
            -- Rejoin fight immediately
            esports_core.teams.players[pname] = side
            esports_core.teams.update_nametag(player)
            esports_core.reset_player(player, false)
            player:set_pos(esports_core.get_safe_spawn_pos(pname))
            core.chat_send_player(pname, "LUANTI ESPORTS: Welcome back. Team " .. side:upper() .. " is in combat!")
            return -- Skip Lobby
        end
    end

    -- Regular join (Lobby flow)
    if esports_core.is_spectator(pname) then
        local inv = player:get_inventory()
        inv:set_list("main", {})
        inv:set_list("ammo", {})
    else
        esports_core.reset_player(player, false)
    end
    
    player:set_pos(esports_core.get_safe_spawn_pos(pname))
    
    -- Lobby Ghost Mode: Invisible, Invulnerable, and Frozen
    if not side or not match_active then
        player:set_properties({
            hp_max = 100,
            visual_size = {x=1, y=1, z=1}, -- Full size for light calculation
            textures = {"character.png^[alpha:0"}, -- 100% transparent
            eye_height = 1.625,
            interact_distance = 0, -- Cannot hit anything in lobby
        })
        player:set_hp(100)
        player:set_armor_groups({immortal = 1})
        
        -- Admins can still move, but are hidden/protected
        if not core.check_player_privs(pname, {server=true}) then
            player:set_physics_override({speed = 0, jump = 0, gravity = 1})
        else
            -- Admin Movement Baseline
            player:set_physics_override({speed = 1.2, jump = 1.1, gravity = 1})
        end
    end
    
    -- Show Lobby (Immediate)
    core.after(0, function()
        if core.get_player_by_name(pname) then
            esports_core.lobby.show(player)
        end
    end)
end)

core.register_on_respawnplayer(function(player)
    if esports_core.match.state == "active" then
        local pname = player:get_player_name()
        
        -- Ensure invisible during repositioning
        player:set_properties({visual_size = {x=0, y=0, z=0}})
        player:set_pos(esports_core.get_safe_spawn_pos(pname))
        
        -- Respawn Invulnerability (3 seconds)
        player:set_armor_groups({immortal = 1})
        core.after(3, function()
            if player:is_player() then
                player:set_armor_groups({fleshy = 100})
                core.chat_send_player(pname, "Shield deactivated! You are now vulnerable.")
            end
        end)

        -- Clean Slate Reset
        esports_core.reset_player(player, esports_core.match.is_debug)
        
        -- Reveal player after brief delay to prevent "teleport glitching"
        core.after(0.2, function()
            if player:is_player() then
                local side = esports_core.match.get_player_match_side(pname)
                esports_core.skins.apply(player, side)
            end
        end)
    end
    return true
end)

esports_core.match.current_map_scale = 1.0

function esports_core.match.start(t1, t2, dur_secs, pve_mode, time_mode, bot_count, bot_diff, game_mode, map_size)
    -- 1. DEEP STATE RESET: Purge all stale data and physical nodes
    esports_core.ctf.reset()
    esports_core.match.player_sides = {}
    esports_core.match.last_attacker = {}
    esports_core.match.player_stats = {}
    
    -- 2. Map Scaling
    local scales = {Small = 0.5, Medium = 0.75, Large = 1.0}
    local scale = scales[map_size or "Large"] or 1.0
    esports_core.match.current_map_scale = scale
    
    -- 3. Apply Scaling to Environment & CTF Data
    esports_storm.current_radius = 100 * scale
    esports_core.ctf.bases.red.x = 80 * scale
    esports_core.ctf.bases.blue.x = -80 * scale

    -- 4. Mode Configuration
    local is_pve = (pve_mode == true)
    esports_core.match.is_pve = is_pve
    esports_core.match.is_ctf = (game_mode == "ctf")
    esports_core.teams.scores = {red = 0, blue = 0}

    -- 5. Physical Objective Deployment
    if esports_core.match.is_ctf then
        esports_core.ctf.spawn_flags()
    end
    
    -- 6. World Time Logic
    core.settings:set("time_speed", "0") -- Freeze time
    if time_mode == "night" then
        core.set_timeofday(0) -- Midnight
    else
        core.set_timeofday(0.5) -- Noon
    end

    -- 7. Update Team Names for HUD
    if is_pve then
        esports_core.teams.active_team_names.red = "BOTS"
        esports_core.teams.active_team_names.blue = t1
    else
        esports_core.teams.active_team_names.red = t1
        esports_core.teams.active_team_names.blue = t2
    end
    
    -- Force HUD refresh for everyone
    for _, p in ipairs(core.get_connected_players()) do
        esports_core.hud.init_hud(p)
    end
    esports_core.hud.update_timer("MATCH ACTIVE!")

    local players = core.get_connected_players()
    local t1_online = {}
    local t2_online = {}
    
    if is_pve then
        -- PVE: Team 1 is players, Team 2 is Bots
        for _, p in ipairs(players) do
            local pname = p:get_player_name()
            if not esports_core.is_spectator(pname) then
                local pteam = esports_league.player_to_team[pname]
                if pteam == t1 then table.insert(t1_online, p) end
            end
        end
    else
        -- Regular PVP
        for _, p in ipairs(players) do
            local pname = p:get_player_name()
            if not esports_core.is_spectator(pname) then
                local pteam = esports_league.player_to_team[pname]
                if pteam == t1 then table.insert(t1_online, p) end
                if pteam == t2 then table.insert(t2_online, p) end
            end
        end
    end

    if not is_pve and (#t1_online < 1 or #t2_online < 1) then
        return false, "Each team needs at least 1 player online. (Found: " .. t1 .. ": " .. #t1_online .. ", " .. t2 .. ": " .. #t2_online .. ")"
    end
    if is_pve and #t1_online < 1 then
        return false, "Your team must have at least 1 player online."
    end
    
    -- Start match (with countdown)
    if is_pve then
        -- PVE SPECIFIC: Team 1 (Players) is always BLUE, Team 2 (Bots) is always RED
        esports_core.match.active_teams = {red = t2, blue = t1}
    else
        esports_core.match.active_teams = {red = t1, blue = t2}
    end
    esports_core.match.state = "countdown"
    esports_core.match.is_debug = false
    esports_core.match.timer = 6
    esports_core.match.match_duration = tonumber(dur_secs) or 300
    
    -- Clear old assignments
    esports_core.teams.players = {}
    
    -- Assign participants to their respective Red/Blue sides
    if is_pve then
        -- In PvE, Team online 1 (Players) are ALL BLUE
        for _, p in ipairs(t1_online) do
            esports_core.teams.players[p:get_player_name()] = "blue"
            esports_core.teams.update_nametag(p)
        end
    else
        -- In PvP, follow the standard Red/Blue mapping
        for _, p in ipairs(t1_online) do
            esports_core.teams.players[p:get_player_name()] = "red"
            esports_core.teams.update_nametag(p)
        end
        for _, p in ipairs(t2_online) do
            esports_core.teams.players[p:get_player_name()] = "blue"
            esports_core.teams.update_nametag(p)
        end
    end
    
    -- Reset Arena and CTF State
    if esports_mapgen and esports_mapgen.reset_island then
        esports_mapgen.reset_island()
    end
    
    if esports_core.match.is_ctf then
        esports_core.ctf.reset()
        esports_core.ctf.spawn_flags()
    end
    
    if esports_storm then
        esports_storm.current_radius = 100
        if esports_storm.randomize_center then
            esports_storm.randomize_center()
        end
    end
    
    esports_core.teams.scores.red = 0
    esports_core.teams.scores.blue = 0
    esports_core.hud.update_scores()
    
    -- Teleport Combatants
        for _, p in ipairs(core.get_connected_players()) do
            local pname = p:get_player_name()
            local my_team = esports_league.get_team(pname)
            
            -- PVE Overdrive: If in PVE, everyone not spectating should join the fight
            if is_pve and not esports_core.is_spectator(pname) and (not my_team or my_team == "NONE") then
                my_team = t1
                -- Temporarily assign them for the duration of this match
                esports_core.match.player_sides[pname] = "red"
            end

            if my_team == t1 or my_team == t2 then
                local side
                if is_pve then
                    side = "blue" -- Everyone online is on the player side
                else
                    side = (my_team == t1) and "red" or "blue"
                end
                esports_core.match.player_sides[pname] = side
                
                -- Full Match Setup (Inventory, Physics, HUD)
                esports_core.reset_player(p, esports_core.match.is_debug)
                p:set_pos(esports_core.get_safe_spawn_pos(side))
                esports_core.hud.init_hud(p)
                
                -- Close lobby and hide blackout on match start
                if esports_core.lobby and esports_core.lobby.blackout_hide then
                    esports_core.lobby.blackout_hide(p)
                end
                core.close_formspec(pname, "esports_core:lobby")
            end
        end
    
    if is_pve then
        -- Spawn Bots
        esports_core.bots.clear_all()
        core.after(5, function()
            local count = bot_count or 5
            local diff = bot_diff or "medium"
            for i = 1, count do
                -- Tactical Mix: 60% Rusher (Aggressive Pressure), 40% Standard (Balanced)
                local class = math.random() > 0.6 and "standard" or "rusher"
                esports_core.bots.spawn(esports_core.get_safe_spawn_pos("red"), diff, class)
            end
        end)
        core.chat_send_all("PVE SENTRY PROTOCOL INITIATED. " .. (bot_count or 5) .. " Hostiles Detected.")
    else
        core.chat_send_all("MATCH STARTED: " .. t1 .. " vs " .. t2 .. "!")
    end
    
    return true, "Match started."
end

core.register_chatcommand("match", {
    params = "<team1> <team2> [duration] [ff_on/off] [day/night]",
    description = "Start a league match (Admin only). Options: [off] for FF, [night] for Time.",
    privs = {server = true},
    func = function(name, param)
        local t1, t2, dur, ff, time_mode = param:match("^(%S+)%s+(%S+)%s*(%d*)%s*(%S*)%s*(%S*)$")
        if not t1 or not t2 then return false, "Usage: /match <Team1> <Team2> [duration] [off] [day/night]" end
        esports_core.match.friendly_fire = (ff ~= "off")
        return esports_core.match.start(t1, t2, dur, false, time_mode)
    end
})

core.register_chatcommand("matchdebug", {
    params = "<team1> <team2> [ff_on/off] [day/night]",
    description = "DEBUG: Start a match instantly. Options: [off] for FF, [night] for Time.",
    privs = {server = true},
    func = function(name, param)
        local t1, t2, ff, time_mode = param:match("^(%S+)%s+(%S+)%s*(%S*)%s*(%S*)$")
        if not t1 or not t2 then return false, "Usage: /matchdebug <Team1> <Team2> [off] [day/night]" end
        esports_core.match.friendly_fire = (ff ~= "off")
        -- Debug matches are fast 5 min day or night
        return esports_core.match.start(t1, t2, 300, false, time_mode)
    end
})

core.register_chatcommand("botmatch", {
    params = "<team> <bot_count> [difficulty] [day/night]",
    description = "Start a PVE match against AI bots. Bots replace the blue team.",
    privs = {server = true},
    func = function(name, param)
        local team, count_str, diff, time_mode = param:match("^(%S+)%s+(%d+)%s*(%S*)%s*(%S*)$")
        if not team or not count_str then return false, "Usage: /botmatch <team> <number> [easy/medium/hard] [day/night]" end
        return esports_core.match.start(team, "BOTS", 300, true, time_mode, tonumber(count_str), diff)
    end
})

-- PROTECT SPECTATORS FROM PUNCHES
core.register_on_punchplayer(function(player, hitter, time_from_last_punch, tool_capabilities, dir, damage)
    local pname = player:get_player_name()
    if esports_core.is_spectator(pname) then return true end
    if hitter and hitter:is_player() and esports_core.is_spectator(hitter:get_player_name()) then
        return true -- Block damage
    end
end)



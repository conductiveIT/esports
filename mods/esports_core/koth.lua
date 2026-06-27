esports_core.koth = {}
esports_core.koth.hill_center = nil
esports_core.koth.hill_radius = 6
esports_core.koth.hill_owner = "none" -- "red", "blue", or "none"
esports_core.koth.timer = 60
esports_core.koth.placed_ring = nil
esports_core.koth.contested = false

function esports_core.koth.spawn_new_hill()
    -- Clear the old ring
    if esports_core.koth.placed_ring and esports_core.koth.placed_ring:get_luaentity() then
        esports_core.koth.placed_ring:remove()
    end
    esports_core.koth.placed_ring = nil

    local center = esports_storm.center or {x=0, y=0, z=0}
    local radius = esports_storm.current_radius or 100

    local attempts = 0
    local target_x, target_z
    while attempts < 100 do
        local angle = math.random() * math.pi * 2
        local dist = math.random() * (radius * 0.7) -- Keep it within the storm boundary
        target_x = math.floor(center.x + math.cos(angle) * dist + 0.5)
        target_z = math.floor(center.z + math.sin(angle) * dist + 0.5)

        -- Check if it is on the playable island surface
        local dist_to_island = math.sqrt(target_x^2 + target_z^2)
        if dist_to_island < 90 then
            break
        end
        attempts = attempts + 1
    end

    if not target_x then
        target_x = 0
        target_z = 0
    end

    esports_core.koth.hill_center = {x = target_x, y = 1.0, z = target_z}
    esports_core.koth.hill_owner = "none"
    esports_core.koth.contested = false
    esports_core.koth.timer = 60

    -- Spawn ring entity slightly above the ground to prevent z-fighting
    local pos = {x = target_x, y = 0.55, z = target_z}
    esports_core.koth.placed_ring = core.add_entity(pos, "esports_core:koth_ring")
    if esports_core.koth.placed_ring then
        esports_core.koth.placed_ring:set_properties({
            textures = {"esports_hud_bar.png^[colorize:#FFFFFF:150"} -- Unclaimed initially
        })
    end

    core.chat_send_all(">> KOTH: The Hill has rotated to (" .. target_x .. ", " .. target_z .. ")!")

    if esports_core.hud and esports_core.hud.update_scores then
        esports_core.hud.update_scores()
    end
end

function esports_core.koth.update(dtime)
    local center = esports_core.koth.hill_center
    if not center then return end

    local red_players = 0
    local blue_players = 0
    local red_names = {}
    local blue_names = {}

    for _, p in ipairs(core.get_connected_players()) do
        local pname = p:get_player_name()
        if not esports_core.is_spectator(pname) and p:get_hp() > 0 then
            local pos = p:get_pos()
            local dist = math.sqrt((pos.x - center.x)^2 + (pos.z - center.z)^2)
            -- Within 6 meters horizontally and 3 meters vertically
            if dist <= esports_core.koth.hill_radius and math.abs(pos.y - center.y) <= 3 then
                local team = esports_core.teams.get_player_team(pname)
                if team == "red" then
                    red_players = red_players + 1
                    table.insert(red_names, pname)
                elseif team == "blue" then
                    blue_players = blue_players + 1
                    table.insert(blue_names, pname)
                end
            end
        end
    end

    local new_owner = esports_core.koth.hill_owner
    local texture = "esports_hud_bar.png^[colorize:#FFFFFF:150"

    if red_players > 0 and blue_players == 0 then
        -- Red team uncontested control
        esports_core.teams.scores.red = esports_core.teams.scores.red + 1
        new_owner = "red"
        esports_core.koth.contested = false
        texture = "esports_hud_bar.png^[colorize:#FF3333:200"

        for _, pname in ipairs(red_names) do
            if not esports_core.match.player_stats[pname] then
                esports_core.match.player_stats[pname] = {kills = 0, deaths = 0, captures = 0, hill_time = 0}
            end
            esports_core.match.player_stats[pname].hill_time = (esports_core.match.player_stats[pname].hill_time or 0) + 1
        end

        if math.random() > 0.8 then
            for _, pname in ipairs(red_names) do
                core.sound_play("esports_pickup", {to_player = pname, gain = 0.5})
            end
        end
    elseif blue_players > 0 and red_players == 0 then
        -- Blue team uncontested control
        esports_core.teams.scores.blue = esports_core.teams.scores.blue + 1
        new_owner = "blue"
        esports_core.koth.contested = false
        texture = "esports_hud_bar.png^[colorize:#3333FF:200"

        for _, pname in ipairs(blue_names) do
            if not esports_core.match.player_stats[pname] then
                esports_core.match.player_stats[pname] = {kills = 0, deaths = 0, captures = 0, hill_time = 0}
            end
            esports_core.match.player_stats[pname].hill_time = (esports_core.match.player_stats[pname].hill_time or 0) + 1
        end

        if math.random() > 0.8 then
            for _, pname in ipairs(blue_names) do
                core.sound_play("esports_pickup", {to_player = pname, gain = 0.5})
            end
        end
    elseif red_players > 0 and blue_players > 0 then
        -- Contested Hill
        esports_core.koth.contested = true
        texture = "esports_hud_bar.png^[colorize:#FFFF33:200"
    else
        -- Unoccupied Hill
        esports_core.koth.contested = false
        if esports_core.koth.hill_owner == "red" then
            texture = "esports_hud_bar.png^[colorize:#FF8888:150"
        elseif esports_core.koth.hill_owner == "blue" then
            texture = "esports_hud_bar.png^[colorize:#8888FF:150"
        end
    end

    if new_owner ~= esports_core.koth.hill_owner then
        esports_core.koth.hill_owner = new_owner
        core.chat_send_all(">> KOTH: The Hill is now controlled by " .. new_owner:upper() .. "!")
    end

    if esports_core.koth.placed_ring and esports_core.koth.placed_ring:get_luaentity() then
        esports_core.koth.placed_ring:set_properties({
            textures = {texture}
        })
    end

    esports_core.koth.timer = esports_core.koth.timer - 1
    if esports_core.koth.timer <= 0 then
        esports_core.koth.spawn_new_hill()
    else
        if esports_core.hud and esports_core.hud.update_scores then
            esports_core.hud.update_scores()
        end
    end
end

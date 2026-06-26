tdm_storm = {}
tdm_storm.current_radius = 100
tdm_storm.target_radius = 120
tdm_storm.center = {x=0, y=0, z=0}
tdm_storm.placed_nodes = {}

-- Register the original gas node for compatibility/fallback
core.register_node("tdm_storm:gas", {
    description = "Storm Gas",
    drawtype = "glasslike",
    tiles = {"tdm_storm_gas.png"},
    use_texture_alpha = "blend",
    paramtype = "light",
    sunlight_propagates = true,
    walkable = false,
    pointable = false,
    diggable = false,
    climbable = false,
    buildable_to = true,
    is_ground_content = false,
    groups = {not_in_creative_inventory = 1},
    post_effect_color = {a = 100, r = 150, g = 0, b = 255}, -- Purple screen tint
})

-- Register the new highly-optimized long gas wall node
core.register_node("tdm_storm:gas_wall", {
    description = "Storm Gas Wall",
    drawtype = "nodebox",
    paramtype = "light",
    paramtype2 = "facedir",
    tiles = {"tdm_storm_gas.png"},
    use_texture_alpha = "blend",
    sunlight_propagates = true,
    walkable = false,
    pointable = false,
    diggable = false,
    climbable = false,
    buildable_to = true,
    is_ground_content = false,
    groups = {not_in_creative_inventory = 1},
    post_effect_color = {a = 100, r = 150, g = 0, b = 255}, -- Purple screen tint
    node_box = {
        type = "fixed",
        fixed = {
            -- A wall that is 1 block wide, 20 blocks high, and 10 blocks long
            {-0.5, -2.0, -5.0, 0.5, 18.0, 5.0}
        }
    }
})

function tdm_storm.randomize_center()
    local scale = tdm_core.match.current_map_scale or 1.0
    local angle = math.random() * math.pi * 2
    local dist = math.random() * (50 * scale) -- scaled distance from center
    tdm_storm.center = {
        x = math.floor(math.cos(angle) * dist + 0.5),
        y = 0,
        z = math.floor(math.sin(angle) * dist + 0.5)
    }
    core.log("action", "[TDM Storm] Randomized center to: " .. core.pos_to_string(tdm_storm.center))
end

-- Draw a highly-optimized square storm using long wall blocks
local function draw_square_storm(center, R)
    local old_nodes = tdm_storm.placed_nodes or {}
    
    -- 1. Clear old nodes
    for _, pos in ipairs(old_nodes) do
        local node = core.get_node(pos)
        if node.name == "tdm_storm:gas_wall" then
            core.set_node(pos, {name = "air"})
        end
    end
    tdm_storm.placed_nodes = {}
    
    -- If match is not active, don't draw new ones
    if tdm_core.match.state ~= "active" then
        return
    end

    local new_nodes = {}
    local Y = 1 -- Place at default ground/sea level

    local r_int = math.floor(R + 0.5)
    local min_x = center.x - r_int
    local max_x = center.x + r_int
    local min_z = center.z - r_int
    local max_z = center.z + r_int

    -- West & East walls (aligned with Z axis, param2 = 0)
    for z = min_z, max_z, 10 do
        -- West wall
        local pos_w = {x = min_x, y = Y, z = z}
        core.set_node(pos_w, {name = "tdm_storm:gas_wall", param2 = 0})
        table.insert(new_nodes, pos_w)
        
        -- East wall
        local pos_e = {x = max_x, y = Y, z = z}
        core.set_node(pos_e, {name = "tdm_storm:gas_wall", param2 = 0})
        table.insert(new_nodes, pos_e)
    end
    -- Ensure corner coverage at positive end
    if (max_z - min_z) % 10 ~= 0 then
        local pos_w_end = {x = min_x, y = Y, z = max_z}
        core.set_node(pos_w_end, {name = "tdm_storm:gas_wall", param2 = 0})
        table.insert(new_nodes, pos_w_end)
        
        local pos_e_end = {x = max_x, y = Y, z = max_z}
        core.set_node(pos_e_end, {name = "tdm_storm:gas_wall", param2 = 0})
        table.insert(new_nodes, pos_e_end)
    end

    -- North & South walls (aligned with X axis, param2 = 1)
    for x = min_x, max_x, 10 do
        -- South wall
        local pos_s = {x = x, y = Y, z = min_z}
        core.set_node(pos_s, {name = "tdm_storm:gas_wall", param2 = 1})
        table.insert(new_nodes, pos_s)
        
        -- North wall
        local pos_n = {x = x, y = Y, z = max_z}
        core.set_node(pos_n, {name = "tdm_storm:gas_wall", param2 = 1})
        table.insert(new_nodes, pos_n)
    end
    -- Ensure corner coverage at positive end
    if (max_x - min_x) % 10 ~= 0 then
        local pos_s_end = {x = max_x, y = Y, z = min_z}
        core.set_node(pos_s_end, {name = "tdm_storm:gas_wall", param2 = 1})
        table.insert(new_nodes, pos_s_end)
        
        local pos_n_end = {x = max_x, y = Y, z = max_z}
        core.set_node(pos_n_end, {name = "tdm_storm:gas_wall", param2 = 1})
        table.insert(new_nodes, pos_n_end)
    end
    
    tdm_storm.placed_nodes = new_nodes
end

local dtime_accumulator = 0

core.register_globalstep(function(dtime)
    dtime_accumulator = dtime_accumulator + dtime
    if dtime_accumulator < 1 then return end
    dtime_accumulator = dtime_accumulator - 1
    
    if tdm_core.match.state == "active" then
        -- Shrink logic (PVP TDM ONLY)
        if not tdm_core.match.is_pve and not tdm_core.match.is_ctf then
            local shrink_speed = 0.5 -- units per second
            local min_radius = 27 -- tightness of endgame
            
            if tdm_storm.current_radius > min_radius then
                tdm_storm.current_radius = tdm_storm.current_radius - shrink_speed
            end
        end
        
        -- Damage players outside
        if not tdm_storm.last_cough then tdm_storm.last_cough = {} end
        
        local current_center = tdm_storm.center
        local current_radius = tdm_storm.current_radius
        
        local min_x = current_center.x - current_radius
        local max_x = current_center.x + current_radius
        local min_z = current_center.z - current_radius
        local max_z = current_center.z + current_radius
        
        for _, player in ipairs(core.get_connected_players()) do
            local pname = player:get_player_name()
            local pos = player:get_pos()
            
            -- Check if outside the square bounds
            if pos.x < min_x or pos.x > max_x or pos.z < min_z or pos.z > max_z then
                -- Player is outside the storm
                if not tdm_core.is_spectator(pname) and player:get_hp() > 0 then
                    player:set_hp(player:get_hp() - 2)
                    
                    -- Play cough sound with 2s cooldown
                    local now = core.get_gametime()
                    local last = tdm_storm.last_cough[pname] or 0
                    if now - last >= 2 then
                        core.sound_play("tdm_cough", {pos = pos, gain = 1.0, max_hear_distance = 16})
                        tdm_storm.last_cough[pname] = now
                    end
                end
            end
        end
        
        -- Visualize storm bounds by placing optimized gas walls
        draw_square_storm(current_center, current_radius)
    else
        -- Reset and clear storm when not active
        if tdm_storm.current_radius ~= 100 or (tdm_storm.placed_nodes and #tdm_storm.placed_nodes > 0) then
            tdm_storm.current_radius = 100
            draw_square_storm(tdm_storm.center, 100) -- This will clear the old nodes since state is not active
        end
    end
end)

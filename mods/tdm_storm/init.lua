tdm_storm = {}
tdm_storm.current_radius = 100

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

tdm_storm.target_radius = 120
tdm_storm.center = {x=0, y=0, z=0}

function tdm_storm.randomize_center()
    local angle = math.random() * math.pi * 2
    local dist = math.random() * 50 -- within 50 blocks of center
    tdm_storm.center = {
        x = math.floor(math.cos(angle) * dist + 0.5),
        y = 0,
        z = math.floor(math.sin(angle) * dist + 0.5)
    }
    core.log("action", "[TDM Storm] Randomized center to: " .. core.pos_to_string(tdm_storm.center))
end

local dtime_accumulator = 0

core.register_globalstep(function(dtime)
    dtime_accumulator = dtime_accumulator + dtime
    if dtime_accumulator < 1 then return end
    dtime_accumulator = dtime_accumulator - 1
    
    if tdm_core.match.state == "active" and not tdm_core.match.is_pve then
        -- Shrink logic
        local shrink_speed = 0.5 -- units per second
        local min_radius = 30 -- Increased from 10
        
        if tdm_storm.current_radius > min_radius then
            tdm_storm.current_radius = tdm_storm.current_radius - shrink_speed
        end
        
        -- Damage players outside
        if not tdm_storm.last_cough then tdm_storm.last_cough = {} end
        
        for _, player in ipairs(core.get_connected_players()) do
            local pname = player:get_player_name()
            local pos = player:get_pos()
            local dist = math.sqrt((pos.x - tdm_storm.center.x)^2 + (pos.z - tdm_storm.center.z)^2)
            
            if dist > tdm_storm.current_radius then
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
        
        -- Visualize storm bounds by placing gas nodes
        local steps = math.floor(tdm_storm.current_radius * math.pi * 2)
        local step_size = 2 -- how often to place a column
        for i = 0, steps, step_size do
            local angle = (i / steps) * math.pi * 2
            local px = math.floor(tdm_storm.center.x + math.cos(angle) * tdm_storm.current_radius + 0.5)
            local pz = math.floor(tdm_storm.center.z + math.sin(angle) * tdm_storm.current_radius + 0.5)
            
            -- Place a vertical column of gas
            for py = -2, 15 do
                local rpos = {x=px, y=py, z=pz}
                local node = core.get_node(rpos)
                if node.name == "air" then
                    core.set_node(rpos, {name="tdm_storm:gas"})
                end
            end
        end
    else
        -- Reset storm when not active
        tdm_storm.current_radius = 100
    end
end)

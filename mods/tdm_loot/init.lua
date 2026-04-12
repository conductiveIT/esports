tdm_loot = {}

-- Register the Loot Box node
core.register_node("tdm_loot:box", {
    description = "Loot Crate",
    tiles = {"tdm_loot_box.png"},
    groups = {choppy = 2, oddly_breakable_by_hand = 2, loot_box = 1},
    on_punch = function(pos, node, puncher, pointed_thing)
        -- Random loot table
        local loot_options = {
            "tdm_weapons:assault_rifle",
            "tdm_weapons:shotgun",
            "tdm_weapons:rifle_ammo 10",
            "tdm_weapons:rifle_ammo 20",
            "tdm_weapons:shotgun_ammo 5",
            "tdm_weapons:shotgun_ammo 10",
            "tdm_weapons:health_pack",
        }
        
        local chosen_loot = loot_options[math.random(#loot_options)]
        
        -- Drop the item as an entity
        local drop_pos = {x = pos.x, y = pos.y, z = pos.z}
        core.add_item(drop_pos, chosen_loot)
        
        -- Play break sound
        core.sound_play("tdm_break_crate", {pos = pos, max_hear_distance = 16})
        
        -- Remove the crate
        core.remove_node(pos)
    end,
})

-- Spawning logic
local spawn_timer = 0
local MAX_BOXES = 40
local ISLAND_RADIUS = 100

core.register_globalstep(function(dtime)
    if not tdm_core or not tdm_core.match or tdm_core.match.state ~= "active" then
        return
    end

    spawn_timer = spawn_timer + dtime
    if spawn_timer >= 5 then
        spawn_timer = 0
        
        -- Count existing boxes to avoid clutter
        local boxes = core.find_nodes_in_area({x=-ISLAND_RADIUS, y=1, z=-ISLAND_RADIUS}, {x=ISLAND_RADIUS, y=1, z=ISLAND_RADIUS}, {"tdm_loot:box"})
        if #boxes < MAX_BOXES then
            -- Try to find a spawn spot
            for i = 1, 10 do -- try 10 times
                local x = math.random(-ISLAND_RADIUS, ISLAND_RADIUS)
                local z = math.random(-ISLAND_RADIUS, ISLAND_RADIUS)
                
                -- Check if within circular island bounds
                if math.sqrt(x*x + z*z) <= ISLAND_RADIUS then
                    local pos = {x=x, y=1, z=z}
                    local node_below = core.get_node({x=x, y=0, z=z}).name
                    local node_at = core.get_node(pos).name
                    
                    if node_below == "tdm_mapgen:grass" and node_at == "air" then
                        core.set_node(pos, {name = "tdm_loot:box"})
                        break
                    end
                end
            end
        end
    end
end)

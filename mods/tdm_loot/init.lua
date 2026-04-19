tdm_loot = {}
tdm_loot.crate_positions = {}
tdm_loot.box_count = 0

function tdm_loot.clear_cache()
    tdm_loot.crate_positions = {}
    tdm_loot.box_count = 0
end

-- Register the Loot Box node
core.register_node("tdm_loot:box", {
    description = "Loot Crate",
    tiles = {"tdm_loot_box.png"},
    groups = {choppy = 2, oddly_breakable_by_hand = 2, loot_box = 1},
    
    on_construct = function(pos)
        local hash = core.hash_node_position(pos)
        if not tdm_loot.crate_positions[hash] then
            tdm_loot.crate_positions[hash] = {x=pos.x, y=pos.y, z=pos.z}
            tdm_loot.box_count = tdm_loot.box_count + 1
        end
    end,
    
    after_destruct = function(pos, oldnode)
        local hash = core.hash_node_position(pos)
        if tdm_loot.crate_positions[hash] then
            tdm_loot.crate_positions[hash] = nil
            tdm_loot.box_count = tdm_loot.box_count - 1
        end
    end,

    on_punch = function(pos, node, puncher, pointed_thing)
        -- Safety check for puncher
        if not puncher or not puncher:is_player() then return end
        
        -- Random loot table (Bypassing spectator check for mobile/PC parity)
        
        -- Random loot table
        local loot_options = {
            "tdm_weapons:assault_rifle",
            "tdm_weapons:shotgun",
            "tdm_weapons:rifle_ammo 20",
            "tdm_weapons:shotgun_ammo 10",
            "tdm_weapons:health_pack",
        }
        
        local chosen_loot = loot_options[math.random(#loot_options)]
        core.add_item(pos, chosen_loot)
        core.sound_play("tdm_break_crate", {pos = pos, max_hear_distance = 16})
        core.remove_node(pos)
    end,

    on_dig = function(pos, node, digger)
        -- Instant dig for crates
        local n_def = core.registered_nodes[node.name]
        if n_def and n_def.on_punch then
            n_def.on_punch(pos, node, digger)
        end
        return false 
    end,
    on_rightclick = function(pos, node, clicker, itemstack, pointed_thing)
        -- Support for mobile "Tap to Interact"
        local n_def = core.registered_nodes[node.name]
        if n_def and n_def.on_punch then
            n_def.on_punch(pos, node, clicker)
        end
    end,
})

-- GLOBAL PUNCH HOOK (Definitive interaction fix)
core.register_on_punchnode(function(pos, node, puncher)
    if not puncher:is_player() then return end
    if node.name == "tdm_loot:box" then
        local n_def = core.registered_nodes[node.name]
        if n_def and n_def.on_punch then
            n_def.on_punch(pos, node, puncher)
        end
    end
end)

-- Spawning logic
local spawn_timer = 0
local ISLAND_RADIUS = 100

-- Dynamically calculate combatants (Players + Bots)
local function get_combatant_count()
    local count = 0
    -- Count Players
    for _, p in ipairs(core.get_connected_players()) do
        if not tdm_core.is_spectator(p:get_player_name()) then
            count = count + 1
        end
    end
    -- Count Bots (Sentry entities)
    for _, obj in pairs(core.object_refs) do
        local ent = obj:get_luaentity()
        if ent and ent.name == "tdm_core:bot" then
            count = count + 1
        end
    end
    return math.max(1, count)
end

core.register_globalstep(function(dtime)
    if not tdm_core or not tdm_core.match or tdm_core.match.state ~= "active" then
        return
    end

    spawn_timer = spawn_timer + dtime
    
    local combatants = get_combatant_count()
    local dynamic_interval = math.max(1, 6 - (combatants * 0.5))
    local dynamic_max = combatants * 8
    
    if spawn_timer >= dynamic_interval then
        spawn_timer = 0
        
        -- Use optimized count instead of find_nodes_in_area
        if tdm_loot.box_count < dynamic_max then
            -- Try to find a spawn spot within the Storm's Safe Zone
            local storm_center = tdm_storm.center
            local storm_radius = tdm_storm.current_radius
            
            for i = 1, 15 do -- increased attempts to find valid island ground
                local angle = math.random() * math.pi * 2
                local dist = math.random() * (storm_radius * 0.9) -- Spawn within 90% of radius to be safe
                local x = math.floor(storm_center.x + math.cos(angle) * dist + 0.5)
                local z = math.floor(storm_center.z + math.sin(angle) * dist + 0.5)
                
                -- Check if also within circular island bounds (Don't spawn in ocean)
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

core.register_node("tdm_mapgen:grass", {
    description = "Grass",
    tiles = {"tdm_mapgen_grass.png"},
    groups = {crumbly = 3, soil = 1},
})

core.register_node("tdm_mapgen:dirt", {
    description = "Dirt",
    tiles = {"tdm_mapgen_dirt.png"},
    groups = {crumbly = 3, soil = 1},
})

core.register_node("tdm_mapgen:stone", {
    description = "Stone",
    tiles = {"tdm_mapgen_stone.png"},
    groups = {cracky = 3, stone = 1},
})

local c_grass = core.get_content_id("tdm_mapgen:grass")
local c_dirt = core.get_content_id("tdm_mapgen:dirt")
local c_stone = core.get_content_id("tdm_mapgen:stone")
local c_air = core.CONTENT_AIR

core.register_on_generated(function(minp, maxp, seed)
    -- We only want to generate an island near the center
    if maxp.y < -20 or minp.y > 20 then
        return
    end
    
    local map_size = 100
    
    local vm, emin, emax = core.get_mapgen_object("voxelmanip")
    local data = vm:get_data()
    local area = VoxelArea:new{MinEdge=emin, MaxEdge=emax}
    
    for z = minp.z, maxp.z do
        for y = minp.y, maxp.y do
            for x = minp.x, maxp.x do
                local vi = area:index(x, y, z)
                
                -- Check if within island radius
                local dist = math.sqrt(x*x + z*z)
                if dist <= map_size then
                    if y == 0 then
                        data[vi] = c_grass
                    elseif y > -5 and y < 0 then
                        data[vi] = c_dirt
                    elseif y <= -5 and y > -20 then
                        data[vi] = c_stone
                    end
                end
            end
        end
    end
    
    vm:set_data(data)
    vm:calc_lighting()
    vm:write_to_map(data)
end)

tdm_mapgen = {}

-- Function to reset the island to its base state
function tdm_mapgen.reset_island()
    core.log("action", "[TDM Mapgen] Resetting island for a new session...")
    
    -- Clear internal caches
    if tdm_loot and tdm_loot.clear_cache then
        tdm_loot.clear_cache()
    end
    
    -- 1. Clear all items and entities on the island
    core.clear_objects({mode = "full"})
    
    -- 2. WIPE the island nodes back to their default state
    local map_radius = 110 -- slightly larger than island to be sure
    local minp = {x=-map_radius, y=-20, z=-map_radius}
    local maxp = {x=map_radius, y=20, z=map_radius}
    
    local vm = VoxelManip()
    local emin, emax = vm:read_from_map(minp, maxp)
    
    local area = VoxelArea:new{MinEdge=emin, MaxEdge=emax}
    local data = vm:get_data()
    
    local c_grass = core.get_content_id("tdm_mapgen:grass")
    local c_dirt = core.get_content_id("tdm_mapgen:dirt")
    local c_stone = core.get_content_id("tdm_mapgen:stone")
    local c_air = core.CONTENT_AIR
    
    for z = minp.z, maxp.z do
        for y = minp.y, maxp.y do
            for x = minp.x, maxp.x do
                local vi = area:index(x, y, z)
                local dist = math.sqrt(x*x + z*z)
                
                if dist <= 100 then -- Island radius
                    if y == 0 then
                        data[vi] = c_grass
                    elseif y > -5 and y < 0 then
                        data[vi] = c_dirt
                    elseif y <= -5 and y >= -20 then
                        data[vi] = c_stone
                    else
                        data[vi] = c_air
                    end
                else
                    -- Outside island radius, just air
                    data[vi] = c_air
                end
            end
        end
    end
    
    vm:set_data(data)
    vm:calc_lighting()
    vm:write_to_map()
    core.log("action", "[TDM Mapgen] Map reset complete!")
end

-- Reset the map on startup
core.after(0, function()
    tdm_mapgen.reset_island()
end)

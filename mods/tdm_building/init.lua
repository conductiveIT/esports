-- Wooden Player Wall
core.register_node("tdm_building:player_wall", {
    description = "Player Wall",
    tiles = {"tdm_building_wood.png"},
    groups = {choppy = 2, oddly_breakable_by_hand = 2, player_built = 1},
    paramtype2 = "facedir",
})

-- Wooden Player Ramp (Stairs)
core.register_node("tdm_building:player_ramp", {
    description = "Player Ramp",
    drawtype = "mesh",
    -- For now use a nodebox approximation of a ramp
    drawtype = "nodebox",
    paramtype = "light",
    paramtype2 = "facedir",
    tiles = {"tdm_building_wood.png"},
    node_box = {
        type = "fixed",
        fixed = {
            {-0.5, -0.5, -0.5, 0.5, 0.0, 0.5},
            {-0.5, 0.0, 0.0, 0.5, 0.5, 0.5},
        },
    },
    groups = {choppy = 2, oddly_breakable_by_hand = 2, player_built = 1},
})

-- Blueprints
local function place_structure(itemstack, user, pointed_thing, node_name)
    if pointed_thing.type ~= "node" then return itemstack end
    
    local pos = pointed_thing.above
    if pos.y >= 10 then
        core.chat_send_player(user:get_player_name(), "Height limit reached! Max build height is 10 blocks.")
        return itemstack
    end
    
    local ppos = user:get_pos()
    
    -- basic facedir calc
    local dir = user:get_look_dir()
    local angle = math.atan2(dir.z, dir.x)
    local facedir = core.dir_to_facedir(dir)
    
    core.set_node(pos, {name = node_name, param2 = facedir})
    -- Instant placement sound
    core.sound_play("tdm_build", {pos = pos, max_hear_distance = 16})
    return itemstack
end

core.register_tool("tdm_building:blueprint_wall", {
    description = "Wall Blueprint",
    inventory_image = "tdm_building_blueprint_wall.png",
    on_use = function(itemstack, user, pointed_thing)
        return place_structure(itemstack, user, pointed_thing, "tdm_building:player_wall")
    end,
})

core.register_tool("tdm_building:blueprint_ramp", {
    description = "Ramp Blueprint",
    inventory_image = "tdm_building_blueprint_ramp.png",
    on_use = function(itemstack, user, pointed_thing)
        return place_structure(itemstack, user, pointed_thing, "tdm_building:player_ramp")
    end,
})

-- Give starting items
core.register_on_joinplayer(function(player)
    local inv = player:get_inventory()
    inv:set_size("main", 8 * 4)
    inv:set_list("main", {}) -- Clear inventory to remove old items
    inv:add_item("main", "tdm_weapons:pickaxe")
    inv:add_item("main", "tdm_building:blueprint_wall")
    inv:add_item("main", "tdm_building:blueprint_ramp")
end)

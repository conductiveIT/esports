esports_core.skins = {}

-- Initialize the player to use the 3D model
core.register_on_joinplayer(function(player)
    player:set_properties({
        mesh = "character.b3d",
        textures = {"character.png"}, -- initial default
        visual = "mesh",
        visual_size = {x=1, y=1},
        collisionbox = {-0.3, 0.0, -0.3, 0.3, 1.7, 0.3},
        stepheight = 0.6,
        eye_height = 1.47,
    })
    -- Apply selected skin immediately
    esports_core.skins.apply(player, nil)
end)

function esports_core.skins.apply(player, color_hex)
    if not player or not player:is_player() then return end
    
    local meta = player:get_meta()
    local base_skin = meta:get_string("esports_selected_skin")
    if not base_skin or base_skin == "" then
        base_skin = "character.png"
    end
    
    if not color_hex or color_hex == "" then
        player:set_properties({ textures = {base_skin} })
    else
        -- Apply a translucent color tint over the selected base skin
        -- Use a composite texture to ensure the base skin detail remains visible
        player:set_properties({
            textures = {base_skin .. "^[colorize:" .. color_hex .. ":120"}
        })
    end
end

-- Command to swap skins (Useful for testing)
core.register_chatcommand("skin", {
    params = "reset|#RRGGBB",
    description = "Tint your character skin",
    privs = {server = true},
    func = function(name, param)
        local player = core.get_player_by_name(name)
        if not player then return false, "Player not found." end
        
        if param == "reset" then
            esports_core.skins.apply(player, nil)
            return true, "Skin reset to default!"
        elseif param:match("^#%x%x%x%x%x%x$") then
            esports_core.skins.apply(player, param)
            return true, "Skin tinted to " .. param .. "!"
        else
            return false, "Invalid format. Try /skin reset or /skin #ff0000"
        end
    end
})

-- LOCKER PREVIEW NODES (Self-Lit Scaled Icons)-- STUDIO LIGHT NODE (eSports High-Altitude Lighting)
core.register_node("esports_core:studio_light", {
    description = "Studio Light",
    drawtype = "glasslike",
    tiles = {"esports_hud_bar.png^[colorize:#ffffff:200"},
    use_texture_alpha = "clip",
    light_source = 14,
    sunlight_propagates = true,
    groups = {not_in_creative_inventory = 1},
    walkable = false,
    pointable = false,
})
local preview_skins = {
    {id = "sam", file = "character.png"},
    {id = "elite", file = "skin_1.png"},
    {id = "recon", file = "skin_2.png"},
    {id = "infil", file = "skin_3.png"},
}

for _, s in ipairs(preview_skins) do
    core.register_node("esports_core:locker_" .. s.id, {
        description = "Locker Icon " .. s.id,
        drawtype = "mesh",
        mesh = "character.b3d",
        tiles = {{name = s.file, glow = 31}}, -- Fullbright emissive texture
        visual_scale = 0.4, -- Scaled down to fit full body in square icon
        light_source = 14,
        groups = {not_in_creative_inventory = 1},
        walkable = false,
        pointable = false,
        -- Full-body selection box ensures the item icon zooms out to show head-to-toe
        selection_box = {
            type = "fixed",
            fixed = {-0.3, 0.0, -0.3, 0.3, 1.9, 0.3}
        },
        collision_box = {type = "none"},
        paramtype = "light",
    })
end


tdm_core = {}
local modpath = core.get_modpath("tdm_core")

dofile(modpath .. "/teams.lua")
dofile(modpath .. "/hud.lua")
dofile(modpath .. "/match.lua")
dofile(modpath .. "/spectator.lua")
dofile(modpath .. "/bots.lua")

dofile(modpath .. "/player_anim.lua")
dofile(modpath .. "/skins.lua")
dofile(modpath .. "/lobby.lua")
dofile(modpath .. "/ctf.lua")

-- High-Performance Combat Settings for Hands (Testing & Gameplay)
core.override_item("", {
    tool_capabilities = {
        full_punch_interval = 0.5, -- Faster response between hits
        max_drop_level = 0,
        groupcaps = {
            fleshy = {times={[1]=2.0, [2]=0.8, [3]=0.4}, uses=0, maxlevel=1},
        },
        damage_groups = {fleshy = 10}, -- Significant damage increase
    }
})

-- Cache for existing custom logos (Populated on startup)
tdm_core.registered_logos = {}
local tx_path = core.get_modpath("tdm_core") .. "/textures"
local files = core.get_dir_list(tx_path, false)
if files then
    for _, f in ipairs(files) do
        -- Store both as-is and lowercase for robust matching
        tdm_core.registered_logos[f:lower()] = f
    end
end

-- Helper to resolve dynamic team logos with automatic detection
function tdm_core.get_team_logo(teamname, fallback)
    local def_logo = fallback or "tdm_logo_red.png"
    if not teamname or teamname == "" or teamname == "NONE" or teamname == "No teams registered" then
        return def_logo
    end

    local lower_name = teamname:lower()
    -- Special case for default tactical team names
    if lower_name == "red" then return "tdm_logo_red.png" end
    if lower_name == "blue" then return "tdm_logo_blue.png" end
    if lower_name == "bots" then return "tdm_logo_red.png" end

    -- Sanitize: lowercase and replace spaces with underscores
    local clean = lower_name:gsub("%s+", "_"):gsub("[^%w_]", "")
    local target_file = clean .. "_logo.png"

    -- Check if we actually have this file in our textures folder
    if tdm_core.registered_logos[target_file] then
        return tdm_core.registered_logos[target_file]
    end

    -- Real-time Fallback: Use the default if the file is missing
    return def_logo
end

-- Increase player movement speed and jump height for a more energetic feel
core.register_on_joinplayer(function(player)
    local name = player:get_player_name()
    -- Grant essential privileges for gameplay (Force-Enable)
    local privs = core.get_player_privs(name)
    privs.interact = true
    privs.shout = true
    privs.zoom = true
    core.set_player_privs(name, privs)
    
    -- Physics and interact distance are now handled per-state in match.lua
end)

-- CTF ASSETS: Flag Stands and Carrying Entity
core.register_node("tdm_core:flag_stand_red", {
    description = "Red Flag Stand",
    drawtype = "mesh",
    mesh = "character.b3d", -- Temporary: Use character mesh scaled down as a flag pole
    tiles = {{name = "tdm_logo_red.png", glow = 14}},
    groups = {not_in_creative_inventory = 1, flag_stand = 1},
    visual_scale = 0.5,
    selection_box = {type = "fixed", fixed = {-0.3, 0, -0.3, 0.3, 1.5, 0.3}},
    walkable = false,
    light_source = 10,
    paramtype = "light",
})

core.register_node("tdm_core:flag_stand_blue", {
    description = "Blue Flag Stand",
    drawtype = "mesh",
    mesh = "character.b3d",
    tiles = {{name = "tdm_logo_blue.png", glow = 14}},
    groups = {not_in_creative_inventory = 1, flag_stand = 1},
    visual_scale = 0.5,
    selection_box = {type = "fixed", fixed = {-0.3, 0, -0.3, 0.3, 1.5, 0.3}},
    walkable = false,
    light_source = 10,
    paramtype = "light",
})

-- The actual flag that appears on your back
core.register_entity("tdm_core:flag_carrier_visual", {
    initial_properties = {
        visual = "mesh",
        mesh = "character.b3d",
        textures = {"tdm_logo_red.png"}, -- changed dynamically
        visual_size = {x=0.2, y=0.5, z=0.2},
        physical = false,
        pointable = false,
        glow = 14,
    },
    on_activate = function(self, staticdata)
        if staticdata ~= "" then
            self.object:set_properties({textures = {staticdata}})
        end
    end,
})

-- Visual indicator for where to bring the flag
core.register_entity("tdm_core:capture_ring", {
    initial_properties = {
        visual = "mesh",
        mesh = "character.b3d", -- Temporary: Use flat circle if possible, but mesh with scale works
        textures = {"tdm_hud_bar.png^[colorize:#FFFF00:150"}, -- Glowing yellow circle
        visual_size = {x=2, y=0.1, z=2},
        physical = false,
        pointable = false,
        glow = 14,
        static_save = false,
    },
})

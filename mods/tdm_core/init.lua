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

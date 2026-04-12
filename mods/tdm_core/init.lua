tdm_core = {}
local modpath = core.get_modpath("tdm_core")

dofile(modpath .. "/teams.lua")
dofile(modpath .. "/hud.lua")
dofile(modpath .. "/match.lua")
dofile(modpath .. "/spectator.lua")
dofile(modpath .. "/bots.lua")

dofile(modpath .. "/player_anim.lua")
dofile(modpath .. "/skins.lua")

-- Increase player movement speed and jump height for a more energetic feel
core.register_on_joinplayer(function(player)
    player:set_physics_override({
        speed = 1.5,
        jump = 1.2,
        gravity = 1.0
    })
end)

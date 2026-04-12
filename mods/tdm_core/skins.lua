tdm_core.skins = {}

-- Initialize the player to use the 3D model
core.register_on_joinplayer(function(player)
    player:set_properties({
        mesh = "character.b3d",
        textures = {"skin_1.png"}, -- default skin
        visual = "mesh",
        visual_size = {x=1, y=1},
        collisionbox = {-0.3, 0.0, -0.3, 0.3, 1.7, 0.3},
        stepheight = 0.6,
        eye_height = 1.47,
    })
end)

-- Command to swap skins
core.register_chatcommand("skin", {
    params = "<1|2|3>",
    description = "Change your character's skin (options: 1, 2, 3)",
    func = function(name, param)
        local player = core.get_player_by_name(name)
        if not player then return false, "Player not found." end
        
        if param == "1" or param == "2" or param == "3" then
            player:set_properties({
                textures = {"skin_" .. param .. ".png"}
            })
            return true, "Skin updated to option " .. param .. "!"
        else
            return false, "Invalid skin. Try /skin 1, /skin 2, or /skin 3."
        end
    end
})

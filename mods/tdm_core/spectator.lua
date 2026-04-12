tdm_core.spectators = {} -- name -> {target = "playerName" or nil}

function tdm_core.is_spectator(name)
    return tdm_core.spectators[name] ~= nil
end

-- COMMANDS
core.register_chatcommand("spectate", {
    params = "<name>",
    description = "Toggle spectator mode for a player (Admin only)",
    privs = {server = true},
    func = function(name, param)
        local target_name = param == "" and name or param
        local player = core.get_player_by_name(target_name)
        if not player then return false, "Player not found." end
        
        if tdm_core.spectators[target_name] then
            -- Disable Spectator Mode
            tdm_core.spectators[target_name] = nil
            player:set_properties({visual_size = {x=1, y=1, z=1}})
            player:set_nametag_attributes({color = {a=255, r=255, g=255, b=255}})
            
            -- Restore HUD
            player:hud_set_flags({hotbar = true, healthbar = true, breathbar = true, chat = true})
            
            -- Remove privs and restore physics
            player:set_physics_override({gravity = 1.0, speed = 1.5, jump = 1.2})
            local privs = core.get_player_privs(target_name)
            privs.fly = nil
            privs.noclip = nil
            privs.fast = nil
            core.set_player_privs(target_name, privs)
            
            core.chat_send_player(target_name, "Spectator mode disabled.")
            tdm_core.hud.init_hud(player)
            return true, "Spectator mode disabled for " .. target_name
        else
            -- Enable Spectator Mode
            tdm_core.spectators[target_name] = {target = nil}
            player:set_properties({visual_size = {x=0, y=0, z=0}})
            tdm_core.teams.update_nametag(player)
            player:set_physics_override({gravity = 1.0, speed = 2.0})
            
            -- Hide HUD for cinematic view
            player:hud_set_flags({hotbar = false, healthbar = false, breathbar = false, chat = false})
            
            -- Grant privs
            local privs = core.get_player_privs(target_name)
            privs.fly = true
            privs.noclip = true
            privs.fast = true
            core.set_player_privs(target_name, privs)
            
            -- Clear from any active match team
            if tdm_core.teams then
                tdm_core.teams.players[target_name] = nil
            end
            
            core.chat_send_player(target_name, "Spectator mode enabled! Use /follow <name> or /follow off")
            tdm_core.hud.init_hud(player)
            return true, "Spectator mode enabled for " .. target_name
        end
    end
})

core.register_chatcommand("follow", {
    params = "<target_name> | off",
    description = "Follow a player cinematically (Spectator only)",
    func = function(name, param)
        if not tdm_core.spectators[name] then
            return false, "You must be in /spectate mode to use this."
        end
        
        if param == "off" then
            tdm_core.spectators[name].target = nil
            return true, "Stopped following."
        end
        
        local target = core.get_player_by_name(param)
        if not target then return false, "Target player not found." end
        if target:get_player_name() == name then return false, "Cannot follow yourself." end
        
        tdm_core.spectators[name].target = param
        return true, "Now following " .. param .. " cinematically."
    end
})

-- CHAT SUPPRESSION
core.register_on_chat_message(function(name, message)
    if tdm_core.spectators[name] then
        core.chat_send_player(name, "Spectators cannot talk in chat.")
        return true -- Block message
    end
end)

-- CINEMATIC UPDATE
core.register_globalstep(function(dtime)
    for spec_name, data in pairs(tdm_core.spectators) do
        local spectator = core.get_player_by_name(spec_name)
        if spectator then
            if data.target then
                local target = core.get_player_by_name(data.target)
                if target then
                    -- If not already attached, perform the high-sync attachment
                    if not spectator:get_attach() then
                        -- Attach exactly at target center (0,0,0)
                        spectator:set_attach(target, "", {x=0, y=0, z=0}, {x=0, y=0, z=0})
                        
                        -- Shift the CAMERA (not the body) over the shoulder
                        -- Units for eye_offset are nodes * 10. 
                        -- X=7 (right), Y=15 (height), Z=-25 (back)
                        spectator:set_eye_offset({x=7, y=15, z=-25}, {x=7, y=15, z=-25})
                        
                        -- Ensure spectator is invisible
                        spectator:set_properties({visual_size = {x=0, y=0, z=0}})
                    end
                    
                    -- Keep rotation in sync with target
                    spectator:set_look_horizontal(target:get_look_horizontal())
                    spectator:set_look_vertical(target:get_look_vertical())
                else
                    data.target = nil
                end
            else
                -- Not following, clean up attachment and eye offset
                if spectator:get_attach() then
                    spectator:set_detach()
                    spectator:set_eye_offset({x=0, y=0, z=0}, {x=0, y=0, z=0})
                end
            end
        end
    end
end)

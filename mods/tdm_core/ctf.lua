tdm_core.ctf = {}
tdm_core.ctf.bases = {
    red = {x = 80, y = 1, z = 0},
    blue = {x = -80, y = 1, z = 0}
}
tdm_core.ctf.states = {red = "home", blue = "home"}
tdm_core.ctf.carriers = {red = nil, blue = nil} -- Red flag carried by...
tdm_core.ctf.visuals = {} -- pname -> entity_ref
tdm_core.ctf.rings = {} -- list of entity refs

function tdm_core.ctf.reset()
    -- Clear physical nodes at old base locations
    for _, pos in pairs(tdm_core.ctf.bases) do
        core.remove_node(pos)
    end

    tdm_core.ctf.states = {red = "home", blue = "home"}
    tdm_core.ctf.carriers = {red = nil, blue = nil}
    for pname, ent in pairs(tdm_core.ctf.visuals) do
        if ent and ent:get_luaentity() then ent:remove() end
    end
    tdm_core.ctf.visuals = {}
    
    for _, ent in ipairs(tdm_core.ctf.rings) do
        if ent and ent:get_luaentity() then ent:remove() end
    end
    tdm_core.ctf.rings = {}
    
    -- Clean up all other artifacts in world
    core.clear_objects({mode = "full"})
    
    -- Universal Combat Reset: Ensure no one is left with a shadow flag lockout
    for _, player in ipairs(core.get_connected_players()) do
        player:get_meta():set_int("has_flag", 0)
    end
end

function tdm_core.ctf.spawn_flags()
    for team, pos in pairs(tdm_core.ctf.bases) do
        local node = (team == "red") and "tdm_core:flag_stand_red" or "tdm_core:flag_stand_blue"
        core.set_node(pos, {name = node})
        
        -- Spawn Capture Ring
        local ring_pos = {x=pos.x, y=pos.y - 0.45, z=pos.z}
        local ent = core.add_entity(ring_pos, "tdm_core:capture_ring")
        if ent then
            ent:set_properties({textures = {(team == "red") and "tdm_hud_bar.png^[colorize:#FF4444:150" or "tdm_hud_bar.png^[colorize:#4444FF:150"}})
            table.insert(tdm_core.ctf.rings, ent)
        end
    end
end

function tdm_core.ctf.get_carrier(team)
    return tdm_core.ctf.carriers[team]
end

-- Returns true if the node punched should be removed
function tdm_core.ctf.pickup(player, flag_team)
    local pname = player:get_player_name()
    local p_side = tdm_core.match.get_player_match_side(pname)
    
    if not p_side then return false end
    
    if p_side == flag_team then
        -- Punched own flag
        if tdm_core.ctf.states[flag_team] == "dropped" then
            tdm_core.ctf.return_home(flag_team)
            core.chat_send_all("LOBBY: " .. pname .. " returned the " .. flag_team:upper() .. " flag!")
            return true -- Remove the dropped node
        elseif tdm_core.ctf.states[flag_team] == "home" then
            -- Attempting to SCORE
            local enemy_team = (p_side == "red") and "blue" or "red"
            if tdm_core.ctf.carriers[enemy_team] == pname then
                tdm_core.ctf.score(pname, p_side)
                -- Node stays at home
            end
        else
            -- Flag is CARRIED (not home, not dropped)
            local enemy_team = (p_side == "red") and "blue" or "red"
            if tdm_core.ctf.carriers[enemy_team] == pname then
                core.chat_send_player(pname, core.colorize("#FF4444", "TACTICAL ALERT: You cannot score while your own flag is compromised! Recover it first!"))
                core.sound_play("tdm_deny", {pos = player:get_pos(), gain = 1.0})
            end
        end
        return false -- Don't remove own flag stand at home
    end
    
    -- Punched enemy flag
    if tdm_core.ctf.states[flag_team] == "home" or tdm_core.ctf.states[flag_team] == "dropped" then
        -- Pick up!
        tdm_core.ctf.states[flag_team] = "carried"
        tdm_core.ctf.carriers[flag_team] = pname
        
        -- Visual Attachment
        local visual = core.add_entity(player:get_pos(), "tdm_core:flag_carrier_visual", (flag_team == "red") and "tdm_logo_red.png" or "tdm_logo_blue.png")
        visual:set_attach(player, "", {x=0, y=10, z=-2}, {x=0, y=0, z=0})
        tdm_core.ctf.visuals[pname] = visual
        
        -- Player Meta / Speed Penalty
        local meta = player:get_meta()
        meta:set_int("has_flag", 1)
        player:set_physics_override({speed = 0.9})
        
        core.chat_send_all("LOBBY: " .. flag_team:upper() .. " flag taken by " .. pname .. "!")
        core.sound_play("tdm_pickup", {pos = player:get_pos(), gain = 1.0})
        tdm_core.hud.update_scores()
        return true -- Remove the node (home or dropped)
    end
    
    return false
end

function tdm_core.ctf.drop(player)
    local pname = player:get_player_name()
    
    for team, carrier in pairs(tdm_core.ctf.carriers) do
        if carrier == pname then
            tdm_core.ctf.carriers[team] = nil
            tdm_core.ctf.states[team] = "dropped"
            
            local pos = player:get_pos()
            pos.y = pos.y + 0.5
            local node = (team == "red") and "tdm_core:flag_stand_red" or "tdm_core:flag_stand_blue"
            core.set_node(pos, {name = node})
            
            -- Clean up visual
            if tdm_core.ctf.visuals[pname] then
                tdm_core.ctf.visuals[pname]:remove()
                tdm_core.ctf.visuals[pname] = nil
            end
            
            -- Clear Meta
            player:get_meta():set_int("has_flag", 0)
            player:set_physics_override({speed = 1.2})
            
            core.chat_send_all("LOBBY: " .. team:upper() .. " flag dropped!")
            tdm_core.hud.update_scores()
            
            -- Auto-return timer
            local f_team = team
            core.after(30, function()
                if tdm_core.ctf.states[f_team] == "dropped" then
                    tdm_core.ctf.return_home(f_team)
                    core.chat_send_all("LOBBY: The " .. f_team .. " flag has auto-returned to base.")
                end
            end)
        end
    end
end

function tdm_core.ctf.return_home(team)
    tdm_core.ctf.states[team] = "home"
    tdm_core.ctf.carriers[team] = nil
    
    -- Ensure base node exists
    core.set_node(tdm_core.ctf.bases[team], {name = (team == "red") and "tdm_core:flag_stand_red" or "tdm_core:flag_stand_blue"})
end

function tdm_core.ctf.score(pname, team)
    local enemy_team = (team == "red") and "blue" or "red"
    
    -- Score point
    tdm_core.teams.scores[team] = tdm_core.teams.scores[team] + 1
    tdm_core.match.add_capture(pname)
    core.chat_send_all("LOBBY: " .. pname .. " CAPTURED the " .. enemy_team:upper() .. " flag!")
    core.sound_play("tdm_pickup", {pos = core.get_player_by_name(pname):get_pos(), gain = 2.0})
    
    -- Reset flags
    tdm_core.ctf.return_home(enemy_team)
    
    -- Clean up carrier visual and meta
    local player = core.get_player_by_name(pname)
    if player then
        player:get_meta():set_int("has_flag", 0)
        player:set_physics_override({speed = 1.2})
        if tdm_core.ctf.visuals[pname] then
            tdm_core.ctf.visuals[pname]:remove()
            tdm_core.ctf.visuals[pname] = nil
        end
    end
    
    tdm_core.hud.update_scores()
    
    -- Win condition check
    if tdm_core.teams.scores[team] >= 5 then
        tdm_core.match.state = "over"
    end
end

-- INTERACTION HOOKS
core.register_on_punchnode(function(pos, node, puncher, pointed_thing)
    if not tdm_core.match.is_ctf then return end
    
    if node.name == "tdm_core:flag_stand_red" then
        if tdm_core.ctf.pickup(puncher, "red") then
            core.remove_node(pos)
        end
    elseif node.name == "tdm_core:flag_stand_blue" then
        if tdm_core.ctf.pickup(puncher, "blue") then
            core.remove_node(pos)
        end
    end
end)

core.register_on_dieplayer(function(player)
    if tdm_core.match.is_ctf then
        tdm_core.ctf.drop(player)
    end
end)

-- NO-BUILD ZONE PROTECTION
local function is_near_flag(pos)
    local scale = tdm_core.match.current_map_scale or 1.0
    for team, base_pos in pairs(tdm_core.ctf.bases) do
        local d = vector.distance(pos, base_pos)
        if d < (30 * scale) then return true, team end
    end
    return false
end

core.register_on_placenode(function(pos, newnode, placer, oldnode, itemstack, pointed_thing)
    if not tdm_core.match.is_ctf then return end
    if not placer or not placer:is_player() then return end
    
    local pname = placer:get_player_name()
    if core.check_player_privs(pname, {server=true}) or core.check_player_privs(pname, {admin=true}) then
        return -- Admin bypass
    end
    
    if is_near_flag(pos) then
        core.chat_send_player(pname, core.colorize("#FF4444", "STRATEGIC OVERRIDE: Building is prohibited within 30m of a flag objective!"))
        -- To prevent the block from staying, we return true to "cancel" the place if the engine supports it,
        -- but on_placenode is often called AFTER placement. The robust way is to swap it back.
        core.set_node(pos, oldnode)
        return true
    end
end)

core.register_on_dignode(function(pos, oldnode, digger)
    if not tdm_core.match.is_ctf then return end
    if not digger or not digger:is_player() then return end
    
    local pname = digger:get_player_name()
    if core.check_player_privs(pname, {server=true}) or core.check_player_privs(pname, {admin=true}) then
        return -- Admin bypass
    end
    
    if is_near_flag(pos) then
        core.chat_send_player(pname, core.colorize("#FF4444", "STRATEGIC OVERRIDE: Modification is prohibited within 30m of a flag objective!"))
        -- Restore the node
        core.set_node(pos, oldnode)
        return true
    end
end)

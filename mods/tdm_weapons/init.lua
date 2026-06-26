tdm_weapons = {}
tdm_weapons.cooldowns = {} -- player_name -> timer

-- Initialize ammo stash on join
core.register_on_joinplayer(function(player)
    local inv = player:get_inventory()
    inv:set_size("ammo", 8)
end)

-- Simple globalstep to handle cooldowns
local dtime_acc = 0
core.register_globalstep(function(dtime)
    for p_name, cd in pairs(tdm_weapons.cooldowns) do
        if cd > 0 then
            tdm_weapons.cooldowns[p_name] = cd - dtime
        end
    end
end)

-- [x] Update `tdm_weapons.shoot_raycast` to handle node impacts
-- [x] Implement node-based HP tracking using metadata
-- [x] Add destruction sound and particle effects
-- [/] Calibrate weapon damage (Rifle: 10, Shotgun: 2.5)
-- [ ] Verify functionality against walls and ramps

tdm_weapons.shoot_raycast = function(player, damage, range, spread)
    local p_name = player:get_player_name()
    if tdm_core.is_spectator(p_name) then return false end
    
    local dir = player:get_look_dir()
    local pos = player:get_pos()
    pos.y = pos.y + player:get_properties().eye_height
    
    -- Apply spread
    if spread > 0 then
        dir.x = dir.x + (math.random() - 0.5) * spread
        dir.y = dir.y + (math.random() - 0.5) * spread
        dir.z = dir.z + (math.random() - 0.5) * spread
        local len = math.sqrt(dir.x^2 + dir.y^2 + dir.z^2)
        dir.x = dir.x / len
        dir.y = dir.y / len
        dir.z = dir.z / len
    end
    
    local end_pos = {
        x = pos.x + dir.x * range,
        y = pos.y + dir.y * range,
        z = pos.z + dir.z * range
    }
    
    local hit_pos = end_pos
    local ray = core.raycast(pos, end_pos, true, true)
    for pointed_thing in ray do
        if pointed_thing.type == "object" then
            local obj = pointed_thing.ref
            if obj ~= player then
                -- Ignore spectators
                if obj:is_player() and tdm_core.is_spectator(obj:get_player_name()) then
                    -- Don't break the ray here, but don't hit either. 
                    -- Actually, bullets should pass THROUGH spectators.
                else
                    -- Friendly Fire Check
                    if obj:is_player() and not tdm_core.match.friendly_fire then
                        local shooter_team = tdm_core.teams.get_player_team(player:get_player_name())
                        local victim_team = tdm_core.teams.get_player_team(obj:get_player_name())
                        if shooter_team == victim_team then
                            return false -- Don't hit teammates
                        end
                    end

                    obj:punch(player, 1.0, {
                        full_punch_interval = 1.0,
                        damage_groups = {fleshy = damage}
                    }, dir)
                end

                
                hit_pos = pointed_thing.intersection_point
                -- Spawn some particle effect on hit
                core.add_particlespawner({
                    amount = 5,
                    time = 0.1,
                    minpos = hit_pos,
                    maxpos = hit_pos,
                    minvel = {x=-1, y=-1, z=-1},
                    maxvel = {x=1, y=1, z=1},
                    minexptime = 0.5,
                    maxexptime = 1,
                    minsize = 1,
                    maxsize = 2,
                    texture = "tdm_muzzle_flash.png^[colorize:#FF0000:200", 
                })
                -- Play hit sound
                core.sound_play("tdm_hit", {pos = hit_pos, max_hear_distance = 16})
                -- Fallback to a standard thud
                core.sound_play("player_punch", {pos = hit_pos, max_hear_distance = 16, gain = 0.5})
                break -- hit an object, stop ray
            end
        elseif pointed_thing.type == "node" then
            -- Hit a block
            hit_pos = pointed_thing.intersection_point
            
            -- Particle impact
            core.add_particlespawner({
                amount = 10,
                time = 0.1,
                minpos = hit_pos,
                maxpos = hit_pos,
                minvel = {x=-0.5, y=0.5, z=-0.5},
                maxvel = {x=0.5, y=1.5, z=0.5},
                minexptime = 0.5,
                maxexptime = 1,
                minsize = 1,
                maxsize = 2,
                texture = "tdm_muzzle_flash.png^[colorize:#FFFFFF:200",
            })

            -- Node damage logic for player-built structures
            local node_pos = pointed_thing.under
            local node = core.get_node(node_pos)
            
            -- DEBUG: Report what we hit
            
            if node.name == "tdm_loot:box" or core.get_item_group(node.name, "loot_box") > 0 then
                -- Force destruction
                core.remove_node(node_pos)
                core.sound_play("tdm_break_crate", {pos = node_pos, max_hear_distance = 16})
                
                -- Try to trigger loot drop logic
                local n_def = core.registered_nodes[node.name]
                if n_def and n_def.on_punch then
                    n_def.on_punch(node_pos, node, player)
                end
            elseif core.get_item_group(node.name, "player_built") > 0 then
                local meta = core.get_meta(node_pos)
                local hp = meta:get_int("hp")
                if hp == 0 then hp = 50 end
                
                hp = hp - damage
                if hp <= 0 then
                    core.remove_node(node_pos)
                    core.sound_play("tdm_break_crate", {pos = node_pos, max_hear_distance = 16})
                else
                    meta:set_int("hp", hp)
                end
            end
            break
        end
    end

    -- Muzzle flash
    core.add_particle({
        pos = {x=pos.x + dir.x * 0.7, y=pos.y + dir.y * 0.7 - 0.1, z=pos.z + dir.z * 0.7},
        velocity = {x=0, y=0, z=0},
        expirationtime = 0.1,
        size = 1.5, -- Reduced from 4
        texture = "tdm_muzzle_flash.png",
        glow = 14,
    })

    -- Tracer line
    if not hit_pos then hit_pos = end_pos end
    local dist = vector.distance(pos, hit_pos)
    local step = 2.0 -- Optimized: 75% fewer particles for massive network and rendering performance gains
    for d = 1.0, dist, step do -- Start closer to gun
        local tpos = vector.add(pos, vector.multiply(dir, d))
        core.add_particle({
            pos = tpos,
            velocity = {x=0, y=0, z=0},
            acceleration = {x=0, y=0, z=0}, -- Explicitly zeroed out
            expirationtime = 0.1,
            size = 0.4,
            texture = "tdm_tracer.png",
            glow = 14,
            vertical = false, -- Prevent billboard misalignment
        })
    end

    return (hit_pos ~= end_pos)
end

tdm_weapons.register_gun = function(name, def)
    core.register_tool("tdm_weapons:" .. name, {
        description = def.description,
        inventory_image = "tdm_weapons_" .. name .. ".png",
        range = 0, -- Disable default melee reach behavior
        on_use = function(itemstack, user, pointed_thing)
            if tdm_weapons.handle_interaction(user, pointed_thing) then
                return itemstack
            end
            local p_name = user:get_player_name()
            
            -- CTF TACTICAL LOCKOUT: Cannot fire while carrying flag
            if user:get_meta():get_int("has_flag") == 1 then
                core.chat_send_player(p_name, "TACTICAL LOCKOUT: You cannot fire while carrying the flag! Rely on your team for cover.")
                return itemstack
            end

            local cd = tdm_weapons.cooldowns[p_name] or 0
            
            if cd <= 0 then
                for i = 1, (def.pellets or 1) do
                    tdm_weapons.shoot_raycast(user, def.damage, def.range, def.spread or 0)
                end
                tdm_weapons.cooldowns[p_name] = def.fire_rate
                
                -- Play sound
                core.sound_play("tdm_shoot_" .. name, {pos = user:get_pos(), max_hear_distance = 32})
            end
            return itemstack
        end
    })
end

-- HELPER: Allow interacting with crates/items while wielding weapons
function tdm_weapons.handle_interaction(user, pointed_thing)
    if pointed_thing.type == "node" then
        local pos = pointed_thing.under
        local node = core.get_node(pos)
        if node.name == "tdm_loot:box" then
            local n_def = core.registered_nodes[node.name]
            if n_def and n_def.on_punch then
                n_def.on_punch(pos, node, user)
            end
            return true
        end
    elseif pointed_thing.type == "object" then
        local obj = pointed_thing.ref
        local ent = obj:get_luaentity()
        -- Direct pickup for dropped items
        if ent and ent.name == "__builtin:item" then
            if core.registered_on_item_pickups[1] then
                core.registered_on_item_pickups[1](ItemStack(ent.itemstring), user, pointed_thing)
                return true
            end
        end
    end
    return false
end

-- Wait, Minetest usually relies on image files to not error out completely, 
-- but we can use colorization on a dummy transparent or white texture if we don't have images.
-- For now, we will create simple colored squares for textures using texturing modifiers.

core.register_tool("tdm_weapons:assault_rifle", {
    description = "Assault Rifle",
    inventory_image = "tdm_weapons_assault_rifle.png",
    wield_image = "tdm_weapons_assault_rifle_wield.png",
    wield_scale = {x=1.5, y=1.5, z=1.5},
    on_use = function(itemstack, user, pointed_thing)
        if tdm_weapons.handle_interaction(user, pointed_thing) then
            return itemstack
        end
        local p_name = user:get_player_name()
        
        -- CTF TACTICAL LOCKOUT: Cannot fire while carrying flag
        if user:get_meta():get_int("has_flag") == 1 then
            core.chat_send_player(p_name, "TACTICAL LOCKOUT: You cannot fire while carrying the flag! Rely on your team for cover.")
            return itemstack
        end

        local cd = tdm_weapons.cooldowns[p_name] or 0
        local inv = user:get_inventory()
        
        if cd <= 0 then
            -- Try to take from ammo stash first, fallback to main for legacy
            local count = 0
            if inv:contains_item("ammo", "tdm_weapons:rifle_ammo") then
                inv:remove_item("ammo", "tdm_weapons:rifle_ammo 1")
                count = 1
            elseif inv:contains_item("main", "tdm_weapons:rifle_ammo") then
                inv:remove_item("main", "tdm_weapons:rifle_ammo 1")
                count = 1
            end
            
            if count > 0 then
                -- Rifle deals 10 damage to players and nodes
                tdm_weapons.shoot_raycast(user, 10, 50, 0.05)
                tdm_weapons.cooldowns[p_name] = 0.15
                
                -- Play sound
                core.sound_play("tdm_shoot_assault_rifle", {pos = user:get_pos(), max_hear_distance = 32})
                
                -- Update HUD
                tdm_core.hud.update_ammo(user)
            else
                core.chat_send_player(p_name, "Out of rifle ammo!")
            end
        end
        return itemstack
    end,
})

core.register_craftitem("tdm_weapons:rifle_ammo", {
    description = "Rifle Ammo",
    inventory_image = "tdm_weapons_rifle_ammo.png",
    stack_max = 100,
})

core.register_tool("tdm_weapons:shotgun", {
    description = "Pump Shotgun",
    inventory_image = "tdm_weapons_shotgun.png",
    wield_image = "tdm_weapons_shotgun_wield.png",
    wield_scale = {x=1.5, y=1.5, z=1.5},
    on_use = function(itemstack, user, pointed_thing)
        if tdm_weapons.handle_interaction(user, pointed_thing) then
            return itemstack
        end
        local p_name = user:get_player_name()
        
        -- CTF TACTICAL LOCKOUT: Cannot fire while carrying flag
        if user:get_meta():get_int("has_flag") == 1 then
            core.chat_send_player(p_name, "TACTICAL LOCKOUT: You cannot fire while carrying the flag! Rely on your team for cover.")
            return itemstack
        end

        local cd = tdm_weapons.cooldowns[p_name] or 0
        local inv = user:get_inventory()
        
        if cd <= 0 then
            -- Try to take from ammo stash first, fallback to main for legacy
            local count = 0
            if inv:contains_item("ammo", "tdm_weapons:shotgun_ammo") then
                inv:remove_item("ammo", "tdm_weapons:shotgun_ammo 1")
                count = 1
            elseif inv:contains_item("main", "tdm_weapons:shotgun_ammo") then
                inv:remove_item("main", "tdm_weapons:shotgun_ammo 1")
                count = 1
            end
            
            if count > 0 then
                for i = 1, 8 do
                    -- Shotgun deals 4.2 per pellet (33.6 total per blast)
                    -- 3 hits = 100.8 damage (Lethal for 100 HP players)
                    tdm_weapons.shoot_raycast(user, 4.2, 30, 0.2)
                end
                tdm_weapons.cooldowns[p_name] = 1.0
                
                -- Play sound
                core.sound_play("tdm_shoot_shotgun", {pos = user:get_pos(), max_hear_distance = 32})
                
                -- Update HUD
                tdm_core.hud.update_ammo(user)
            else
                core.chat_send_player(p_name, "Out of shotgun ammo!")
            end
        end
        return itemstack
    end,
})

core.register_craftitem("tdm_weapons:shotgun_ammo", {
    description = "Shotgun Ammo",
    inventory_image = "tdm_weapons_shotgun_ammo.png",
    stack_max = 50,
})

core.register_craftitem("tdm_weapons:health_pack", {
    description = "Health Pack (+20% HP)",
    inventory_image = "tdm_weapons_health_pack.png",
    stack_max = 5,
    on_use = function(itemstack, user, pointed_thing)
        if tdm_weapons.handle_interaction(user, pointed_thing) then
            return itemstack
        end
        local hp = user:get_hp()
        if hp >= 100 then
            core.chat_send_player(user:get_player_name(), "Health is already full!")
            return itemstack
        end
        
        -- Restore 20 HP (20% of 100 max)
        user:set_hp(math.min(100, hp + 20))
        
        -- Sound effect
        core.sound_play("tdm_heal", {pos = user:get_pos(), gain = 1.0, max_hear_distance = 16})
        
        -- Consume item
        itemstack:take_item()
        return itemstack
    end,
})

core.register_tool("tdm_weapons:pickaxe", {
    description = "Harvesting Tool",
    inventory_image = "tdm_weapons_pickaxe.png",
    wield_image = "tdm_weapons_pickaxe_wield.png",
    wield_scale = {x=1.5, y=1.5, z=1.5},
    tool_capabilities = {
        full_punch_interval = 0.5,
        max_drop_level = 3,
        groupcaps = {
            choppy = {times={[1]=0.5, [2]=0.2, [3]=0.1}, uses=0, maxlevel=3},
            cracky = {times={[1]=0.5, [2]=0.2, [3]=0.1}, uses=0, maxlevel=3},
            snappy = {times={[1]=0.5, [2]=0.2, [3]=0.1}, uses=0, maxlevel=3},
        },
        damage_groups = {fleshy = 2},
    },
})

-- Prevent picking up duplicate weapons or items for spectators
core.register_on_item_pickup(function(itemstack, picker, pointed_thing)
    local pname = picker:get_player_name()
    if tdm_core.is_spectator(pname) then
        return itemstack -- Spectators can't pick up anything
    end

    local item_name = itemstack:get_name()
    local inv = picker:get_inventory()
    
    -- Auto-sort ammo into the hidden stash
    if item_name == "tdm_weapons:rifle_ammo" or item_name == "tdm_weapons:shotgun_ammo" then
        local leftover = inv:add_item("ammo", itemstack)
        if leftover:get_count() < itemstack:get_count() then
            if pointed_thing and pointed_thing.ref then
                pointed_thing.ref:remove()
                core.sound_play("tdm_pickup", {pos = picker:get_pos(), gain = 0.5})
            end
            tdm_core.hud.update_ammo(picker)
        end
        return leftover
    end

    if item_name == "tdm_weapons:assault_rifle" or item_name == "tdm_weapons:shotgun" then
        local ammo_name = (item_name == "tdm_weapons:assault_rifle") and "tdm_weapons:rifle_ammo" or "tdm_weapons:shotgun_ammo"
        local count = (item_name == "tdm_weapons:assault_rifle") and 20 or 8

        if inv:contains_item("main", item_name) then
            -- Convert duplicate to ammo
            inv:add_item("ammo", ammo_name .. " " .. count)
            
            if pointed_thing and pointed_thing.ref then
                pointed_thing.ref:remove()
                core.sound_play("tdm_pickup", {pos = picker:get_pos(), gain = 0.5})
            end
            tdm_core.hud.update_ammo(picker)
            return ItemStack("") -- Successfully scavenged
        else
            -- First time pickup: Give weapon AND starting ammo
            local leftover = inv:add_item("main", itemstack)
            if leftover:get_count() < itemstack:get_count() then
                inv:add_item("ammo", ammo_name .. " " .. count)
                
                if pointed_thing and pointed_thing.ref then
                    pointed_thing.ref:remove()
                    core.sound_play("tdm_pickup", {pos = picker:get_pos(), gain = 0.5})
                end
                tdm_core.hud.update_ammo(picker)
            end
            return leftover
        end
    end
    
    -- Manually implement pickup for other items (e.g. pickaxe, health pack) into 'main'
    local leftover = inv:add_item("main", itemstack)
    
    if leftover:get_count() < itemstack:get_count() then
        if pointed_thing and pointed_thing.ref then
            pointed_thing.ref:remove()
            core.sound_play("tdm_pickup", {pos = picker:get_pos(), gain = 0.5})
        end
    end
    
    return leftover
end)

tdm_core.bots = {}

local difficulty_settings = {
    easy = { hp = 50, fire_rate = 1.5, spread = 0.2, damage = 5, speed = 3 },
    medium = { hp = 100, fire_rate = 1.0, spread = 0.1, damage = 10, speed = 4.5 },
    hard = { hp = 150, fire_rate = 0.5, spread = 0.05, damage = 15, speed = 5.5 }
}

function tdm_core.bots.spawn(pos, diff)
    local obj = core.add_entity(pos, "tdm_core:bot")
    if obj then
        local ent = obj:get_luaentity()
        if ent then
            ent:set_difficulty(diff)
        end
    end
end

function tdm_core.bots.clear_all()
    for _, obj in pairs(core.object_refs) do
        local ent = obj:get_luaentity()
        if ent and ent.name == "tdm_core:bot" then
            obj:remove()
        end
    end
end

core.register_entity("tdm_core:bot", {
    initial_properties = {
        hp_max = 100,
        physical = true,
        collide_with_objects = true,
        collisionbox = {-0.3, 0.0, -0.3, 0.3, 1.7, 0.3},
        visual = "mesh",
        mesh = "character.b3d",
        textures = {"character.png^[colorize:#FF3333:120"}, -- Red tint for bots
        is_visible = true,
        makes_footstep_sound = true,
    },
    
    _difficulty = "medium",
    _cooldown = 0,
    _anim = "",
    _ammo = 0, -- Bots spawn empty and must loot
    
    set_difficulty = function(self, diff)
        self._difficulty = diff or "medium"
        local def = difficulty_settings[self._difficulty]
        if def then
            self.object:set_properties({hp_max = def.hp})
            self.object:set_hp(def.hp)
        end
        self.object:set_armor_groups({fleshy = 100})
    end,
    
    on_activate = function(self, staticdata)
        self.object:set_armor_groups({fleshy = 100})
        self.object:set_acceleration({x=0, y=-9.81, z=0})
        self:set_animation("stand")
    end,
    
    set_animation = function(self, anim)
        if self._anim == anim then return end
        self._anim = anim
        if anim == "stand" then
            self.object:set_animation({x=0, y=79}, 30, 0)
        elseif anim == "walk" then
            self.object:set_animation({x=168, y=187}, 30, 0)
        end
    end,
    
    on_step = function(self, dtime)
        if tdm_core.match.state ~= "active" or not tdm_core.match.is_pve then
            self.object:set_velocity({x=0, y=self.object:get_velocity().y, z=0})
            self:set_animation("stand")
            return
        end
        
        local def = difficulty_settings[self._difficulty] or difficulty_settings["medium"]
        self._cooldown = self._cooldown - dtime
        
        local pos = self.object:get_pos()
        
        -- LOOTING STATE: Need ammo
        if self._ammo <= 0 then
            local rad = 25
            local ppos = {x=math.floor(pos.x+0.5), y=math.floor(pos.y+0.5), z=math.floor(pos.z+0.5)}
            local crates = core.find_nodes_in_area(
                {x=ppos.x-rad, y=ppos.y-5, z=ppos.z-rad},
                {x=ppos.x+rad, y=ppos.y+5, z=ppos.z+rad},
                {"tdm_loot:box"}
            )
            
            if #crates > 0 then
                -- Find closest crate
                local min_dist = 999
                local target_crate = nil
                for _, cp in ipairs(crates) do
                    local dist = vector.distance(pos, cp)
                    if dist < min_dist then
                        min_dist = dist
                        target_crate = cp
                    end
                end
                
                if target_crate then
                    if min_dist < 2.5 then
                        -- Smash crate and grab loot!
                        core.remove_node(target_crate)
                        core.sound_play("tdm_break_crate", {pos = target_crate, max_hear_distance = 16})
                        self._ammo = 30 -- Reload
                        self.object:set_velocity({x=0, y=self.object:get_velocity().y, z=0})
                        self:set_animation("stand")
                    else
                        -- Sprint to crate
                        local target_pos = {x=target_crate.x, y=target_crate.y, z=target_crate.z}
                        local dir = vector.direction(pos, target_pos)
                        local yaw = math.atan2(dir.z, dir.x) - math.pi/2
                        self.object:set_yaw(yaw)
                        
                        local vel = vector.multiply(dir, def.speed * 1.2) -- Move faster when looting
                        vel.y = self.object:get_velocity().y
                        
                        -- Basic jump logic
                        local front_node = core.get_node({x=pos.x+dir.x, y=pos.y, z=pos.z+dir.z})
                        if front_node.name ~= "air" and core.registered_nodes[front_node.name].walkable then
                            vel.y = 5 
                        end
                        
                        self.object:set_velocity(vel)
                        self:set_animation("walk")
                    end
                end
                return -- Skip combat this tick
            end
        end
        
        -- COMBAT STATE: Hunt and Destroy
        local nearest = nil
        local min_dist = 9999
        
        -- Find target
        for _, p in ipairs(core.get_connected_players()) do
            local pname = p:get_player_name()
            if not tdm_core.is_spectator(pname) and p:get_hp() > 0 then
                local p_pos = p:get_pos()
                local dist = vector.distance(pos, p_pos)
                if dist < min_dist then
                    min_dist = dist
                    nearest = p
                end
            end
        end
        
        if nearest and min_dist < 40 then
            local p_pos = nearest:get_pos()
            p_pos.y = p_pos.y + 1.5 -- target chest
            local dir = vector.direction(pos, p_pos)
            
            -- Look at player
            local yaw = math.atan2(dir.z, dir.x) - math.pi/2
            self.object:set_yaw(yaw)
            
            -- Line of Sight Check
            local los = core.line_of_sight({x=pos.x, y=pos.y+1.5, z=pos.z}, p_pos)
            
            if los and min_dist < 30 and self._ammo > 0 then
                -- Open Fire
                self.object:set_velocity({x=0, y=self.object:get_velocity().y, z=0})
                self:set_animation("stand")
                
                if self._cooldown <= 0 then
                    self._cooldown = def.fire_rate
                    self._ammo = self._ammo - 1
                    tdm_core.bots.shoot(self.object, nearest, def.damage, def.spread)
                end
            else
                -- Advance aggressively
                local vel = vector.multiply(dir, def.speed)
                vel.y = self.object:get_velocity().y
                
                local front_node = core.get_node({x=pos.x+dir.x, y=pos.y, z=pos.z+dir.z})
                if front_node.name ~= "air" and core.registered_nodes[front_node.name].walkable then
                    vel.y = 5 
                end
                
                self.object:set_velocity(vel)
                self:set_animation("walk")
            end
        else
            self.object:set_velocity({x=0, y=self.object:get_velocity().y, z=0})
            self:set_animation("stand")
        end
    end,
    
    on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir)
        local hp = self.object:get_hp()
        if hp <= 0 then
            local pos = self.object:get_pos()
            core.add_particlespawner({
                amount = 20, time = 0.2,
                minpos = pos, maxpos = {x=pos.x, y=pos.y+2, z=pos.z},
                minvel = {x=-2, y=-1, z=-2}, maxvel = {x=2, y=3, z=2},
                minexptime = 1, maxexptime = 2, minsize = 2, maxsize = 4,
                texture = "core_particle_white.png^[colorize:#FF0000:120"
            })
            core.sound_play("tdm_hit", {pos = pos, max_hear_distance = 16})
            
            -- Score integration: If puncher is player, give their team a point
            if puncher and puncher:is_player() then
                local p_team = tdm_core.teams.get_player_team(puncher:get_player_name())
                if p_team == "red" then tdm_core.teams.scores.red = tdm_core.teams.scores.red + 1 end
                if p_team == "blue" then tdm_core.teams.scores.blue = tdm_core.teams.scores.blue + 1 end
                tdm_core.hud.update_scores()
            end
            
            -- Auto-Respawn bot
            local diff = self._difficulty
            core.after(2, function()
                if tdm_core.match.state == "active" and tdm_core.match.is_pve then
                    tdm_core.bots.spawn(tdm_core.get_safe_spawn_pos(nil), diff)
                end
            end)
            
            self.object:remove()
        else
            core.sound_play("player_punch", {pos = self.object:get_pos(), max_hear_distance = 16, gain=0.5})
        end
    end
})

function tdm_core.bots.shoot(bot_obj, target_player, damage, spread)
    local pos = bot_obj:get_pos()
    pos.y = pos.y + 1.5
    local target_pos = target_player:get_pos()
    target_pos.y = target_pos.y + 1.0 
    
    local dir = vector.direction(pos, target_pos)
    
    if spread > 0 then
        dir.x = dir.x + (math.random() - 0.5) * spread
        dir.y = dir.y + (math.random() - 0.5) * spread
        dir.z = dir.z + (math.random() - 0.5) * spread
        dir = vector.normalize(dir)
    end
    
    local range = 40
    local end_pos = vector.add(pos, vector.multiply(dir, range))
    local hit_pos = end_pos
    local ray = core.raycast(pos, end_pos, true, true)
    
    for pointed_thing in ray do
        if pointed_thing.type == "object" then
            local obj = pointed_thing.ref
            if obj ~= bot_obj then
                if obj:is_player() and not tdm_core.is_spectator(obj:get_player_name()) then
                    obj:punch(bot_obj, 1.0, {
                        full_punch_interval = 1.0,
                        damage_groups = {fleshy = damage}
                    }, dir)
                end
                hit_pos = pointed_thing.intersection_point
                break
            end
        elseif pointed_thing.type == "node" then
            hit_pos = pointed_thing.intersection_point
            break
        end
    end
    
    core.sound_play("tdm_shoot_assault_rifle", {pos = pos, max_hear_distance = 32, gain = 0.5})
    
    local dist = vector.distance(pos, hit_pos)
    for d = 1.0, dist, 0.5 do
        local tpos = vector.add(pos, vector.multiply(dir, d))
        core.add_particle({
            pos = tpos, velocity = {x=0, y=0, z=0}, expirationtime = 0.1,
            size = 0.4, texture = "tdm_tracer.png^[colorize:#FF0000:200", glow = 14,
        })
    end
end

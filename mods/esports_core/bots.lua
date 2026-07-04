local math_random = math.random
local math_atan2 = math.atan2
local math_pi = math.pi
local vector_distance = vector.distance
local vector_direction = vector.direction
local vector_multiply = vector.multiply
local core_get_node = core.get_node

local function get_obstacle_in_way(pos, dir)
	local check_dists = {0.8, 1.5, 2.2}
	local check_heights = {0.5, 1.5}
	for _, dist in ipairs(check_dists) do
		for _, height in ipairs(check_heights) do
			local check_pos = vector.round({
				x = pos.x + dir.x * dist,
				y = pos.y + height,
				z = pos.z + dir.z * dist
			})
			local node = core.get_node(check_pos)
			if core.get_item_group(node.name, "player_built") > 0 then
				return check_pos, node
			end
		end
	end
	return nil
end

local function attack_obstacle(self, pos, dir, obstacle_pos, def, cdef)
	-- Stop moving
	self.object:set_velocity({x=0, y=self.object:get_velocity().y, z=0})
	self:set_animation("stand")

	-- Face the block
	local block_dir = vector_direction(pos, obstacle_pos)
	self.object:set_yaw(math_atan2(-block_dir.x, block_dir.z))

	if self._cooldown <= 0 then
		local dist = vector_distance(pos, obstacle_pos)
		if self._ammo > 0 and dist > 1.2 then
			-- Ranged shoot
			self._cooldown = def.fire_rate * cdef.fire_mult
			self._ammo = self._ammo - 1

			local bullet_pos = {x=pos.x, y=pos.y + 1.5, z=pos.z}
			core.sound_play("esports_shoot_assault_rifle", {pos = pos, max_hear_distance = 32, gain = 0.5})

			-- Muzzle flash
			core.add_particle({
				pos = bullet_pos,
				velocity = {x=0, y=0, z=0},
				expirationtime = 0.1,
				size = 5,
				texture = "esports_muzzle_flash.png",
				glow = 14
			})

			-- Tracer
			local t_dir = vector_direction(bullet_pos, obstacle_pos)
			local tracer_dist = vector_distance(bullet_pos, obstacle_pos)
			local step = 2.0
			for d = 1.0, tracer_dist, step do
				local tpos = vector.add(bullet_pos, vector.multiply(t_dir, d))
				core.add_particle({
					pos = tpos, velocity = {x=0, y=0, z=0}, expirationtime = 0.1,
					size = 0.4, texture = "esports_tracer.png^[colorize:#33FF33:200", glow = 14,
				})
			end

			-- Damage node
			local meta = core.get_meta(obstacle_pos)
			local hp = meta:get_int("hp")
			if hp == 0 then hp = 50 end

			local damage = def.damage * cdef.dmg_mult
			hp = hp - damage

			-- Node hit particles
			core.add_particlespawner({
				amount = 8,
				time = 0.1,
				minpos = obstacle_pos,
				maxpos = obstacle_pos,
				minvel = {x=-0.5, y=0.5, z=-0.5},
				maxvel = {x=0.5, y=1.5, z=0.5},
				minexptime = 0.5,
				maxexptime = 1,
				minsize = 1,
				maxsize = 2,
				texture = "esports_muzzle_flash.png^[colorize:#FFFFFF:200",
			})

			if hp <= 0 then
				core.remove_node(obstacle_pos)
				core.sound_play("esports_break_crate", {pos = obstacle_pos, max_hear_distance = 16})
			else
				meta:set_int("hp", hp)
			end
		else
			-- Melee punch
			self._cooldown = 0.6
			core.sound_play("player_punch", {pos = pos, max_hear_distance = 16, gain = 0.8})

			-- Damage node
			local meta = core.get_meta(obstacle_pos)
			local hp = meta:get_int("hp")
			if hp == 0 then hp = 50 end

			hp = hp - 15

			-- Wood chips particles
			core.add_particlespawner({
				amount = 5,
				time = 0.1,
				minpos = obstacle_pos,
				maxpos = obstacle_pos,
				minvel = {x=-0.5, y=0.5, z=-0.5},
				maxvel = {x=0.5, y=1.0, z=0.5},
				minexptime = 0.4,
				maxexptime = 0.8,
				minsize = 1,
				maxsize = 2,
				texture = "core_particle_white.png^[colorize:#8B5A2B:150",
			})

			if hp <= 0 then
				core.remove_node(obstacle_pos)
				core.sound_play("esports_break_crate", {pos = obstacle_pos, max_hear_distance = 16})
			else
				meta:set_int("hp", hp)
			end
		end
	end
end

esports_core.bots = {}

local difficulty_settings = {
	easy = {hp = 70, fire_rate = 1.5, spread = 0.3, damage = 6, speed = 1.5},
	medium = {hp = 170, fire_rate = 0.8, spread = 0.15, damage = 12, speed = 3.0},
	hard = {hp = 340, fire_rate = 0.4, spread = 0.05, damage = 18, speed = 4.5}
}

local class_settings = {
	standard = {
		min_dist = 20, max_dist = 30,
		fire_mult = 1.0, dmg_mult = 1.0, speed_mult = 1.0, spread_mult = 1.0,
		tint = "^[colorize:#FF4444:150"  -- Red Tactical
	},
	sniper = {
		min_dist = 40, max_dist = 60,
		fire_mult = 2.5, dmg_mult = 3.0, speed_mult = 0.8, spread_mult = 0.05,
		tint = "^[colorize:#FF4444:150"  -- Red Tactical
	},
	rusher = {
		min_dist = 5, max_dist = 12,
		fire_mult = 0.5, dmg_mult = 0.5, speed_mult = 1.4, spread_mult = 2.0,
		tint = "^[colorize:#FF4444:150"  -- Red Tactical
	}
}

function esports_core.bots.spawn(pos, diff, class)
	local obj = core.add_entity(pos, "esports_core:bot")
	if obj then
		local ent = obj:get_luaentity()
		if ent then
			ent:set_difficulty(diff)
			ent:set_class(class)
		end
	end
end

function esports_core.bots.clear_all()
	local all_objs = core.get_objects_inside_radius({x=0, y=0, z=0}, 500)
	for _, obj in ipairs(all_objs) do
		local ent = obj:get_luaentity()
		if ent and ent.name == "esports_core:bot" then
			obj:remove()
		end
	end
end

core.register_entity("esports_core:bot", {
	initial_properties = {
		hp_max = 100,
		physical = true,
		collide_with_objects = true,
		collisionbox = {-0.3, 0.0, -0.3, 0.3, 1.7, 0.3},
		visual = "mesh",
		mesh = "character.b3d",
		textures = {"character.png^[colorize:#FF4444:150"},  -- Standardized Red Tactical for bots
		is_visible = true,
		makes_footstep_sound = true,
	},

	_difficulty = "medium",
	_class = "standard",
	_cooldown = 0,
	_anim = "",
	_ammo = 0,  -- Bots spawn empty and must loot crates for ammo
	_scan_timer = 0,  -- Throttle node scans

	set_class = function(self, class)
		self._class = class or "standard"
		local cdef = class_settings[self._class]
		if cdef then
			local tex = "character.png" .. cdef.tint
			self.object:set_properties({textures = {tex}})
		end
	end,

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
		if esports_core.match.state ~= "active" or not esports_core.match.is_pve then
			self.object:set_velocity({x=0, y=self.object:get_velocity().y, z=0})
			self:set_animation("stand")
			return
		end

		local def = difficulty_settings[self._difficulty] or difficulty_settings["medium"]
		local cdef = class_settings[self._class] or class_settings["standard"]
		self._cooldown = self._cooldown - dtime
		self._scan_timer = self._scan_timer - dtime

		local pos = self.object:get_pos()

		-- Update dynamic nametag with health for bots/sentries
		local hp = self.object:get_hp()
		local tag_text = string.format("Sentry (%d HP)", hp)

		self.object:set_properties({
			nametag = tag_text,
			nametag_color = {a = 255, r = 255, g = 50, b = 50}  -- Red tactical color for bot nametags
		})

		-- LOOTING STATE: Need ammo
		if self._ammo <= 0 then
			-- OPTIMIZED: Use internal cache and throttle scans to once every 2 seconds
			if not self._target_crate or self._scan_timer <= 0 then
				self._scan_timer = 2.0
				local min_dist = 30  -- Scan radius
				local target_crate = nil

				if esports_loot and esports_loot.crate_positions then
					for _, cp in pairs(esports_loot.crate_positions) do
						local d = vector_distance(pos, cp)
						if d < min_dist then
							min_dist = d
							target_crate = cp
						end
					end
				end
				self._target_crate = target_crate
			end

			-- If no crates found, don't just stand there - fall through to combat/hunt logic
			if self._target_crate then
				local dist = vector_distance(pos, self._target_crate)
				if dist < 2.5 then
					-- Smash crate and grab loot!
					core.remove_node(self._target_crate)
					core.sound_play("esports_break_crate", {pos = self._target_crate, max_hear_distance = 16})
					self._ammo = 30  -- Reload
					self._target_crate = nil
					self.object:set_velocity({x=0, y=self.object:get_velocity().y, z=0})
					self:set_animation("stand")
				else
					-- Move toward crate
					local dir = vector_direction(pos, self._target_crate)

					-- Check and attack obstacles in our way
					local obstacle_pos, obstacle_node = get_obstacle_in_way(pos, dir)
					if obstacle_pos then
						attack_obstacle(self, pos, dir, obstacle_pos, def, cdef)
					else
						self.object:set_yaw(math_atan2(-dir.x, dir.z))

						local vel = vector_multiply(dir, def.speed * 1.5)
						vel.y = self.object:get_velocity().y
						self.object:set_velocity(vel)
						self:set_animation("walk")

						-- Jump over obstacles
						local node_ahead = core.get_node({x=pos.x + dir.x, y=pos.y + 0.5, z=pos.z + dir.z})
						if node_ahead.name ~= "air" and node_ahead.name ~= "ignore" then
							local v = self.object:get_velocity()
							self.object:set_velocity({x=v.x, y=5, z=v.z})
						end
					end
				end
				return
			end
		end

		-- COMBAT STATE: Hunt Players
		-- Throttle target and LOS scanning to ~0.15s intervals
		self._combat_timer = (self._combat_timer or 0) - dtime
		if self._combat_timer <= 0 then
			self._combat_timer = 0.15

			local target = nil
			local min_dist = 100

			for _, player in ipairs(core.get_connected_players()) do
				local pname = player:get_player_name()
				if not esports_core.is_spectator(pname) and player:get_hp() > 0 then
					local ppos = player:get_pos()
					local d = vector_distance(pos, ppos)
					if d < min_dist then
						min_dist = d
						target = player
					end
				end
			end

			self._target = target
			self._target_dist = min_dist

			if target then
				local ppos = target:get_pos()
				local ray = core.raycast({x=pos.x, y=pos.y+1.5, z=pos.z}, {x=ppos.x, y=ppos.y+1.5, z=ppos.z}, true, false)
				local los = true
				for pointed in ray do
					if pointed.type == "node" then
						los = false
						break
					end
				end
				self._has_los = los
			else
				self._has_los = false
			end
		end

		local target = self._target
		local min_dist = self._target_dist or 100
		local los = self._has_los

		if target and target:get_hp() > 0 then
			local ppos = target:get_pos()
			local dir = vector_direction(pos, ppos)
			self.object:set_yaw(math_atan2(-dir.x, dir.z))

			if los and min_dist < (cdef.max_dist or 30) and self._ammo > 0 then
				-- Move toward ideal distance or back away if too close (for snipers)
				if min_dist < (cdef.min_dist or 5) then
					-- Too close! Retreat or stay mobile
					local vel = vector_multiply(dir, -def.speed * cdef.speed_mult * 0.7)
					self.object:set_velocity({x=vel.x, y=self.object:get_velocity().y, z=vel.z})
					self:set_animation("walk")
				else
					-- Ideal range: Stop and fire
					self.object:set_velocity({x=0, y=self.object:get_velocity().y, z=0})
					self:set_animation("stand")
				end

				if self._cooldown <= 0 then
					self._cooldown = def.fire_rate * cdef.fire_mult
					self._ammo = self._ammo - 1

					local bullet_pos = {x=pos.x, y=pos.y + 1.5, z=pos.z}
					esports_core.bots.shoot(self.object, target, def.damage * cdef.dmg_mult, def.spread * cdef.spread_mult)

					-- Muzzle flash
					core.add_particle({
						pos = bullet_pos,
						velocity = {x=0, y=0, z=0},
						acceleration = {x=0, y=0, z=0},
						expirationtime = 0.1,
						size = 5,
						collisiondetection = false,
						vertical = false,
						texture = "esports_muzzle_flash.png",
						glow = 14
					})
				end
			else
				-- Check and attack obstacles in our way
				local obstacle_pos, obstacle_node = get_obstacle_in_way(pos, dir)
				if obstacle_pos then
					attack_obstacle(self, pos, dir, obstacle_pos, def, cdef)
				else
					-- Advance aggressively
					local vel = vector_multiply(dir, def.speed * cdef.speed_mult)
					vel.y = self.object:get_velocity().y
					self.object:set_velocity(vel)
					self:set_animation("walk")

					-- Jump over obstacles
					local node_ahead = core.get_node({x=pos.x + dir.x, y=pos.y + 0.5, z=pos.z + dir.z})
					if node_ahead.name ~= "air" and node_ahead.name ~= "ignore" and node_ahead.name ~= "esports_core:storm_gas" then
						local v = self.object:get_velocity()
						self.object:set_velocity({x=v.x, y=5, z=v.z})
					end
				end
			end
		else
			self.object:set_velocity({x=0, y=self.object:get_velocity().y, z=0})
			self:set_animation("stand")
		end
	end,

	on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir)
		local damage = tool_capabilities.damage_groups.fleshy or 5
		local hp = self.object:get_hp() - damage

		if hp <= 0 then
			local pos = self.object:get_pos()
			core.add_particlespawner({
				amount = 20, time = 0.2,
				minpos = pos, maxpos = {x=pos.x, y=pos.y+2, z=pos.z},
				minvel = {x=-2, y=-1, z=-2}, maxvel = {x=2, y=3, z=2},
				minexptime = 1, maxexptime = 2, minsize = 2, maxsize = 4,
				texture = "core_particle_white.png^[colorize:#33FF33:150"
			})
			core.sound_play("esports_hit", {pos = pos, max_hear_distance = 16})

			-- Score integration
			if puncher and puncher:is_player() then
				local pname = puncher:get_player_name()
				local p_team = esports_core.teams.get_player_team(pname)
				if p_team == "red" then esports_core.teams.scores.red = esports_core.teams.scores.red + 1 end
				if p_team == "blue" then esports_core.teams.scores.blue = esports_core.teams.scores.blue + 1 end

				esports_core.match.add_kill(pname)
				esports_core.hud.update_scores()

				-- Broadcast to Kill Feed
				local tool = puncher:get_wielded_item():get_name()
				local weapon = "pickaxe"
				if tool:find("rifle") then weapon = "rifle"
				elseif tool:find("shotgun") then weapon = "shotgun" end
				esports_core.hud.add_kill_event(pname, p_team, "Sentry", "bots", weapon)

				core.chat_send_all(">> Sentry Destroyed by " .. pname .. "!")
			end

			-- Auto-Respawn bot
			local diff = self._difficulty
			local class = self._class or "standard"
			core.after(2, function()
				if esports_core.match.state == "active" and esports_core.match.is_pve then
					esports_core.bots.spawn(esports_core.get_safe_spawn_pos("red"), diff, class)
				end
			end)

			self.object:remove()
		else
			self.object:set_hp(hp)
			core.sound_play("player_punch", {pos = self.object:get_pos(), max_hear_distance = 16, gain=0.5})
		end
		return true  -- We handled the damage logic manually
	end
})

function esports_core.bots.shoot(bot_obj, target_player, damage, spread)
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
				if obj:is_player() and not esports_core.is_spectator(obj:get_player_name()) then
					obj:punch(bot_obj, 1.0, {
						full_punch_interval = 1.0,
						damage_groups = {fleshy = damage, is_gun = 1}
					}, dir)
				end
				hit_pos = pointed_thing.intersection_point
				break
			end
		elseif pointed_thing.type == "node" then
			hit_pos = pointed_thing.intersection_point
			local node_pos = pointed_thing.under
			local node = core.get_node(node_pos)
			if core.get_item_group(node.name, "player_built") > 0 then
				local meta = core.get_meta(node_pos)
				local hp = meta:get_int("hp")
				if hp == 0 then hp = 50 end

				hp = hp - damage
				if hp <= 0 then
					core.remove_node(node_pos)
					core.sound_play("esports_break_crate", {pos = node_pos, max_hear_distance = 16})
				else
					meta:set_int("hp", hp)
				end
			end
			break
		end
	end

	core.sound_play("esports_shoot_assault_rifle", {pos = pos, max_hear_distance = 32, gain = 0.5})

	local dist = vector.distance(pos, hit_pos)
	local step = 2.0  -- Optimized: 75% fewer particles for massive network and rendering performance gains
	for d = 1.0, dist, step do
		local tpos = vector.add(pos, vector.multiply(dir, d))
		core.add_particle({
			pos = tpos, velocity = {x=0, y=0, z=0}, expirationtime = 0.1,
			size = 0.4, texture = "esports_tracer.png^[colorize:#33FF33:200", glow = 14,
		})
	end
end

esports_weapons = {}
esports_weapons.cooldowns = {}  -- player_name -> timer
esports_weapons.last_ammo_warn = {}
esports_weapons.last_lockout_warn = {}
esports_weapons.spray_data = {}  -- player_name -> { count = 0, last_shot = 0, wielded = "" }

-- Initialize ammo stash on join
core.register_on_joinplayer(function(player)
	local inv = player:get_inventory()
	inv:set_size("ammo", 8)
end)

-- Cooldowns are checked and set using absolute timestamps (core.get_us_time)
-- to avoid running a high-frequency globalstep loop on every server tick.

esports_weapons.damage_node = function(pos, node, damage, player)
	if core.get_item_group(node.name, "player_built") > 0 then
		local meta = core.get_meta(pos)
		local hp = meta:get_int("hp")
		if hp == 0 then hp = 50 end

		hp = hp - damage

		-- Add impact particles
		core.add_particlespawner({
			amount = 5,
			time = 0.1,
			minpos = pos,
			maxpos = pos,
			minvel = {x=-0.5, y=0.5, z=-0.5},
			maxvel = {x=0.5, y=1.5, z=0.5},
			minexptime = 0.3,
			maxexptime = 0.7,
			minsize = 1,
			maxsize = 2,
			texture = "esports_muzzle_flash.png^[colorize:#FFFFFF:150",
		})

		if hp <= 0 then
			core.remove_node(pos)
			core.sound_play("esports_break_crate", {pos = pos, max_hear_distance = 16})
		else
			meta:set_int("hp", hp)
			core.sound_play("player_punch", {pos = pos, max_hear_distance = 16, gain = 0.5})
		end
		return true
	elseif node.name == "esports_loot:box" or core.get_item_group(node.name, "loot_box") > 0 then
		core.remove_node(pos)
		core.sound_play("esports_break_crate", {pos = pos, max_hear_distance = 16})

		local n_def = core.registered_nodes[node.name]
		if n_def and n_def.on_punch then
			n_def.on_punch(pos, node, player)
		end
		return true
	end
	return false
end

esports_weapons.shoot_raycast = function(player, damage, range, spread)
	local p_name = player:get_player_name()
	if esports_core.is_spectator(p_name) or (esports_core.is_in_lobby and esports_core.is_in_lobby(p_name)) then return false end

	local dir = player:get_look_dir()
	local pos = player:get_pos()
	pos.y = pos.y + player:get_properties().eye_height

	-- Apply spread (with class modifier support)
	if spread > 0 then
		local cdef = esports_core.skins and esports_core.skins.get_player_class and esports_core.skins.get_player_class(player)
		local spread_mult = cdef and cdef.spread_mult or 1.0
		local eff_spread = spread * spread_mult
		dir.x = dir.x + (math.random() - 0.5) * eff_spread
		dir.y = dir.y + (math.random() - 0.5) * eff_spread
		dir.z = dir.z + (math.random() - 0.5) * eff_spread
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
				local ent = obj:get_luaentity()
				local is_item = ent and ent.name == "__builtin:item"
				local is_spec = obj:is_player() and esports_core.is_spectator(obj:get_player_name())

				if not is_item and not is_spec then
					-- Friendly Fire Check
					if obj:is_player() and not esports_core.match.friendly_fire then
						local shooter_team = esports_core.teams.get_player_team(player:get_player_name())
						local victim_team = esports_core.teams.get_player_team(obj:get_player_name())
						if shooter_team == victim_team then
							return false  -- Don't hit teammates
						end
					end

					obj:punch(player, 1.0, {
						full_punch_interval = 1.0,
						damage_groups = {fleshy = damage, is_gun = 1}
					}, dir)

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
						texture = "esports_muzzle_flash.png^[colorize:#FF0000:200",
					})
					-- Play hit sound
					core.sound_play("esports_hit", {pos = hit_pos, max_hear_distance = 16})
					-- Fallback to a standard thud
					core.sound_play("player_punch", {pos = hit_pos, max_hear_distance = 16, gain = 0.5})
					break  -- hit an object, stop ray
				end
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
				texture = "esports_muzzle_flash.png^[colorize:#FFFFFF:200",
			})

			-- Node damage logic for player-built structures and crates
			local node_pos = pointed_thing.under
			local node = core.get_node(node_pos)
			esports_weapons.damage_node(node_pos, node, damage, player)
			break
		end
	end

	-- Muzzle flash
	core.add_particle({
		pos = {x=pos.x + dir.x * 0.7, y=pos.y + dir.y * 0.7 - 0.1, z=pos.z + dir.z * 0.7},
		velocity = {x=0, y=0, z=0},
		expirationtime = 0.1,
		size = 1.5,  -- Reduced from 4
		texture = "esports_muzzle_flash.png",
		glow = 14,
	})

	-- Tracer line
	if not hit_pos then hit_pos = end_pos end
	local dist = vector.distance(pos, hit_pos)
	local step = 2.0  -- Optimized: 75% fewer particles for massive network and rendering performance gains
	for d = 1.0, dist, step do  -- Start closer to gun
		local tpos = vector.add(pos, vector.multiply(dir, d))
		core.add_particle({
			pos = tpos,
			velocity = {x=0, y=0, z=0},
			acceleration = {x=0, y=0, z=0},  -- Explicitly zeroed out
			expirationtime = 0.1,
			size = 0.4,
			texture = "esports_tracer.png",
			glow = 14,
			vertical = false,  -- Prevent billboard misalignment
		})
	end

	return (hit_pos ~= end_pos)
end

esports_weapons.register_gun = function(name, def)
	core.register_tool("esports_weapons:" .. name, {
		description = def.description,
		inventory_image = "esports_weapons_" .. name .. ".png",
		range = 0,  -- Disable default melee reach behavior
		on_use = function(itemstack, user, pointed_thing)
			if esports_weapons.handle_interaction(user, pointed_thing) then
				return itemstack
			end
			local p_name = user:get_player_name()

			-- CTF TACTICAL LOCKOUT: Cannot fire while carrying flag
			if user:get_meta():get_int("has_flag") == 1 then
				core.chat_send_player(p_name, "TACTICAL LOCKOUT: You cannot fire while carrying the flag! Rely on your team for cover.")
				return itemstack
			end

			local current_time = core.get_us_time() / 1000000
			local cd = esports_weapons.cooldowns[p_name] or 0

			if current_time >= cd then
				for _ = 1, (def.pellets or 1) do
					esports_weapons.shoot_raycast(user, def.damage, def.range, def.spread or 0)
				end
				esports_weapons.cooldowns[p_name] = current_time + def.fire_rate

				-- Play sound
				core.sound_play("esports_shoot_" .. name, {pos = user:get_pos(), max_hear_distance = 32})
			end
			return itemstack
		end
	})
end

-- HELPER: Allow interacting with crates/items while wielding weapons
function esports_weapons.handle_interaction(user, pointed_thing)
	local pname = user:get_player_name()
	if esports_core.is_in_lobby and esports_core.is_in_lobby(pname) then
		return true  -- Block weapon interaction in lobby
	end
	if pointed_thing.type == "node" then
		local pos = pointed_thing.under
		local node = core.get_node(pos)
		if node.name == "esports_loot:box" then
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

-- Scope & ADS Manager for Sniper Rifles
esports_weapons.scoped_players = {} -- [pname] = hud_id

function esports_weapons.unscope(player)
	if not player or not player:is_player() then return end
	local pname = player:get_player_name()
	if esports_weapons.scoped_players[pname] then
		player:hud_remove(esports_weapons.scoped_players[pname])
		esports_weapons.scoped_players[pname] = nil
		player:set_fov(0)

		-- Restore all HUD elements (health, stamina, hotbar, ammo, stats, crosshair, etc.)
		if esports_core.hud and esports_core.hud.set_scope_mode then
			esports_core.hud.set_scope_mode(player, false)
		else
			local flags = player:hud_get_flags()
			flags.wielditem = true
			flags.crosshair = true
			player:hud_set_flags(flags)
		end

		if esports_core.sprint then
			esports_core.sprint.update_physics(player)
		else
			player:set_physics_override({speed = 1.2})
		end
	end
end

function esports_weapons.toggle_scope(player)
	if not player or not player:is_player() then return end
	local pname = player:get_player_name()
	if esports_weapons.scoped_players[pname] then
		esports_weapons.unscope(player)
	else
		-- Scope in: 20 deg optical zoom + fullscreen tactical reticle
		player:set_fov(20, false, 0.15)
		local hid = player:hud_add({
			hud_elem_type = "image",
			position = {x = 0.5, y = 0.5},
			alignment = {x = 0, y = 0},
			offset = {x = 0, y = 0},
			scale = {x = -100, y = -100},
			text = "esports_scope_overlay.png",
			z_index = 100,
		})
		esports_weapons.scoped_players[pname] = hid

		-- Remove other HUD elements (health, stamina, hotbar, ammo, stats, crosshair) in zoom mode
		if esports_core.hud and esports_core.hud.set_scope_mode then
			esports_core.hud.set_scope_mode(player, true)
		else
			local flags = player:hud_get_flags()
			flags.wielditem = false
			flags.crosshair = false
			player:hud_set_flags(flags)
		end

		-- Movement slow for steady breathing/stabilization
		player:set_physics_override({speed = 0.65})
		core.sound_play("player_damage", {to_player = pname, gain = 0.2, pitch = 2.0})
	end
end

-- Automatic unscope monitor (on death, weapon switch, or lobby transition)
local scope_monitor_timer = 0
core.register_globalstep(function(dtime)
	scope_monitor_timer = scope_monitor_timer + dtime
	if scope_monitor_timer < 0.15 then return end
	scope_monitor_timer = 0
	for pname, _ in pairs(esports_weapons.scoped_players) do
		local player = core.get_player_by_name(pname)
		if not player or not player:is_player() then
			esports_weapons.scoped_players[pname] = nil
		else
			local item = player:get_wielded_item():get_name()
			if item ~= "esports_weapons:sniper_rifle" or player:get_hp() <= 0 or (esports_core.is_in_lobby and esports_core.is_in_lobby(player)) then
				esports_weapons.unscope(player)
			end
		end
	end
end)

core.register_on_dieplayer(function(player)
	local pname = player:get_player_name()
	if esports_weapons.spray_data then
		esports_weapons.spray_data[pname] = nil
	end
	esports_weapons.unscope(player)
end)
core.register_on_leaveplayer(function(player)
	local pname = player:get_player_name()
	esports_weapons.cooldowns[pname] = nil
	if esports_weapons.last_ammo_warn then
		esports_weapons.last_ammo_warn[pname] = nil
	end
	if esports_weapons.last_lockout_warn then
		esports_weapons.last_lockout_warn[pname] = nil
	end
	if esports_weapons.spray_data then
		esports_weapons.spray_data[pname] = nil
	end
	esports_weapons.unscope(player)
end)

-- Ballistic Sniper Projectile Entity (Gravity Drop & Travel Time)
core.register_entity("esports_weapons:sniper_bullet", {
	initial_properties = {
		visual = "sprite",
		textures = {"esports_tracer.png^[colorize:#00E5FF:255"},
		visual_size = {x = 0.5, y = 0.5},
		physical = false,
		pointable = false,
		glow = 14,
		collisionbox = {-0.1, -0.1, -0.1, 0.1, 0.1, 0.1},
	},
	_shooter = "",
	_shooter_team = nil,
	_last_pos = nil,
	_age = 0,

	on_step = function(self, dtime)
		self._age = self._age + dtime
		local pos = self.object:get_pos()
		if not pos or self._age > 1.5 or pos.y < -20 then
			self.object:remove()
			return
		end

		if not self._last_pos then
			self._last_pos = vector.new(pos)
			return
		end

		-- Glowing bullet tracer vapor trail so the flight arc is clearly visible
		core.add_particle({
			pos = pos,
			velocity = {x = 0, y = 0, z = 0},
			expirationtime = 0.35,
			size = 1.6,
			texture = "esports_tracer.png^[colorize:#00E5FF:220",
			glow = 14,
		})

		local ray = core.raycast(self._last_pos, pos, true, false)
		for pt in ray do
			if pt.type == "object" then
				local obj = pt.ref
				local pname = self._shooter
				if obj and obj:is_player() and obj:get_player_name() ~= pname then
					local target_name = obj:get_player_name()
					if not esports_core.is_spectator(target_name) and not (esports_core.is_in_lobby and esports_core.is_in_lobby(target_name)) then
						local shooter_player = core.get_player_by_name(pname)
						local target_team = esports_core.match.get_player_match_side(target_name)
						local same_team = self._shooter_team and target_team and (self._shooter_team == target_team)

						if not same_team or esports_core.match.friendly_fire then
							-- Headshot Check (eye height is ~1.62m, upper head is >= 1.35m relative to origin)
							local target_pos = obj:get_pos()
							local hit_y = pt.intersection_point and pt.intersection_point.y or pos.y
							local is_headshot = (hit_y - target_pos.y) >= 1.35

							local damage = is_headshot and 110 or 75
							if is_headshot then
								core.chat_send_player(pname, "🎯 HEADSHOT CRITICAL! (110 DMG)")
								core.sound_play("player_damage", {to_player = pname, gain = 1.0, pitch = 1.6})
							end

							obj:punch(shooter_player or obj, 1.0, {
								full_punch_interval = 0.5,
								damage_groups = {fleshy = damage, is_gun = 1}
							}, vector.direction(self._last_pos, pos))

							-- Impact blood/spark particles
							core.add_particlespawner({
								amount = 8,
								time = 0.1,
								minpos = pt.intersection_point or pos,
								maxpos = pt.intersection_point or pos,
								minvel = {x=-1, y=0, z=-1},
								maxvel = {x=1, y=2, z=1},
								texture = "esports_tracer.png^[colorize:#FF0000:200",
								minexptime = 0.2,
								maxexptime = 0.5,
								minsize = 1,
								maxsize = 2,
							})

							self.object:remove()
							return
						end
					end
				elseif obj and obj:get_luaentity() then
					local ent = obj:get_luaentity()
					if ent.name == "esports_core:bot" then
						local shooter_player = core.get_player_by_name(pname)
						local target_pos = obj:get_pos()
						local hit_y = pt.intersection_point and pt.intersection_point.y or pos.y
						local is_headshot = target_pos and ((hit_y - target_pos.y) >= 1.35)

						local damage = is_headshot and 110 or 75
						if is_headshot and shooter_player then
							core.chat_send_player(pname, "🎯 HEADSHOT CRITICAL! (110 DMG)")
							core.sound_play("player_damage", {to_player = pname, gain = 1.0, pitch = 1.6})
						end

						obj:punch(shooter_player or obj, 1.0, {
							full_punch_interval = 0.5,
							damage_groups = {fleshy = damage, is_gun = 1}
						}, vector.direction(self._last_pos, pos))

						-- Impact blood/spark particles
						core.add_particlespawner({
							amount = 8,
							time = 0.1,
							minpos = pt.intersection_point or pos,
							maxpos = pt.intersection_point or pos,
							minvel = {x=-1, y=0, z=-1},
							maxvel = {x=1, y=2, z=1},
							texture = "esports_tracer.png^[colorize:#FF0000:200",
							minexptime = 0.2,
							maxexptime = 0.5,
							minsize = 1,
							maxsize = 2,
						})

						self.object:remove()
						return
					elseif ent.name == "esports_core:practice_target" then
						local shooter_player = core.get_player_by_name(pname)
						obj:punch(shooter_player or obj, 1.0, {
							full_punch_interval = 0.5,
							damage_groups = {fleshy = 75, is_gun = 1}
						}, vector.direction(self._last_pos, pos))
						self.object:remove()
						return
					elseif ent.name ~= "__builtin:item" and ent.name ~= "esports_weapons:sniper_bullet" then
						local shooter_player = core.get_player_by_name(pname)
						obj:punch(shooter_player or obj, 1.0, {
							full_punch_interval = 0.5,
							damage_groups = {fleshy = 75, is_gun = 1}
						}, vector.direction(self._last_pos, pos))
						self.object:remove()
						return
					end
				end
			elseif pt.type == "node" then
				local node_pos = pt.under
				local node = core.get_node(node_pos)
				local shooter_player = core.get_player_by_name(self._shooter)
				if core.get_item_group(node.name, "player_built") > 0 then
					esports_weapons.damage_node(node_pos, node, 45, shooter_player)
				elseif node.name == "esports_loot:box" then
					esports_weapons.damage_node(node_pos, node, 45, shooter_player)
				end

				-- Impact dust
				core.add_particlespawner({
					amount = 6,
					time = 0.1,
					minpos = pt.intersection_point or pos,
					maxpos = pt.intersection_point or pos,
					minvel = {x=-0.5, y=0.5, z=-0.5},
					maxvel = {x=0.5, y=1.5, z=0.5},
					texture = "esports_muzzle_flash.png^[colorize:#CCCCCC:150",
					minexptime = 0.2,
					maxexptime = 0.4,
				})
				self.object:remove()
				return
			end
		end

		self._last_pos = vector.new(pos)
	end
})

-- Configuration for weapons capable of continuous full-automatic fire
esports_weapons.auto_weapons = {
	["esports_weapons:smg"] = {
		ammo = "esports_weapons:smg_ammo",
		damage = 12,
		range = 35,
		base_spread = 0.02,
		max_spread = 0.12,
		spread_growth = 0.010,
		recovery_time = 0.30,
		fire_rate = 0.11,
		sound = "esports_shoot_assault_rifle",
		sound_gain = 0.5,
		sound_pitch = 1.3,
		sound_dist = 28,
		out_msg = "Out of SMG ammo!",
	},
	["esports_weapons:assault_rifle"] = {
		ammo = "esports_weapons:rifle_ammo",
		damage = 10,
		range = 50,
		base_spread = 0.015,
		max_spread = 0.09,
		spread_growth = 0.008,
		recovery_time = 0.35,
		fire_rate = 0.20,
		sound = "esports_shoot_assault_rifle",
		sound_gain = 1.0,
		sound_pitch = 1.0,
		sound_dist = 32,
		out_msg = "Out of rifle ammo!",
	},
}

function esports_weapons.try_fire_auto(user, item_name)
	if not user or not user:is_player() then return false end
	if user:get_hp() <= 0 then return false end
	local p_name = user:get_player_name()

	if esports_core.is_spectator(p_name) or (esports_core.is_in_lobby and esports_core.is_in_lobby(p_name)) then
		return false
	end

	-- CTF TACTICAL LOCKOUT: Cannot fire while carrying flag
	if user:get_meta():get_int("has_flag") == 1 then
		local current_time = core.get_us_time() / 1000000
		local last_warn = esports_weapons.last_lockout_warn[p_name] or 0
		if current_time - last_warn >= 2.0 then
			core.chat_send_player(p_name, "TACTICAL LOCKOUT: You cannot fire while carrying the flag! Rely on your team for cover.")
			esports_weapons.last_lockout_warn[p_name] = current_time
		end
		return false
	end

	local wep = esports_weapons.auto_weapons[item_name]
	if not wep then
		return false
	end

	local current_time = core.get_us_time() / 1000000
	local cd = esports_weapons.cooldowns[p_name] or 0

	-- Jitter tolerance of 0.02s ensures sub-tick engine/step variance doesn't drop shots
	if (current_time + 0.02) < cd then
		return false
	end

	local inv = user:get_inventory()
	local count = 0
	if inv:contains_item("ammo", wep.ammo) then
		inv:remove_item("ammo", wep.ammo .. " 1")
		count = 1
	elseif inv:contains_item("main", wep.ammo) then
		inv:remove_item("main", wep.ammo .. " 1")
		count = 1
	end

	if count > 0 then
		-- Dynamic spread bloom calculation based on continuous firing hold
		local spray = esports_weapons.spray_data[p_name]
		if not spray or spray.wielded ~= item_name then
			spray = { count = 0, last_shot = 0, wielded = item_name }
			esports_weapons.spray_data[p_name] = spray
		end

		local recovery = wep.recovery_time or 0.30
		local dt_since_last = current_time - spray.last_shot

		if dt_since_last > recovery then
			-- Recoil fully recovered
			spray.count = 0
		elseif dt_since_last > (wep.fire_rate * 1.5) then
			-- Partial recovery between quick bursts
			local idle = dt_since_last - wep.fire_rate
			local decay_shots = math.floor(idle / (recovery / 6))
			spray.count = math.max(0, spray.count - decay_shots)
		end

		-- Spread for the current round
		local dynamic_spread = math.min(wep.max_spread, wep.base_spread + (spray.count * wep.spread_growth))

		-- Advance spray counter for next continuous round
		spray.count = spray.count + 1
		spray.last_shot = current_time

		-- Track shots in practice mode
		if esports_core.practice and esports_core.practice.players then
			local session = esports_core.practice.players[p_name]
			if session then
				session.shots = session.shots + 1
			end
		end

		esports_weapons.shoot_raycast(user, wep.damage, wep.range, dynamic_spread)
		esports_weapons.cooldowns[p_name] = current_time + wep.fire_rate

		core.sound_play(wep.sound, {
			pos = user:get_pos(),
			max_hear_distance = wep.sound_dist or 32,
			gain = wep.sound_gain or 1.0,
			pitch = wep.sound_pitch or 1.0,
		})

		esports_core.hud.update_ammo(user)
		return true
	else
		local last_warn = esports_weapons.last_ammo_warn[p_name] or 0
		if current_time - last_warn >= 1.5 then
			core.chat_send_player(p_name, wep.out_msg)
			esports_weapons.last_ammo_warn[p_name] = current_time
			core.sound_play("player_punch", {to_player = p_name, gain = 0.2, pitch = 2.0})
		end
		esports_weapons.cooldowns[p_name] = current_time + 0.25
		return false
	end
end

-- Continuous full-automatic fire loop: checks held LMB every server tick
core.register_globalstep(function(_dtime)
	for _, player in ipairs(core.get_connected_players()) do
		if player:get_hp() > 0 then
			local ctrl = player:get_player_control()
			if ctrl.LMB then
				local wielded = player:get_wielded_item():get_name()
				if esports_weapons.auto_weapons[wielded] then
					esports_weapons.try_fire_auto(player, wielded)
				end
			end
		end
	end
end)

core.register_tool("esports_weapons:assault_rifle", {
	description = "Assault Rifle",
	inventory_image = "esports_weapons_assault_rifle.png",
	wield_image = "esports_weapons_assault_rifle_wield.png",
	wield_scale = {x=1.5, y=1.5, z=1.5},
	on_use = function(itemstack, user, pointed_thing)
		if esports_weapons.handle_interaction(user, pointed_thing) then
			return itemstack
		end
		esports_weapons.try_fire_auto(user, "esports_weapons:assault_rifle")
		return itemstack
	end,
})

core.register_craftitem("esports_weapons:rifle_ammo", {
	description = "Rifle Ammo",
	inventory_image = "esports_weapons_rifle_ammo.png",
	stack_max = 100,
})

core.register_tool("esports_weapons:shotgun", {
	description = "Pump Shotgun",
	inventory_image = "esports_weapons_shotgun.png",
	wield_image = "esports_weapons_shotgun_wield.png",
	wield_scale = {x=1.5, y=1.5, z=1.5},
	on_use = function(itemstack, user, pointed_thing)
		if esports_weapons.handle_interaction(user, pointed_thing) then
			return itemstack
		end
		local p_name = user:get_player_name()

		-- CTF TACTICAL LOCKOUT: Cannot fire while carrying flag
		if user:get_meta():get_int("has_flag") == 1 then
			core.chat_send_player(p_name, "TACTICAL LOCKOUT: You cannot fire while carrying the flag! Rely on your team for cover.")
			return itemstack
		end

		local current_time = core.get_us_time() / 1000000
		local cd = esports_weapons.cooldowns[p_name] or 0
		local inv = user:get_inventory()

		if current_time >= cd then
			-- Try to take from ammo stash first, fallback to main for legacy
			local count = 0
			if inv:contains_item("ammo", "esports_weapons:shotgun_ammo") then
				inv:remove_item("ammo", "esports_weapons:shotgun_ammo 1")
				count = 1
			elseif inv:contains_item("main", "esports_weapons:shotgun_ammo") then
				inv:remove_item("main", "esports_weapons:shotgun_ammo 1")
				count = 1
			end

			if count > 0 then
				if esports_core.practice and esports_core.practice.players then
					local session = esports_core.practice.players[p_name]
					if session then
						session.shots = session.shots + 1
					end
				end
				for _ = 1, 8 do
					-- Shotgun deals 4.2 per pellet (33.6 total per blast)
					-- 3 hits = 100.8 damage (Lethal for 100 HP players)
					esports_weapons.shoot_raycast(user, 4.2, 30, 0.2)
				end
				esports_weapons.cooldowns[p_name] = current_time + 1.0

				-- Play sound
				core.sound_play("esports_shoot_shotgun", {pos = user:get_pos(), max_hear_distance = 32})

				-- Update HUD
				esports_core.hud.update_ammo(user)
			else
				core.chat_send_player(p_name, "Out of shotgun ammo!")
			end
		end
		return itemstack
	end,
})

core.register_craftitem("esports_weapons:shotgun_ammo", {
	description = "Shotgun Ammo",
	inventory_image = "esports_weapons_shotgun_ammo.png",
	stack_max = 50,
})

core.register_tool("esports_weapons:sniper_rifle", {
	description = "Ballistic Sniper Rifle (Right-Click Scope)",
	inventory_image = "esports_weapons_sniper_rifle.png",
	wield_image = "esports_weapons_sniper_rifle_wield.png",
	wield_scale = {x=1.6, y=1.6, z=1.6},
	on_secondary_use = function(itemstack, user)
		esports_weapons.toggle_scope(user)
		return itemstack
	end,
	on_place = function(itemstack, user, _pointed_thing)
		esports_weapons.toggle_scope(user)
		return itemstack
	end,
	on_use = function(itemstack, user, pointed_thing)
		if esports_weapons.handle_interaction(user, pointed_thing) then
			return itemstack
		end
		local p_name = user:get_player_name()

		-- CTF TACTICAL LOCKOUT
		if user:get_meta():get_int("has_flag") == 1 then
			core.chat_send_player(p_name, "TACTICAL LOCKOUT: You cannot fire while carrying the flag! Rely on your team for cover.")
			return itemstack
		end

		local current_time = core.get_us_time() / 1000000
		local cd = esports_weapons.cooldowns[p_name] or 0
		local inv = user:get_inventory()

		if current_time >= cd then
			local count = 0
			if inv:contains_item("ammo", "esports_weapons:sniper_ammo") then
				inv:remove_item("ammo", "esports_weapons:sniper_ammo 1")
				count = 1
			elseif inv:contains_item("main", "esports_weapons:sniper_ammo") then
				inv:remove_item("main", "esports_weapons:sniper_ammo 1")
				count = 1
			end

			if count > 0 then
				if esports_core.practice and esports_core.practice.players then
					local session = esports_core.practice.players[p_name]
					if session then
						session.shots = session.shots + 1
					end
				end
				local is_scoped = (esports_weapons.scoped_players[p_name] ~= nil)
				local dir = user:get_look_dir()
				local pos = user:get_pos()
				pos.y = pos.y + user:get_properties().eye_height

				-- Spread: Scoped has 0 spread; hip-fire has slight spread
				local spread = is_scoped and 0 or 0.05
				local cdef = esports_core.skins and esports_core.skins.get_player_class and esports_core.skins.get_player_class(user)
				if cdef and cdef.spread_mult then
					spread = spread * cdef.spread_mult
				end

				if spread > 0 then
					dir.x = dir.x + (math.random() - 0.5) * spread
					dir.y = dir.y + (math.random() - 0.5) * spread
					dir.z = dir.z + (math.random() - 0.5) * spread
					local len = math.sqrt(dir.x*dir.x + dir.y*dir.y + dir.z*dir.z)
					dir = vector.divide(dir, len)
				end

				-- Spawn Ballistic Projectile: 200 m/s velocity with -9.8 gravity
				local spawn_pos = vector.add(pos, vector.multiply(dir, 1.2))
				local bullet = core.add_entity(spawn_pos, "esports_weapons:sniper_bullet")
				if bullet then
					local ent = bullet:get_luaentity()
					if ent then
						ent._shooter = p_name
						ent._shooter_team = esports_core.match.get_player_match_side(p_name)
						ent._last_pos = vector.new(spawn_pos)
					end
					bullet:set_velocity(vector.multiply(dir, 140))
					bullet:set_acceleration({x = 0, y = -11.0, z = 0})
				end

				-- Muzzle Flash
				core.add_particle({
					pos = spawn_pos,
					velocity = {x=0, y=0, z=0},
					acceleration = {x=0, y=0, z=0},
					expirationtime = 0.1,
					size = 2.0,
					texture = "esports_muzzle_flash.png",
					glow = 14,
				})

				esports_weapons.cooldowns[p_name] = current_time + 1.5 -- Bolt Action

				-- Booming high-caliber sniper gunshot sound
				core.sound_play("esports_shoot_sniper", {pos = user:get_pos(), max_hear_distance = 80, gain = 1.0})

				esports_core.hud.update_ammo(user)
			else
				core.chat_send_player(p_name, "Out of sniper ammo!")
			end
		end
		return itemstack
	end,
})

core.register_craftitem("esports_weapons:sniper_ammo", {
	description = "Sniper Ammo",
	inventory_image = "esports_weapons_sniper_ammo.png",
	stack_max = 30,
})

core.register_tool("esports_weapons:smg", {
	description = "Tactical SMG",
	inventory_image = "esports_weapons_smg.png",
	wield_image = "esports_weapons_smg_wield.png",
	wield_scale = {x=1.3, y=1.3, z=1.3},
	on_use = function(itemstack, user, pointed_thing)
		if esports_weapons.handle_interaction(user, pointed_thing) then
			return itemstack
		end
		esports_weapons.try_fire_auto(user, "esports_weapons:smg")
		return itemstack
	end,
})

core.register_craftitem("esports_weapons:smg_ammo", {
	description = "SMG Ammo",
	inventory_image = "esports_weapons_smg_ammo.png",
	stack_max = 120,
})

core.register_craftitem("esports_weapons:health_pack", {
	description = "Health Pack (+20% HP)",
	inventory_image = "esports_weapons_health_pack.png",
	stack_max = 5,
	on_use = function(itemstack, user, pointed_thing)
		if esports_weapons.handle_interaction(user, pointed_thing) then
			return itemstack
		end
		local pname = user:get_player_name()
		if esports_core.is_in_lobby and esports_core.is_in_lobby(pname) then
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
		core.sound_play("esports_heal", {pos = user:get_pos(), gain = 1.0, max_hear_distance = 16})

		-- Consume item
		itemstack:take_item()
		return itemstack
	end,
})

core.register_tool("esports_weapons:pickaxe", {
	description = "Harvesting Tool",
	inventory_image = "esports_weapons_pickaxe.png",
	wield_image = "esports_weapons_pickaxe_wield.png",
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
	if esports_core.is_spectator(pname) then
		return itemstack  -- Spectators can't pick up anything
	end

	local item_name = itemstack:get_name()
	local inv = picker:get_inventory()

	-- Auto-sort ammo into the hidden stash
	if item_name == "esports_weapons:rifle_ammo" or item_name == "esports_weapons:shotgun_ammo" or
	   item_name == "esports_weapons:sniper_ammo" or item_name == "esports_weapons:smg_ammo" then
		local leftover = inv:add_item("ammo", itemstack)
		if leftover:get_count() < itemstack:get_count() then
			if pointed_thing and pointed_thing.ref then
				pointed_thing.ref:remove()
				core.sound_play("esports_pickup", {pos = picker:get_pos(), gain = 0.5})
			end
			esports_core.hud.update_ammo(picker)
		end
		return leftover
	end

	if item_name == "esports_weapons:assault_rifle" or item_name == "esports_weapons:shotgun" or
	   item_name == "esports_weapons:sniper_rifle" or item_name == "esports_weapons:smg" then
		local ammo_name = "esports_weapons:rifle_ammo"
		local count = 20
		if item_name == "esports_weapons:shotgun" then
			ammo_name = "esports_weapons:shotgun_ammo"
			count = 8
		elseif item_name == "esports_weapons:sniper_rifle" then
			ammo_name = "esports_weapons:sniper_ammo"
			count = 5
		elseif item_name == "esports_weapons:smg" then
			ammo_name = "esports_weapons:smg_ammo"
			count = 30
		end

		if inv:contains_item("main", item_name) then
			-- Convert duplicate to ammo
			inv:add_item("ammo", ammo_name .. " " .. count)

			if pointed_thing and pointed_thing.ref then
				pointed_thing.ref:remove()
				core.sound_play("esports_pickup", {pos = picker:get_pos(), gain = 0.5})
			end
			esports_core.hud.update_ammo(picker)
			return ItemStack("")  -- Successfully scavenged
		else
			-- First time pickup: Give weapon starting at slot 4+ (leaving slot 1 empty)
			local leftover = itemstack
			local main_list = inv:get_list("main")
			for i = 4, #main_list do
				if main_list[i]:is_empty() then
					inv:set_stack("main", i, itemstack)
					leftover = ItemStack("")
					break
				end
			end
			-- Fallback if all slots from 4 onwards are full
			if not leftover:is_empty() then
				leftover = inv:add_item("main", itemstack)
			end
			if leftover:get_count() < itemstack:get_count() then
				inv:add_item("ammo", ammo_name .. " " .. count)

				if pointed_thing and pointed_thing.ref then
					pointed_thing.ref:remove()
					core.sound_play("esports_pickup", {pos = picker:get_pos(), gain = 0.5})
				end
				esports_core.hud.update_ammo(picker)
			end
			return leftover
		end
	end

	-- Manually implement pickup for other items (e.g. pickaxe, health pack) into 'main'
	local leftover = inv:add_item("main", itemstack)

	if leftover:get_count() < itemstack:get_count() then
		if pointed_thing and pointed_thing.ref then
			pointed_thing.ref:remove()
			core.sound_play("esports_pickup", {pos = picker:get_pos(), gain = 0.5})
		end
	end

	return leftover
end)

core.register_on_punchnode(function(pos, node, puncher)
	if not puncher or not puncher:is_player() then return end
	local pname = puncher:get_player_name()
	if esports_core.is_spectator(pname) or (esports_core.is_in_lobby and esports_core.is_in_lobby(pname)) then return end

	-- Melee Damage:
	-- If holding pickaxe, deal 25 damage to the block.
	-- Otherwise (hand, blueprints, guns, healthpack etc.), deal 10 damage to the block.
	local item = puncher:get_wielded_item():get_name()
	local damage = 10
	if item == "esports_weapons:pickaxe" then
		damage = 25
	end

	-- CTF Base Protection check
	if esports_core.match.is_ctf and esports_core.ctf then
		local red_base = esports_core.ctf.bases.red
		local blue_base = esports_core.ctf.bases.blue
		local d_red = vector.distance(pos, red_base)
		local d_blue = vector.distance(pos, blue_base)
		if d_red < 30 or d_blue < 30 then
			if not core.check_player_privs(pname, {server=true}) and not core.check_player_privs(pname, {admin=true}) then
				return  -- Protected area, don't allow damage
			end
		end
	end

	-- Apply Class Demolition Multiplier (e.g. Elite Soldier Tank perk)
	local cdef = esports_core.skins and esports_core.skins.get_player_class and esports_core.skins.get_player_class(puncher)
	if cdef and cdef.demo_mult and cdef.demo_mult ~= 1.0 then
		damage = math.floor(damage * cdef.demo_mult + 0.5)
	end

	esports_weapons.damage_node(pos, node, damage, puncher)
end)

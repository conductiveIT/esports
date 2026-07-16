esports_weapons = {}
esports_weapons.cooldowns = {}  -- player_name -> timer

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

-- Wait, Minetest usually relies on image files to not error out completely,
-- But we can use colorization on a dummy transparent or white texture if we don't have images.
-- For now, we will create simple colored squares for textures using texturing modifiers.

core.register_tool("esports_weapons:assault_rifle", {
	description = "Assault Rifle",
	inventory_image = "esports_weapons_assault_rifle.png",
	wield_image = "esports_weapons_assault_rifle_wield.png",
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
			if inv:contains_item("ammo", "esports_weapons:rifle_ammo") then
				inv:remove_item("ammo", "esports_weapons:rifle_ammo 1")
				count = 1
			elseif inv:contains_item("main", "esports_weapons:rifle_ammo") then
				inv:remove_item("main", "esports_weapons:rifle_ammo 1")
				count = 1
			end

			if count > 0 then
				-- Rifle deals 10 damage to players and nodes
				esports_weapons.shoot_raycast(user, 10, 50, 0.05)
				esports_weapons.cooldowns[p_name] = current_time + 0.15

				-- Play sound
				core.sound_play("esports_shoot_assault_rifle", {pos = user:get_pos(), max_hear_distance = 32})

				-- Update HUD
				esports_core.hud.update_ammo(user)
			else
				core.chat_send_player(p_name, "Out of rifle ammo!")
			end
		end
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
	if item_name == "esports_weapons:rifle_ammo" or item_name == "esports_weapons:shotgun_ammo" then
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

	if item_name == "esports_weapons:assault_rifle" or item_name == "esports_weapons:shotgun" then
		local ammo_name = (item_name == "esports_weapons:assault_rifle") and "esports_weapons:rifle_ammo" or "esports_weapons:shotgun_ammo"
		local count = (item_name == "esports_weapons:assault_rifle") and 20 or 8

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
			-- First time pickup: Give weapon AND starting ammo
			local leftover = inv:add_item("main", itemstack)
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

	esports_weapons.damage_node(pos, node, damage, puncher)
end)

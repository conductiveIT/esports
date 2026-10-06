-- mods/esports_core/practice_range.lua
-- Tactical Practice Range & Aim Trainer for Luanti Deathmatch Core

esports_core.practice = {}
esports_core.practice.players = {} -- name -> {hits=0, shots=0, start_time=0}

local arena_pos = {x = 2000, y = 100, z = 2000}

function esports_core.practice.leave(name)
	local player = core.get_player_by_name(name)
	if player then
		esports_core.practice.players[name] = nil
		player:set_pos({x = 0, y = 1.5, z = 0})
		esports_core.reset_to_lobby(player)
		esports_core.lobby.show(player)
	end
end

core.register_craftitem("esports_core:return_to_lobby", {
	description = "STOP Practice (Right-click to return to Lobby)",
	inventory_image = "esports_feed_skull.png^[colorize:#FF3333:200",
	stack_max = 1,
	on_use = function(itemstack, user, pointed_thing)
		if user and user:is_player() then
			local name = user:get_player_name()
			esports_core.practice.leave(name)
		end
		return itemstack
	end,
	on_drop = function(itemstack, dropper, pos)
		return itemstack
	end,
})

local function build_practice_arena()
	local minp = {x = arena_pos.x - 18, y = arena_pos.y - 2, z = arena_pos.z - 18}
	local maxp = {x = arena_pos.x + 18, y = arena_pos.y + 10, z = arena_pos.z + 18}

	-- Ensure map chunk is emerged before reading/writing voxelmanip
	core.emerge_area(minp, maxp)

	local vm = VoxelManip()
	local emin, emax = vm:read_from_map(minp, maxp)
	local area = VoxelArea:new{MinEdge = emin, MaxEdge = emax}
	local data = vm:get_data()

	local c_stone = core.registered_nodes["esports_mapgen:stone"] and core.get_content_id("esports_mapgen:stone") or core.CONTENT_AIR
	local c_wall = core.registered_nodes["esports_building:player_wall"] and core.get_content_id("esports_building:player_wall") or c_stone
	local c_light = core.registered_nodes["esports_core:studio_light"] and core.get_content_id("esports_core:studio_light") or c_wall
	local c_air = core.CONTENT_AIR

	local ystride = emax.x - emin.x + 1

	for z = arena_pos.z - 15, arena_pos.z + 15 do
		local abs_z = math.abs(z - arena_pos.z)
		for x = arena_pos.x - 15, arena_pos.x + 15 do
			local abs_x = math.abs(x - arena_pos.x)
			local vi = area:index(x, arena_pos.y - 1, z)

			-- Floor (y = arena_pos.y - 1)
			data[vi] = c_stone
			vi = vi + ystride

			-- Clear air & build walls (y = 0 to 8)
			for y = 0, 8 do
				if (abs_x == 15 or abs_z == 15) and y <= 5 then
					-- Border lights along the top for full visibility
					if y == 5 and (abs_x == 15 and abs_z == 15 or abs_x == 0 or abs_z == 0) then
						data[vi] = c_light
					else
						data[vi] = c_wall
					end
				else
					data[vi] = c_air
				end
				vi = vi + ystride
			end
		end
	end

	vm:set_data(data)
	vm:write_to_map()
	vm:update_map()
end

-- Target Entity definition
core.register_entity("esports_core:practice_target", {
	initial_properties = {
		physical = false,
		collisionbox = {-0.6, -0.6, -0.6, 0.6, 0.6, 0.6},
		selectionbox = {-0.6, -0.6, -0.6, 0.6, 0.6, 0.6},
		pointable = true,
		visual = "sprite",
		visual_size = {x = 1.5, y = 1.5},
		textures = {"esports_logo_red.png"}, -- Emissive target visual
		glow = 14,
		hp_max = 10000,
		armor_groups = {immortal = 1}, -- Immortal prevents engine death from weapon raycasts
	},
	on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir)
		if not puncher or not puncher:is_player() then return end
		local pname = puncher:get_player_name()

		-- Restore health so engine never destroys the target entity
		self.object:set_hp(10000)

		-- Play hit sound
		core.sound_play("player_punch", {to_player = pname, gain = 1.0})

		-- Calculate response
		local session = esports_core.practice.players[pname]
		if session then
			session.hits = session.hits + 1
			if session.shots < session.hits then
				session.shots = session.hits
			end
			local accuracy = 0
			if session.shots > 0 then
				accuracy = math.floor((session.hits / session.shots) * 100)
			end
			core.chat_send_player(pname, string.format("[AIM TRAINER] HIT! Hits: %d | Accuracy: %d%%", session.hits, accuracy))
			if esports_core.hud and esports_core.hud.update_personal_stats then
				local p = core.get_player_by_name(pname)
				if p then esports_core.hud.update_personal_stats(p) end
			end
		end

		-- Respawn target at new location in range
		local new_x = arena_pos.x + math.random(-10, 10)
		local new_z = arena_pos.z + math.random(3, 12)
		local new_y = arena_pos.y + math.random(1, 3)

		self.object:set_pos({x = new_x, y = new_y, z = new_z})

		-- Determine lateral movement speed based on progression
		local vx = 0
		if session then
			if session.hits >= 20 then
				vx = (math.random() > 0.5 and 1 or -1) * 6
			elseif session.hits >= 10 then
				vx = (math.random() > 0.5 and 1 or -1) * 4
			elseif session.hits >= 5 then
				vx = (math.random() > 0.5 and 1 or -1) * 2
			end
		end
		self.object:set_velocity({x = vx, y = 0, z = 0})

		return true
	end,
	on_step = function(self, dtime)
		local pos = self.object:get_pos()
		if pos then
			local vel = self.object:get_velocity()
			if vel and vel.x ~= 0 then
				-- Bounce off left/right walls of the range
				if pos.x < arena_pos.x - 12 and vel.x < 0 then
					self.object:set_velocity({x = -vel.x, y = vel.y, z = vel.z})
				elseif pos.x > arena_pos.x + 12 and vel.x > 0 then
					self.object:set_velocity({x = -vel.x, y = vel.y, z = vel.z})
				end
			end
		end
	end,
})

-- Track player shots for accuracy
core.register_on_punchnode(function(pos, node, puncher, pointed_thing)
	if not puncher or not puncher:is_player() then return end
	local pname = puncher:get_player_name()
	local session = esports_core.practice.players[pname]
	if session then
		session.shots = session.shots + 1
	end
end)

core.register_on_punchplayer(function(player, hitter, time_from_last_punch, tool_capabilities, dir, damage)
	if hitter and hitter:is_player() then
		local pname = hitter:get_player_name()
		local session = esports_core.practice.players[pname]
		if session then
			session.shots = session.shots + 1
		end
	end
end)

function esports_core.practice.enter(name)
	local player = core.get_player_by_name(name)
	if not player then return false, "Player not found." end

	-- 1. Register practice session immediately so is_in_lobby returns false
	esports_core.practice.players[name] = {hits = 0, shots = 0, start_time = os.time()}

	-- 2. Build/refresh the arena structures
	build_practice_arena()

	-- 3. Reset previous targets
	for _, obj in ipairs(core.get_objects_inside_radius(arena_pos, 30)) do
		local ent = obj:get_luaentity()
		if ent and ent.name == "esports_core:practice_target" then
			obj:remove()
		end
	end

	-- 4. Spawn 3 new practice targets
	for _ = 1, 3 do
		local tx = arena_pos.x + math.random(-8, 8)
		local ty = arena_pos.y + math.random(1, 3)
		local tz = arena_pos.z + math.random(4, 10)
		core.add_entity({x = tx, y = ty, z = tz}, "esports_core:practice_target")
	end

	-- 5. Close Lobby GUI and Blackout
	esports_core.lobby.blackout_hide(player)
	core.close_formspec(name, "esports_core:lobby")

	-- 6. Restore Player Properties & Combat Interaction (Break Lobby Ghost Mode)
	local cdef = esports_core.skins and esports_core.skins.get_player_class and esports_core.skins.get_player_class(player)
	local class_hp = cdef and cdef.hp or 100
	local class_spd = cdef and cdef.base_speed or 1.2

	player:set_properties({
		hp_max = class_hp,
		visual_size = {x = 1, y = 1, z = 1},
		eye_height = 1.625,
		interact_distance = 10,
	})
	player:set_hp(class_hp)
	player:set_armor_groups({fleshy = 100})
	if esports_core.skins and esports_core.skins.apply then
		esports_core.skins.apply(player, nil)
	end

	-- 7. Restore Essential Privileges
	local privs = core.get_player_privs(name)
	privs.interact = true
	privs.shout = true
	core.set_player_privs(name, privs)

	-- 8. Unfreeze Physics
	player:set_physics_override({
		speed = class_spd,
		jump = 1.1,
		gravity = 1.0,
	})

	-- 9. Clear Weapon Cooldowns
	if esports_weapons and esports_weapons.cooldowns then
		esports_weapons.cooldowns[name] = 0
	end

	-- 10. Teleport Player to shooting station
	player:set_pos({x = arena_pos.x, y = arena_pos.y + 0.5, z = arena_pos.z - 10})
	player:set_look_horizontal(0) -- Look North (towards targets)
	player:set_look_vertical(0)

	-- 11. Give Weapons, Ammo & Return Item
	local inv = player:get_inventory()
	inv:set_list("main", {})
	inv:set_list("ammo", {})
	inv:add_item("main", "esports_weapons:assault_rifle")
	inv:add_item("main", "esports_weapons:shotgun")
	inv:add_item("main", "esports_weapons:sniper_rifle")
	inv:add_item("main", "esports_weapons:smg")
	inv:add_item("ammo", "esports_weapons:rifle_ammo 500")
	inv:add_item("ammo", "esports_weapons:shotgun_ammo 100")
	inv:add_item("ammo", "esports_weapons:sniper_ammo 100")
	inv:add_item("ammo", "esports_weapons:smg_ammo 500")
	inv:set_stack("main", 8, ItemStack("esports_core:return_to_lobby"))

	-- 12. Initialize HUD & Stamina
	esports_core.hud.init_hud(player)
	if esports_core.sprint then
		esports_core.sprint.reset_player(player)
	end

	core.chat_send_player(name, "===============================================")
	core.chat_send_player(name, "  WELCOME TO THE TACTICAL AIM TRAINING RANGE    ")
	core.chat_send_player(name, "  Shoot the targets to train your accuracy!     ")
	core.chat_send_player(name, "  Use the 'STOP Practice' item (slot 8) or      ")
	core.chat_send_player(name, "  type /lobby to exit the range.               ")
	core.chat_send_player(name, "===============================================")
	return true, "Teleported to practice range."
end

core.register_chatcommand("practice", {
	description = "Teleport to the tactical Practice Range (Aim Trainer)",
	func = function(name, param)
		return esports_core.practice.enter(name)
	end
})

core.register_on_leaveplayer(function(player)
	esports_core.practice.players[player:get_player_name()] = nil
end)

-- Hook into raycast shooting to track gun shots for the aim trainer
core.register_on_mods_loaded(function()
	if esports_weapons and esports_weapons.shoot_raycast then
		local old_shoot_raycast = esports_weapons.shoot_raycast
		esports_weapons.shoot_raycast = function(player, damage, range, spread)
			local pname = player:get_player_name()
			local session = esports_core.practice.players[pname]
			if session then
				session.shots = session.shots + 1
				if esports_core.hud and esports_core.hud.update_personal_stats then
					esports_core.hud.update_personal_stats(player)
				end
			end
			return old_shoot_raycast(player, damage, range, spread)
		end
	end
end)

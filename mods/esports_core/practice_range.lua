esports_core.practice = {}
esports_core.practice.players = {} -- name -> {hits=0, shots=0, start_time=0}

core.register_craftitem("esports_core:return_to_lobby", {
	description = "STOP Practice (Right-click to return to Lobby)",
	inventory_image = "esports_feed_skull.png^[colorize:#FF3333:200",
	stack_max = 1,
	on_use = function(itemstack, user, pointed_thing)
		if user and user:is_player() then
			local name = user:get_player_name()
			local cmd = core.registered_chatcommands["lobby"]
			if cmd then
				cmd.func(name)
			end
		end
		return itemstack
	end,
	on_drop = function(itemstack, dropper, pos)
		return itemstack
	end,
})

local arena_pos = {x = 2000, y = 100, z = 2000}

local function build_practice_arena()
	local minp = {x = arena_pos.x - 16, y = arena_pos.y - 2, z = arena_pos.z - 16}
	local maxp = {x = arena_pos.x + 16, y = arena_pos.y + 10, z = arena_pos.z + 16}

	local vm = VoxelManip()
	local emin, emax = vm:read_from_map(minp, maxp)
	local area = VoxelArea:new{MinEdge = emin, MaxEdge = emax}
	local data = vm:get_data()

	-- Try to get default mod content IDs, fallback to esports equivalents or air if not found
	local c_stone
	if core.registered_nodes["default:stone"] then
		c_stone = core.get_content_id("default:stone")
	elseif core.registered_nodes["esports_mapgen:stone"] then
		c_stone = core.get_content_id("esports_mapgen:stone")
	else
		c_stone = core.CONTENT_AIR
	end

	local c_air = core.CONTENT_AIR

	local c_brick
	if core.registered_nodes["default:brick"] then
		c_brick = core.get_content_id("default:brick")
	elseif core.registered_nodes["esports_building:player_wall"] then
		c_brick = core.get_content_id("esports_building:player_wall")
	elseif core.registered_nodes["esports_mapgen:stone"] then
		c_brick = core.get_content_id("esports_mapgen:stone")
	else
		c_brick = core.CONTENT_AIR
	end

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
					data[vi] = c_brick
				else
					data[vi] = c_air
				end
				vi = vi + ystride
			end
		end
	end

	vm:set_data(data)
	vm:write_to_map()
end

-- Target Entity definition
core.register_entity("esports_core:practice_target", {
	initial_properties = {
		physical = false,
		collisionbox = {-0.4, -0.4, -0.4, 0.4, 0.4, 0.4},
		visual = "sprite",
		visual_size = {x=1.2, y=1.2},
		textures = {"esports_logo_red.png"}, -- Emissive target visual
		glow = 14,
	},
	on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir)
		if not puncher or not puncher:is_player() then return end
		local pname = puncher:get_player_name()

		-- Play hit sound
		core.sound_play("default_cool_item", {to_player = pname, gain = 0.9})

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
		end

		-- Respawn target at new location in range
		local new_x = arena_pos.x + math.random(-10, 10)
		local new_z = arena_pos.z + math.random(2, 12) -- Spawn in front of player spawn (Y=2000, Z=2000)
		local new_y = arena_pos.y + math.random(1, 3)

		self.object:set_pos({x=new_x, y=new_y, z=new_z})

		-- Determine movement speed based on hits (dynamic progression)
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
		self.object:set_velocity({x=vx, y=0, z=0})

		return true
	end,
	on_step = function(self, dtime)
		local pos = self.object:get_pos()
		if pos then
			local vel = self.object:get_velocity()
			if vel and vel.x ~= 0 then
				-- Bounce off left/right walls of the range (x range: arena_pos.x - 12 to arena_pos.x + 12)
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

-- Hook punch player/object for shot tracking
local old_register_on_punchplayer = core.register_on_punchplayer
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

	-- Build/refresh the arena structures
	build_practice_arena()

	-- Reset previous targets
	for _, obj in ipairs(core.get_objects_inside_radius(arena_pos, 30)) do
		local ent = obj:get_luaentity()
		if ent and ent.name == "esports_core:practice_target" then
			obj:remove()
		end
	end

	-- Spawn 3 new practice targets
	for i = 1, 3 do
		local tx = arena_pos.x + math.random(-8, 8)
		local ty = arena_pos.y + math.random(1, 3)
		local tz = arena_pos.z + math.random(4, 10)
		core.add_entity({x=tx, y=ty, z=tz}, "esports_core:practice_target")
	end

	-- Teleport player
	player:set_pos({x=arena_pos.x, y=arena_pos.y+0.5, z=arena_pos.z-10})
	player:set_look_horizontal(0) -- Look North (towards targets)
	player:set_look_vertical(0)

	-- Give weapons and ammo
	local inv = player:get_inventory()
	inv:set_list("main", {})
	inv:set_list("ammo", {})
	inv:add_item("main", "esports_weapons:assault_rifle")
	inv:add_item("main", "esports_weapons:shotgun")
	inv:add_item("ammo", "esports_weapons:rifle_ammo 500")
	inv:add_item("ammo", "esports_weapons:shotgun_ammo 100")
	inv:set_stack("main", 8, ItemStack("esports_core:return_to_lobby"))

	-- Start session tracking (initialize shots at 0 for accurate percentage calculations)
	esports_core.practice.players[name] = {hits = 0, shots = 0, start_time = os.time()}

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
			end
			return old_shoot_raycast(player, damage, range, spread)
		end
	end
end)

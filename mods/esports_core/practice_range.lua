esports_core.practice = {}
esports_core.practice.players = {} -- name -> {hits=0, shots=0, start_time=0}

local arena_pos = {x = 2000, y = 100, z = 2000}

local function build_practice_arena()
	-- Build stone floor
	for x = -15, 15 do
		for z = -15, 15 do
			core.set_node({x=arena_pos.x+x, y=arena_pos.y-1, z=arena_pos.z+z}, {name="default:stone"})
			-- Clear air inside
			for y = 0, 8 do
				core.set_node({x=arena_pos.x+x, y=arena_pos.y+y, z=arena_pos.z+z}, {name="air"})
			end
			-- Build walls
			if math.abs(x) == 15 or math.abs(z) == 15 then
				for y = 0, 5 do
					core.set_node({x=arena_pos.x+x, y=arena_pos.y+y, z=arena_pos.z+z}, {name="default:brick"})
				end
			end
		end
	end
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
			local accuracy = math.floor((session.hits / session.shots) * 100)
			core.chat_send_player(pname, string.format("[AIM TRAINER] HIT! Hits: %d | Accuracy: %d%%", session.hits, accuracy))
		end

		-- Respawn target at new location in range
		local new_x = arena_pos.x + math.random(-10, 10)
		local new_z = arena_pos.z + math.random(2, 12) -- Spawn in front of player spawn (Y=2000, Z=2000)
		local new_y = arena_pos.y + math.random(1, 3)

		self.object:set_pos({x=new_x, y=new_y, z=new_z})
		return true
	end
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

core.register_chatcommand("practice", {
	description = "Teleport to the tactical Practice Range (Aim Trainer)",
	func = function(name, param)
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

		-- Start session tracking
		esports_core.practice.players[name] = {hits = 0, shots = 1, start_time = os.time()}

		core.chat_send_player(name, "===============================================")
		core.chat_send_player(name, "  WELCOME TO THE TACTICAL AIM TRAINING RANGE    ")
		core.chat_send_player(name, "  Shoot the targets to train your accuracy!     ")
		core.chat_send_player(name, "  Type /lobby to exit the range.               ")
		core.chat_send_player(name, "===============================================")
		return true, "Teleported to practice range."
	end
})

core.register_on_leaveplayer(function(player)
	esports_core.practice.players[player:get_player_name()] = nil
end)

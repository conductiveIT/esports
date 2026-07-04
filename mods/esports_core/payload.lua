esports_core.payload = {}
esports_core.payload.cart_entity = nil
esports_core.payload.progress = 0
esports_core.payload.state = "stopped"

function esports_core.payload.reset()
	if esports_core.payload.cart_entity then
		esports_core.payload.cart_entity:remove()
		esports_core.payload.cart_entity = nil
	end
	-- Clean up any stray carts in the world
	local all_objs = core.get_objects_inside_radius({x=0, y=0, z=0}, 500)
	for _, obj in ipairs(all_objs) do
		local ent = obj:get_luaentity()
		if ent and ent.name == "esports_core:payload_cart" then
			obj:remove()
		end
	end
	esports_core.payload.progress = 0
	esports_core.payload.state = "stopped"
end

function esports_core.payload.spawn_cart()
	esports_core.payload.reset()

	local scale = esports_core.match.current_map_scale or 1.0
	local start_pos = {x = 80 * scale, y = 1.5, z = 0}

	esports_core.payload.cart_entity = core.add_entity(start_pos, "esports_core:payload_cart")

	core.chat_send_all(">> PAYLOAD: The cart has spawned at Red Base! RED Team: Escort it to BLUE Base!")
end

function esports_core.payload.update(dtime)
	-- This function can be called once per second from the match globalstep
	-- Primarily to accumulate escort time stats for players near the cart.
	if esports_core.match.state ~= "active" or not esports_core.match.is_payload then
		return
	end

	local cart = esports_core.payload.cart_entity
	if not cart or not cart:get_luaentity() then return end

	local pos = cart:get_pos()
	local radius = 8

	-- Award escort points (escort_time) to attackers standing near the cart
	for _, p in ipairs(core.get_connected_players()) do
		local pname = p:get_player_name()
		if not esports_core.is_spectator(pname) and p:get_hp() > 0 then
			local ppos = p:get_pos()
			local dist = vector.distance(pos, ppos)
			if dist <= radius then
				local side = esports_core.match.get_player_match_side(pname)
				-- Red is the attacker/escorter
				if side == "red" then
					if not esports_core.match.player_stats[pname] then
						esports_core.match.player_stats[pname] = {kills = 0, deaths = 0, captures = 0, escort_time = 0}
					end
					esports_core.match.player_stats[pname].escort_time = (esports_core.match.player_stats[pname].escort_time or 0) + 1
				end
			end
		end
	end
end

-- Register the Payload Cart Entity
core.register_entity("esports_core:payload_cart", {
	initial_properties = {
		visual = "cube",
		textures = {
			"esports_cart.png", -- top
			"esports_cart.png", -- bottom
			"esports_cart.png", -- right
			"esports_cart.png", -- left
			"esports_cart.png", -- back
			"esports_cart.png", -- front
		},
		visual_size = {x = 3.0, y = 2.0, z = 3.0},
		physical = true,
		collide_with_objects = true,
		collisionbox = {-1.5, -1.0, -1.5, 1.5, 1.0, 1.5},
		glow = 8,
		static_save = false,
	},

	_idle_timer = 0,
	_hud_timer = 0,
	_last_state = "stopped",

	on_activate = function(self, staticdata)
		self.object:set_armor_groups({immortal = 1})
		self.object:set_acceleration({x = 0, y = 0, z = 0})
	end,

	on_step = function(self, dtime)
		if esports_core.match.state ~= "active" or not esports_core.match.is_payload then
			self.object:set_velocity({x=0, y=0, z=0})
			return
		end

		local pos = self.object:get_pos()
		local scale = esports_core.match.current_map_scale or 1.0
		local start_x = 80 * scale
		local end_x = -80 * scale
		local total_dist = start_x - end_x

		-- Proximity scan
		local red_count = 0
		local blue_count = 0
		local red_players_list = {}
		local all_players_near = {}
		local radius = 8

		for _, p in ipairs(core.get_connected_players()) do
			local pname = p:get_player_name()
			if not esports_core.is_spectator(pname) and p:get_hp() > 0 then
				local ppos = p:get_pos()
				local dist = vector.distance(pos, ppos)
				if dist <= radius then
					table.insert(all_players_near, pname)
					local side = esports_core.match.get_player_match_side(pname)
					if side == "red" then
						red_count = red_count + 1
						table.insert(red_players_list, pname)
					elseif side == "blue" then
						blue_count = blue_count + 1
					end
				end
			end
		end

		-- Determine speed and state
		local speed = 0
		local state = "stopped"

		if red_count > 0 and blue_count > 0 then
			state = "contested"
			speed = 0
			self._idle_timer = 0
		elseif red_count > 0 then
			state = "moving"
			-- Speed escalates with more escorters: 1.5 m/s, 2.25 m/s, 3.0 m/s max
			speed = 1.5 + math.min(red_count - 1, 2) * 0.75
			self._idle_timer = 0
		elseif blue_count > 0 then
			state = "retreating"
			speed = -1.5  -- Defenders actively push it back
			self._idle_timer = 0
		else
			-- No one near: retreats after 10 seconds of inactivity
			self._idle_timer = (self._idle_timer or 0) + dtime
			if self._idle_timer >= 10 then
				state = "retreating"
				speed = -0.5  -- Slow passive roll back
			else
				state = "stopped"
				speed = 0
			end
		end

		esports_core.payload.state = state

		-- Audio and feedback logic
		if state == "moving" then
			if math.random() > 0.95 then
				for _, pname in ipairs(red_players_list) do
					core.sound_play("esports_pickup", {to_player = pname, gain = 0.4})
				end
			end
		elseif state == "contested" then
			if self._last_state ~= "contested" then
				for _, pname in ipairs(all_players_near) do
					core.sound_play("esports_deny", {to_player = pname, gain = 0.7})
				end
			end
		end
		self._last_state = state

		-- Calculate next position along the X axis
		-- We move Red (+X) -> Blue (-X). So positive movement is negative X velocity.
		local vx = -speed
		local new_x = pos.x + vx * dtime

		-- Bound checks
		if new_x > start_x then
			new_x = start_x
			vx = 0
		elseif new_x <= end_x then
			new_x = end_x
			vx = 0
			-- Red Wins!
			esports_core.teams.scores.red = 100
			esports_core.teams.scores.blue = 0
			esports_core.match.timer = 0
			core.chat_send_all(">> PAYLOAD: The cart has reached the destination! RED TEAM WINS!")
			core.sound_play("esports_pickup", {gain = 2.0})
		end

		-- Break blocks in the cart's path if it is moving
		if vx ~= 0 then
			local min_x = math.floor(pos.x - 3)
			local max_x = math.ceil(pos.x + 3)
			local min_y = 1
			local max_y = 3
			local min_z = -2
			local max_z = 2
			local broke_any = false

			for x = min_x, max_x do
				for y = min_y, max_y do
					for z = min_z, max_z do
						local p = {x = x, y = y, z = z}
						local node = core.get_node(p)
						if node.name ~= "air" and node.name ~= "ignore" then
							core.remove_node(p)
							broke_any = true
						end
					end
				end
			end
			if broke_any then
				core.sound_play("esports_break_crate", {pos = pos, max_hear_distance = 16, gain = 0.8})
			end
		end

		-- Apply physics (forcing Y and Z velocity to 0 to stay on track)
		self.object:set_velocity({x = vx, y = 0, z = 0})
		if vx == 0 then
			self.object:set_pos({x = new_x, y = 1.5, z = 0})
		else
			-- Snap coordinates twice per second to prevent drift while keeping velocity movement smooth
			self._snap_timer = (self._snap_timer or 0) + dtime
			if self._snap_timer >= 0.5 then
				self._snap_timer = 0
				self.object:set_pos({x = new_x, y = 1.5, z = 0})
			end
		end

		-- Calculate progress percentage
		local progress = ((start_x - pos.x) / total_dist) * 100
		esports_core.payload.progress = math.max(0, math.min(100, math.floor(progress + 0.5)))

		-- HUD Update throttling
		self._hud_timer = (self._hud_timer or 0) + dtime
		if self._hud_timer >= 0.5 then
			self._hud_timer = 0
			esports_core.hud.update_scores()
		end
	end
})

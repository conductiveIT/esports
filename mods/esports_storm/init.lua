esports_storm = {}
esports_storm.current_radius = 100
esports_storm.target_radius = 120
esports_storm.center = {x=0, y=0, z=0}
esports_storm.placed_nodes = {}

-- Register the original gas node for compatibility/fallback
core.register_node("esports_storm:gas", {
	description = "Storm Gas",
	drawtype = "glasslike",
	tiles = {"esports_storm_gas.png"},
	use_texture_alpha = "blend",
	paramtype = "light",
	sunlight_propagates = true,
	walkable = false,
	pointable = false,
	diggable = false,
	climbable = false,
	buildable_to = true,
	is_ground_content = false,
	groups = {not_in_creative_inventory = 1},
	post_effect_color = {a = 100, r = 150, g = 0, b = 255},  -- Purple screen tint
})

-- Register the new highly-optimized 2x20x2 circular storm gas column node
core.register_node("esports_storm:gas_column", {
	description = "Storm Gas Column",
	drawtype = "nodebox",
	paramtype = "light",
	tiles = {"esports_storm_gas.png"},
	use_texture_alpha = "blend",
	sunlight_propagates = true,
	walkable = false,
	pointable = false,
	diggable = false,
	climbable = false,
	buildable_to = true,
	is_ground_content = false,
	groups = {not_in_creative_inventory = 1},
	post_effect_color = {a = 100, r = 150, g = 0, b = 255},  -- Purple screen tint
	node_box = {
		type = "fixed",
		fixed = {
			-- A column that is 2 blocks wide, 20 blocks high, and 2 blocks deep
			{-1.0, -2.0, -1.0, 1.0, 18.0, 1.0}
		}
	}
})

function esports_storm.randomize_center()
	local scale = esports_core.match.current_map_scale or 1.0
	local angle = math.random() * math.pi * 2
	local dist = math.random() * (50 * scale)  -- scaled distance from center
	esports_storm.center = {
		x = math.floor(math.cos(angle) * dist + 0.5),
		y = 0,
		z = math.floor(math.sin(angle) * dist + 0.5)
	}
	core.log("action", "[TDM Storm] Randomized center to: " .. core.pos_to_string(esports_storm.center))
end

-- Draw a highly-optimized circular storm using spaced 2x20x2 columns
local function draw_circular_storm(center, R)
	local old_nodes = esports_storm.placed_nodes or {}

	-- 1. Clear old nodes
	for _, pos in ipairs(old_nodes) do
		local node = core.get_node(pos)
		if node.name == "esports_storm:gas_column" or node.name == "esports_storm:gas_wall" then
			core.set_node(pos, {name = "air"})
		end
	end
	esports_storm.placed_nodes = {}

	-- If match is not active, don't draw new ones
	if esports_core.match.state ~= "active" then
		return
	end

	local new_nodes = {}
	local Y = 1  -- Place at default ground/sea level

	-- Calculate number of columns needed based on circumference
	-- We place a column roughly every 2 meters for a visually continuous circle
	local circumference = 2 * math.pi * R
	local num_columns = math.max(8, math.floor(circumference / 2.0))

	local seen = {}

	for i = 1, num_columns do
		local angle = (i / num_columns) * math.pi * 2
		local px = math.floor(center.x + math.cos(angle) * R + 0.5)
		local pz = math.floor(center.z + math.sin(angle) * R + 0.5)

		local hash = px .. "," .. pz
		if not seen[hash] then
			seen[hash] = true
			local pos = {x = px, y = Y, z = pz}
			core.set_node(pos, {name = "esports_storm:gas_column"})
			table.insert(new_nodes, pos)
		end
	end

	esports_storm.placed_nodes = new_nodes
end

local dtime_accumulator = 0

core.register_globalstep(function(dtime)
	dtime_accumulator = dtime_accumulator + dtime
	if dtime_accumulator < 1 then return end
	dtime_accumulator = dtime_accumulator - 1

	if esports_core.match.state == "active" then
		if esports_core.match.is_spleef then
			if esports_storm.placed_nodes and #esports_storm.placed_nodes > 0 then
				draw_circular_storm(esports_storm.center, 100)
			end
			return
		end
		-- Shrink logic (PVP TDM ONLY)
		if not esports_core.match.is_pve and not esports_core.match.is_ctf and not esports_core.match.is_koth and not esports_core.match.is_payload then
			local shrink_speed = 0.5  -- units per second
			local min_radius = 27  -- tightness of endgame

			if esports_storm.current_radius > min_radius then
				esports_storm.current_radius = esports_storm.current_radius - shrink_speed
			end
		end

		-- Damage players outside
		if not esports_storm.last_cough then esports_storm.last_cough = {} end

		local current_center = esports_storm.center
		local current_radius = esports_storm.current_radius

		for _, player in ipairs(core.get_connected_players()) do
			local pname = player:get_player_name()
			local pos = player:get_pos()

			-- Circular distance check to match the map shape
			local dist = math.sqrt((pos.x - current_center.x)^2 + (pos.z - current_center.z)^2)

			if dist > current_radius then
				-- Player is outside the storm
				if not esports_core.is_spectator(pname) and player:get_hp() > 0 then
					player:set_hp(player:get_hp() - 2)

					-- Play cough sound with 2s cooldown
					local now = core.get_gametime()
					local last = esports_storm.last_cough[pname] or 0
					if now - last >= 2 then
						core.sound_play("esports_cough", {pos = pos, gain = 1.0, max_hear_distance = 16})
						esports_storm.last_cough[pname] = now
					end
				end
			end
		end

		-- Visualize storm bounds by placing optimized circular gas columns
		draw_circular_storm(current_center, current_radius)
	else
		-- Reset and clear storm when not active
		if esports_storm.current_radius ~= 100 or (esports_storm.placed_nodes and #esports_storm.placed_nodes > 0) then
			esports_storm.current_radius = 100
			draw_circular_storm(esports_storm.center, 100)  -- This will clear the old nodes since state is not active
		end
	end
end)

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

-- Draw a highly-optimized circular storm using spaced 2x20x2 columns in bulk VoxelManip
local function draw_circular_storm(center, R)
	local old_nodes = esports_storm.placed_nodes or {}

	-- If match is not active, and we have no old nodes to clear, do nothing
	if esports_core.match.state ~= "active" and #old_nodes == 0 then
		return
	end

	-- Calculate the new column positions
	local new_nodes = {}
	local Y = 1
	local seen = {}

	if esports_core.match.state == "active" then
		local circumference = 2 * math.pi * R
		local num_columns = math.max(8, math.floor(circumference / 2.0))

		for i = 1, num_columns do
			local angle = (i / num_columns) * math.pi * 2
			local px = math.floor(center.x + math.cos(angle) * R + 0.5)
			local pz = math.floor(center.z + math.sin(angle) * R + 0.5)

			local hash = px .. "," .. pz
			if not seen[hash] then
				seen[hash] = true
				table.insert(new_nodes, {x = px, y = Y, z = pz})
			end
		end
	end

	-- If both old_nodes and new_nodes are empty, nothing to do
	if #old_nodes == 0 and #new_nodes == 0 then
		return
	end

	-- OPTIMIZATION: If new storm column coordinates are identical to old coordinates,
	-- skip expensive VoxelManip read/write entirely.
	if #new_nodes == #old_nodes then
		local identical = true
		for i = 1, #new_nodes do
			local n = new_nodes[i]
			local o = old_nodes[i]
			if n.x ~= o.x or n.z ~= o.z then
				identical = false
				break
			end
		end
		if identical then
			return
		end
	end

	-- Find the bounding box containing all old and new nodes to manipulate
	local minx, maxx = 0, 0
	local minz, maxz = 0, 0
	local first = true

	local function expand_bounds(pos)
		if first then
			minx, maxx = pos.x, pos.x
			minz, maxz = pos.z, pos.z
			first = false
		else
			if pos.x < minx then minx = pos.x end
			if pos.x > maxx then maxx = pos.x end
			if pos.z < minz then minz = pos.z end
			if pos.z > maxz then maxz = pos.z end
		end
	end

	for _, pos in ipairs(old_nodes) do expand_bounds(pos) end
	for _, pos in ipairs(new_nodes) do expand_bounds(pos) end

	-- Add a 1-block safety buffer to bounds
	local minp = {x = minx - 1, y = Y, z = minz - 1}
	local maxp = {x = maxx + 1, y = Y, z = maxz + 1}

	-- Load area using VoxelManip
	local vm = VoxelManip()
	local emin, emax = vm:read_from_map(minp, maxp)
	local area = VoxelArea:new{MinEdge = emin, MaxEdge = emax}
	local data = vm:get_data()

	local c_air = core.CONTENT_AIR
	local c_gas = core.get_content_id("esports_storm:gas_column")

	-- Clear old nodes in VoxelManip data
	for _, pos in ipairs(old_nodes) do
		local vi = area:index(pos.x, Y, pos.z)
		if data[vi] == c_gas then
			data[vi] = c_air
		end
	end

	-- Place new nodes in VoxelManip data
	for _, pos in ipairs(new_nodes) do
		local vi = area:index(pos.x, Y, pos.z)
		data[vi] = c_gas
	end

	vm:set_data(data)
	vm:write_to_map()

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
					player:set_hp(player:get_hp() - 4)

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

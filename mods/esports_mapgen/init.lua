core.log("action", "====================================================")
core.log("action", "[TDM Mapgen] Starting Luanti Deathmatch Mapgen v0.5.2")
core.log("action", "====================================================")

-- Force the world's map generator to Singlenode (void) to prevent natural v7/v6 hills/oceans
core.set_mapgen_setting("mg_name", "singlenode", true)

-- Increase server block update sending range to 128 blocks (8 chunks)
core.settings:set("active_block_range", "8")

-- Increase packet quota per iteration to prevent client send quota warnings on join
core.settings:set("max_packets_per_iteration", "4096")

core.register_node("esports_mapgen:grass", {
	description = "Grass",
	tiles = {"esports_mapgen_grass.png"},
	groups = {crumbly = 3, soil = 1},
})

core.register_node("esports_mapgen:dirt", {
	description = "Dirt",
	tiles = {"esports_mapgen_dirt.png"},
	groups = {crumbly = 3, soil = 1},
})

core.register_node("esports_mapgen:stone", {
	description = "Stone",
	tiles = {"esports_mapgen_stone.png"},
	groups = {cracky = 3, stone = 1},
})

local c_grass = core.get_content_id("esports_mapgen:grass")
local c_dirt = core.get_content_id("esports_mapgen:dirt")
local c_stone = core.get_content_id("esports_mapgen:stone")
local c_air = core.CONTENT_AIR

core.register_on_generated(function(minp, maxp, seed)
	-- We only want to generate an island near the center
	if maxp.y < -20 or minp.y > 20 then
		return
	end

	local layout = (esports_core and esports_core.match and esports_core.match.current_map_layout) or "circular"
	local scale = (esports_core and esports_core.match and esports_core.match.current_map_scale) or 1.0

	local vm, emin, emax = core.get_mapgen_object("voxelmanip")
	local data = vm:get_data()
	local area = VoxelArea:new{MinEdge=emin, MaxEdge=emax}

	local max_r = 100 * scale
	local max_r2 = max_r * max_r

	for z = minp.z, maxp.z do
		local z2 = z * z
		for y = minp.y, maxp.y do
			for x = minp.x, maxp.x do
				local vi = area:index(x, y, z)
				local in_island = false

				if layout == "lobby" then
					in_island = (x*x + z2 <= 15*15)
				elseif layout == "circular" then
					in_island = (x*x + z2 <= max_r2)
				elseif layout == "choke_point" then
					local base_r = 30 * scale
					local base_r2 = base_r * base_r
					local dist_red2 = (x - 80*scale)*(x - 80*scale) + z2
					local dist_blue2 = (x + 80*scale)*(x + 80*scale) + z2
					local is_bridge = (x >= -60*scale and x <= 60*scale) and (z >= -8*scale and z <= 8*scale)
					in_island = (dist_red2 <= base_r2) or (dist_blue2 <= base_r2) or is_bridge
				elseif layout == "three_lanes" then
					local base_r = 30 * scale
					local base_r2 = base_r * base_r
					local dist_red2 = (x - 80*scale)*(x - 80*scale) + z2
					local dist_blue2 = (x + 80*scale)*(x + 80*scale) + z2

					local mid_bridge = (x >= -60*scale and x <= 60*scale) and (z >= -5*scale and z <= 5*scale)
					local top_bridge = (x >= -60*scale and x <= 60*scale) and (z >= 25*scale - 4*scale and z <= 25*scale + 4*scale)
					local btm_bridge = (x >= -60*scale and x <= 60*scale) and (z >= -25*scale - 4*scale and z <= -25*scale + 4*scale)
					in_island = (dist_red2 <= base_r2) or (dist_blue2 <= base_r2) or mid_bridge or top_bridge or btm_bridge
				elseif layout == "split_center" then
					local base_r = 25 * scale
					local base_r2 = base_r * base_r
					local dist_red2 = (x - 80*scale)*(x - 80*scale) + z2
					local dist_blue2 = (x + 80*scale)*(x + 80*scale) + z2

					local center_r = 25 * scale
					local center_r2 = center_r * center_r
					local dist_center2 = x*x + z2

					local left_bridge = (x >= -60*scale and x <= -20*scale) and (z >= -4*scale and z <= 4*scale)
					local right_bridge = (x >= 20*scale and x <= 60*scale) and (z >= -4*scale and z <= 4*scale)
					in_island = (dist_red2 <= base_r2) or (dist_blue2 <= base_r2) or (dist_center2 <= center_r2) or left_bridge or right_bridge
				end

				if in_island then
					if y == 0 then
						data[vi] = c_grass
					elseif y > -5 and y < 0 then
						data[vi] = c_dirt
					elseif y <= -5 and y > -20 then
						data[vi] = c_stone
					else
						data[vi] = c_air
					end
				else
					data[vi] = c_air
				end
			end
		end
	end

	vm:set_data(data)
	vm:calc_lighting()
	vm:write_to_map()
end)

esports_mapgen = {}
esports_mapgen.valid_crate_spots = {}

-- Function to reset the island to its base state
function esports_mapgen.reset_island(layout_name, scale_val)
	local scale = scale_val or (esports_core and esports_core.match and esports_core.match.current_map_scale) or 1.0
	local layout = layout_name or (esports_core and esports_core.match and esports_core.match.current_map_layout) or "circular"

	core.log("action", string.format("[TDM Mapgen] Resetting island for a new session (Layout: %s, Scale: %.2f)...", layout, scale))

	-- Clear internal caches
	if esports_loot and esports_loot.clear_cache then
		esports_loot.clear_cache()
	end
	esports_mapgen.valid_crate_spots = {}

	-- 1. Clear all items and entities on the island within the match area
	for _, obj in ipairs(core.get_objects_inside_radius({x=0, y=0, z=0}, 200)) do
		if not obj:is_player() then
			obj:remove()
		end
	end
	core.clear_objects({mode = "quick"})

	-- 2. WIPE the island nodes back to their default state
	local prev_scale = esports_mapgen.current_scale or 1.0
	local max_s = math.max(scale, prev_scale)
	local prev_layout = esports_mapgen.current_layout or "circular"

	local function get_layout_extent(lay)
		if lay == "lobby" then return 17 end
		if lay == "spleef" then return 30 end
		if lay == "choke_point" or lay == "three_lanes" then return 112 end
		if lay == "split_center" then return 107 end
		return 102 -- circular or default
	end

	local curr_ext = get_layout_extent(layout)
	local prev_ext = get_layout_extent(prev_layout)
	local max_extent = math.ceil(math.max(curr_ext, prev_ext) * max_s)

	-- Height is optimized from -20..40 to -6..40 since players cannot dig or place below -5
	local minp = {x=-max_extent, y=-6, z=-max_extent}
	local maxp = {x=max_extent, y=40, z=max_extent}

	local vm = VoxelManip()
	local emin, emax = vm:read_from_map(minp, maxp)

	local area = VoxelArea:new{MinEdge=emin, MaxEdge=emax}
	local data = vm:get_data()

	local c_grass = core.get_content_id("esports_mapgen:grass")
	local c_dirt = core.get_content_id("esports_mapgen:dirt")
	local c_stone = core.get_content_id("esports_mapgen:stone")
	local c_air = core.CONTENT_AIR

	local max_r = 100 * scale
	local max_r2 = max_r * max_r

	-- Pre-calculate layout checks to optimize loop execution
	local check_in_island
	if layout == "lobby" then
		check_in_island = function(x, z)
			return (x*x + z*z <= 225)
		end
	elseif layout == "circular" then
		check_in_island = function(x, z)
			return (x*x + z*z <= max_r2)
		end
	elseif layout == "choke_point" then
		local base_r = 30 * scale
		local base_r2 = base_r * base_r
		local offset = 80 * scale
		local x_min_bridge = -60 * scale
		local x_max_bridge = 60 * scale
		local z_min_bridge = -8 * scale
		local z_max_bridge = 8 * scale
		check_in_island = function(x, z)
			local dist_red2 = (x - offset)*(x - offset) + z*z
			local dist_blue2 = (x + offset)*(x + offset) + z*z
			local is_bridge = (x >= x_min_bridge and x <= x_max_bridge) and (z >= z_min_bridge and z <= z_max_bridge)
			return (dist_red2 <= base_r2) or (dist_blue2 <= base_r2) or is_bridge
		end
	elseif layout == "three_lanes" then
		local base_r = 30 * scale
		local base_r2 = base_r * base_r
		local offset = 80 * scale
		local x_min_bridge = -60 * scale
		local x_max_bridge = 60 * scale
		local z_mid_min, z_mid_max = -5 * scale, 5 * scale
		local z_top_min, z_top_max = 21 * scale, 29 * scale
		local z_btm_min, z_btm_max = -29 * scale, -21 * scale
		check_in_island = function(x, z)
			local dist_red2 = (x - offset)*(x - offset) + z*z
			local dist_blue2 = (x + offset)*(x + offset) + z*z
			local in_x_bridge = (x >= x_min_bridge and x <= x_max_bridge)
			local mid_bridge = in_x_bridge and (z >= z_mid_min and z <= z_mid_max)
			local top_bridge = in_x_bridge and (z >= z_top_min and z <= z_top_max)
			local btm_bridge = in_x_bridge and (z >= z_btm_min and z <= z_btm_max)
			return (dist_red2 <= base_r2) or (dist_blue2 <= base_r2) or mid_bridge or top_bridge or btm_bridge
		end
	elseif layout == "split_center" then
		local base_r = 25 * scale
		local base_r2 = base_r * base_r
		local offset = 80 * scale
		local center_r = 25 * scale
		local center_r2 = center_r * center_r
		local x_left_min, x_left_max = -60 * scale, -20 * scale
		local x_right_min, x_right_max = 20 * scale, 60 * scale
		local z_bridge_min, z_bridge_max = -4 * scale, 4 * scale
		check_in_island = function(x, z)
			local dist_red2 = (x - offset)*(x - offset) + z*z
			local dist_blue2 = (x + offset)*(x + offset) + z*z
			local dist_center2 = x*x + z*z
			local left_bridge = (x >= x_left_min and x <= x_left_max) and (z >= z_bridge_min and z <= z_bridge_max)
			local right_bridge = (x >= x_right_min and x <= x_right_max) and (z >= z_bridge_min and z <= z_bridge_max)
			return (dist_red2 <= base_r2) or (dist_blue2 <= base_r2) or (dist_center2 <= center_r2) or left_bridge or right_bridge
		end
	else
		check_in_island = function(x, z) return false end
	end

	local ystride = area.ystride
	for z = minp.z, maxp.z do
		for x = minp.x, maxp.x do
			local vi = area:index(x, minp.y, z)
			if check_in_island(x, z) then
				for y = minp.y, maxp.y do
					if y == 0 then
						data[vi] = c_grass
						table.insert(esports_mapgen.valid_crate_spots, {x=x, y=1, z=z})
					elseif y > -5 and y < 0 then
						data[vi] = c_dirt
					elseif y <= -5 then
						data[vi] = c_stone
					else
						data[vi] = c_air
					end
					vi = vi + ystride
				end
			else
				for y = minp.y, maxp.y do
					data[vi] = c_air
					vi = vi + ystride
				end
			end
		end
	end

	vm:set_data(data)
	vm:write_to_map()
	core.fix_light(minp, maxp)

	esports_mapgen.current_layout = layout
	esports_mapgen.current_scale = scale

	-- Force the server to immediately send block updates for the modified area to connected clients
	core.emerge_area(minp, maxp)

	core.log("action", "[TDM Mapgen] Map reset complete!")
end

core.register_node("esports_mapgen:spleef_block", {
	description = "Spleef Block",
	tiles = {"esports_mapgen_stone.png^[colorize:#00ffff:120"},
	groups = {snappy = 3, oddly_breakable_by_hand = 3, spleef = 1},
	on_punch = function(pos, node, puncher)
		if not puncher or not puncher:is_player() then return end
		if esports_core and esports_core.match and esports_core.match.state == "active" and esports_core.match.is_spleef then
			local pname = puncher:get_player_name()
			if not (esports_core.is_spectator and esports_core.is_spectator(pname)) then
				core.remove_node(pos)
				core.sound_play("esports_break_crate", {pos = pos, gain = 0.5, max_hear_distance = 16})
				if esports_core.match.add_spleef_block then
					esports_core.match.add_spleef_block(pname)
				end
			end
		end
	end,
})

-- Generate the Spleef Arena platform and boundary walls
function esports_mapgen.setup_spleef_arena(levels)
	local lvls = tonumber(levels) or 1
	core.log("action", "[TDM Mapgen] Generating Spleef arena with " .. lvls .. " levels...")

	-- Clear objects first
	core.clear_objects({mode = "quick"})

	-- Boundary bounds
	local minp = {x=-30, y=-10, z=-30}
	local maxp = {x=30, y=40, z=30}

	local vm = VoxelManip()
	local emin, emax = vm:read_from_map(minp, maxp)
	local area = VoxelArea:new{MinEdge=emin, MaxEdge=emax}
	local data = vm:get_data()

	local c_spleef = core.get_content_id("esports_mapgen:spleef_block")
	local c_air = core.CONTENT_AIR
	local c_stone = core.get_content_id("esports_mapgen:stone")

	-- Pre-calculate floor Y values
	local floors = {}
	for i = 1, lvls do
		floors[5 + (i - 1) * 4] = true
	end

	local max_wall_y = 5 + lvls * 4 + 15

	for z = minp.z, maxp.z do
		for y = minp.y, maxp.y do
			for x = minp.x, maxp.x do
				local vi = area:index(x, y, z)
				local abs_x = math.abs(x)
				local abs_z = math.abs(z)

				if abs_x <= 26 and abs_z <= 26 then
					if abs_x == 26 or abs_z == 26 then
						-- Outer wall to contain players
						if y >= 5 and y <= max_wall_y then
							data[vi] = c_stone
						else
							data[vi] = c_air
						end
					elseif floors[y] then
						-- Breakable Spleef Floor
						data[vi] = c_spleef
					else
						-- Air pit
						data[vi] = c_air
					end
				end
			end
		end
	end

	vm:set_data(data)
	vm:write_to_map()
	core.fix_light(minp, maxp)
	core.emerge_area(minp, maxp)
	esports_mapgen.current_layout = "spleef"
	esports_mapgen.current_scale = 1.0
	core.log("action", "[TDM Mapgen] Spleef arena generation complete!")
end

-- Reset the map on startup to the small lobby island
core.after(0, function()
	esports_mapgen.reset_island("lobby")
end)


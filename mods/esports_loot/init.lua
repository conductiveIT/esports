esports_loot = {}
esports_loot.crate_positions = {}
esports_loot.box_count = 0

function esports_loot.clear_cache()
	esports_loot.crate_positions = {}
	esports_loot.box_count = 0
end

-- Register the Loot Box node
core.register_node("esports_loot:box", {
	description = "Loot Crate",
	tiles = {"esports_loot_box.png"},
	groups = {choppy = 2, oddly_breakable_by_hand = 2, loot_box = 1},

	on_construct = function(pos)
		local hash = core.hash_node_position(pos)
		if not esports_loot.crate_positions[hash] then
			esports_loot.crate_positions[hash] = {x=pos.x, y=pos.y, z=pos.z}
			esports_loot.box_count = esports_loot.box_count + 1
		end
	end,

	after_destruct = function(pos, oldnode)
		local hash = core.hash_node_position(pos)
		if esports_loot.crate_positions[hash] then
			esports_loot.crate_positions[hash] = nil
			esports_loot.box_count = esports_loot.box_count - 1
		end
	end,

	on_punch = function(pos, node, puncher, pointed_thing)
		-- Safety check for puncher
		if not puncher or not puncher:is_player() then return end

		-- Random loot table (Bypassing spectator check for mobile/PC parity)

		-- Random loot table
		local loot_options
		local meta = puncher:get_meta()
		if meta:get_int("needs_weapon_from_crate") == 1 then
			loot_options = {
				"esports_weapons:assault_rifle",
				"esports_weapons:shotgun",
			}
			meta:set_int("needs_weapon_from_crate", 0)
		else
			loot_options = {
				"esports_weapons:assault_rifle",
				"esports_weapons:shotgun",
				"esports_weapons:rifle_ammo 20",
				"esports_weapons:shotgun_ammo 10",
				"esports_weapons:health_pack",
			}
		end

		local chosen_loot = loot_options[math.random(#loot_options)]
		core.add_item(pos, chosen_loot)
		core.sound_play("esports_break_crate", {pos = pos, max_hear_distance = 16})
		core.remove_node(pos)
	end,

	on_dig = function(pos, node, digger)
		-- Instant dig for crates
		local n_def = core.registered_nodes[node.name]
		if n_def and n_def.on_punch then
			n_def.on_punch(pos, node, digger)
		end
		return false
	end,
	on_rightclick = function(pos, node, clicker, itemstack, pointed_thing)
		-- Support for mobile "Tap to Interact"
		local n_def = core.registered_nodes[node.name]
		if n_def and n_def.on_punch then
			n_def.on_punch(pos, node, clicker)
		end
	end,
})

-- GLOBAL PUNCH HOOK (Definitive interaction fix)
core.register_on_punchnode(function(pos, node, puncher)
	if not puncher:is_player() then return end
	if node.name == "esports_loot:box" then
		local n_def = core.registered_nodes[node.name]
		if n_def and n_def.on_punch then
			n_def.on_punch(pos, node, puncher)
		end
	end
end)

-- Spawning logic
local spawn_timer = 0
local ISLAND_RADIUS = 100

-- Dynamically calculate combatants (Players + Bots)
local function get_combatant_count()
	local count = 0
	-- Count Players
	for _, p in ipairs(core.get_connected_players()) do
		if not esports_core.is_spectator(p:get_player_name()) then
			count = count + 1
		end
	end
	-- Count Bots (Sentry entities)
	for _, obj in pairs(core.object_refs) do
		local ent = obj:get_luaentity()
		if ent and ent.name == "esports_core:bot" then
			count = count + 1
		end
	end
	return math.max(1, count)
end

local dtime_acc = 0
core.register_globalstep(function(dtime)
	dtime_acc = dtime_acc + dtime
	if dtime_acc < 1.0 then return end
	local step_time = dtime_acc
	dtime_acc = 0

	if not esports_core or not esports_core.match or esports_core.match.state ~= "active" then
		return
	end

	if esports_core.match.is_tagctf or esports_core.match.is_spleef then
		return
	end

	spawn_timer = spawn_timer + step_time

	local combatants = get_combatant_count()
	local dynamic_interval = math.max(1, 6 - (combatants * 0.5))
	local dynamic_max = combatants * 8

	if spawn_timer >= dynamic_interval then
		spawn_timer = 0

		-- Use optimized count instead of find_nodes_in_area
		if esports_loot.box_count < dynamic_max then
			-- Try to find a spawn spot within the Storm's Safe Zone
			local storm_center = esports_storm.center
			local storm_radius = esports_storm.current_radius

			for i = 1, 15 do  -- increased attempts to find valid island ground
				local angle = math.random() * math.pi * 2
				local dist = math.random() * (storm_radius * 0.9)  -- Spawn within 90% of radius to be safe
				local x = math.floor(storm_center.x + math.cos(angle) * dist + 0.5)
				local z = math.floor(storm_center.z + math.sin(angle) * dist + 0.5)

				-- Check if within active map layout geometry boundary
				local on_island = false
				local layout = (esports_core and esports_core.match and esports_core.match.current_map_layout) or "circular"
				local scale = (esports_core and esports_core.match and esports_core.match.current_map_scale) or 1.0

				if layout == "lobby" then
					on_island = (x*x + z*z <= 15*15)
				elseif layout == "circular" then
					on_island = (x*x + z*z <= 100*100 * scale*scale)
				elseif layout == "choke_point" then
					local base_r = 30 * scale
					local base_r2 = base_r * base_r
					local dist_red2 = (x - 80*scale)*(x - 80*scale) + z*z
					local dist_blue2 = (x + 80*scale)*(x + 80*scale) + z*z
					local is_bridge = (x >= -60*scale and x <= 60*scale) and (z >= -8*scale and z <= 8*scale)
					on_island = (dist_red2 <= base_r2) or (dist_blue2 <= base_r2) or is_bridge
				elseif layout == "three_lanes" then
					local base_r = 30 * scale
					local base_r2 = base_r * base_r
					local dist_red2 = (x - 80*scale)*(x - 80*scale) + z*z
					local dist_blue2 = (x + 80*scale)*(x + 80*scale) + z*z
					local mid_bridge = (x >= -60*scale and x <= 60*scale) and (z >= -5*scale and z <= 5*scale)
					local top_bridge = (x >= -60*scale and x <= 60*scale) and (z >= 25*scale - 4*scale and z <= 25*scale + 4*scale)
					local btm_bridge = (x >= -60*scale and x <= 60*scale) and (z >= -25*scale - 4*scale and z <= -25*scale + 4*scale)
					on_island = (dist_red2 <= base_r2) or (dist_blue2 <= base_r2) or mid_bridge or top_bridge or btm_bridge
				elseif layout == "split_center" then
					local base_r = 25 * scale
					local base_r2 = base_r * base_r
					local dist_red2 = (x - 80*scale)*(x - 80*scale) + z*z
					local dist_blue2 = (x + 80*scale)*(x + 80*scale) + z*z

					local center_r = 25 * scale
					local center_r2 = center_r * center_r
					local dist_center2 = x*x + z*z

					local left_bridge = (x >= -60*scale and x <= -20*scale) and (z >= -4*scale and z <= 4*scale)
					local right_bridge = (x >= 20*scale and x <= 60*scale) and (z >= -4*scale and z <= 4*scale)
					on_island = (dist_red2 <= base_r2) or (dist_blue2 <= base_r2) or (dist_center2 <= center_r2) or left_bridge or right_bridge
				end

				if on_island then
					local pos = {x=x, y=1, z=z}
					local node_below = core.get_node({x=x, y=0, z=z}).name
					local node_at = core.get_node(pos).name

					if node_below == "esports_mapgen:grass" and node_at == "air" then
						core.set_node(pos, {name = "esports_loot:box"})
						break
					end
				end
			end
		end
	end
end)

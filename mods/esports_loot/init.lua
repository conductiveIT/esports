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
			-- Try to find a spawn spot within the Storm's Safe Zone using pre-calculated grass coordinates
			local storm_center = esports_storm.center
			local storm_radius = esports_storm.current_radius
			local spots = esports_mapgen.valid_crate_spots or {}
			local num_spots = #spots

			if num_spots > 0 then
				local safe_r = storm_radius * 0.9
				local safe_r2 = safe_r * safe_r
				for attempt = 1, 30 do
					local spot = spots[math.random(num_spots)]
					local dx = spot.x - storm_center.x
					local dz = spot.z - storm_center.z
					if dx*dx + dz*dz <= safe_r2 then
						local node_at = core.get_node(spot).name
						if node_at == "air" then
							core.set_node(spot, {name = "esports_loot:box"})
							break
						end
					end
				end
			end
		end
	end
end)

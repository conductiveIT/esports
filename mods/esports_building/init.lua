-- Wooden Player Wall
core.register_node("esports_building:player_wall", {
	description = "Player Wall",
	tiles = {"esports_building_wood.png"},
	groups = {choppy = 2, oddly_breakable_by_hand = 2, player_built = 1},
	paramtype2 = "facedir",
})

-- Wooden Player Ramp (Stairs)
core.register_node("esports_building:player_ramp", {
	description = "Player Ramp",
	drawtype = "nodebox",
	paramtype = "light",
	paramtype2 = "facedir",
	tiles = {"esports_building_wood.png"},
	node_box = {
		type = "fixed",
		fixed = {
			{-0.5, -0.5, -0.5, 0.5, 0.0, 0.5},
			{-0.5, 0.0, 0.0, 0.5, 0.5, 0.5},
		},
	},
	groups = {choppy = 2, oddly_breakable_by_hand = 2, player_built = 1},
})

-- Blueprints
local function place_structure(itemstack, user, pointed_thing, node_name, is_rightclick)
	if not user or not user:is_player() then return itemstack end
	local pname = user:get_player_name()
	if esports_core.is_in_lobby and esports_core.is_in_lobby(pname) then
		return itemstack
	end
	if not pointed_thing or pointed_thing.type ~= "node" then return itemstack end

	local node_under = core.get_node(pointed_thing.under)
	local def_under = core.registered_nodes[node_under.name]

	-- If right-clicked on an interactive node (chest, button, etc.), interact with it instead of placing
	if is_rightclick and def_under and def_under.on_rightclick and not user:get_player_control().sneak then
		return def_under.on_rightclick(pointed_thing.under, node_under, user, itemstack, pointed_thing) or itemstack
	end

	local pos = pointed_thing.above
	if def_under and def_under.buildable_to then
		pos = pointed_thing.under
	end

	local is_admin = core.check_player_privs(pname, {server=true}) or core.check_player_privs(pname, {admin=true})

	if not is_admin then
		-- Check Build Restrictions
		local is_restricted = false
		local restrict_reason = ""

		-- 1. CTF Objective Protection
		if esports_core.match.is_ctf and esports_core.ctf and esports_core.ctf.bases then
			local scale = esports_core.match.current_map_scale or 1.0
			local limit = 15 * scale
			for _, base_pos in pairs(esports_core.ctf.bases) do
				if vector.distance(pos, base_pos) < limit then
					is_restricted = true
					restrict_reason = "No building within " .. math.floor(limit) .. " blocks of a Flag Stand!"
					break
				end
			end
		end

		-- 2. KotH Hill Protection
		if not is_restricted and esports_core.match.is_koth and esports_core.koth and esports_core.koth.hill_center then
			local center = esports_core.koth.hill_center
			local dist = math.sqrt((pos.x - center.x)^2 + (pos.z - center.z)^2)
			if dist <= esports_core.koth.hill_radius and math.abs(pos.y - center.y) <= 3 then
				is_restricted = true
				restrict_reason = "No building within the Hill zone!"
			end
		end

		-- 3. Domination Point Protection
		if not is_restricted and esports_core.match.is_domination and esports_core.dom and esports_core.dom.points then
			for id, pt in pairs(esports_core.dom.points) do
				local center = pt.center
				if center then
					local dist = math.sqrt((pos.x - center.x)^2 + (pos.z - center.z)^2)
					if dist <= esports_core.dom.radius and math.abs(pos.y - center.y) <= 3 then
						is_restricted = true
						restrict_reason = "No building within Domination Point " .. id .. "!"
						break
					end
				end
			end
		end

		if is_restricted then
			core.chat_send_player(pname, core.colorize("#FF4444", "STRATEGIC OVERRIDE: " .. restrict_reason))
			return itemstack
		end
	end

	if pos.y >= 10 then
		core.chat_send_player(pname, "Height limit reached! Max build height is 10 blocks.")
		return itemstack
	end

	local dir = user:get_look_dir()
	local facedir = core.dir_to_facedir(dir)

	-- Collision Check: Prevent placing blocks inside players or bots, or nudge them safely
	local nearby = core.get_objects_inside_radius(pos, 2.5)
	for _, obj in ipairs(nearby) do
		local is_p = obj:is_player()
		local is_b = false
		if not is_p then
			local ent = obj:get_luaentity()
			is_b = (ent and ent.name == "esports_core:bot")
		end

		if (is_p and not (esports_core.is_spectator and esports_core.is_spectator(obj:get_player_name()))) or is_b then
			local obj_pos = obj:get_pos()
			if obj_pos then
				-- Entity collision box: [-0.35, 0.0, -0.35, 0.35, 1.75, 0.35]
				local e_min_x = obj_pos.x - 0.35
				local e_max_x = obj_pos.x + 0.35
				local e_min_y = obj_pos.y
				local e_max_y = obj_pos.y + 1.75
				local e_min_z = obj_pos.z - 0.35
				local e_max_z = obj_pos.z + 0.35

				local b_min_x = pos.x - 0.5
				local b_max_x = pos.x + 0.5
				local b_min_y = pos.y - 0.5
				local b_max_y = pos.y + 0.5
				local b_min_z = pos.z - 0.5
				local b_max_z = pos.z + 0.5

				-- Check 3D AABB overlap
				local overlaps = (e_min_x < b_max_x and e_max_x > b_min_x) and
				                 (e_min_y < b_max_y and e_max_y > b_min_y) and
				                 (e_min_z < b_max_z and e_max_z > b_min_z)

				if overlaps then
					-- If the entity is jumping or hovering near the top surface of the block:
					-- Bump them up on top of the block so they don't get trapped (allows smooth towering / 90s)!
					if obj_pos.y >= (pos.y - 0.2) then
						local above_node = core.get_node({x = pos.x, y = pos.y + 1, z = pos.z})
						local above_def = core.registered_nodes[above_node.name]
						if not above_def or not above_def.walkable then
							obj:set_pos({x = obj_pos.x, y = pos.y + 0.55, z = obj_pos.z})
						else
							core.chat_send_player(pname, "Cannot place: blocked by entity above!")
							return itemstack
						end
					else
						-- Entity is inside the horizontal body of the block:
						-- Attempt to push them safely to the nearest adjacent clear air block
						local dx = obj_pos.x - pos.x
						local dz = obj_pos.z - pos.z
						local pushed = false

						local test_offsets = {}
						if math.abs(dx) >= math.abs(dz) then
							local sign = (dx >= 0) and 1 or -1
							table.insert(test_offsets, {x = sign * 0.9, z = 0})
							table.insert(test_offsets, {x = -sign * 0.9, z = 0})
							table.insert(test_offsets, {x = 0, z = 0.9})
							table.insert(test_offsets, {x = 0, z = -0.9})
						else
							local sign = (dz >= 0) and 1 or -1
							table.insert(test_offsets, {x = 0, z = sign * 0.9})
							table.insert(test_offsets, {x = 0, z = -sign * 0.9})
							table.insert(test_offsets, {x = 0.9, z = 0})
							table.insert(test_offsets, {x = -0.9, z = 0})
						end

						for _, off in ipairs(test_offsets) do
							local tpos = {x = pos.x + off.x, y = obj_pos.y, z = pos.z + off.z}
							local ix = math.floor(tpos.x + 0.5)
							local iy = math.floor(tpos.y + 0.5)
							local iz = math.floor(tpos.z + 0.5)
							local n_feet = core.get_node({x = ix, y = iy, z = iz})
							local n_head = core.get_node({x = ix, y = iy + 1, z = iz})
							local d_feet = core.registered_nodes[n_feet.name]
							local d_head = core.registered_nodes[n_head.name]
							if (not d_feet or not d_feet.walkable) and (not d_head or not d_head.walkable) then
								obj:set_pos(tpos)
								pushed = true
								break
							end
						end

						if not pushed then
							core.chat_send_player(pname, "Cannot place: space occupied by entity!")
							return itemstack
						end
					end
				end
			end
		end
	end

	core.set_node(pos, {name = node_name, param2 = facedir})
	-- Instant placement sound
	core.sound_play("esports_build", {pos = pos, max_hear_distance = 16})
	return itemstack
end

core.register_tool("esports_building:blueprint_wall", {
	description = "Wall Blueprint",
	inventory_image = "esports_building_blueprint_wall.png",
	on_use = function(itemstack, user, pointed_thing)
		return place_structure(itemstack, user, pointed_thing, "esports_building:player_wall", false)
	end,
	on_place = function(itemstack, user, pointed_thing)
		return place_structure(itemstack, user, pointed_thing, "esports_building:player_wall", true)
	end,
})

core.register_tool("esports_building:blueprint_ramp", {
	description = "Ramp Blueprint",
	inventory_image = "esports_building_blueprint_ramp.png",
	on_use = function(itemstack, user, pointed_thing)
		return place_structure(itemstack, user, pointed_thing, "esports_building:player_ramp", false)
	end,
	on_place = function(itemstack, user, pointed_thing)
		return place_structure(itemstack, user, pointed_thing, "esports_building:player_ramp", true)
	end,
})

-- Give starting items
core.register_on_joinplayer(function(player)
	local inv = player:get_inventory()
	inv:set_size("main", 8 * 4)
	inv:set_list("main", {})  -- Clear inventory to remove old items
	inv:set_stack("main", 1, ItemStack(""))
	inv:set_stack("main", 2, ItemStack("esports_building:blueprint_wall"))
	inv:set_stack("main", 3, ItemStack("esports_building:blueprint_ramp"))
end)

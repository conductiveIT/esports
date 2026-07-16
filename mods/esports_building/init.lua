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
	drawtype = "mesh",
	-- For now use a nodebox approximation of a ramp
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

	local pname = user:get_player_name()
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
	inv:set_stack("main", 2, ItemStack("esports_building:blueprint_wall"))
	inv:set_stack("main", 3, ItemStack("esports_building:blueprint_ramp"))
end)

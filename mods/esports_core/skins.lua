esports_core.skins = {}

-- Tactical Class Archetypes for the 4 Locker Outfits
esports_core.skins.classes = {
	["character.png"] = {
		id = "sam",
		name = "Tactical Sam",
		role = "Operator",
		subrole = "All-Rounder",
		hp = 100,
		base_speed = 1.20,
		sprint_mult = 1.40,
		max_stamina = 100,
		drain_rate = 22,
		regen_rate = 25,
		regen_delay = 1.0,
		jump_cost = 8,
		demo_mult = 1.0,
		spread_mult = 1.0,
		flag_speed = 0.90,
		flag_drain_mult = 1.5,
		perk = "Balanced baseline stats",
	},
	["skin_1.png"] = {
		id = "elite",
		name = "Elite Soldier",
		role = "Juggernaut",
		subrole = "Tank",
		hp = 120,
		base_speed = 1.15,
		sprint_mult = 1.30,
		max_stamina = 100,
		drain_rate = 22,
		regen_rate = 22,
		regen_delay = 1.2,
		jump_cost = 10,
		demo_mult = 1.5,
		spread_mult = 1.0,
		flag_speed = 0.90,
		flag_drain_mult = 1.5,
		perk = "+20 HP, +50% Demo dmg",
	},
	["skin_2.png"] = {
		id = "recon",
		name = "Ghost Recon",
		role = "Marksman",
		subrole = "Precision",
		hp = 90,
		base_speed = 1.20,
		sprint_mult = 1.40,
		max_stamina = 100,
		drain_rate = 20,
		regen_rate = 30,
		regen_delay = 0.4,
		jump_cost = 8,
		demo_mult = 1.0,
		spread_mult = 0.75,
		flag_speed = 0.90,
		flag_drain_mult = 1.5,
		perk = "0.4s Regen delay, -25% Spread",
	},
	["skin_3.png"] = {
		id = "infil",
		name = "Infiltrator",
		role = "Rusher",
		subrole = "Flanker",
		hp = 85,
		base_speed = 1.25,
		sprint_mult = 1.50,
		max_stamina = 120,
		drain_rate = 22,
		regen_rate = 25,
		regen_delay = 0.8,
		jump_cost = 6,
		demo_mult = 1.0,
		spread_mult = 1.0,
		flag_speed = 0.98,
		flag_drain_mult = 1.2,
		perk = "120 Stamina, 1.5x Sprint, Swift Flag",
	},
}

local default_class = {
	id = "sam",
	name = "Tactical Sam",
	role = "Operator",
	subrole = "Standard",
	hp = 100,
	base_speed = 1.20,
	sprint_mult = 1.40,
	max_stamina = 100,
	drain_rate = 22,
	regen_rate = 25,
	regen_delay = 1.0,
	jump_cost = 8,
	demo_mult = 1.0,
	spread_mult = 1.0,
	flag_speed = 0.90,
	flag_drain_mult = 1.5,
	perk = "Standard baseline",
}

function esports_core.skins.get_player_class(player_or_name)
	if not esports_core.classes_enabled then
		return default_class
	end

	local player = type(player_or_name) == "string" and core.get_player_by_name(player_or_name) or player_or_name
	if not player or not player:is_player() then
		return default_class
	end

	local skin = player:get_meta():get_string("esports_selected_skin")
	if not skin or skin == "" then
		skin = "character.png"
	end

	return esports_core.skins.classes[skin] or default_class
end

-- Initialize the player to use the 3D model
core.register_on_joinplayer(function(player)
	player:set_properties({
		mesh = "character.b3d",
		textures = {"character.png"},  -- initial default
		visual = "mesh",
		visual_size = {x=1, y=1},
		collisionbox = {-0.3, 0.0, -0.3, 0.3, 1.7, 0.3},
		stepheight = 0.6,
		eye_height = 1.47,
	})
	-- Apply selected skin immediately
	esports_core.skins.apply(player, nil)
end)

function esports_core.skins.apply(player, color_hex)
	if not player or not player:is_player() then return end
	local pname = player:get_player_name()
	if esports_core.is_spectator and esports_core.is_spectator(pname) then return end

	local meta = player:get_meta()
	local base_skin = meta:get_string("esports_selected_skin")
	if not base_skin or base_skin == "" then
		base_skin = "character.png"
	end

	if not color_hex or color_hex == "" then
		player:set_properties({textures = {base_skin}})
	else
		-- Apply a translucent color tint over the selected base skin
		-- Use a composite texture to ensure the base skin detail remains visible
		player:set_properties({
			textures = {base_skin .. "^[colorize:" .. color_hex .. ":120"}
		})
	end
end

-- Command to swap skins (Useful for testing)
core.register_chatcommand("skin", {
	params = "reset|#RRGGBB",
	description = "Tint your character skin",
	privs = {server = true},
	func = function(name, param)
		local player = core.get_player_by_name(name)
		if not player then return false, "Player not found." end

		if param == "reset" then
			esports_core.skins.apply(player, nil)
			return true, "Skin reset to default!"
		elseif param:match("^#%x%x%x%x%x%x$") then
			esports_core.skins.apply(player, param)
			return true, "Skin tinted to " .. param .. "!"
		else
			return false, "Invalid format. Try /skin reset or /skin #ff0000"
		end
	end
})

-- LOCKER PREVIEW NODES (Self-Lit Scaled Icons)-- STUDIO LIGHT NODE (eSports High-Altitude Lighting)
core.register_node("esports_core:studio_light", {
	description = "Studio Light",
	drawtype = "glasslike",
	tiles = {"esports_hud_bar.png^[colorize:#ffffff:200"},
	use_texture_alpha = "clip",
	light_source = 14,
	sunlight_propagates = true,
	groups = {not_in_creative_inventory = 1},
	walkable = false,
	pointable = false,
})
local preview_skins = {
	{id = "sam", file = "character.png"},
	{id = "elite", file = "skin_1.png"},
	{id = "recon", file = "skin_2.png"},
	{id = "infil", file = "skin_3.png"},
}

for _, s in ipairs(preview_skins) do
	core.register_node("esports_core:locker_" .. s.id, {
		description = "Locker Icon " .. s.id,
		drawtype = "mesh",
		mesh = "character.b3d",
		tiles = {{name = s.file, glow = 31}},  -- Fullbright emissive texture
		visual_scale = 0.4,  -- Scaled down to fit full body in square icon
		light_source = 14,
		groups = {not_in_creative_inventory = 1},
		walkable = false,
		pointable = false,
		-- Full-body selection box ensures the item icon zooms out to show head-to-toe
		selection_box = {
			type = "fixed",
			fixed = {-0.3, 0.0, -0.3, 0.3, 1.9, 0.3}
		},
		collision_box = {type = "none"},
		paramtype = "light",
	})
end


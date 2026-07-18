esports_core = {}
esports_core.version = "0.6"
esports_core.build = 3
core.log("action", "====================================================")
core.log("action", "[TDM Core] Starting Luanti Deathmatch Core v" .. esports_core.version .. " (build " .. esports_core.build .. ")")
core.log("action", "====================================================")
local modpath = core.get_modpath("esports_core")

-- Persistent Nicknames System
local storage = core.get_mod_storage()
esports_core.nicknames = core.deserialize(storage:get_string("nicknames")) or {}
esports_core.allow_nicks = (storage:get_string("allow_nicks") ~= "false")

function esports_core.save_nicknames()
	storage:set_string("nicknames", core.serialize(esports_core.nicknames))
	storage:set_string("allow_nicks", esports_core.allow_nicks and "true" or "false")
end

function esports_core.get_nick(name)
	local display = esports_core.nicknames[name] or name
	if esports_league and esports_league.player_to_team and esports_league.teams then
		local tname = esports_league.player_to_team[name]
		if tname then
			local team = esports_league.teams[tname]
			if team and team.tag and team.tag ~= "" then
				return "[" .. team.tag .. "] " .. display
			end
		end
	end
	return display
end

function esports_core.is_in_lobby(player)
	local name = type(player) == "string" and player or player:get_player_name()

	-- Admins are exempt from lobby lock to permit administrative building, testing, and debugging
	local is_admin = core.check_player_privs(name, {server = true})
	if is_admin then
		return false
	end

	-- If they are in the practice range, they are not in lobby mode (they need to shoot/interact)
	if esports_core.practice and esports_core.practice.players and esports_core.practice.players[name] then
		return false
	end

	-- If a match is active or in countdown, check if they are an active player in the match
	if esports_core.match then
		local match_active = (esports_core.match.state == "active" or esports_core.match.state == "countdown")
		if match_active then
			local side = esports_core.match.get_player_match_side and esports_core.match.get_player_match_side(name)
			if side and not esports_core.is_spectator(name) then
				return false -- Active player, not in lobby mode
			end
		end
	end

	-- Otherwise, they are in lobby mode!
	return true
end

function esports_core.reset_to_lobby(player)
	local pname = player:get_player_name()
	local inv = player:get_inventory()

	if inv then
		-- Wipe Inventories of weapons/ammo (only keep blueprints)
		inv:set_list("main", {})
		inv:set_list("ammo", {})

		-- Re-add standard lobby blueprints
		inv:set_stack("main", 2, ItemStack("esports_building:blueprint_wall"))
		inv:set_stack("main", 3, ItemStack("esports_building:blueprint_ramp"))
	end

	-- Wipe custom combat stats/cooldowns
	if esports_weapons and esports_weapons.cooldowns then
		esports_weapons.cooldowns[pname] = 0
	end

	-- Apply Lobby Ghost Mode: Invisible, Invulnerable, and Frozen
	player:set_properties({
		hp_max = 100,
		visual_size = {x=1, y=1, z=1},  -- Full size for light calculation
		textures = {"character.png^[alpha:0"},  -- 100% transparent
		eye_height = 1.625,
		interact_distance = 0,  -- Cannot hit anything in lobby
	})
	player:set_hp(100)
	player:set_armor_groups({immortal = 1})

	-- Physics freeze (unless admin)
	if not core.check_player_privs(pname, {server=true}) then
		player:set_physics_override({speed = 0, jump = 0, gravity = 1})
	else
		player:set_physics_override({speed = 1.2, jump = 1.1, gravity = 1})
	end
end

dofile(modpath .. "/teams.lua")
dofile(modpath .. "/hud.lua")
dofile(modpath .. "/match.lua")
dofile(modpath .. "/spectator.lua")
dofile(modpath .. "/broadcaster.lua")
dofile(modpath .. "/pings.lua")
dofile(modpath .. "/practice_range.lua")
dofile(modpath .. "/announcer.lua")
dofile(modpath .. "/radar.lua")
dofile(modpath .. "/bots.lua")

dofile(modpath .. "/player_anim.lua")
dofile(modpath .. "/skins.lua")
dofile(modpath .. "/lobby.lua")
dofile(modpath .. "/ctf.lua")
dofile(modpath .. "/koth.lua")
dofile(modpath .. "/payload.lua")
dofile(modpath .. "/dom.lua")

-- High-Performance Combat Settings for Hands (Testing & Gameplay)
core.override_item("", {
	tool_capabilities = {
		full_punch_interval = 0.5,  -- Faster response between hits
		max_drop_level = 0,
		groupcaps = {
			fleshy = {times={[1]=2.0, [2]=0.8, [3]=0.4}, uses=0, maxlevel=1},
		},
		damage_groups = {fleshy = 10},  -- Significant damage increase
	}
})

-- Cache for existing custom logos (Populated on startup)
esports_core.registered_logos = {}
local tx_path = core.get_modpath("esports_core") .. "/textures"
local files = core.get_dir_list(tx_path, false)
if files then
	for _, f in ipairs(files) do
		-- Store both as-is and lowercase for robust matching
		esports_core.registered_logos[f:lower()] = f
	end
end

-- Helper to resolve dynamic team logos with automatic detection
function esports_core.get_team_logo(teamname, fallback)
	local def_logo = fallback or "esports_logo_red.png"
	if not teamname or teamname == "" or teamname == "NONE" or teamname == "No teams registered" then
		return def_logo
	end

	local lower_name = teamname:lower()
	-- Special case for default tactical team names
	if lower_name == "red" then return "esports_logo_red.png" end
	if lower_name == "blue" then return "esports_logo_blue.png" end
	if lower_name == "bots" then return "esports_logo_red.png" end

	-- Sanitize: lowercase and replace spaces with underscores
	local clean = lower_name:gsub("%s+", "_"):gsub("[^%w_]", "")
	local target_file = clean .. "_logo.png"

	-- Check if we actually have this file in our textures folder
	if esports_core.registered_logos[target_file] then
		return esports_core.registered_logos[target_file]
	end

	-- Real-time Fallback: Use the default if the file is missing
	return def_logo
end

-- Increase player movement speed and jump height for a more energetic feel
core.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	-- Grant essential privileges for gameplay (Force-Enable)
	local privs = core.get_player_privs(name)
	privs.interact = true
	privs.shout = true
	privs.zoom = true
	core.set_player_privs(name, privs)

	-- Enable minimap and radar by default
	player:hud_set_flags({
		minimap = true,
		minimap_radar = true
	})

	-- Apply nickname to nametag if exists
	local nick = esports_core.get_nick(name)
	if nick ~= name then
		player:set_properties({nametag = nick})
	end
end)

-- Chat Nickname Formatter
core.register_on_chat_message(function(name, message)
	if message:sub(1, 1) == "/" then return false end
	local nick = esports_core.get_nick(name)
	core.chat_send_all("<" .. nick .. "> " .. message)
	return true
end)

-- Nickname Command
core.register_chatcommand("nick", {
	params = "[player] <nickname>",
	description = "Set your nickname or another player's nickname (Admin only)",
	func = function(name, param)
		local is_admin = core.check_player_privs(name, {server = true})
		if not esports_core.allow_nicks and not is_admin then
			return false, "ERROR: Nickname changes are currently disabled by an administrator."
		end
		local target_name, new_nick

		-- Parse arguments
		local args = {}
		for w in param:gmatch("%S+") do
			table.insert(args, w)
		end

		if #args == 0 then
			return false, "Usage: /nick <nickname> (or /nick <player> <nickname> as Admin)"
		elseif #args == 1 then
			target_name = name
			new_nick = args[1]
		else
			if is_admin then
				target_name = args[1]
				new_nick = table.concat(args, " ", 2)
			else
				target_name = name
				new_nick = table.concat(args, " ")
			end
		end

		-- Reset mechanism
		if new_nick:lower() == "reset" or new_nick:lower() == "clear" then
			esports_core.nicknames[target_name] = nil
			esports_core.save_nicknames()
			local target_player = core.get_player_by_name(target_name)
			if target_player then
				target_player:set_properties({nametag = target_name})
			end
			if target_name == name then
				return true, "Your nickname has been reset to your default username."
			else
				return true, "Reset " .. target_name .. "'s nickname to default."
			end
		end

		-- Sanitize nickname: max 15 chars, alphanumeric/spaces
		new_nick = new_nick:gsub("[^%w%s%-%_]", ""):sub(1, 15)
		if new_nick == "" then
			return false, "Invalid nickname."
		end

		esports_core.nicknames[target_name] = new_nick
		esports_core.save_nicknames()

		local target_player = core.get_player_by_name(target_name)
		if target_player then
			target_player:set_properties({nametag = new_nick})
		end

		if target_name == name then
			return true, "Your nickname has been set to: " .. new_nick
		else
			return true, "Set " .. target_name .. "'s nickname to: " .. new_nick
		end
	end,
})

-- CTF ASSETS: Flag Stands and Carrying Entity
core.register_node("esports_core:flag_stand_red", {
	description = "Red Flag Stand",
	drawtype = "mesh",
	mesh = "character.b3d",  -- Temporary: Use character mesh scaled down as a flag pole
	tiles = {{name = "esports_logo_red.png", glow = 14}},
	groups = {not_in_creative_inventory = 1, flag_stand = 1},
	visual_scale = 0.5,
	selection_box = {type = "fixed", fixed = {-0.3, 0, -0.3, 0.3, 1.5, 0.3}},
	walkable = false,
	light_source = 10,
	paramtype = "light",
})

core.register_node("esports_core:flag_stand_blue", {
	description = "Blue Flag Stand",
	drawtype = "mesh",
	mesh = "character.b3d",
	tiles = {{name = "esports_logo_blue.png", glow = 14}},
	groups = {not_in_creative_inventory = 1, flag_stand = 1},
	visual_scale = 0.5,
	selection_box = {type = "fixed", fixed = {-0.3, 0, -0.3, 0.3, 1.5, 0.3}},
	walkable = false,
	light_source = 10,
	paramtype = "light",
})

-- The actual flag that appears on your back
core.register_entity("esports_core:flag_carrier_visual", {
	initial_properties = {
		visual = "mesh",
		mesh = "character.b3d",
		textures = {"esports_logo_red.png"},  -- changed dynamically
		visual_size = {x=0.2, y=0.5, z=0.2},
		physical = false,
		pointable = false,
		glow = 14,
	},
	on_activate = function(self, staticdata)
		if staticdata ~= "" then
			self.object:set_properties({textures = {staticdata}})
		end
	end,
})

-- Visual indicator for where to bring the flag
core.register_entity("esports_core:capture_ring", {
	initial_properties = {
		visual = "mesh",
		mesh = "character.b3d",  -- Temporary: Use flat circle if possible, but mesh with scale works
		textures = {"esports_hud_bar.png^[colorize:#FFFF00:150"},  -- Glowing yellow circle
		visual_size = {x=2, y=0.1, z=2},
		physical = false,
		pointable = false,
		glow = 14,
		static_save = false,
	},
})

-- Visual indicator for the KOTH capture hill
core.register_entity("esports_core:koth_ring", {
	initial_properties = {
		visual = "mesh",
		mesh = "character.b3d",
		textures = {"esports_hud_bar.png^[colorize:#FFFFFF:150"},
		visual_size = {x=12, y=0.1, z=12},
		physical = false,
		pointable = false,
		glow = 14,
		static_save = false,
	},
})

-- Visual indicator for the Domination capture points
core.register_entity("esports_core:dom_ring", {
	initial_properties = {
		visual = "mesh",
		mesh = "character.b3d",
		textures = {"esports_hud_bar.png^[colorize:#FFFFFF:150"},
		visual_size = {x=12, y=0.1, z=12}, -- visual scale managed in setup
		physical = false,
		pointable = false,
		glow = 14,
		static_save = false,
	},
})

-- Floating Point text labels for Domination
core.register_entity("esports_core:dom_label", {
	initial_properties = {
		visual = "upright_sprite",
		textures = {"esports_hud_bar.png^[colorize:#00000000"}, -- Completely transparent billboard
		visual_size = {x=0.01, y=0.01}, -- Zero visual footprint, only nametag is shown
		physical = false,
		pointable = false,
		static_save = false,
	},
})

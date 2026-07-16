esports_core.pings = {}

function esports_core.pings.trigger(sender_name, team_name, pos, ping_type)
	ping_type = ping_type or "move"
	local label = "📍 MOVE HERE"
	local color = 0x33FF33
	if ping_type == "danger" then
		label = "⚠️ DANGER"
		color = 0xFF3333
	elseif ping_type == "defend" then
		label = "🛡️ DEFEND"
		color = 0x3333FF
	end

	label = label .. " (" .. esports_core.get_nick(sender_name) .. ")"

	local team = esports_league.teams[team_name]
	if not team then return end

	for _, mname in ipairs(team.members) do
		local p = core.get_player_by_name(mname)
		if p then
			-- Send sound indicator
			core.sound_play("default_cool_item", {to_player = mname, gain = 0.8})

			core.chat_send_player(mname, string.format("[TEAM PING] %s placed marker: %s at %d, %d, %d", 
				esports_core.get_nick(sender_name), ping_type:upper(), math.floor(pos.x), math.floor(pos.y), math.floor(pos.z)))

			local id = p:hud_add({
				type = "waypoint",
				name = label,
				text = "m",
				number = color,
				world_pos = pos,
			})

			core.after(6, function()
				local player_now = core.get_player_by_name(mname)
				if player_now then
					player_now:hud_remove(id)
				end
			end)
		end
	end
end

local function place_ping(player, ping_type)
	local name = player:get_player_name()
	local team = esports_league.get_team(name)
	if not team then
		return false, "You must be in a league team to use tactical pings."
	end

	local pos = player:get_pos()
	local eye_height = player:get_properties().eye_height or 1.47
	local start_pos = {x = pos.x, y = pos.y + eye_height, z = pos.z}
	local look_dir = player:get_look_dir()
	local end_pos = {
		x = start_pos.x + look_dir.x * 40,
		y = start_pos.y + look_dir.y * 40,
		z = start_pos.z + look_dir.z * 40
	}

	local ray = core.raycast(start_pos, end_pos, true, false)
	local hit = ray:next()
	local hit_pos
	if hit and hit.type == "node" then
		hit_pos = hit.intersection_point
	else
		hit_pos = end_pos
	end

	esports_core.pings.trigger(name, team, hit_pos, ping_type)
	return true, "Ping placed."
end

core.register_chatcommand("ping", {
	params = "[danger|defend|move]",
	description = "Place a tactical ping waypoint for your team",
	func = function(name, param)
		local player = core.get_player_by_name(name)
		if not player then return end
		local p_type = param:lower():trim()
		if p_type == "" then p_type = "move" end
		if p_type ~= "danger" and p_type ~= "defend" and p_type ~= "move" then
			return false, "Invalid ping type. Use danger, defend, or move."
		end
		return place_ping(player, p_type)
	end
})

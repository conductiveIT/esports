esports_core.radar = {}
esports_core.radar.player_huds = {} -- name -> HUD ID
esports_core.radar.player_texts = {} -- name -> last displayed text (guard)

local function get_arrow(rel_angle)
	-- Normalize to [-pi, pi]
	rel_angle = (rel_angle + math.pi) % (2 * math.pi) - math.pi

	if math.abs(rel_angle) < math.pi / 8 then
		return "⬆"
	elseif rel_angle <= -math.pi / 8 and rel_angle > -3 * math.pi / 8 then
		return "↗"
	elseif rel_angle <= -3 * math.pi / 8 and rel_angle > -5 * math.pi / 8 then
		return "➡"
	elseif rel_angle <= -5 * math.pi / 8 and rel_angle > -7 * math.pi / 8 then
		return "↘"
	elseif math.abs(rel_angle) >= 7 * math.pi / 8 then
		return "⬇"
	elseif rel_angle >= 5 * math.pi / 8 and rel_angle < 7 * math.pi / 8 then
		return "↙"
	elseif rel_angle >= 3 * math.pi / 8 and rel_angle < 5 * math.pi / 8 then
		return "⬅"
	else
		return "↖"
	end
end

function esports_core.radar.clear(player)
	local name = player:get_player_name()
	local hud = esports_core.radar.player_huds[name]
	if hud then
		player:hud_remove(hud)
		esports_core.radar.player_huds[name] = nil
	end
	esports_core.radar.player_texts[name] = nil
end

function esports_core.radar.update(player)
	local name = player:get_player_name()
	local p_side = esports_core.match.get_player_match_side(name)
	
	-- Skip if not in an active match or if match is not active
	local match_active = (esports_core.match.state == "active" or esports_core.match.state == "countdown")
	if not p_side or not match_active then
		esports_core.radar.clear(player)
		return
	end

	local p_pos = player:get_pos()
	local p_yaw = player:get_look_horizontal()
	local lines = {}
	table.insert(lines, "=== TACTICAL RADAR ===")

	-- 1. Gather Teammates
	local teammates = {}
	for pname, side in pairs(esports_core.teams.players) do
		if pname ~= name and side == p_side then
			local tm = core.get_player_by_name(pname)
			if tm and tm:get_hp() > 0 then
				local tm_pos = tm:get_pos()
				local dx = tm_pos.x - p_pos.x
				local dz = tm_pos.z - p_pos.z
				local dist = math.floor(math.sqrt(dx*dx + dz*dz))
				local target_yaw = math.atan2(-dx, dz)
				local rel_angle = target_yaw - p_yaw
				local arrow = get_arrow(rel_angle)
				table.insert(teammates, string.format("• %s (%dm %s)", esports_core.get_nick(pname), dist, arrow))
			end
		end
	end

	if #teammates > 0 then
		table.insert(lines, "Teammates:")
		for _, tm_str in ipairs(teammates) do
			table.insert(lines, tm_str)
		end
	end

	-- 2. Gather Objectives
	local objectives = {}

	-- CTF Mode Objectives
	if esports_core.match.is_ctf and esports_core.ctf then
		-- Red Flag
		if esports_core.ctf.bases and esports_core.ctf.bases.red then
			local red_pos = esports_core.ctf.bases.red
			local carrier = esports_core.ctf.carriers and esports_core.ctf.carriers.red
			local state = esports_core.ctf.states and esports_core.ctf.states.red or "home"
			local t_pos = red_pos
			local label = "RED Flag"

			if carrier then
				local cp = core.get_player_by_name(carrier)
				if cp then
					t_pos = cp:get_pos()
					label = "RED Flag (Carried)"
				end
			elseif state == "dropped" then
				label = "RED Flag (Dropped)"
			end

			local dx = t_pos.x - p_pos.x
			local dz = t_pos.z - p_pos.z
			local dist = math.floor(math.sqrt(dx*dx + dz*dz))
			local rel_angle = math.atan2(-dx, dz) - p_yaw
			table.insert(objectives, string.format("🚩 %s: %dm %s", label, dist, get_arrow(rel_angle)))
		end

		-- Blue Flag
		if esports_core.ctf.bases and esports_core.ctf.bases.blue then
			local blue_pos = esports_core.ctf.bases.blue
			local carrier = esports_core.ctf.carriers and esports_core.ctf.carriers.blue
			local state = esports_core.ctf.states and esports_core.ctf.states.blue or "home"
			local t_pos = blue_pos
			local label = "BLUE Flag"

			if carrier then
				local cp = core.get_player_by_name(carrier)
				if cp then
					t_pos = cp:get_pos()
					label = "BLUE Flag (Carried)"
				end
			elseif state == "dropped" then
				label = "BLUE Flag (Dropped)"
			end

			local dx = t_pos.x - p_pos.x
			local dz = t_pos.z - p_pos.z
			local dist = math.floor(math.sqrt(dx*dx + dz*dz))
			local rel_angle = math.atan2(-dx, dz) - p_yaw
			table.insert(objectives, string.format("🚩 %s: %dm %s", label, dist, get_arrow(rel_angle)))
		end
	end

	-- KotH Mode Objectives
	if esports_core.match.is_koth and esports_core.koth and esports_core.koth.hill_center then
		local hill_pos = esports_core.koth.hill_center
		local dx = hill_pos.x - p_pos.x
		local dz = hill_pos.z - p_pos.z
		local dist = math.floor(math.sqrt(dx*dx + dz*dz))
		local rel_angle = math.atan2(-dx, dz) - p_yaw
		table.insert(objectives, string.format("👑 Active Hill: %dm %s", dist, get_arrow(rel_angle)))
	end

	-- Domination Mode Objectives
	if esports_core.match.is_domination and esports_core.dom and esports_core.dom.points then
		for id, pt in pairs(esports_core.dom.points) do
			if pt.center then
				local dx = pt.center.x - p_pos.x
				local dz = pt.center.z - p_pos.z
				local dist = math.floor(math.sqrt(dx*dx + dz*dz))
				local rel_angle = math.atan2(-dx, dz) - p_yaw
				local owner = pt.owner or "none"
				table.insert(objectives, string.format("⚑ Point %s (%s): %dm %s", id, owner:upper(), dist, get_arrow(rel_angle)))
			end
		end
	end

	-- Payload Mode Objectives
	if esports_core.match.is_payload and esports_core.payload and esports_core.payload.cart_entity then
		local cart = esports_core.payload.cart_entity
		if cart:get_pos() then
			local cart_pos = cart:get_pos()
			local dx = cart_pos.x - p_pos.x
			local dz = cart_pos.z - p_pos.z
			local dist = math.floor(math.sqrt(dx*dx + dz*dz))
			local rel_angle = math.atan2(-dx, dz) - p_yaw
			table.insert(objectives, string.format("🛒 Cart: %dm %s", dist, get_arrow(rel_angle)))
		end
	end

	if #objectives > 0 then
		table.insert(lines, "Objectives:")
		for _, obj_str in ipairs(objectives) do
			table.insert(lines, obj_str)
		end
	end

	local text = table.concat(lines, "\n")

	-- HUD Guard: Only send updates if the text changed
	if esports_core.radar.player_texts[name] == text then
		return
	end
	esports_core.radar.player_texts[name] = text

	-- Create or update the HUD element
	local hud = esports_core.radar.player_huds[name]
	if not hud then
		esports_core.radar.player_huds[name] = player:hud_add({
			hud_elem_type = "text",
			position = {x = 0.95, y = 0.15},
			offset = {x = 0, y = 0},
			text = text,
			alignment = {x = 1, y = -1},
			scale = {x = 100, y = 100},
			number = 0xFFFFFF,
		})
	else
		player:hud_change(hud, "text", text)
	end
end

-- Refresh radar for combatants every 1.0 second
local timer = 0
core.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer >= 1.0 then
		timer = 0
		-- Only loop through active match players
		for pname, _ in pairs(esports_core.teams.players) do
			local p = core.get_player_by_name(pname)
			if p then
				esports_core.radar.update(p)
			end
		end
	end
end)

-- Cleanup on leave
core.register_on_leaveplayer(function(player)
	esports_core.radar.clear(player)
end)

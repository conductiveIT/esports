esports_core.broadcaster = {}
esports_core.broadcaster.active_huds = {} -- name -> table of HUD IDs

function esports_core.broadcaster.clear_hud(player)
	local name = player:get_player_name()
	local hids = esports_core.broadcaster.active_huds[name]
	if hids then
		for _, id in pairs(hids) do
			player:hud_remove(id)
		end
		esports_core.broadcaster.active_huds[name] = nil
	end
end

function esports_core.broadcaster.update_hud(player)
	local name = player:get_player_name()
	if not esports_core.is_spectator(name) then
		esports_core.broadcaster.clear_hud(player)
		return
	end

	-- Clean up previous elements first
	esports_core.broadcaster.clear_hud(player)

	local hids = {}

	-- Check if a match is active
	local match_active = (esports_core.match.state == "active" or esports_core.match.state == "countdown")
	if not match_active then
		-- Display simple idle label
		hids.title = player:hud_add({
			hud_elem_type = "text",
			position = {x = 0.5, y = 0.15},
			offset = {x = 0, y = 0},
			text = "SPECTATOR MODE - WAITING FOR MATCH",
			alignment = {x = 0, y = 0},
			scale = {x = 100, y = 100},
			number = 0xFFFFFF,
		})
		esports_core.broadcaster.active_huds[name] = hids
		return
	end

	-- Group active match players by side
	local red_team = {}
	local blue_team = {}
	for pname, side in pairs(esports_core.teams.players) do
		local p = core.get_player_by_name(pname)
		if p then
			local stats = esports_core.match.player_stats[pname] or {kills = 0, deaths = 0}
			local p_data = {
				name = pname,
				nick = esports_core.get_nick(pname),
				hp = p:get_hp(),
				kills = stats.kills or 0,
				deaths = stats.deaths or 0,
				weapon = p:get_wielded_item():get_name():match(":(%w+)$") or "Hands"
			}
			if side == "red" then
				table.insert(red_team, p_data)
			elseif side == "blue" then
				table.insert(blue_team, p_data)
			end
		end
	end

	-- 1. TITLE
	hids.title = player:hud_add({
		hud_elem_type = "text",
		position = {x = 0.5, y = 0.05},
		offset = {x = 0, y = 0},
		text = "LIVE SPECTATOR FEED",
		alignment = {x = 0, y = 0},
		scale = {x = 100, y = 100},
		number = 0xFFFF00,
	})

	-- 2. RED ROSTER (LEFT PANEL)
	hids.red_header = player:hud_add({
		hud_elem_type = "text",
		position = {x = 0.15, y = 0.15},
		offset = {x = 0, y = 0},
		text = "RED TEAM STATUS",
		alignment = {x = -1, y = 0},
		scale = {x = 100, y = 100},
		number = 0xFF5555,
	})

	local y_off = 0.20
	for _, p in ipairs(red_team) do
		local desc = string.format("%s - HP: %d | K: %d (Weapon: %s)", p.nick, p.hp, p.kills, p.weapon)
		local id = player:hud_add({
			hud_elem_type = "text",
			position = {x = 0.15, y = y_off},
			offset = {x = 0, y = 0},
			text = desc,
			alignment = {x = -1, y = 0},
			scale = {x = 100, y = 100},
			number = 0xFFFFFF,
		})
		table.insert(hids, id)
		y_off = y_off + 0.04
	end

	-- 3. BLUE ROSTER (RIGHT PANEL)
	hids.blue_header = player:hud_add({
		hud_elem_type = "text",
		position = {x = 0.85, y = 0.15},
		offset = {x = 0, y = 0},
		text = "BLUE TEAM STATUS",
		alignment = {x = 1, y = 0},
		scale = {x = 100, y = 100},
		number = 0x5555FF,
	})

	y_off = 0.20
	for _, p in ipairs(blue_team) do
		local desc = string.format("(Weapon: %s) %d :K | %d :HP - %s", p.weapon, p.kills, p.hp, p.nick)
		local id = player:hud_add({
			hud_elem_type = "text",
			position = {x = 0.85, y = y_off},
			offset = {x = 0, y = 0},
			text = desc,
			alignment = {x = 1, y = 0},
			scale = {x = 100, y = 100},
			number = 0xFFFFFF,
		})
		table.insert(hids, id)
		y_off = y_off + 0.04
	end

	-- 4. CURRENT TARGET DETAILS (BOTTOM PANEL)
	local spec_data = esports_core.spectators[name]
	if spec_data and spec_data.target then
		local t_player = core.get_player_by_name(spec_data.target)
		if t_player then
			local stats = esports_core.match.player_stats[spec_data.target] or {kills = 0, deaths = 0}
			local weapon = t_player:get_wielded_item():get_name():match(":(%w+)$") or "Hands"
			local text = string.format("FOLLOWING: %s | HP: %d | Kills: %d | Wielding: %s", 
				esports_core.get_nick(spec_data.target), t_player:get_hp(), stats.kills or 0, weapon)

			hids.target_info = player:hud_add({
				hud_elem_type = "text",
				position = {x = 0.5, y = 0.85},
				offset = {x = 0, y = 0},
				text = text,
				alignment = {x = 0, y = 0},
				scale = {x = 100, y = 100},
				number = 0x00FF00,
			})
		end
	end

	esports_core.broadcaster.active_huds[name] = hids
end

-- Refresh spectator HUDs every second
local timer = 0
core.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer >= 1.0 then
		timer = 0
		for spec_name, _ in pairs(esports_core.spectators) do
			local p = core.get_player_by_name(spec_name)
			if p then
				esports_core.broadcaster.update_hud(p)
			end
		end
	end
end)

-- Remove HUD when stopping spectate
core.register_on_leaveplayer(function(player)
	esports_core.broadcaster.clear_hud(player)
end)

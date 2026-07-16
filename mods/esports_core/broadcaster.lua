esports_core.broadcaster = {}
esports_core.broadcaster.active_huds = {} -- name -> table of HUD IDs
esports_core.broadcaster.last_states = {} -- name -> table of text states

function esports_core.broadcaster.clear_hud(player)
	local name = player:get_player_name()
	local hids = esports_core.broadcaster.active_huds[name]
	if hids then
		if hids.title then player:hud_remove(hids.title) end
		if hids.red then player:hud_remove(hids.red) end
		if hids.blue then player:hud_remove(hids.blue) end
		if hids.target then player:hud_remove(hids.target) end
		esports_core.broadcaster.active_huds[name] = nil
	end
	esports_core.broadcaster.last_states[name] = nil
end

function esports_core.broadcaster.update_hud(player)
	local name = player:get_player_name()
	if not esports_core.is_spectator(name) then
		esports_core.broadcaster.clear_hud(player)
		return
	end

	-- Initialize HUD tracking structure if missing
	local hids = esports_core.broadcaster.active_huds[name]
	if not hids then
		hids = {title = nil, red = nil, blue = nil, target = nil}
		esports_core.broadcaster.active_huds[name] = hids
	end

	local last_state = esports_core.broadcaster.last_states[name]
	if not last_state then
		last_state = {title = "", red = "", blue = "", target = ""}
		esports_core.broadcaster.last_states[name] = last_state
	end

	-- Check if a match is active
	local match_active = (esports_core.match.state == "active" or esports_core.match.state == "countdown")
	if not match_active then
		-- Display simple idle label
		local title_text = "SPECTATOR MODE - WAITING FOR MATCH"
		if last_state.title ~= title_text then
			last_state.title = title_text
			if hids.title then
				player:hud_change(hids.title, "text", title_text)
			else
				hids.title = player:hud_add({
					type = "text",
					position = {x = 0.5, y = 0.15},
					offset = {x = 0, y = 0},
					text = title_text,
					alignment = {x = 0, y = 0},
					scale = {x = 100, y = 100},
					number = 0xFFFFFF,
				})
			end
		end

		-- Clear other panels if they exist
		if hids.red then player:hud_remove(hids.red); hids.red = nil; last_state.red = "" end
		if hids.blue then player:hud_remove(hids.blue); hids.blue = nil; last_state.blue = "" end
		if hids.target then player:hud_remove(hids.target); hids.target = nil; last_state.target = "" end
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
	local title_text = "LIVE SPECTATOR FEED"
	if last_state.title ~= title_text then
		last_state.title = title_text
		if hids.title then
			player:hud_change(hids.title, "text", title_text)
		else
			hids.title = player:hud_add({
				type = "text",
				position = {x = 0.5, y = 0.05},
				offset = {x = 0, y = 0},
				text = title_text,
				alignment = {x = 0, y = 0},
				scale = {x = 100, y = 100},
				number = 0xFFFF00,
			})
		end
	end

	-- 2. RED ROSTER (LEFT PANEL)
	local red_lines = { "RED TEAM STATUS", "----------------" }
	for _, p in ipairs(red_team) do
		table.insert(red_lines, string.format("%s - HP: %d | K: %d (%s)", p.nick, p.hp, p.kills, p.weapon))
	end
	if #red_team == 0 then
		table.insert(red_lines, "(No players)")
	end
	local red_text = table.concat(red_lines, "\n")

	if last_state.red ~= red_text then
		last_state.red = red_text
		if hids.red then
			player:hud_change(hids.red, "text", red_text)
		else
			hids.red = player:hud_add({
				type = "text",
				position = {x = 0.15, y = 0.15},
				offset = {x = 0, y = 0},
				text = red_text,
				alignment = {x = -1, y = -1},
				scale = {x = 100, y = 100},
				number = 0xFF5555,
			})
		end
	end

	-- 3. BLUE ROSTER (RIGHT PANEL)
	local blue_lines = { "BLUE TEAM STATUS", "----------------" }
	for _, p in ipairs(blue_team) do
		table.insert(blue_lines, string.format("(%s) %d :K | %d :HP - %s", p.weapon, p.kills, p.hp, p.nick))
	end
	if #blue_team == 0 then
		table.insert(blue_lines, "(No players)")
	end
	local blue_text = table.concat(blue_lines, "\n")

	if last_state.blue ~= blue_text then
		last_state.blue = blue_text
		if hids.blue then
			player:hud_change(hids.blue, "text", blue_text)
		else
			hids.blue = player:hud_add({
				type = "text",
				position = {x = 0.85, y = 0.15},
				offset = {x = 0, y = 0},
				text = blue_text,
				alignment = {x = 1, y = -1},
				scale = {x = 100, y = 100},
				number = 0x5555FF,
			})
		end
	end

	-- 4. CURRENT TARGET DETAILS (BOTTOM PANEL)
	local target_text = ""
	local spec_data = esports_core.spectators[name]
	if spec_data and spec_data.target then
		local t_player = core.get_player_by_name(spec_data.target)
		if t_player then
			local stats = esports_core.match.player_stats[spec_data.target] or {kills = 0, deaths = 0}
			local weapon = t_player:get_wielded_item():get_name():match(":(%w+)$") or "Hands"
			target_text = string.format("FOLLOWING: %s | HP: %d | Kills: %d | Wielding: %s", 
				esports_core.get_nick(spec_data.target), t_player:get_hp(), stats.kills or 0, weapon)
		end
	end

	if last_state.target ~= target_text then
		last_state.target = target_text
		if target_text == "" then
			if hids.target then
				player:hud_remove(hids.target)
				hids.target = nil
			end
		else
			if hids.target then
				player:hud_change(hids.target, "text", target_text)
			else
				hids.target = player:hud_add({
					type = "text",
					position = {x = 0.5, y = 0.85},
					offset = {x = 0, y = 0},
					text = target_text,
					alignment = {x = 0, y = 0},
					scale = {x = 100, y = 100},
					number = 0x00FF00,
				})
			end
		end
	end
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

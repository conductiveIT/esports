esports_core.ctf = {}
esports_core.ctf.bases = {
	red = {x = 80, y = 1, z = 0},
	blue = {x = -80, y = 1, z = 0}
}
esports_core.ctf.states = {red = "home", blue = "home"}
esports_core.ctf.carriers = {red = nil, blue = nil}  -- Red flag carried by...
esports_core.ctf.visuals = {}  -- pname -> entity_ref
esports_core.ctf.rings = {}  -- list of entity refs
esports_core.ctf.waypoint_huds = {}  -- pname -> {red = HUD ID, blue = HUD ID}
esports_core.ctf.dropped_pos = {red = nil, blue = nil}

function esports_core.ctf.clear_waypoints(player)
	local pname = player:get_player_name()
	local huds = esports_core.ctf.waypoint_huds[pname]
	if huds then
		if huds.red then player:hud_remove(huds.red) end
		if huds.blue then player:hud_remove(huds.blue) end
		esports_core.ctf.waypoint_huds[pname] = nil
	end
end

function esports_core.ctf.reset()
	-- Clear physical nodes at old base locations
	for _, pos in pairs(esports_core.ctf.bases) do
		core.remove_node(pos)
	end

	esports_core.ctf.states = {red = "home", blue = "home"}
	esports_core.ctf.carriers = {red = nil, blue = nil}
	for pname, ent in pairs(esports_core.ctf.visuals) do
		if ent and ent:get_luaentity() then ent:remove() end
	end
	esports_core.ctf.visuals = {}

	for _, ent in ipairs(esports_core.ctf.rings) do
		if ent and ent:get_luaentity() then ent:remove() end
	end
	esports_core.ctf.rings = {}

	-- Clean up all other artifacts in loaded areas (quick mode)
	core.clear_objects({mode = "quick"})

	-- Clear all waypoints
	for _, player in ipairs(core.get_connected_players()) do
		esports_core.ctf.clear_waypoints(player)
	end
	esports_core.ctf.waypoint_huds = {}
	esports_core.ctf.dropped_pos = {red = nil, blue = nil}

	-- Universal Combat Reset: Ensure no one is left with a shadow flag lockout
	for _, player in ipairs(core.get_connected_players()) do
		player:get_meta():set_int("has_flag", 0)
	end
end

function esports_core.ctf.spawn_flags()
	for team, pos in pairs(esports_core.ctf.bases) do
		local node = (team == "red") and "esports_core:flag_stand_red" or "esports_core:flag_stand_blue"
		core.set_node(pos, {name = node})

		-- Spawn Capture Ring
		local ring_pos = {x=pos.x, y=pos.y - 0.45, z=pos.z}
		local ent = core.add_entity(ring_pos, "esports_core:capture_ring")
		if ent then
			ent:set_properties({textures = {(team == "red") and "esports_hud_bar.png^[colorize:#FF4444:150" or "esports_hud_bar.png^[colorize:#4444FF:150"}})
			table.insert(esports_core.ctf.rings, ent)
		end
	end
end

function esports_core.ctf.get_carrier(team)
	return esports_core.ctf.carriers[team]
end

-- Returns true if the node punched should be removed
function esports_core.ctf.pickup(player, flag_team)
	local pname = player:get_player_name()
	local p_side = esports_core.match.get_player_match_side(pname)

	if not p_side then return false end

	if p_side == flag_team then
		-- Punched own flag
		if esports_core.ctf.states[flag_team] == "dropped" then
			esports_core.ctf.return_home(flag_team)
			core.chat_send_all("LOBBY: " .. pname .. " returned the " .. flag_team:upper() .. " flag!")
			return true  -- Remove the dropped node
		elseif esports_core.ctf.states[flag_team] == "home" then
			-- Attempting to SCORE
			local enemy_team = (p_side == "red") and "blue" or "red"
			if esports_core.ctf.carriers[enemy_team] == pname then
				esports_core.ctf.score(pname, p_side)
				-- Node stays at home
			end
		else
			-- Flag is CARRIED (not home, not dropped)
			local enemy_team = (p_side == "red") and "blue" or "red"
			if esports_core.ctf.carriers[enemy_team] == pname then
				core.chat_send_player(pname, core.colorize("#FF4444", "TACTICAL ALERT: You cannot score while your own flag is compromised! Recover it first!"))
				core.sound_play("esports_deny", {pos = player:get_pos(), gain = 1.0})
			end
		end
		return false  -- Don't remove own flag stand at home
	end

	-- Punched enemy flag
	if esports_core.ctf.states[flag_team] == "home" or esports_core.ctf.states[flag_team] == "dropped" then
		-- Pick up!
		esports_core.ctf.states[flag_team] = "carried"
		esports_core.ctf.carriers[flag_team] = pname

		-- Visual Attachment
		local visual = core.add_entity(player:get_pos(), "esports_core:flag_carrier_visual", (flag_team == "red") and "esports_logo_red.png" or "esports_logo_blue.png")
		visual:set_attach(player, "", {x=0, y=10, z=-2}, {x=0, y=0, z=0})
		esports_core.ctf.visuals[pname] = visual

		-- Player Meta / Speed Penalty
		local meta = player:get_meta()
		meta:set_int("has_flag", 1)
		player:set_physics_override({speed = 0.9})

		core.chat_send_all("LOBBY: " .. flag_team:upper() .. " flag taken by " .. pname .. "!")
		core.sound_play("esports_pickup", {pos = player:get_pos(), gain = 1.0})
		esports_core.hud.update_scores()
		return true  -- Remove the node (home or dropped)
	end

	return false
end

function esports_core.ctf.drop(player)
	local pname = player:get_player_name()

	for team, carrier in pairs(esports_core.ctf.carriers) do
		if carrier == pname then
			esports_core.ctf.carriers[team] = nil
			local pos = player:get_pos()

			if pos.y < -10 then
				-- Fell into the void: return flag to base immediately
				esports_core.ctf.return_home(team)

				-- Clean up visual
				if esports_core.ctf.visuals[pname] then
					esports_core.ctf.visuals[pname]:remove()
					esports_core.ctf.visuals[pname] = nil
				end

				-- Clear Meta / speed
				player:get_meta():set_int("has_flag", 0)
				player:set_physics_override({speed = 1.2})

				core.chat_send_all("LOBBY: The " .. team:upper() .. " flag fell into the void and returned home!")
				esports_core.hud.update_scores()
			else
				-- Normal drop on map
				esports_core.ctf.states[team] = "dropped"
				pos.y = pos.y + 0.5
				local node = (team == "red") and "esports_core:flag_stand_red" or "esports_core:flag_stand_blue"
				core.set_node(pos, {name = node})

				esports_core.ctf.dropped_pos[team] = {x = pos.x, y = pos.y, z = pos.z}

				-- Clean up visual
				if esports_core.ctf.visuals[pname] then
					esports_core.ctf.visuals[pname]:remove()
					esports_core.ctf.visuals[pname] = nil
				end

				-- Clear Meta
				player:get_meta():set_int("has_flag", 0)
				player:set_physics_override({speed = 1.2})

				core.chat_send_all("LOBBY: " .. team:upper() .. " flag dropped!")
				esports_core.hud.update_scores()

				-- Auto-return timer (removes dropped flag node)
				local f_team = team
				local dpos = {x = pos.x, y = pos.y, z = pos.z}
				core.after(30, function()
					if esports_core.ctf.states[f_team] == "dropped" then
						esports_core.ctf.return_home(f_team)
						core.remove_node(dpos)
						core.chat_send_all("LOBBY: The " .. f_team .. " flag has auto-returned to base.")
						esports_core.hud.update_scores()
					end
				end)
			end
		end
	end
end

function esports_core.ctf.return_home(team)
	esports_core.ctf.states[team] = "home"
	esports_core.ctf.carriers[team] = nil
	esports_core.ctf.dropped_pos[team] = nil

	-- Ensure base node exists
	core.set_node(esports_core.ctf.bases[team], {name = (team == "red") and "esports_core:flag_stand_red" or "esports_core:flag_stand_blue"})
end

function esports_core.ctf.score(pname, team)
	local enemy_team = (team == "red") and "blue" or "red"

	-- Score point
	esports_core.teams.scores[team] = esports_core.teams.scores[team] + 1
	esports_core.match.add_capture(pname)
	core.chat_send_all("LOBBY: " .. pname .. " CAPTURED the " .. enemy_team:upper() .. " flag!")
	core.sound_play("esports_pickup", {pos = core.get_player_by_name(pname):get_pos(), gain = 2.0})

	-- Reset flags
	esports_core.ctf.return_home(enemy_team)

	-- Clean up carrier visual and meta
	local player = core.get_player_by_name(pname)
	if player then
		player:get_meta():set_int("has_flag", 0)
		player:set_physics_override({speed = 1.2})
		if esports_core.ctf.visuals[pname] then
			esports_core.ctf.visuals[pname]:remove()
			esports_core.ctf.visuals[pname] = nil
		end
	end

	esports_core.hud.update_scores()

	-- Win condition check
	if esports_core.teams.scores[team] >= 5 then
		esports_core.match.timer = 0
	end
end

-- INTERACTION HOOKS
core.register_on_punchnode(function(pos, node, puncher, pointed_thing)
	if not esports_core.match.is_ctf then return end

	if node.name == "esports_core:flag_stand_red" then
		if esports_core.ctf.pickup(puncher, "red") then
			core.remove_node(pos)
		end
	elseif node.name == "esports_core:flag_stand_blue" then
		if esports_core.ctf.pickup(puncher, "blue") then
			core.remove_node(pos)
		end
	end
end)

core.register_on_dieplayer(function(player)
	if esports_core.match.is_ctf then
		esports_core.ctf.drop(player)
	end
end)

-- NO-BUILD ZONE PROTECTION
local function is_near_flag(pos)
	local scale = esports_core.match.current_map_scale or 1.0
	for team, base_pos in pairs(esports_core.ctf.bases) do
		local d = vector.distance(pos, base_pos)
		if d < (15 * scale) then return true, team end
	end
	return false
end

core.register_on_placenode(function(pos, newnode, placer, oldnode, itemstack, pointed_thing)
	if not esports_core.match.is_ctf then return end
	if not placer or not placer:is_player() then return end

	local pname = placer:get_player_name()
	if core.check_player_privs(pname, {server=true}) or core.check_player_privs(pname, {admin=true}) then
		return  -- Admin bypass
	end

	if is_near_flag(pos) then
		core.chat_send_player(pname, core.colorize("#FF4444", "STRATEGIC OVERRIDE: Building is prohibited within 15m of a flag objective!"))
		-- To prevent the block from staying, we return true to "cancel" the place if the engine supports it,
		-- But on_placenode is often called AFTER placement. The robust way is to swap it back.
		core.set_node(pos, oldnode)
		return true
	end
end)

core.register_on_dignode(function(pos, oldnode, digger)
	if not esports_core.match.is_ctf then return end
	if not digger or not digger:is_player() then return end

	local pname = digger:get_player_name()
	if core.check_player_privs(pname, {server=true}) or core.check_player_privs(pname, {admin=true}) then
		return  -- Admin bypass
	end

	if is_near_flag(pos) then
		core.chat_send_player(pname, core.colorize("#FF4444", "STRATEGIC OVERRIDE: Modification is prohibited within 15m of a flag objective!"))
		-- Restore the node
		core.set_node(pos, oldnode)
		return true
	end
end)

-- Proximity-based collision detection for flag pickup, return, and score
function esports_core.ctf.check_proximity()
	if not esports_core.match.is_ctf or (esports_core.match.state ~= "active" and esports_core.match.state ~= "countdown") then
		return
	end

	for _, player in ipairs(core.get_connected_players()) do
		if player:get_hp() > 0 then
			local pname = player:get_player_name()
			local p_side = esports_core.match.get_player_match_side(pname)

			if p_side == "red" or p_side == "blue" then
				local ppos = player:get_pos()

				-- Check both flags
				for flag_team, base_pos in pairs(esports_core.ctf.bases) do
					local state = esports_core.ctf.states[flag_team]
					local flag_pos = nil

					if state == "home" then
						flag_pos = base_pos
					elseif state == "dropped" then
						flag_pos = esports_core.ctf.dropped_pos[flag_team]
					end

					if flag_pos then
						local dist = vector.distance(ppos, flag_pos)
						if dist <= 2.2 then
							if p_side == flag_team then
								-- Friendly flag interaction
								if state == "dropped" then
									esports_core.ctf.return_home(flag_team)
									core.remove_node(flag_pos)
									core.chat_send_all("LOBBY: " .. pname .. " returned the " .. flag_team:upper() .. " flag!")
									core.sound_play("esports_pickup", {pos = ppos, gain = 1.0})
									esports_core.hud.update_scores()
								elseif state == "home" then
									-- Attempting to SCORE
									local enemy_team = (p_side == "red") and "blue" or "red"
									if esports_core.ctf.carriers[enemy_team] == pname then
										esports_core.ctf.score(pname, p_side)
									end
								end
							else
								-- Enemy flag interaction: Pick up!
								esports_core.ctf.states[flag_team] = "carried"
								esports_core.ctf.carriers[flag_team] = pname
								core.remove_node(flag_pos)

								-- Visual Attachment
								local visual = core.add_entity(ppos, "esports_core:flag_carrier_visual", (flag_team == "red") and "esports_logo_red.png" or "esports_logo_blue.png")
								visual:set_attach(player, "", {x=0, y=10, z=-2}, {x=0, y=0, z=0})
								esports_core.ctf.visuals[pname] = visual

								-- Player Meta / Speed Penalty
								local meta = player:get_meta()
								meta:set_int("has_flag", 1)
								player:set_physics_override({speed = 0.9})

								core.chat_send_all("LOBBY: " .. flag_team:upper() .. " flag taken by " .. pname .. "!")
								core.sound_play("esports_pickup", {pos = ppos, gain = 1.0})
								esports_core.hud.update_scores()
							end
						end
					end
				end
			end
		end
	end
end

-- DYNAMIC HUD WAYPOINT TRACKING LOGIC
function esports_core.ctf.update_waypoints()
	-- If it's not active CTF mode, clear all waypoints
	if not esports_core.match.is_ctf or (esports_core.match.state ~= "active" and esports_core.match.state ~= "countdown") then
		for _, p in ipairs(core.get_connected_players()) do
			esports_core.ctf.clear_waypoints(p)
		end
		return
	end

	-- Determine RED flag waypoint status
	local red_pos = esports_core.ctf.bases.red
	local red_carrier = esports_core.ctf.carriers.red
	local red_state = esports_core.ctf.states.red
	local red_waypoint_pos = red_pos
	local red_label = "🔴 RED FLAG"

	if red_carrier then
		local cp = core.get_player_by_name(red_carrier)
		if cp then
			local pos = cp:get_pos()
			red_waypoint_pos = {x = pos.x, y = pos.y + 2.0, z = pos.z}
			red_label = "🚩 RED CARRIER (" .. esports_core.get_nick(red_carrier) .. ")"
		end
	elseif red_state == "dropped" then
		if esports_core.ctf.dropped_pos.red then
			red_waypoint_pos = esports_core.ctf.dropped_pos.red
		end
		red_label = "⚠️ RED FLAG (DROPPED)"
	else
		red_label = "🔴 RED FLAG (BASE)"
	end

	-- Determine BLUE flag waypoint status
	local blue_pos = esports_core.ctf.bases.blue
	local blue_carrier = esports_core.ctf.carriers.blue
	local blue_state = esports_core.ctf.states.blue
	local blue_waypoint_pos = blue_pos
	local blue_label = "🔵 BLUE FLAG"

	if blue_carrier then
		local cp = core.get_player_by_name(blue_carrier)
		if cp then
			local pos = cp:get_pos()
			blue_waypoint_pos = {x = pos.x, y = pos.y + 2.0, z = pos.z}
			blue_label = "🚩 BLUE CARRIER (" .. esports_core.get_nick(blue_carrier) .. ")"
		end
	elseif blue_state == "dropped" then
		if esports_core.ctf.dropped_pos.blue then
			blue_waypoint_pos = esports_core.ctf.dropped_pos.blue
		end
		blue_label = "⚠️ BLUE FLAG (DROPPED)"
	else
		blue_label = "🔵 BLUE FLAG (BASE)"
	end

	-- Update waypoints for every connected player
	for _, player in ipairs(core.get_connected_players()) do
		local pname = player:get_player_name()
		local huds = esports_core.ctf.waypoint_huds[pname]
		if not huds then
			huds = {red = nil, blue = nil}
			esports_core.ctf.waypoint_huds[pname] = huds
		end

		-- RED Flag Waypoint
		if not huds.red then
			huds.red = player:hud_add({
				type = "waypoint",
				name = red_label,
				text = "m",
				number = 0xFF4444,
				world_pos = red_waypoint_pos,
			})
		else
			player:hud_change(huds.red, "name", red_label)
			player:hud_change(huds.red, "world_pos", red_waypoint_pos)
		end

		-- BLUE Flag Waypoint
		if not huds.blue then
			huds.blue = player:hud_add({
				type = "waypoint",
				name = blue_label,
				text = "m",
				number = 0x4444FF,
				world_pos = blue_waypoint_pos,
			})
		else
			player:hud_change(huds.blue, "name", blue_label)
			player:hud_change(huds.blue, "world_pos", blue_waypoint_pos)
		end
	end
end

-- Refresh waypoints and check proximity periodically
local waypoint_timer = 0
core.register_globalstep(function(dtime)
	waypoint_timer = waypoint_timer + dtime
	if waypoint_timer >= 0.1 then
		waypoint_timer = 0
		esports_core.ctf.update_waypoints()
		esports_core.ctf.check_proximity()
	end
end)

-- Cleanup waypoints and drop carried flag on leave
core.register_on_leaveplayer(function(player)
	if esports_core.match.is_ctf then
		esports_core.ctf.drop(player)
	end
	esports_core.ctf.clear_waypoints(player)
end)
